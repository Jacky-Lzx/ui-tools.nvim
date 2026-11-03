local t = dofile("tests/helpers.lua")
local ui = require("ui_tools")
local dashboard = require("ui_tools.dashboard")
local layout = require("ui_tools.dashboard_layout")
local art = table.concat(
  { "+------------------+", "|   /\\     /\\     |", "|  (  o   o  )     |", "+------------------+" },
  "\n"
)
local items = {
  { key = "f", desc = "Find File" },
  { key = "n", desc = "新建文件" },
  { key = "q", desc = "Quit" },
}
for _, position in ipairs({ "vertical", "horizontal" }) do
  for _, size in ipairs({ { 100, 30 }, { 40, 12 }, { 20, 8 }, { 12, 6 }, { 5, 4 }, { 1, 1 } }) do
    local result = layout.build(
      { layout = position, width = 28, gap = 2, header = art, footer = "ready" },
      items,
      size[1],
      size[2]
    )
    assert(#result.lines <= math.max(size[2], #items))
    for _, line in ipairs(result.lines) do
      assert(vim.fn.strdisplaywidth(line) <= size[1], vim.inspect({ size, line }))
    end
    for _, mark in ipairs(result.marks) do
      assert(mark[2] <= mark[3] and mark[3] <= #result.lines[mark[1] + 1])
    end
    if size[1] >= 12 and size[2] >= 6 then
      assert(result.header_height > 0, "Art must shrink instead of disappearing")
    end
    t.eq(#items, #result.rows)
  end
end
local side =
  layout.build({ layout = "horizontal", width = 28, gap = 2, header = art, footer = false }, items, 100, 30)
assert(side.lines[side.rows[2]]:find("|", 1, true) < side.lines[side.rows[2]]:find("新建文件", 1, true))
local above =
  layout.build({ layout = "vertical", width = 28, gap = 2, header = art, footer = false }, items, 100, 30)
assert(above.rows[1] > 4)
assert(not pcall(ui.dashboard, { layout = "invalid" }))
local source = t.buffer({ "unsaved work" })
vim.bo[source].modified = true
vim.o.hidden = false
assert(not pcall(ui.dashboard), "Opening must respect modified-buffer protection")
t.eq(source, vim.api.nvim_get_current_buf())
vim.o.hidden = true
vim.wo.number = true
vim.wo.wrap = true
vim.wo.cursorline = true
vim.wo.colorcolumn = "80"
ui.setup({ dashboard = { autostart = false, header = "中文 header", keys = {} } })
local buf = ui.dashboard()
assert(buf ~= source)
t.eq("ui_tools_dashboard", vim.bo[buf].filetype)
t.eq(false, vim.bo[buf].modifiable)
t.eq(false, vim.bo[buf].buflisted)
t.eq(false, vim.wo.number)
t.eq(false, vim.wo.cursorline)
t.eq("", vim.wo.colorcolumn)
dashboard.close()
t.eq(source, vim.api.nvim_get_current_buf())
t.eq({ "unsaved work" }, vim.api.nvim_buf_get_lines(source, 0, -1, false))
t.eq(true, vim.bo[source].modified)
t.eq(true, vim.wo.number)
t.eq(true, vim.wo.wrap)
t.eq(true, vim.wo.cursorline)
t.eq("80", vim.wo.colorcolumn)
t.eq(false, vim.api.nvim_buf_is_valid(buf))

ui.dashboard()
vim.wo.wrap = true -- A later owner wins over restoration.
vim.cmd("enew")
t.eq(nil, dashboard.state())
t.eq(true, vim.wo.number)
t.eq(true, vim.wo.wrap)
assert(vim.api.nvim_buf_is_valid(source))

ui.dashboard()
local old = dashboard.state().buf
ui.setup({ dashboard = { autostart = false } })
t.eq(false, vim.api.nvim_buf_is_valid(old))
assert(dashboard.enabled)
ui.toggle("dashboard")
t.eq(false, dashboard.enabled)
ui.toggle("dashboard")
t.eq(true, dashboard.enabled)
ui.disable()
t.eq(nil, dashboard.state())
t.eq(0, #vim.api.nvim_get_autocmds({ group = vim.api.nvim_create_augroup("UiToolsDashboard", {}) }))
print("dashboard lifecycle and unsaved-buffer checks passed")
