local M = {}
local modules =
  { "dashboard", "context_menu", "indent", "statuscolumn", "guide", "feedback", "focus", "scrollbar" }

local function highlights()
  require("ui_tools.util").hl({
    UiToolsIndent = "Whitespace",
    UiToolsScope = "Special",
    UiToolsMark = "Special",
    UiToolsStatusSeparator = "WinSeparator",
    UiToolsLineNr = "LineNr",
    UiToolsCursorLineNr = "CursorLineNr",
    UiToolsFoldSeparator = "LineNr",
    UiToolsFoldScope = "FoldColumn",
    UiToolsGuide = "NonText",
    UiToolsFlash = "Visual",
    UiToolsDim = "Comment",
    UiToolsBackdrop = "NormalFloat",
    UiToolsScrollbar = "NormalFloat",
    UiToolsScrollbarHandle = "Visual",
    UiToolsScrollbarCursor = "Special",
    UiToolsSearch = "Search",
    UiToolsDashboardHeader = "Title",
    UiToolsDashboardDesc = "Function",
    UiToolsDashboardIcon = "DiagnosticHint",
    UiToolsDashboardKey = "Special",
    UiToolsDashboardFooter = "Comment",
  })
end

function M.setup(opts)
  assert(vim.fn.has("nvim-0.11") == 1, "ui-tools.nvim requires Neovim 0.11+")
  opts = opts or {}
  assert(
    M.disable() ~= false,
    "ui-tools: cannot replace configuration while a modified focus buffer is blocked"
  )
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
      if module.disable() == false then
        return false
      end
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

function M.flash(opts)
  return require("ui_tools.feedback").flash(opts)
end

function M.pulse(opts)
  return M.flash(opts)
end

function M.zen(opts)
  return require("ui_tools.focus").open("zen", opts)
end

function M.zoom(opts)
  return require("ui_tools.focus").open("zoom", opts)
end

function M.dim(value)
  return require("ui_tools.focus").dim(value)
end

function M.menu(opts)
  return require("ui_tools.context_menu").open(opts)
end

function M.dashboard(opts)
  return require("ui_tools.dashboard").open(opts)
end

return M
