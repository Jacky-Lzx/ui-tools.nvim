local t = dofile("tests/helpers.lua")
local root = vim.env.THEME_TOOLS_DIR or vim.fn.fnamemodify(vim.fn.getcwd(), ":h") .. "/theme-tools.nvim"
if vim.fn.isdirectory(root) == 0 then
  print("SKIP optional theme-tools integration (set THEME_TOOLS_DIR)")
  return
end
vim.opt.rtp:append(root)
local ui = require("ui_tools")
local api = vim.api
local opts = { statusline = { force = true }, bufferline = { force = true, auto_hide = -1 }, winbar = true }
ui.setup(opts)
assert(not package.loaded.theme_tools, "UI setup eagerly loaded its optional theme provider")
local themes = require("theme_tools")
local config = {
  persist = false,
  catppuccin = false,
  dracula = false,
  default = "theme-tools-mocha",
  themes = { "theme-tools-mocha", "morning", "desert" },
  icons = { default = "ascii" },
}
local function rgb(value)
  return value == "NONE" and nil or tonumber(value:sub(2), 16)
end
local function check()
  local c = themes.palette()
  t.eq(rgb(c.ui.border), api.nvim_get_hl(0, { name = "UiToolsStatusSeparator", link = false }).fg)
  t.eq(rgb(c.ui.accent), api.nvim_get_hl(0, { name = "UiToolsStatusNormal", link = false }).bg)
  local status_bg = api.nvim_get_hl(0, { name = "UiToolsStatus", link = false }).bg
  t.eq(rgb(c.ui.bg ~= "NONE" and c.ui.bg or c.palette.bg), status_bg)
  assert(status_bg ~= api.nvim_get_hl(0, { name = "UiToolsStatusAlt", link = false }).bg)
  local recording = api.nvim_get_hl(0, { name = "UiToolsStatusRecording", link = false })
  t.eq(rgb(c.diagnostic.error), recording.fg)
  t.eq(require("ui_tools.bar").blend(status_bg, c.diagnostic.error, 0.12), recording.bg)
  assert(recording.bold)
  t.eq(rgb(c.ui.selection_bg), api.nvim_get_hl(0, { name = "UiToolsBufferCurrent", link = false }).bg)
  t.eq(
    rgb(c.ui.bg ~= "NONE" and c.ui.bg or c.palette.bg),
    api.nvim_get_hl(0, { name = "WinBar", link = false }).bg
  )
end
-- The UI was configured before theme-tools; ColorScheme/Ready must attach it.
themes.setup(config)
check()
assert(themes.set("morning"))
check()
vim.cmd.colorscheme("desert")
vim.wait(20)
check()
-- Theme configuration before UI setup and repeated setup must work too.
config.palette = { overrides = { ui = { accent = "#123456", border = "#654321" } } }
themes.setup(config)
ui.setup(opts)
check()
local before = api.nvim_get_hl(0, { name = "UiToolsStatusNormal", link = false })
ui.disable()
assert(themes.set("morning"))
assert(
  vim.tbl_isempty(api.nvim_get_hl(0, { name = "UiToolsStatusNormal", create = false })),
  "disabled UI kept its subscription"
)
assert(before.bg == 0x123456)
ui.setup(opts)
check()
local line = require("ui_tools.statusline")
assert(line.render():find("? NORMAL", 1, true), line.render())
assert(themes.icons.set("none"))
vim.wait(60)
assert(not line.render():find("? NORMAL", 1, true), line.render())
assert(themes.icons.set("ascii"))
vim.wait(60)
assert(line.render():find("? NORMAL", 1, true), line.render())
-- Rendering must use cached highlights, never resolve the palette itself.
local get = themes.palette
themes.palette = function()
  error("palette resolution during redraw")
end
require("ui_tools.statusline").render()
require("ui_tools.bufferline").render()
themes.palette = get
ui.disable()
print(
  "theme-tools: optional loading, both setup orders, shared highlights, overrides, external changes and unsubscribe passed"
)
