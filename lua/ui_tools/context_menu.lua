local M = { enabled = false, errors = {} }
local api = vim.api
local context = require("ui_tools.context_menu.context")
local providers, serial, active = {}, 0, nil
local mappings = {}
local mouse_keys = { "<RightMouse>", "<2-RightMouse>", "<3-RightMouse>", "<4-RightMouse>" }
local options = {}
local ns = api.nvim_create_namespace("UiToolsContextMenu")

local function highlights()
  require("ui_tools.util").hl({
    UiToolsMenu = "NormalFloat",
    UiToolsMenuBorder = "FloatBorder",
    UiToolsMenuSelected = "PmenuSel",
    UiToolsMenuDisabled = "Comment",
    UiToolsMenuSelection = "Visual",
  })
end

local function fail(name, err)
  M.errors[name] = tostring(err)
end

local function live(s)
  return active == s and not s.closed and context.unchanged(s.ctx)
end

local function selectable(item)
  return item and item.enabled ~= false and type(item.action) == "function"
end

local function clean(value)
  return tostring(value):gsub("[%c]", " ")
end

local function fit(text, width)
  local result = ""
  for _, char in ipairs(vim.fn.split(text, "\\zs")) do
    if vim.fn.strdisplaywidth(result .. char) > width then
      break
    end
    result = result .. char
  end
  return result
end

