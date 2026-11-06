local M = { enabled = false, errors = {} }
local api = vim.api
local bar = require("ui_tools.bar")
local icons = require("ui_tools.icons")
local expression = "%!v:lua.require'ui_tools.winbar'.render()"
local owned, blocked, buffers, cache, client_dirty = {}, {}, {}, {}, {}
local queue
local profiles = {}

local function highlights(colors)
  local c = bar.colors(colors)
  local file_bg = bar.blend(c.bg, c.fg, 0.06)
  local groups = {
    WinBar = { fg = c.fg, bg = c.bg },
    WinBarNC = { fg = c.muted, bg = c.bg },
    UiToolsWinbarFile = { fg = c.fg, bg = file_bg, bold = true },
    UiToolsWinbarFileNC = { fg = c.muted, bg = c.bg },
    UiToolsWinbarIndicator = { fg = c.accent, bg = file_bg },
    UiToolsWinbarIndicatorNC = { fg = c.border, bg = c.bg },
    UiToolsWinbarSeparator = { fg = c.muted, bg = c.bg },
    UiToolsWinbarClient = { fg = c.muted, bg = c.bg },
  }
  for name, value in pairs(groups) do
    if name:match("^UiTools") then
      require("ui_tools.theme").define(name, value)
    else
      api.nvim_set_hl(0, name, value)
    end
  end
end

local function local_option(win)
  return api.nvim_get_option_value("winbar", { win = win, scope = "local" })
end

local function set_option(win, value)
  if (vim.wo[win].winbar == "") ~= (value == "") then
    bar.preserve_views(function()
      api.nvim_set_option_value("winbar", value, { win = win, scope = "local" })
    end)
  else
    api.nvim_set_option_value("winbar", value, { win = win, scope = "local" })
  end
end

local function release(win)
  if owned[win] ~= nil and api.nvim_win_is_valid(win) and local_option(win) == expression then
    set_option(win, owned[win])
  end
  owned[win], buffers[win], profiles[win], M.errors[win] = nil, nil, nil, nil
end

local function eligible(win, buf)
  local profile = bar.profile(buf, "winbar", M.options)
  return api.nvim_win_get_config(win).relative == ""
    and profile ~= false
    and (profile ~= nil or vim.bo[buf].buftype == "" and not vim.tbl_contains(
      M.options.exclude,
      vim.bo[buf].filetype
    ))
    and vim.b[buf].ui_tools_disable ~= true
end

