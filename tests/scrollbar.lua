local t = dofile("tests/helpers.lua")
local ui = require("ui_tools")
local bar = require("ui_tools.scrollbar")
t.eq(1, bar.project(1, 100, 10))
t.eq(10, bar.project(100, 100, 10))
t.eq(1, bar.project(100, 1, 10))
local lines = {}
for i = 1, 200 do
  lines[i] = "line " .. i
end
local buf = t.buffer(lines)
local source = vim.api.nvim_get_current_win()
local remove = bar.register("custom", function()
  return { { line = 100, char = "!", hl = "Error", priority = 200 } }
end)
ui.setup({ scrollbar = { search = false } })
bar.refresh()
assert(next(bar.errors) == nil, vim.inspect(bar.errors))
assert(bar.bars[source])
local rendered = vim.api.nvim_buf_get_lines(bar.bars[source].buf, 0, -1, false)
assert(vim.tbl_contains(rendered, "!"))
local failed = bar.register("broken", function()
  error("isolated failure")
end)
bar.refresh()
assert(bar.errors.broken:find("isolated failure", 1, true))
failed()
remove()
bar.refresh()
assert(not vim.tbl_contains(vim.api.nvim_buf_get_lines(bar.bars[source].buf, 0, -1, false), "!"))
local missing = require("ui_tools.integrations.git_tools").setup()
bar.refresh()
t.eq(nil, package.loaded["git_tools.buffer"])
package.loaded["git_tools.buffer"] = {
  get_hunks = function()
    return { { old_count = 0, new_start = 80, new_count = 20 } }
  end,
}
bar.refresh()
assert(vim.tbl_contains(vim.api.nvim_buf_get_lines(bar.bars[source].buf, 0, -1, false), "┃"))
missing()
package.loaded["git_tools.buffer"] = nil
ui.disable()
t.eq(nil, next(bar.bars))
ui.setup({ scrollbar = true })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "small" })
bar.refresh()
t.eq(nil, next(bar.bars))
ui.disable()
print("scrollbar: projection, providers, failure isolation, optional Git adapter and cleanup passed")
