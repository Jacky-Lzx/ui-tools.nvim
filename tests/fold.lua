local t = dofile("tests/helpers.lua")
local api = vim.api
local before_events = #api.nvim_get_autocmds({})
local fold = require("ui_tools.fold")
t.eq(before_events, #api.nvim_get_autocmds({}))
local ui = require("ui_tools")
vim.o.hidden = true
vim.cmd("filetype plugin on")
local buf = t.buffer({
  "local function outer()",
  "  if true then",
  "    print('你好')",
  "    print('two')",
  "  end",
  "end",
  "return outer",
})
vim.bo.filetype, vim.bo.modified = "lua", false
local win = api.nvim_get_current_win()
local keys = { "foldmethod", "foldexpr", "foldtext", "foldenable", "foldlevel", "fillchars" }
local function snapshot()
  local result = {}
  for _, key in ipairs(keys) do
    result[key] = api.nvim_get_option_value(key, { win = win, scope = "local" })
  end
  return result
end
local before, global_level = snapshot(), vim.o.foldlevelstart
local function initialized(target)
  target = target or api.nvim_get_current_win()
  assert(
    vim.wait(2000, function()
      return vim.wo[target].foldlevel ~= 99
    end),
    "Fold initialization timed out"
  )
end
ui.setup({ fold = { suffix = "  ::%d", preview = { max_lines = 3, max_width = 40, max_height = 8 } } })
initialized()
t.eq(global_level, vim.o.foldlevelstart)
t.eq("expr", vim.wo.foldmethod)
local depth = vim.wo.foldlevel
assert(depth >= 2)
vim.cmd("normal! zm")
t.eq(depth - 1, vim.wo.foldlevel)
t.eq(2, vim.fn.foldclosed(3))
vim.cmd("normal! zM")
vim.treesitter.start(buf)
t.eq("local function outer()  ::5", vim.fn.foldtextresult(1))
local chunks, original = nil, fold.text
fold.text = function()
  chunks = original()
  return chunks
end
vim.fn.foldtextresult(1)
fold.text = original
assert(
  vim.iter(chunks):any(function(chunk)
    return chunk[2]:match("^@")
  end),
  "Missing syntax colors"
)

local preview_buf, preview_win = fold.preview()
t.eq(win, api.nvim_get_current_win())
t.eq(3, api.nvim_buf_line_count(preview_buf))
assert(not vim.bo[preview_buf].modifiable)
assert(api.nvim_win_get_config(preview_win).title[1][1]:find("first 3 shown", 1, true))
fold.preview()
t.eq(preview_win, api.nvim_get_current_win())
api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
assert(not api.nvim_win_is_valid(preview_win))
api.nvim_set_current_win(win)
vim.cmd("normal! zR")
t.eq(nil, fold.preview())
vim.cmd("normal! zM")
vim.cmd("vsplit")
local other = api.nvim_get_current_win()
initialized(other)
vim.cmd("normal! zR")
api.nvim_set_current_win(win)
t.eq(0, vim.wo.foldlevel)
t.eq(1, vim.fn.foldclosed(3))
api.nvim_win_close(other, false)

-- Disable closes previews and restores still-owned options, without mappings.
local _, closing = fold.preview()
ui.disable()
assert(not api.nvim_win_is_valid(closing))
t.eq(before, snapshot())
for _, key in ipairs({ "K", "zK", "zM", "zR", "zm", "zr", "za", "zo", "zc", "zx", "zX" }) do
  t.eq("", vim.fn.maparg(key, "n"))
end
t.eq(nil, fold.preview())

-- Pending parse/initialization callbacks must not outlive disable or setup.
fold.setup()
fold.disable()
vim.wait(80)
t.eq(before, snapshot())
fold.setup({ method = "indent", level = 1, suffix = " [%d]" })
vim.wait(80)
t.eq("indent", vim.wo.foldmethod)
t.eq(1, vim.wo.foldlevel)
fold.disable()
t.eq(before, snapshot())

-- Existing and later owners are preserved, with explicit force available.
vim.wo.foldtext = "'external'"
fold.setup()
t.eq("'external'", vim.wo.foldtext)
t.eq(before.foldmethod, vim.wo.foldmethod)
fold.setup({ force = true })
initialized()
assert(vim.wo.foldtext:find("ui_tools.fold", 1, true))
fold.disable()
t.eq("'external'", vim.wo.foldtext)
vim.wo.foldtext = before.foldtext
fold.setup()
initialized()
vim.wo.foldtext = "'later'"
fold.attach(win)
api.nvim_exec_autocmds("WinEnter", {})
t.eq("'later'", vim.wo.foldtext)
fold.disable()
t.eq("'later'", vim.wo.foldtext)
vim.wo.foldtext = before.foldtext

-- Explicit exclusions/private buffers and diff are left to their own owners.
vim.b.ui_tools_disable = true
fold.setup()
t.eq(before.foldmethod, vim.wo.foldmethod)
fold.disable()
vim.b.ui_tools_disable = nil
fold.setup({ exclude = { "lua" } })
t.eq(before.foldmethod, vim.wo.foldmethod)
fold.disable()
fold.setup()
initialized()
vim.cmd("diffthis")
fold.attach(win)
t.eq("diff", vim.wo.foldmethod)
vim.cmd("diffoff")
initialized()
t.eq("expr", vim.wo.foldmethod)
fold.disable()
t.eq(before, snapshot())
ui.setup({ fold = true })
initialized()
ui.toggle("fold")
assert(not fold.enabled)
ui.toggle("fold")
assert(fold.enabled)
initialized()
ui.disable()
t.eq("", vim.v.errmsg)
print("fold native sources, text, previews, ownership, cancellation and lifecycle passed")
