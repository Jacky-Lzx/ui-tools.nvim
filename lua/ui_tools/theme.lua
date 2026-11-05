-- Optional palette subscriptions. Never load theme-tools as a side effect of UI setup.
local M = {}
local bindings = {}

-- Public groups belong to the colorscheme/user; only private defaults are ours.
-- Stable links also survive theme preview snapshots and exact restoration.
function M.define(name, value, fallback)
  local api = vim.api
  local target = "UiToolsDefault" .. name:sub(#"UiTools" + 1)
  local function empty(group)
    return vim.tbl_isempty(api.nvim_get_hl(0, { name = group, link = true, create = false }))
  end
  if not fallback or empty(target) then
    local definition = vim.deepcopy(value)
    definition.default = nil
    api.nvim_set_hl(0, target, definition)
  end
  -- default=true alone can skip an explicitly cleared group after rollback.
  api.nvim_set_hl(0, name, { link = target, default = not empty(name) })
end

function M.unbind(id)
  local entry = bindings[id]
  if entry then
    if entry.stop then
      entry.stop()
    end
    vim.api.nvim_del_augroup_by_id(entry.group)
    bindings[id] = nil
  end
end

function M.bind(id, callback)
  M.unbind(id)
  local entry = { group = require("ui_tools.util").group("Theme" .. id) }
  bindings[id] = entry
  local function attach()
    if entry.stop then
      return true
    end
    local themes = package.loaded.theme_tools
    if type(themes) == "table" and type(themes.on_change) == "function" then
      entry.stop = themes.on_change("ui-tools:" .. id, callback)
      return true
    end
    return false
  end
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = entry.group,
    callback = function()
      if not attach() then
        callback(nil)
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = entry.group,
    pattern = "ThemeToolsReady",
    callback = attach,
  })
  if not attach() then
    callback(nil)
  end
end

return M
