local t = dofile("tests/helpers.lua")
local root = vim.env.THEME_TOOLS_DIR or vim.fn.fnamemodify(vim.fn.getcwd(), ":h") .. "/theme-tools.nvim"
if vim.fn.isdirectory(root) == 0 then
  print("SKIP optional theme-tools ownership tests")
  return
end
vim.opt.rtp:append(root)
local api = vim.api
local themes, ui = require("theme_tools"), require("ui_tools")
local colors = require("theme_tools.colors")
local opts = { statusline = { force = true }, bufferline = { force = true, auto_hide = -1 }, winbar = true }
themes.setup({
  persist = false,
  catppuccin = false,
  dracula = false,
  icons = { default = "none" },
  default = "theme-tools-mocha",
  themes = { "theme-tools-mocha", "theme-tools-dracula", "habamax" },
})
local function hl(name)
  return api.nvim_get_hl(0, { name = name, link = false })
end
local function personal()
  t.eq(0xf2cdcd, hl("UiToolsScope").fg)
  t.eq(0x585b70, hl("UiToolsLineNr").fg)
  t.eq(0xb4befe, hl("UiToolsCursorLineNr").fg)
  t.eq(0x000000, hl("UiToolsScrollbarHandle").bg)
end
ui.setup(opts)
personal()
-- Repeated setup and subscriber refresh must not overwrite generated definitions.
ui.setup(opts)
themes.refresh_palette()
personal()
local original = colors.snapshot()
assert(themes.set("theme-tools-dracula"))
local palette = themes.palette()
t.eq(tonumber(palette.ui.accent:sub(2), 16), hl("UiToolsScope").fg)
assert(hl("UiToolsScope").fg ~= 0xf2cdcd, "old explicit overrides leaked to the next theme")
colors.restore(original)
personal()
local group = api.nvim_create_augroup("TestUiToolsOverrides", { clear = true })
api.nvim_create_autocmd("ColorScheme", {
  group = group,
  pattern = "habamax",
  callback = function()
    api.nvim_set_hl(0, "UiToolsScope", { fg = "#112233", bold = true })
    api.nvim_set_hl(0, "UiToolsBufferCurrent", { fg = "#223344", bg = "#334455" })
    api.nvim_set_hl(0, "UiToolsStatusNormal", { fg = "#445566", bg = "#556677" })
    api.nvim_set_hl(0, "UiToolsWinbarFile", { fg = "#667788", bg = "#778899" })
  end,
})
assert(themes.set("habamax"))
local function explicit()
  t.eq(0x112233, hl("UiToolsScope").fg)
  assert(hl("UiToolsScope").bold)
  t.eq(0x334455, hl("UiToolsBufferCurrent").bg)
  t.eq(0x556677, hl("UiToolsStatusNormal").bg)
  t.eq(0x778899, hl("UiToolsWinbarFile").bg)
end
explicit()
ui.setup(opts)
themes.refresh_palette()
explicit()
original = colors.snapshot()
assert(colors.apply({ colorscheme = "theme-tools-dracula", background = "dark" }))
colors.restore(original)
explicit()
-- Manual user definitions and cleared snapshot entries also survive refresh.
api.nvim_set_hl(0, "UiToolsScope", { link = "DiagnosticWarn" })
themes.refresh_palette()
t.eq("DiagnosticWarn", api.nvim_get_hl(0, { name = "UiToolsScope" }).link)
api.nvim_set_hl(0, "UiToolsStatusAlt", {})
themes.refresh_palette()
assert(hl("UiToolsStatusAlt").bg, "cleared public group did not regain its default")
api.nvim_del_augroup_by_id(group)
assert(themes.set("theme-tools-dracula"))
t.eq(tonumber(themes.palette().ui.accent:sub(2), 16), hl("UiToolsScope").fg)
vim.cmd.colorscheme("theme-tools-mocha")
vim.wait(30)
personal()
ui.disable()
print(
  "theme ownership: personal colors, user overrides, fresh defaults, setup orders and preview rollback passed"
)
