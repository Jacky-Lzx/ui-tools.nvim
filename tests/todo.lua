local t = dofile("tests/helpers.lua")
local ui, todo = require("ui_tools"), require("ui_tools.todo")
local buf = t.buffer({
  "-- TODO(lzx): 实现 #abc",
  'local s = "TODO: ordinary string"',
  "-- FIXME: broken; NOTE: context",
  "-- NOTTODO: no; TODO no colon",
})
vim.bo.filetype = "lua"
vim.cmd("syntax on")
vim.bo.syntax = "lua"
local function marks(kind)
  return vim.api.nvim_buf_get_extmarks(buf, todo.ns, 0, -1, { details = true, type = kind })
end
ui.setup({ todo = true })
t.eq(2, #marks("sign"))
t.eq("✓ ", marks("sign")[1][4].sign_text)
t.eq("! ", marks("sign")[2][4].sign_text)
t.eq(6, #marks("highlight"))
local matches = todo.scan("中文 TODO(lzx): next FIXME: fix")
t.eq(2, #matches)
t.eq(7, matches[1].col)
t.eq("TODO", matches[1].keyword)
t.eq("FIX", matches[2].keyword)
t.eq({}, todo.scan("MYTODO: TODO_without_colon todo: TODO(unclosed:"))
local tick = vim.api.nvim_buf_get_changedtick(buf)
todo.refresh()
t.eq(tick, vim.api.nvim_buf_get_changedtick(buf))
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "-- ordinary comment" })
assert(vim.wait(200, function()
  return #marks("sign") == 1
end))
ui.toggle("todo")
t.eq({}, marks())
ui.toggle("todo")
t.eq(1, #marks("sign"))
ui.setup({ todo = { comments_only = false, signs = false, after = false, style = "foreground" } })
t.eq({}, marks("sign"))
t.eq(3, #marks("highlight"))
ui.setup({
  todo = {
    keywords = {
      NOTE = false,
      SECURITY = { icon = "!", hl = "DiagnosticError", rank = 100, alt = { "SEC" } },
    },
  },
})
t.eq({}, todo.scan("NOTE: ignored INFO: ignored"))
t.eq("SECURITY", todo.scan("SEC: audit")[1].keyword)
vim.bo.filetype = "text"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "TODO: prose" })
todo.refresh()
t.eq(1, #marks("sign"))
vim.b[buf].ui_tools_disable = true
todo.refresh()
t.eq({}, marks())
vim.b[buf].ui_tools_disable = nil
ui.setup({ todo = true })
todo.queue()
ui.disable()
vim.wait(80)
t.eq({}, marks())
assert(not pcall(ui.setup, { todo = { keywords = { BAD = { icon = "XX", hl = "Special", rank = 1 } } } }))
ui.disable()
print(
  "todo: syntax filtering, aliases/owners, Unicode, signs, multiple tags, custom keywords and lifecycle passed"
)
