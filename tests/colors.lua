local t = dofile("tests/helpers.lua")
local color = require("ui_tools.color")
for input, expected in pairs({
  ["#abc"] = "#aabbcc",
  ["#aBcD"] = "#aabbcc",
  ["0x123456"] = "#123456",
  ["rgb(255, 0, 128)"] = "#ff0080",
  ["rgba(100% 0% 50% / 25%)"] = "#ff0080",
  ["hsl(120,100%,50%)"] = "#00ff00",
  ["hsla(.5turn 100% 50% / .5)"] = "#00ffff",
  ["hsl(-120deg 100% 50%)"] = "#0000ff",
  ["hsl(400grad 100% 50%)"] = "#ff0000",
  ["rebeccapurple"] = "#663399",
  ["green"] = "#008000",
  ["gray"] = "#808080",
  ["RGB(300 -1 0)"] = "#ff0000",
}) do
  t.eq(expected, assert(color.parse(input), input).hex)
end
for _, invalid in ipairs({
  "#ab",
  "#12345",
  "#123456789",
  "rgb(1,2)",
  "rgb(1,,2,3)",
  "rgb(1,2,3 / .5)",
  "rgb(1 2 3 / nope)",
  "rgb(1 2 3 / .5 / .5)",
  "rgba(1,2,3,bad)",
  "hsl(0 1 1)",
  "hsl(2foo 50% 50%)",
  "none",
  "0xabc",
  "rgb(1 2 3 .5)",
}) do
  t.eq(nil, color.parse(invalid))
end
t.eq(0, color.parse("transparent").alpha)
t.eq(0, color.parse("#abcdef00").alpha)
t.eq(0xdd / 255, color.parse("#abcd").alpha)
t.eq("#800080", color.blend(color.parse("rgba(255 0 0 / .5)"), "#0000ff"))
local source = "中文 #abc #12345678 rgb(255 0 0 / .5) rebeccapurple"
local matches = color.scan(source)
t.eq(4, #matches)
t.eq(7, matches[1].col)
t.eq("#abc", source:sub(matches[1].col + 1, matches[1].end_col))
for _, invalid in ipairs({ "a#abc", "#abcdefg", "#123456789", "0xabcde", "redwood", "--red", "bg-red-500" }) do
  t.eq({}, color.scan(invalid))
end
t.eq({}, color.scan("red green", { names = false }))
t.eq("#123456", color.scan("accent", { names = false, custom = { accent = "#123456" } })[1].hex)
local ui, colors = require("ui_tools"), require("ui_tools.colors")
local buf = t.buffer({ "#ff0000", string.rep("x", 5000), "#abc" })
vim.wo.wrap = false
local tick = vim.api.nvim_buf_get_changedtick(buf)
local function marks()
  return vim.api.nvim_buf_get_extmarks(buf, colors.ns, 0, -1, { details = true })
end
ui.setup({ colors = true })
t.eq(2, #marks())
t.eq("inline", marks()[1][4].virt_text_pos)
t.eq(tick, vim.api.nvim_buf_get_changedtick(buf))
ui.toggle("colors")
t.eq({}, marks())
ui.toggle("colors")
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "nothing" })
assert(
  vim.wait(200, function()
    return #marks() == 1
  end),
  "buffer API edits were not refreshed"
)
ui.setup({ colors = { style = "background", names = false } })
t.eq(4, marks()[1][4].end_col)
vim.b[buf].ui_tools_disable = true
colors.refresh()
t.eq({}, marks())
vim.b[buf].ui_tools_disable = nil
ui.setup({})
t.eq(false, colors.enabled)
t.eq({}, marks())
assert(not pcall(ui.setup, { colors = { style = "bad" } }))
ui.disable()
print("colors: formats, alpha, boundaries, byte ranges, opt-in, live edits and lifecycle passed")
