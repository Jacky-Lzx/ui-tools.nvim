local M = {}
local modules = { "indent", "statuscolumn" }

local function highlights()
  require("ui_tools.util").hl({
    UiToolsIndent = "Whitespace",
    UiToolsScope = "Special",
    UiToolsMark = "Special",
  })
end

function M.setup(opts)
  assert(vim.fn.has("nvim-0.11") == 1, "ui-tools.nvim requires Neovim 0.11+")
  opts = opts or {}
  M.disable()
  highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = require("ui_tools.util").group("Highlights"),
    callback = highlights,
  })
  M.options = vim.deepcopy(opts)
  for _, name in ipairs(modules) do
    local config = opts[name]
    if config == true or type(config) == "table" and config.enabled ~= false then
      require("ui_tools." .. name).setup(type(config) == "table" and config or {})
    end
  end
end

function M.disable()
  for _, name in ipairs(modules) do
    local module = package.loaded["ui_tools." .. name]
    if module then
      module.disable()
    end
  end
  pcall(vim.api.nvim_del_augroup_by_name, "UiToolsHighlights")
end

function M.toggle(name)
  assert(vim.tbl_contains(modules, name), "Unknown UI module: " .. tostring(name))
  local module = require("ui_tools." .. name)
  -- Each module reports its live enabled state through the shared provider.
  if module.enabled or require("ui_tools.render").sources[name] then
    module.disable()
  else
    local opts = M.options and M.options[name]
    module.setup(type(opts) == "table" and opts or {})
  end
end

return M
