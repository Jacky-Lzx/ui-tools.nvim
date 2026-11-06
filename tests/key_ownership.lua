local h = dofile("tests/helpers.lua")
local before = {}
for _, mode in ipairs({ "n", "x", "i" }) do
  before[mode] = vim.api.nvim_get_keymap(mode)
end
require("ui_tools").setup({ context_menu = true, scroll = true })
for mode, mappings in pairs(before) do
  h.eq(mappings, vim.api.nvim_get_keymap(mode), "UI setup must leave user keys alone")
end
require("ui_tools").disable()
print("UI entry keys remain user-owned")
