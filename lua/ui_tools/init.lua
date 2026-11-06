local M = {}
local modules = {
  "animate",
  "scroll",
  "dashboard",
  "fold",
  "bufferline",
  "statusline",
  "winbar",
  "context_menu",
  "indent",
  "statuscolumn",
  "guide",
  "feedback",
  "focus",
  "scrollbar",
  "colors",
  "todo",
}

local function highlights(c)
  if c then
    local groups = {
      UiToolsIndent = { fg = c.ui.subtle },
      UiToolsScope = { fg = c.ui.accent },
      UiToolsMark = { fg = c.ui.accent },
      UiToolsStatusSeparator = { fg = c.ui.border },
      UiToolsLineNr = { fg = c.ui.subtle },
      UiToolsCursorLineNr = { fg = c.ui.accent, bold = true },
      UiToolsFoldSeparator = { fg = c.ui.subtle },
      UiToolsFoldScope = { fg = c.ui.muted },
      UiToolsGuide = { fg = c.ui.subtle },
      UiToolsFlash = { fg = c.ui.selection_fg, bg = c.ui.selection_bg },
      UiToolsDim = { fg = c.ui.muted },
      UiToolsBackdrop = { fg = c.palette.bg, bg = c.palette.bg },
      UiToolsScrollbar = { bg = "NONE", blend = 100 },
      UiToolsScrollbarHandle = { fg = c.ui.selection_fg, bg = c.ui.selection_bg, blend = 0 },
      UiToolsScrollbarCursor = { fg = c.ui.accent },
      UiToolsSearch = { fg = c.palette.purple },
      UiToolsDashboardHeader = { fg = c.ui.accent },
      UiToolsDashboardDesc = { fg = c.ui.fg },
      UiToolsDashboardIcon = { fg = c.diagnostic.hint },
      UiToolsDashboardKey = { fg = c.ui.accent },
      UiToolsDashboardFooter = { fg = c.ui.muted },
    }
    for name, value in pairs(groups) do
      require("ui_tools.theme").define(name, value)
    end
    return
  end
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
  assert(opts == nil or type(opts) == "table", "ui-tools: setup expects a table")
  opts = opts or {}
  local prepared = {}
  for _, name in ipairs(modules) do
    local value = opts[name]
    assert(
      value == nil or type(value) == "boolean" or type(value) == "table",
      name .. " must be a boolean or table"
    )
    if value == true or type(value) == "table" and value.enabled ~= false then
      local module = require("ui_tools." .. name)
      local config = type(value) == "table" and value or {}
      -- Validate every module before tearing down the live configuration. Keep
      -- the isolated results (including derived data) for initialization below.
      prepared[name] = module.resolve and { module.resolve(config) } or { vim.deepcopy(config) }
    end
  end
  assert(
    M.disable() ~= false,
    "ui-tools: cannot replace configuration while a modified focus buffer is blocked"
  )
  require("ui_tools.theme").bind("core", highlights)
  M.options = vim.deepcopy(opts)
  for _, name in ipairs(modules) do
    if prepared[name] then
      local module = require("ui_tools." .. name)
      local setup = module._setup or module.setup
      setup(unpack(prepared[name]))
    end
  end
end

function M.enable()
  return M.setup(M.options)
end

function M.dispose()
  if M.disable() == false then
    return false
  end
  M.options = nil
  return true
end

function M.disable()
  -- A blocked focus buffer must be detected before changing the other modules.
  local focus = package.loaded["ui_tools.focus"]
  if focus and focus.disable() == false then
    return false
  end
  for _, name in ipairs(modules) do
    local module = package.loaded["ui_tools." .. name]
    if module and name ~= "focus" then
      if module.disable() == false then
        return false
      end
    end
  end
  require("ui_tools.theme").unbind("core")
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