local function update()
  if not M.enabled or require("ui_tools.util").searching() then
    return
  end
  local used, icon_colors = {}, {}
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local suitable = eligible(win, buf)
    if not suitable then
      release(win)
    elseif owned[win] ~= nil and local_option(win) ~= expression then
      -- Native buffer switches may restore an empty window-local option.
      -- A deliberate change in the same buffer transfers ownership instead.
      if buffers[win] == buf or vim.wo[win].winbar ~= "" then
        owned[win], buffers[win], blocked[win] = nil, nil, true
      end
    end
    if
      suitable
      and not blocked[win]
      and (
        owned[win] ~= nil
        or vim.wo[win].winbar == ""
        or local_option(win) == expression
        or M.options.force
      )
    then
      local profile = bar.profile(buf, "winbar", M.options)
      profiles[win] = nil
      if profile ~= nil then
        local active = win == api.nvim_get_current_win()
        local ok, result = pcall(api.nvim_win_call, win, function()
          return bar.profile_text(profile, {
            win = win,
            buf = buf,
            width = api.nvim_win_get_width(win),
            cursor = api.nvim_win_get_cursor(win),
            active = active,
            filetype = vim.bo[buf].filetype,
          })
        end)
        M.errors[win] = not ok and tostring(result) or nil
        profiles[win] = ok and result or { text = "", align = "left" }
      else
        M.errors[win] = nil
        local data = cache[buf]
        if not data or client_dirty[buf] then
          local clients, seen = {}, {}
          if M.options.lsp then
            for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
              if not seen[client.name] then
                clients[#clients + 1], seen[client.name] = client.name, true
              end
            end
            table.sort(clients)
          end
          data = { clients = bar.text(table.concat(clients, ", ")) }
          cache[buf] = data
          client_dirty[buf] = nil
        end
        local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
        data.name = bar.text(name == "" and "[No Name]" or name)
        if not used[buf] then
          local icon, source = "", "Normal"
          if M.options.icons then
            icon, source = icons.prefix("file", name, "")
          end
          data.icon, data.icon_width = bar.escape(icon), bar.width(icon)
          data.icon_hl = bar.icon_highlight(source, "UiToolsWinbarFile", icon_colors)
          data.icon_hl_nc = bar.icon_highlight(source, "UiToolsWinbarFileNC", icon_colors)
          data.client_icon = M.options.icons and icons.prefix("ui", "lsp", "") or ""
        end
        used[buf] = true
      end
      if owned[win] == nil then
        local value = local_option(win)
        owned[win] = value == expression and "" or value
      end
      buffers[win] = buf
      -- Geometry changes can redraw immediately: populate the cache first.
      if local_option(win) ~= expression then
        set_option(win, expression)
      end
    end
  end
  for win in pairs(owned) do
    if not api.nvim_win_is_valid(win) then
      release(win)
    end
  end
  for win in pairs(blocked) do
    if not api.nvim_win_is_valid(win) then
      blocked[win] = nil
    end
  end
  for buf in pairs(cache) do
    if not used[buf] then
      cache[buf] = nil
    end
  end
  client_dirty = {}
  if vim.v.vim_did_enter == 1 then
    vim.cmd("redrawstatus")
  end
end

function M.render()
  local win = tonumber(vim.g.statusline_winid) or api.nvim_get_current_win()
  if not M.enabled or not api.nvim_win_is_valid(win) or owned[win] == nil then
    return " "
  end
  local buf = api.nvim_win_get_buf(win)
  if profiles[win] and buffers[win] == buf then
    return bar.render_profile(
      profiles[win],
      api.nvim_win_get_width(win),
      win == api.nvim_get_current_win() and "WinBar" or "WinBarNC"
    )
  end
  local data = cache[buf]
  if not data or buffers[win] ~= buf then
    return " "
  end
  local width, crumbs = api.nvim_win_get_width(win), ""
  if M.options.breadcrumbs then
    -- The provider returns native statusline syntax and reads its own cache.
    -- Pass the target explicitly: inactive splits have independent cursors.
    local ok, result = pcall(M.options.breadcrumbs, {
      win = win,
      buf = buf,
      width = width,
      cursor = api.nvim_win_get_cursor(win),
    })
    M.errors[win] = not ok and tostring(result) or nil
    if ok then
      crumbs = bar.text(result)
    end
  end
  local active = win == api.nvim_get_current_win()
  local base = active and "WinBar" or "WinBarNC"
  local state = active and "" or "NC"
  local result = { "%#" .. base .. "#" }
  if M.options.filename then
    local budget = math.max(1, math.floor(width * M.options.filename_width))
    local overhead = bar.width(M.options.indicator) + data.icon_width + 2
    if crumbs ~= "" then
      local content_width = width - overhead - bar.width(M.options.separator) - 2
      budget = math.max(1, math.floor(content_width * M.options.filename_width))
    end
    if width > overhead + 1 then
      budget = math.min(budget, width - overhead)
      result[#result + 1] = bar.label(M.options.indicator, "UiToolsWinbarIndicator" .. state)
      result[#result + 1] = "%#UiToolsWinbarFile"
        .. state
        .. "# "
        .. "%#"
        .. (active and data.icon_hl or data.icon_hl_nc)
        .. "#"
        .. data.icon
        .. bar.label(bar.truncate(data.name, budget) .. " ", "UiToolsWinbarFile" .. state)
    else
      result[#result + 1] = bar.label(bar.truncate(data.name, budget), "UiToolsWinbarFile" .. state)
    end
  end
  result[#result + 1] = "%#" .. base .. "#%<"
  if crumbs ~= "" then
    if M.options.filename then
      result[#result + 1] = bar.label(" " .. M.options.separator .. " ", "UiToolsWinbarSeparator")
    end
    result[#result + 1] = crumbs
  end
  result[#result + 1] = "%#" .. base .. "#%="
  -- Client badges yield space to the file and breadcrumbs in narrow splits.
  if data.clients ~= "" and width >= 60 then
    local clients = bar.truncate(data.client_icon .. data.clients, math.floor(width * 0.35))
    result[#result + 1] = bar.label(" │ " .. clients .. " ", "UiToolsWinbarClient")
  end
  return table.concat(result)
end

function M.refresh()
  if not M.enabled then
    return
  end
  for buf in pairs(cache) do
    client_dirty[buf] = true
  end
  update()
end

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "winbar options must be a table")
  opts = vim.deepcopy(opts or {})
  local config = vim.tbl_deep_extend("force", {
    refresh = 30,
    force = false,
    filename = true,
    filename_width = 0.45,
    icons = true,
    indicator = "▎",
    separator = "›",
    filetypes = {},
    lsp = true,
    exclude = { "ui_tools_dashboard" },
  }, opts or {})
  assert(type(config.refresh) == "number" and config.refresh >= 0, "winbar.refresh must be nonnegative")
  assert(type(config.force) == "boolean", "winbar.force must be boolean")
  assert(type(config.filename) == "boolean", "winbar.filename must be boolean")
  assert(type(config.lsp) == "boolean", "winbar.lsp must be boolean")
  assert(type(config.icons) == "boolean", "winbar.icons must be boolean")
  assert(
    type(config.indicator) == "string" and type(config.separator) == "string",
    "winbar markers must be strings"
  )
  config.indicator, config.separator = bar.text(config.indicator), bar.text(config.separator)
  assert(
    type(config.filename_width) == "number" and config.filename_width > 0 and config.filename_width <= 1,
    "winbar.filename_width must be in (0, 1]"
  )
  assert(
    config.breadcrumbs == nil or type(config.breadcrumbs) == "function",
    "winbar.breadcrumbs must be a function"
  )
  local custom = bar.validate_profiles(config.filetypes)
  return config, custom
end

function M.setup(opts)
  local resolved, derived = M.resolve(opts)
  M.disable()
  M.options = resolved
  local custom = derived
  M.enabled = true
  queue = bar.scheduler(M.options.refresh, update)
  require("ui_tools.theme").bind("winbar", function(c)
    highlights(c)
    queue.request()
  end)
  local group = require("ui_tools.util").group("Winbar")
  api.nvim_create_autocmd({ "BufWinEnter", "BufFilePost", "WinEnter", "TabEnter", "FileType" }, {
    group = group,
    callback = function()
      -- Scratch FileType handlers and non-entering floats can temporarily
      -- select an autocmd window. Wait until the real editing window returns.
      if vim.fn.win_gettype() == "autocmd" or api.nvim_win_get_config(0).relative ~= "" then
        queue.request()
      else
        update()
      end
    end,
  })
  api.nvim_create_autocmd({ "WinClosed", "VimResized", "WinResized", "ColorScheme", "CmdlineLeave" }, {
    group = group,
    callback = function()
      queue.request()
    end,
  })
  api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    group = group,
    callback = function(args)
      client_dirty[args.buf] = true
      queue.request()
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "ThemeToolsIconsChanged", "ThemeToolsReady" },
    callback = function()
      queue.request()
    end,
  })
  if custom then
    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
      group = group,
      callback = function()
        queue.request()
      end,
    })
  end
  update()
end

function M.disable()
  M.enabled = false
  if queue then
    queue.cancel()
    queue = nil
  end
  pcall(api.nvim_del_augroup_by_name, "UiToolsWinbar")
  require("ui_tools.theme").unbind("winbar")
  for win in pairs(owned) do
    release(win)
  end
  owned, blocked, buffers, cache, client_dirty, profiles, M.errors = {}, {}, {}, {}, {}, {}, {}
end

return M
