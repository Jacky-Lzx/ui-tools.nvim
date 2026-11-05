local h = dofile("tests/helpers.lua")
local menu = require("ui_tools.context_menu")
local api = vim.api
local function item(id)
  for _, entry in ipairs(menu.state().items) do
    if entry.id == id then
      return entry
    end
  end
end
local function flush()
  vim.wait(20, function()
    return false
  end)
end

local buf = h.buffer({ "alpha", "beta" })
api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/sample.lua")

-- Global mappings are restored, including Lua callbacks; a subsequent owner wins.
local old = function() end
vim.keymap.set("n", "<RightMouse>", old, { silent = true, desc = "original" })
vim.keymap.set("x", "<RightMouse>", "y", { expr = false, desc = "visual original" })
local get_maps, scans = api.nvim_get_keymap, 0
api.nvim_get_keymap = function(...)
  scans = scans + 1
  return get_maps(...)
end
menu.setup()
api.nvim_get_keymap = get_maps
h.eq(3, scans)
assert(menu.enabled)
assert(vim.fn.maparg("<RightMouse>", "n", false, true).callback ~= old)
menu.setup()
menu.disable()
h.eq(old, vim.fn.maparg("<RightMouse>", "n", false, true).callback)
h.eq("y", vim.fn.maparg("<RightMouse>", "x", false, true).rhs)
menu.setup()
vim.keymap.set("n", "<RightMouse>", "j", { desc = "new owner" })
menu.disable()
h.eq("j", vim.fn.maparg("<RightMouse>", "n", false, true).rhs)

-- A buffer-local mapping remains independent of global ownership.
vim.keymap.set("n", "<RightMouse>", "k", { buffer = buf })
menu.setup({ mouse = false })
h.eq("k", vim.fn.maparg("<RightMouse>", "n", false, true).rhs)
menu.open()
assert(item("copy") and item("path") and item("location"))
assert(not item("definition"))
local win, scratch = menu.state().win, menu.state().buf
menu.close()
assert(not api.nvim_win_is_valid(win) and not api.nvim_buf_is_valid(scratch))
vim.keymap.del("n", "<RightMouse>", { buffer = buf })

-- Cancellation and deferred updates are scoped to a single opening.
local pending, cancelled = nil, 0
local remove = menu.register("async", function(ctx, sink)
  h.eq(buf, ctx.buf)
  pending = sink
  sink.on_close(function()
    cancelled = cancelled + 1
  end)
  return { { id = "waiting", label = "Loading…", enabled = false } }
end)
local handle = menu.open()
pending.update({ { id = "ready", label = "Ready", action = function() end } })
flush()
assert(item("ready") and not item("waiting"))
local stale = pending
handle.close()
h.eq(1, cancelled)
assert(not handle.is_active())
menu.open()
stale.update({ { id = "stale", label = "Stale", action = function() end } })
flush()
assert(not item("stale"))
remove()
pending.update({ { id = "removed", label = "Removed", action = function() end } })
flush()
assert(not item("removed"))
menu.close()
h.eq(2, cancelled)

-- Old unregister handles cannot remove replacement registrations.
local old_remove = menu.register("replace", function()
  return {}
end)
local new_remove = menu.register("replace", function()
  return { { id = "new", label = "New", action = function() end } }
end)
old_remove()
menu.open()
assert(item("new"))
new_remove()
assert(not item("new"))
menu.close()

-- Provider failures and malformed items cannot prevent other providers rendering.
local broken = menu.register("broken", function()
  error("provider failed")
end)
local malformed = menu.register("malformed", function()
  return { false, {}, 3 }
end)
menu.open()
assert(item("copy"))
assert(menu.errors.broken:find("provider failed", 1, true))
assert(menu.errors.malformed)
menu.close()
broken()
malformed()

-- Capability filtering uses the source buffer. Configuration supplies callbacks/keys.
local real_clients = vim.lsp.get_clients
local invoked = false
vim.lsp.get_clients = function(opts)
  h.eq(buf, opts.bufnr)
  return {
    {
      id = 901,
      offset_encoding = "utf-16",
      supports_method = function(_, method, source)
        h.eq(buf, source)
        return method == "textDocument/definition" or method == "textDocument/rename"
      end,
      request = function(_, method, _, callback, source)
        h.eq(buf, source)
        h.eq("textDocument/definition", method)
        callback(nil, { uri = vim.uri_from_bufnr(buf), range = {} })
        return true, 1
      end,
    },
  }
end
local detach = require("ui_tools.integrations.context_lsp").setup({
  shortcuts = { definition = "gd" },
  actions = {
    definition = function(ctx)
      invoked = ctx.buf
    end,
  },
})
menu.open()
assert(not item("definition"))
flush()
assert(item("definition") and item("rename") and not item("references"))
h.eq("gd", item("definition").shortcut)
local action, ctx = item("definition").action, menu.state().context
menu.close()
action(ctx)
h.eq(buf, invoked)
vim.bo[buf].readonly = true
menu.open()
assert(item("rename").enabled == false and item("paste").enabled == false)
menu.close()
vim.bo[buf].readonly = false
detach()
vim.lsp.get_clients = real_clients

-- Exclusion and stale-buffer guards must not leave an executable context.
vim.b[buf].ui_tools_disable = true
assert(menu.open() == nil and menu.state() == nil)
vim.b[buf].ui_tools_disable = nil
handle = menu.open()
api.nvim_buf_set_lines(buf, 0, 1, false, { "updated" })
assert(not handle.is_active())
menu.close()
menu.disable()
print("context menu: mapping ownership, providers, cancellation and LSP capabilities passed")