local function draw(s)
  if not live(s) then
    return
  end
  local selected = s.items and s.items[s.index or 0]
  local key = selected and selected.key
  local items, rows, seen = {}, {}, {}
  for _, source in ipairs(s.sources) do
    for _, item in ipairs(source.items or {}) do
      local id = source.name .. "/" .. tostring(item.id)
      if type(item.id) == "string" and type(item.label) == "string" and not seen[id] then
        seen[id] = true
        local entry = vim.tbl_extend("force", item, { key = id })
        local previous = items[#items]
        if previous and previous.group ~= entry.group then
          rows[#rows + 1] = false
        end
        items[#items + 1] = entry
        rows[#rows + 1] = #items
      end
    end
  end
  if #items == 0 then
    rows = { false }
  end
  s.items, s.rows = items, rows
  s.index = nil
  for i, item in ipairs(items) do
    if item.key == key and selectable(item) then
      s.index = i
      break
    end
  end
  if not s.index then
    for i, item in ipairs(items) do
      if selectable(item) then
        s.index = i
        break
      end
    end
  end
  local width = options.min_width or 24
  for _, item in ipairs(items) do
    width = math.max(
      width,
      vim.fn.strdisplaywidth(clean(item.label))
        + 4
        + (item.shortcut and vim.fn.strdisplaywidth(clean(item.shortcut)) + 2 or 0)
    )
  end
  width = math.max(1, math.min(width, options.max_width or 60, vim.o.columns - 2))
  local height = math.max(1, math.min(#rows, options.max_height or 16, vim.o.lines - 3))
  local row = math.max(0, math.min(s.row, vim.o.lines - height - 3))
  local col = math.max(0, math.min(s.col, vim.o.columns - width - 2))
  local config = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = options.border or "rounded",
    zindex = options.zindex or 250,
    noautocmd = true,
  }
  local lines, cursor = {}, 1
  for i, index in ipairs(rows) do
    local item = items[index]
    if item then
      local label = fit(clean(item.label), math.max(1, width - 2))
      local shortcut = clean(item.shortcut or "")
      local gap = width - 2 - vim.fn.strdisplaywidth(label) - vim.fn.strdisplaywidth(shortcut)
      lines[i] = " " .. label .. (gap >= 2 and string.rep(" ", gap) .. shortcut or "")
      if index == s.index then
        cursor = i
      end
    else
      lines[i] = #items == 0 and fit(" No actions", width) or string.rep("─", width)
    end
  end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for i, index in ipairs(rows) do
    if not index or not selectable(items[index]) then
      api.nvim_buf_add_highlight(s.buf, ns, "UiToolsMenuDisabled", i - 1, 0, -1)
    end
  end
  if s.win and api.nvim_win_is_valid(s.win) then
    config.noautocmd = nil -- 0.11 accepts this flag only when creating a window.
    api.nvim_win_set_config(s.win, config)
  else
    s.win = api.nvim_open_win(s.buf, true, config)
    vim.wo[s.win].winhighlight =
      "Normal:UiToolsMenu,FloatBorder:UiToolsMenuBorder,CursorLine:UiToolsMenuSelected"
    vim.wo[s.win].cursorline = true
    vim.wo[s.win].wrap = false
    vim.wo[s.win].scrolloff = 0
  end
  api.nvim_win_set_cursor(s.win, { cursor, 0 })
end

local function close(s, restore)
  if not s or s.closed then
    return
  end
  s.closed = true
  if active == s then
    active = nil
  end
  if s.group then
    pcall(api.nvim_del_augroup_by_id, s.group)
  end
  if s.win and api.nvim_win_is_valid(s.win) then
    api.nvim_win_close(s.win, true)
  end
  if api.nvim_buf_is_valid(s.buf) then
    api.nvim_buf_delete(s.buf, { force = true })
  end
  if api.nvim_win_is_valid(s.ctx.win) then
    for _, match in ipairs(s.matches or {}) do
      pcall(vim.fn.matchdelete, match, s.ctx.win)
    end
  end
  for _, cancel in ipairs(s.cancel) do
    local ok, err = pcall(cancel)
    if not ok then
      fail("cancel", err)
    end
  end
  if restore then
    context.restore(s.ctx, true)
  end
end

function M.close()
  close(active, true)
end

local function choose(s)
  local item = s.items[s.index or 0]
  if not live(s) then
    close(s, false)
    return
  end
  if not selectable(item) then
    return
  end
  close(s, false)
  if context.restore(s.ctx, false) then
    local ok, err = pcall(item.action, s.ctx)
    if not ok then
      fail(item.key, err)
      vim.notify("ui-tools menu: " .. tostring(err), vim.log.levels.ERROR)
    elseif
      s.ctx.mode:sub(1, 1) == "i"
      and item.key:sub(1, 8) == "builtin/"
      and api.nvim_get_current_win() == s.ctx.win
      and vim.fn.mode() == "n"
    then
      vim.cmd.startinsert()
    end
  end
end

local function move(s, delta)
  local index = s.index or 0
  for _ = 1, #s.items do
    index = (index - 1 + delta) % #s.items + 1
    if selectable(s.items[index]) then
      s.index = index
      for row, item in ipairs(s.rows) do
        if item == index then
          api.nvim_win_set_cursor(s.win, { row, 0 })
          break
        end
      end
      return
    end
  end
end

local function collect(s, source)
  local function validate(items)
    local result = {}
    for _, item in ipairs(type(items) == "table" and items or {}) do
      if
        type(item) == "table"
        and type(item.id) == "string"
        and type(item.label) == "string"
        and (item.action == nil or type(item.action) == "function")
      then
        result[#result + 1] = item
      else
        fail(source.name, "invalid menu item (expected id, label and optional action)")
      end
    end
    return result
  end
  local sink = {}
  function sink.update(items)
    -- Safe from fast callbacks; old handles cannot update a replacement menu.
    vim.schedule(function()
      if live(s) and (not source.registration or providers[source.name] == source.registration) then
        if type(items) == "table" then
          source.items = validate(items)
          draw(s)
        end
      end
    end)
  end
  function sink.on_close(callback)
    assert(type(callback) == "function", "on_close expects a function")
    if live(s) then
      s.cancel[#s.cancel + 1] = callback
    else
      pcall(callback)
    end
  end
  local ok, items = pcall(source.provider, s.ctx, sink)
  if ok then
    source.items = validate(items)
  else
    fail(source.name, items)
    source.items = {}
  end
end

---Register a synchronous or asynchronous provider. Registrations survive disable/setup.
---provider(ctx, sink) returns items; sink.update(items) replaces this provider's items.
function M.register(name, provider, opts)
  assert(type(name) == "string" and name ~= "" and name ~= "builtin", "invalid menu provider name")
  assert(type(provider) == "function", "menu provider must be a function")
  assert(not opts or opts.priority == nil or type(opts.priority) == "number", "priority must be a number")
  serial = serial + 1
  local registration =
    { name = name, provider = provider, priority = opts and opts.priority or 100, order = serial }
  providers[name] = registration
  -- Retire visible items immediately; never leave an unregistered action executable.
  local function retire()
    local s = active
    if s then
      for _, source in ipairs(s.sources) do
        if source.name == name then
          source.items = {}
        end
      end
      draw(s)
    end
  end
  retire()
  return function()
    if providers[name] == registration then
      providers[name] = nil
      retire()
    end
  end
end

---Open at the cursor; {mouse=true} targets the last right-click position.
function M.open(opts)
  opts = opts or {}
  M.close()
  highlights()
  local ctx = context.capture()
  local mouse = opts.mouse and vim.fn.getmousepos() or nil
  if mouse then
    if mouse.winid == 0 or mouse.line == 0 or not api.nvim_win_is_valid(mouse.winid) then
      return
    end
    if not context.contains(ctx, mouse) then
      context.suspend()
      api.nvim_set_current_win(mouse.winid)
      api.nvim_win_set_cursor(mouse.winid, { mouse.line, math.max(0, mouse.column - 1) })
      local mode = ctx.mode:sub(1, 1) == "i" and ctx.mode or "n"
      ctx = context.capture()
      ctx.mode = mode
    end
  end
  if vim.b[ctx.buf].ui_tools_disable or vim.tbl_contains(options.exclude or {}, vim.bo[ctx.buf].filetype) then
    return
  end
  local pos = vim.fn.screenpos(ctx.win, ctx.cursor[1], ctx.cursor[2] + 1)
  context.suspend()
  local s = {
    ctx = ctx,
    row = mouse and mouse.screenrow - 1 or math.max(0, pos.row),
    col = mouse and mouse.screencol - 1 or math.max(0, pos.col - 1),
    buf = api.nvim_create_buf(false, true),
    sources = {},
    cancel = {},
    items = {},
    matches = {},
  }
  active = s
  -- Retain a visible selection in the source window while the float has focus.
  -- Window-local matches avoid highlighting other splits of the same buffer.
  if ctx.selection then
    local top, bottom = vim.fn.line("w0"), vim.fn.line("w$")
    local positions = {}
    for _, pair in ipairs(ctx.selection.regions) do
      local first, last = pair[1], pair[2]
      if first[2] >= top and first[2] <= bottom then
        local line = api.nvim_buf_get_lines(ctx.buf, first[2] - 1, first[2], false)[1]
        local tail = line:sub(last[3])
        local char = vim.fn.strcharpart(tail, 0, 1)
        positions[#positions + 1] =
          { first[2], math.max(1, first[3]), math.max(1, last[3] - first[3] + #char) }
      end
    end
    for i = 1, #positions, 8 do
      s.matches[#s.matches + 1] =
        vim.fn.matchaddpos("UiToolsMenuSelection", vim.list_slice(positions, i, i + 7))
    end
  end
  vim.bo[s.buf].bufhidden = "wipe"
  vim.bo[s.buf].filetype = "ui-tools-menu"
  if options.builtin ~= false then
    s.sources[#s.sources + 1] =
      { name = "builtin", provider = require("ui_tools.context_menu.actions").items }
  end
  if options.lsp ~= false and not providers.lsp then
    s.sources[#s.sources + 1] = {
      name = "lsp",
      provider = function(source, sink)
        return require("ui_tools.integrations.context_lsp").items(source, nil, sink)
      end,
    }
  end
  local registered = vim.tbl_values(providers)
  table.sort(registered, function(a, b)
    return a.priority == b.priority and a.order < b.order or a.priority < b.priority
  end)
  for _, registration in ipairs(registered) do
    s.sources[#s.sources + 1] = {
      name = registration.name,
      provider = registration.provider,
      registration = registration,
    }
  end
  for _, source in ipairs(s.sources) do
    collect(s, source)
  end
  draw(s)
  local function map(keys, callback, desc)
    vim.keymap.set("n", keys, callback, { buffer = s.buf, nowait = true, silent = true, desc = desc })
  end
  for _, key in ipairs({ "j", "<Down>", "<Tab>", "<ScrollWheelDown>" }) do
    map(key, function()
      move(s, 1)
    end, "Next context menu item")
  end
  for _, key in ipairs({ "k", "<Up>", "<S-Tab>", "<ScrollWheelUp>" }) do
    map(key, function()
      move(s, -1)
    end, "Previous context menu item")
  end
  map("<CR>", function()
    choose(s)
  end, "Run selected context menu action")
  map("<Space>", function()
    choose(s)
  end, "Run selected context menu action")
  for _, key in ipairs({ "<Esc>", "q", "<C-c>" }) do
    map(key, M.close, "Close context menu")
  end
  map("<LeftMouse>", function()
    local click = vim.fn.getmousepos()
    if click.winid == s.win then
      local index = s.rows[click.line]
      if selectable(s.items[index]) then
        s.index = index
        choose(s)
      end
    else
      close(s, false)
      api.nvim_input_mouse("left", "press", "", 0, click.screenrow - 1, click.screencol - 1)
    end
  end, "Run context menu action under mouse")
  for _, key in ipairs(mouse_keys) do
    map(key, function()
      M.open({ mouse = true })
    end, "Open context menu at mouse")
  end
  -- Consume editing keys: this scratch buffer is a menu, not an editor.
  for _, key in ipairs({
    "i",
    "a",
    "o",
    "I",
    "A",
    "O",
    "v",
    "V",
    "<C-v>",
    "p",
    "P",
    "d",
    "c",
    "x",
    "s",
    "r",
    "u",
    "R",
    ":",
    "/",
    "?",
  }) do
    map(key, "<Nop>", "Disabled in context menu")
  end
  s.group = api.nvim_create_augroup("UiToolsMenuSession", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = s.group, callback = highlights })
  api.nvim_create_autocmd({ "VimResized", "TabLeave" }, {
    group = s.group,
    callback = function()
      close(s, false)
    end,
  })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = s.group,
    buffer = ctx.buf,
    callback = function()
      if not context.unchanged(ctx) then
        close(s, false)
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = s.group,
    callback = function(event)
      if tonumber(event.match) == s.win or tonumber(event.match) == ctx.win then
        close(s, false)
      end
    end,
  })
  api.nvim_create_autocmd("WinLeave", {
    group = s.group,
    buffer = s.buf,
    callback = function()
      vim.schedule(function()
        close(s, false)
      end)
    end,
  })
  return {
    close = function()
      close(s, true)
    end,
    is_active = function()
      return live(s)
    end,
  }
end

function M.state()
  local s = active
  return s and { win = s.win, buf = s.buf, context = s.ctx, items = s.items, selected = s.index } or nil
end

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "context_menu options must be a table")
  opts = vim.deepcopy(opts or {})
  local candidate = vim.tbl_extend("force", {}, opts or {})
  for _, key in ipairs({ "min_width", "max_width", "max_height" }) do
    assert(
      candidate[key] == nil
        or type(candidate[key]) == "number" and candidate[key] >= 1 and candidate[key] % 1 == 0,
      key .. " must be a positive integer"
    )
  end
  return candidate
end

function M.setup(opts)
  return M._setup(M.resolve(opts))
end

function M._setup(resolved)
  M.disable()
  options = resolved
  highlights()
  M.enabled = true
  if options.mouse == true then
    for _, mode in ipairs({ "n", "x", "i" }) do
      local previous_maps = {}
      for _, mapping in ipairs(api.nvim_get_keymap(mode)) do
        previous_maps[mapping.lhs] = mapping
      end
      for _, lhs in ipairs(mouse_keys) do
        local previous = previous_maps[lhs]
        local callback = function()
          M.open({ mouse = true })
        end
        mappings[#mappings + 1] = { mode = mode, lhs = lhs, previous = previous, callback = callback }
        vim.keymap.set(mode, lhs, callback, { silent = true, desc = "ui-tools context menu" })
      end
    end
  end
end

function M.disable()
  M.close()
  local current = {}
  for _, saved in ipairs(mappings) do
    if not current[saved.mode] then
      current[saved.mode] = {}
      for _, mapping in ipairs(api.nvim_get_keymap(saved.mode)) do
        current[saved.mode][mapping.lhs] = mapping
      end
    end
    local mapping = current[saved.mode][saved.lhs]
    if mapping and mapping.callback == saved.callback then
      vim.keymap.del(saved.mode, saved.lhs)
      if saved.previous then
        vim.fn.mapset(saved.mode, false, saved.previous)
      end
    end
  end
  mappings = {}
  M.enabled = false
end

return M
