local t = dofile("tests/helpers.lua")
local api = vim.api
local ui = require("ui_tools")
local winbar = require("ui_tools.winbar")
vim.o.columns, vim.o.hidden = 180, true
local before = { global = vim.go.winbar, local_value = vim.wo.winbar }
local source = t.buffer({ "first", "second" })
api.nvim_buf_set_name(source, "/tmp/ui-tools-winbar/中文%file.lua")
vim.bo.modified = false
local clients, queries = vim.lsp.get_clients, 0
vim.lsp.get_clients = function()
  queries = queries + 1
  return { { name = "z-ls" }, { name = "a%ls" }, { name = "a%ls" } }
end
local function text(win)
  win = win or api.nvim_get_current_win()
  return api.nvim_eval_statusline(vim.wo[win].winbar, {
    winid = win,
    use_winbar = true,
    maxwidth = 240,
  }).str
end
local function owned(win)
  return vim.wo[win or 0].winbar:find("ui_tools.winbar", 1, true)
end
local options = {
  breadcrumbs = function(ctx)
    assert(ctx.buf == api.nvim_win_get_buf(ctx.win))
    assert(ctx.width == api.nvim_win_get_width(ctx.win))
    return "scope_" .. ctx.cursor[1] .. "%%symbol"
  end,
}
ui.setup({ winbar = options })
local original_win = api.nvim_get_current_win()
assert(owned())
assert(text():find("中文%file.lua", 1, true), text())
assert(text():find("scope_1%symbol", 1, true), text())
assert(text():find("a%ls, z-ls", 1, true), text())
t.eq(1, queries)
assert(not package.loaded["lsp-tools"], "Winbar must not load an optional provider")

-- Rendering and cursor movement read cached clients and never enumerate buffers.
local list_bufs = api.nvim_list_bufs
api.nvim_list_bufs = function()
  error("Buffer enumeration during winbar rendering")
end
vim.lsp.get_clients = function()
  error("LSP query during winbar rendering")
end
for i = 1, 100 do
  api.nvim_win_set_cursor(0, { i % 2 + 1, 0 })
  assert(text():find("scope_" .. (i % 2 + 1), 1, true))
end
api.nvim_list_bufs = list_bufs
vim.lsp.get_clients = function()
  queries = queries + 1
  return { { name = "updated-ls" } }
end
api.nvim_exec_autocmds("LspAttach", { buffer = source, data = { client_id = 1 } })
vim.wait(60)
t.eq(2, queries)
assert(text():find("updated-ls", 1, true))

-- Inactive splits use their own cursor even while sharing the buffer cache.
vim.cmd("vsplit")
local split = api.nvim_get_current_win()
api.nvim_win_set_cursor(original_win, { 1, 0 })
api.nvim_win_set_cursor(split, { 2, 0 })
assert(text(original_win):find("scope_1", 1, true), text(original_win))
assert(text(split):find("scope_2", 1, true), text(split))
t.eq(2, queries)
api.nvim_set_current_win(original_win)
assert(text(split):find("中文%file.lua", 1, true), text(split))
api.nvim_exec_autocmds("LspDetach", { buffer = source, data = { client_id = 1 } })
vim.wait(60)
t.eq(3, queries) -- One snapshot shared by both splits, including on invalidation.
local second = t.buffer({ "another file" })
api.nvim_buf_set_name(second, "/tmp/ui-tools-winbar/other.txt")
assert(text():find("other.txt", 1, true), text())
api.nvim_set_current_buf(source)
assert(text():find("中文%file.lua", 1, true), text())
api.nvim_set_current_buf(second)
assert(text():find("other.txt", 1, true), text())

-- Special/excluded/private buffers release the bar; returning adopts it again.
vim.bo.buftype = "nofile"
api.nvim_exec_autocmds("BufWinEnter", { buffer = second })
t.eq("", vim.wo.winbar)
api.nvim_set_current_buf(source)
assert(owned())
vim.b.ui_tools_disable = true
api.nvim_exec_autocmds("BufWinEnter", { buffer = source })
t.eq("", vim.wo.winbar)
vim.b.ui_tools_disable = nil
winbar.refresh()
assert(owned())

-- An autocmd window or non-entering float must not redraw the editor mid-setup.
local exec, temporary = api.nvim_exec2, 0
api.nvim_exec2 = function(command, ...)
  if
    command == "redrawstatus"
    and (vim.fn.win_gettype() == "autocmd" or api.nvim_win_get_config(0).relative ~= "")
  then
    temporary = temporary + 1
  end
  return exec(command, ...)
end
local scratch = api.nvim_create_buf(false, true)
vim.bo[scratch].filetype = "winbar-fixture"
local float = api.nvim_open_win(scratch, false, {
  relative = "editor",
  row = 1,
  col = 1,
  width = 20,
  height = 1,
  style = "minimal",
})
vim.bo[scratch].filetype = "winbar-float-fixture"
api.nvim_win_close(float, true)
api.nvim_buf_delete(scratch, { force = true })
api.nvim_exec2 = exec
t.eq(0, temporary)
t.eq(original_win, api.nvim_get_current_win())
vim.wait(60)

-- Provider failures are isolated; filenames remain available in every split.
winbar.setup({
  breadcrumbs = function()
    error("broken breadcrumb")
  end,
})
assert(text():find("中文%file.lua", 1, true), text())
assert(winbar.errors[original_win]:find("broken breadcrumb", 1, true))
winbar.setup(options)
assert(text():find("scope_1", 1, true), text())
assert(not next(winbar.errors))

-- Repeated setup, inherited splits and pending callbacks restore local options.
ui.setup({ winbar = { exclude = { "excluded" }, lsp = false } })
vim.bo.filetype = "excluded"
t.eq("", vim.wo.winbar)
vim.bo.filetype = "lua"
assert(owned())
api.nvim_exec_autocmds("WinClosed", { pattern = "99999" })
ui.setup({ winbar = options })
vim.wait(60)
ui.toggle("winbar")
assert(not winbar.enabled)
ui.toggle("winbar")
assert(winbar.enabled and owned())
ui.disable()
t.eq(before.local_value, vim.wo.winbar)
t.eq(before.local_value, vim.wo[split].winbar)
t.eq(before.global, vim.go.winbar)
vim.cmd("only")

-- Existing global/local owners and deliberate clears win, even after force.
vim.go.winbar = "external global"
winbar.setup()
t.eq("external global", vim.wo.winbar)
winbar.disable()
winbar.setup({ force = true })
assert(owned())
winbar.disable()
t.eq("external global", vim.wo.winbar)
vim.go.winbar = before.global
vim.wo.winbar = "external local"
winbar.setup({ force = true })
assert(owned())
winbar.disable()
t.eq("external local", vim.wo.winbar)
vim.wo.winbar = ""
winbar.setup()
vim.wo.winbar = ""
api.nvim_exec_autocmds("WinEnter", {})
vim.cmd("enew")
t.eq("", vim.wo.winbar)
winbar.setup({ force = true })
vim.wo.winbar = "later owner"
api.nvim_exec_autocmds("WinEnter", {})
winbar.refresh()
t.eq("later owner", vim.wo.winbar)
winbar.disable()
t.eq("later owner", vim.wo.winbar)
vim.wo.winbar = before.local_value
vim.lsp.get_clients = clients
t.eq("", vim.v.errmsg)
print("winbar target windows, caches, lazy providers, ownership, failures and lifecycle passed")
