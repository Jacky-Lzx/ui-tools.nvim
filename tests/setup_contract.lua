vim.opt.rtp:prepend(vim.fn.getcwd())
local plugin = require("ui_tools")
local options = { guide = { columns = { 80 } }, statuscolumn = true, todo = true }
local caller = vim.deepcopy(options)
plugin.setup(options)
assert(vim.deep_equal(caller, options), "setup mutated caller configuration")
local commands = vim.api.nvim_get_commands({})
local handlers = vim.api.nvim_get_autocmds({})
assert(not pcall(plugin.setup, false), "setup(false) must reject an invalid configuration type")
assert(vim.deep_equal(commands, vim.api.nvim_get_commands({})), "Invalid setup replaced commands")
assert(vim.deep_equal(handlers, vim.api.nvim_get_autocmds({})), "Invalid setup replaced handlers")
plugin.setup(caller)
assert(#vim.api.nvim_get_autocmds({}) == #handlers, "Repeated setup duplicated automatic handlers")
print("ui-tools.nvim: setup input isolation, invalid configuration and registration lifetime passed")

options.guide.columns[1] = 120
assert(require("ui_tools.guide").options.columns[1] == 80)
for _, invalid in ipairs({
  { guide = { columns = { -1 } } },
  { indent = { char = "ab" } },
  { fold = { method = "wrong" } },
  { statusline = { refresh = -1 } },
  { statuscolumn = { layout = { "wrong" } } },
  { todo = { keywords = { BAD = { icon = "xx", rank = 1, hl = "Todo" } } } },
  { colors = { refresh = -1 } },
  { winbar = { filename_width = 2 } },
  { focus = { width = -1 } },
  { dashboard = { layout = "wrong" } },
}) do
  local before = vim.api.nvim_get_autocmds({})
  assert(not pcall(plugin.setup, invalid))
  assert(
    vim.deep_equal(before, vim.api.nvim_get_autocmds({})),
    "Invalid module setup replaced live observers"
  )
  assert(require("ui_tools.guide").options.columns[1] == 80)
end
plugin.disable()
plugin.enable()
assert(require("ui_tools.guide").options.columns[1] == 80)
assert(plugin.dispose())
assert(plugin.dispose())
assert(plugin.options == nil)
plugin.setup(caller)
assert(plugin.dispose())
