local M = { enabled = false }
local api = vim.api
local ns = api.nvim_create_namespace("UiToolsDashboard")
local active
local defaults = {
  autostart = true,
  width = 60,
  layout = "vertical",
  gap = 2,
  header = "N E O V I M",
  keys = {
    { key = "n", desc = "New File", action = "enew | startinsert" },
    { key = "q", desc = "Quit", action = "qa" },
  },
  footer = function()
    return "Neovim " .. tostring(vim.version())
  end,
}
local window_options = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  statuscolumn = "",
  statusline = " ",
  cursorline = false,
  cursorcolumn = false,
  wrap = false,
  list = false,
  spell = false,
  winbar = "",
  colorcolumn = "",
  scrolloff = 0,
}

local function retire_startup_source(s)
  if not s.startup_source then
    return
  end
  -- BufWinLeave runs before the replacement is installed. Wait until the
  -- picker/file action (or close(), which restores the source) has completed.
  vim.schedule(function()
    local buf = s.source
    if
      not api.nvim_buf_is_valid(buf)
      or active and active.source == buf
      or api.nvim_buf_get_changedtick(buf) ~= s.source_tick
      or api.nvim_buf_get_name(buf) ~= ""
      or vim.bo[buf].buftype ~= ""
      or vim.bo[buf].modified
      or api.nvim_buf_line_count(buf) ~= 1
      or api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ""
    then
      return
    end
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == buf then
        return
      end
    end
    pcall(api.nvim_buf_delete, buf, { force = false })
  end)
end

local function release(s)
  if active ~= s then
    return
  end
  active = nil
  pcall(api.nvim_del_augroup_by_id, s.group)
  if vim.o.laststatus == 0 then
    vim.o.laststatus = s.laststatus
  end
  if not vim.o.ruler then
    vim.o.ruler = s.ruler
  end
  if api.nvim_win_is_valid(s.win) then
    for name, value in pairs(s.saved) do
      if vim.wo[s.win][name] == window_options[name] then
        vim.wo[s.win][name] = value
      end
    end
  end
  retire_startup_source(s)
end

