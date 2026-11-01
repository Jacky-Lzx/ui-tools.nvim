local t = dofile("tests/helpers.lua")
local ui = require("ui_tools")
local buf = t.buffer({ "one", "two", "three", "four" })
local win = vim.api.nvim_get_current_win()
vim.wo.number = true
vim.wo.statuscolumn = "%l original"
ui.setup({ statuscolumn = true })
t.eq("%l original", vim.wo.statuscolumn)
ui.setup({ statuscolumn = { force = true } })
assert(vim.wo.statuscolumn:find("ui_tools", 1, true))
local sign_ns = vim.api.nvim_create_namespace("DiagnosticTest")
local git_ns = vim.api.nvim_create_namespace("GitToolsTest")
vim.api.nvim_buf_set_extmark(buf, sign_ns, 1, 0, { sign_text = "E", sign_hl_group = "Error", priority = 20 })
vim.api.nvim_buf_set_extmark(
  buf,
  sign_ns,
  1,
  0,
  { sign_text = "W", sign_hl_group = "WarningMsg", priority = 10 }
)
vim.api.nvim_buf_set_extmark(buf, git_ns, 1, 0, { sign_text = "+", sign_hl_group = "DiffAdd" })
vim.api.nvim_buf_set_mark(buf, "a", 2, 0, {})
local number_ns = vim.api.nvim_create_namespace("NumberHighlightOnly")
vim.api.nvim_buf_set_extmark(buf, number_ns, 1, 0, { number_hl_group = "Error", priority = 1000 })
local stc = require("ui_tools.statuscolumn")
stc.refresh()
t.eq("E ", stc.cache[win][2].sign.sign_text)
t.eq("+ ", stc.cache[win][2].git.sign_text)
t.eq("a", stc.cache[win][2].mark)
t.eq(1, stc.widths[win][1])
vim.cmd("vsplit")
local inherited = vim.api.nvim_get_current_win()
stc.refresh()
assert(stc.windows[inherited] ~= nil, "Inherited formats must be adopted")
t.eq("E ", stc.cache[inherited][2].sign.sign_text)
ui.disable()
t.eq("", vim.wo[inherited].statuscolumn)
vim.api.nvim_set_current_win(win)
t.eq("%l original", vim.wo.statuscolumn)
ui.setup({ statuscolumn = { force = true } })
vim.wo.statuscolumn = "external"
ui.disable()
t.eq("external", vim.wo.statuscolumn)
ui.setup({ statuscolumn = { force = true } })
vim.bo.buftype = "nofile"
stc.refresh()
t.eq("external", vim.wo.statuscolumn)
ui.disable()
print("statuscolumn: sign priority, Git classification, marks, ownership and exclusions passed")
