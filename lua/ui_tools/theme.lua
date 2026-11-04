-- Optional palette subscriptions. Never load theme-tools as a side effect of UI setup.
local M = {}
local bindings = {}

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