local function select_item(s, index)
  if active == s and #s.items > 0 then
    s.selected = ((index - 1) % #s.items) + 1
    local position = { s.rows[s.selected], s.cols[s.selected] }
    if not vim.deep_equal(api.nvim_win_get_cursor(s.win), position) then
      api.nvim_win_set_cursor(s.win, position)
    end
  end
end

local function run(s, item)
  if active ~= s or not item then
    return
  end
  local ok, err = pcall(function()
    if type(item.action) == "function" then
      item.action()
    else
      vim.cmd(item.action:gsub("^:", ""))
    end
  end)
  if not ok then
    vim.notify("ui-tools dashboard: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local function render(s)
  if active ~= s or not api.nvim_win_is_valid(s.win) or api.nvim_win_get_buf(s.win) ~= s.buf then
    return
  end
  local selected = s.items and s.items[s.selected] and s.items[s.selected].key
  for _, key in ipairs(s.mapped or {}) do
    pcall(vim.keymap.del, "n", key, { buffer = s.buf })
  end
  s.items, s.rows, s.mapped = {}, {}, {}
  for _, item in ipairs(s.opts.keys) do
    local enabled = item.enabled
    if type(enabled) == "function" then
      enabled = enabled()
    end
    if enabled ~= false and item.action then
      assert(type(item.key) == "string" and item.key ~= "", "dashboard key must be nonempty")
      item = vim.tbl_extend("force", {}, item)
      if type(item.icon) == "string" and item.icon ~= "" then
        local name = item.icon_name or (item.desc or item.key or "custom"):lower():gsub("%W+", "_")
        local icon =
          require("ui_tools.icons").get(item.icon_category or "ui", name, item.icon:gsub("%s+$", ""))
        item.icon = icon ~= "" and (icon .. " ") or ""
      end
      s.items[#s.items + 1] = item
      vim.keymap.set("n", item.key, function()
        run(s, item)
      end, { buffer = s.buf, nowait = true, silent = true, desc = item.desc })
      s.mapped[#s.mapped + 1] = item.key
    end
  end
  local layout = require("ui_tools.dashboard_layout").build(
    s.opts,
    s.items,
    api.nvim_win_get_width(s.win),
    api.nvim_win_get_height(s.win)
  )
  s.rows, s.cols, s.layout = layout.rows, layout.cols, layout
  local lines, marks = layout.lines, layout.marks
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, #lines > 0 and lines or { "" })
  vim.bo[s.buf].modifiable = false
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(s.buf, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] })
  end
  for i, item in ipairs(s.items) do
    if item.key == selected then
      s.selected = i
    end
  end
  select_item(s, math.min(s.selected, #s.items))
  api.nvim_win_call(s.win, function()
    local view = vim.fn.winsaveview()
    view.leftcol = 0
    if #lines <= api.nvim_win_get_height(s.win) then
      view.topline = 1
    end
    vim.fn.winrestview(view)
  end)
end

function M.state()
  return active
end

function M.close()
  local s = active
  if not s then
    return
  end
  release(s)
  if api.nvim_win_is_valid(s.win) and api.nvim_win_get_buf(s.win) == s.buf then
    local buf = api.nvim_buf_is_valid(s.source) and s.source or api.nvim_create_buf(true, false)
    api.nvim_win_set_buf(s.win, buf)
  end
  if api.nvim_buf_is_valid(s.buf) then
    api.nvim_buf_delete(s.buf, { force = true })
  end
end

local function open(opts, startup)
  M.close()
  opts = vim.tbl_deep_extend("force", defaults, M.options or {}, opts or {})
  assert(
    opts.layout == "vertical" or opts.layout == "horizontal",
    'dashboard layout must be "vertical" or "horizontal"'
  )
  assert(type(opts.width) == "number" and opts.width >= 1, "dashboard width must be positive")
  assert(
    type(opts.gap) == "number" and opts.gap >= 0 and opts.gap % 1 == 0,
    "dashboard gap must be a nonnegative integer"
  )
  require("ui_tools.util").hl({
    UiToolsDashboardHeader = "Title",
    UiToolsDashboardDesc = "Function",
    UiToolsDashboardIcon = "DiagnosticHint",
    UiToolsDashboardKey = "Special",
    UiToolsDashboardFooter = "Comment",
  })
  local s = {
    win = api.nvim_get_current_win(),
    source = api.nvim_get_current_buf(),
    opts = opts,
    selected = 1,
    saved = {},
    laststatus = vim.o.laststatus,
    ruler = vim.o.ruler,
    startup_source = startup,
  }
  assert(api.nvim_win_get_config(s.win).relative == "", "dashboard requires a normal window")
  -- Use normal buffer switching rules so an unsaved source cannot be discarded.
  vim.cmd("enew")
  s.buf = api.nvim_get_current_buf()
  if s.buf == s.source then
    s.buf = api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(s.win, s.buf)
  end
  s.source_tick = api.nvim_buf_is_valid(s.source) and api.nvim_buf_get_changedtick(s.source) or nil
  for name, value in pairs(window_options) do
    s.saved[name] = vim.wo[s.win][name]
    vim.wo[s.win][name] = value
  end
  vim.bo[s.buf].buftype = "nofile"
  vim.bo[s.buf].bufhidden = "wipe"
  vim.bo[s.buf].buflisted = false
  vim.bo[s.buf].swapfile = false
  vim.b[s.buf].ui_tools_disable = true
  s.group = api.nvim_create_augroup("UiToolsDashboardBuffer", { clear = true })
  active = s
  api.nvim_create_autocmd({ "BufWinLeave", "BufWipeout" }, {
    group = s.group,
    buffer = s.buf,
    callback = function()
      release(s)
    end,
  })
  api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = s.group,
    callback = function()
      vim.schedule(function()
        render(s)
      end)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = s.group,
    pattern = { "VeryLazy", "LazyVimStarted", "ThemeToolsIconsChanged", "ThemeToolsReady" },
    callback = function()
      render(s)
    end,
  })
  api.nvim_create_autocmd("CursorMoved", {
    group = s.group,
    buffer = s.buf,
    callback = function()
      if active == s and #s.items > 0 then
        local row, nearest = api.nvim_win_get_cursor(s.win)[1], 1
        for i, item_row in ipairs(s.rows) do
          if math.abs(item_row - row) < math.abs(s.rows[nearest] - row) then
            nearest = i
          end
        end
        select_item(s, nearest)
      end
    end,
  })
  vim.bo[s.buf].filetype = "ui_tools_dashboard"
  vim.o.ruler = false
  if vim.o.laststatus ~= 0 then
    require("ui_tools.bar").preserve_views(function()
      vim.o.laststatus = 0
      render(s)
    end)
    select_item(s, s.selected)
  else
    render(s)
  end
  for _, key in ipairs({ "j", "<Down>", "<Tab>" }) do
    vim.keymap.set("n", key, function()
      select_item(s, s.selected + 1)
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ "k", "<Up>", "<S-Tab>" }) do
    vim.keymap.set("n", key, function()
      select_item(s, s.selected - 1)
    end, { buffer = s.buf, silent = true })
  end
  vim.keymap.set("n", "<CR>", function()
    run(s, s.items[s.selected])
  end, { buffer = s.buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<Cmd>qa<CR>", { buffer = s.buf, silent = true, desc = "Quit Neovim" })
  return s.buf
end

function M.open(opts)
  return open(opts, false)
end

local function autostart()
  if not M.enabled or M.attempted or #api.nvim_list_uis() == 0 then
    return
  end
  M.attempted = true
  local uis, buf = api.nvim_list_uis(), api.nvim_get_current_buf()
  if
    not M.options.autostart
    or M.stdin
    or vim.fn.argc(-1) > 0
    or (uis[1].stdout_tty and not uis[1].stdin_tty)
    or api.nvim_buf_get_name(buf) ~= ""
    or vim.bo[buf].buftype ~= ""
    or vim.bo[buf].modified
    or api.nvim_buf_line_count(buf) ~= 1
    or api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ""
    or #vim.tbl_filter(function(win)
        return api.nvim_win_get_config(win).relative == ""
      end, api.nvim_list_wins())
      ~= 1
  then
    return
  end
  open(nil, true)
end

function M.setup(opts)
  M.disable()
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  M.enabled, M.attempted, M.stdin = true, false, false
  local group = require("ui_tools.util").group("Dashboard")
  api.nvim_create_autocmd("StdinReadPre", {
    group = group,
    callback = function()
      M.stdin = true
    end,
  })
  api.nvim_create_autocmd({ "VimEnter", "UIEnter" }, {
    group = group,
    -- Populate the start screen before the first redraw can display Nvim's intro.
    callback = autostart,
  })
  if vim.v.vim_did_enter == 1 then
    vim.schedule(autostart)
  end
end

function M.disable()
  M.enabled = false
  pcall(api.nvim_del_augroup_by_name, "UiToolsDashboard")
  M.close()
end

return M
