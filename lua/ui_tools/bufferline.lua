local M = { enabled = false }
local api = vim.api
local bar = require("ui_tools.bar")
local util = require("ui_tools.util")
local format = "%!v:lua.require'ui_tools.bufferline'.render()"
local order, entries, pinned, diagnostics = {}, {}, {}, {}
local closed = {}
local output, scan, queue, previous, shown = "", true, nil, nil, nil

local function highlights(c)
  if c then
    local groups = {
      UiToolsBuffer = { fg = c.ui.muted, bg = c.ui.bg },
      UiToolsBufferCurrent = { fg = c.ui.selection_fg, bg = c.ui.selection_bg, bold = true },
      UiToolsBufferVisible = { fg = c.ui.accent, bg = c.ui.bg },
      UiToolsBufferFill = { bg = c.ui.bg },
    }
    for name, value in pairs(groups) do
      api.nvim_set_hl(0, name, value)
    end
    return
  end
  util.hl({
    UiToolsBuffer = "TabLine",
    UiToolsBufferCurrent = "TabLineSel",
    UiToolsBufferVisible = "Title",
    UiToolsBufferFill = "TabLineFill",
  })
end

local function eligible(buf)
  return api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted
    and vim.bo[buf].buftype == ""
    and not vim.tbl_contains(M.options.exclude, vim.bo[buf].filetype)
    and vim.b[buf].ui_tools_disable ~= true
end

local function count(buf)
  if not M.options.diagnostics then
    return ""
  end
  local counts, parts = vim.diagnostic.count(buf), {}
  for severity, prefix in ipairs({ "E", "W", "I", "H" }) do
    if (counts[severity] or 0) > 0 then
      parts[#parts + 1] = prefix .. counts[severity]
    end
  end
  return table.concat(parts, " ")
end

local function collect()
  local alive, paths, suffixes = {}, {}, {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if eligible(buf) then
      alive[buf] = true
      local name = bar.text(api.nvim_buf_get_name(buf))
      local parts = vim.split(name, "/", { trimempty = true })
      paths[buf] = parts
      local suffix = ""
      for i = #parts, 1, -1 do
        suffix = parts[i] .. (suffix == "" and "" or "/" .. suffix)
        suffixes[suffix] = (suffixes[suffix] or 0) + 1
      end
      if not entries[buf] then
        order[#order + 1] = buf
        diagnostics[buf] = count(buf)
      end
    end
  end
  local first, rest, next_entries = {}, {}, {}
  for _, buf in ipairs(order) do
    if alive[buf] then
      local parts, name = paths[buf], ""
      for i = #parts, 1, -1 do
        name = parts[i] .. (name == "" and "" or "/" .. name)
        if suffixes[name] == 1 then
          break
        end
      end
      name = name == "" and "[No Name " .. buf .. "]" or name
      next_entries[buf] = entries[buf] and entries[buf].name == name and entries[buf]
        or { buf = buf, name = name }
      next_entries[buf].modified = vim.bo[buf].modified
      next_entries[buf].readonly = vim.bo[buf].readonly
      local target = pinned[buf] and first or rest
      target[#target + 1] = buf
    else
      pinned[buf], diagnostics[buf] = nil, nil
    end
  end
  vim.list_extend(first, rest)
  order, entries, scan = first, next_entries, false
end

local function sidebar()
  if not next(M.options.sidebar_filetypes) then
    return 0, 0
  end
  local left, right = 0, 0
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      local buf = api.nvim_win_get_buf(win)
      if M.options.sidebar_filetypes[vim.bo[buf].filetype] then
        local col, width = api.nvim_win_get_position(win)[2], api.nvim_win_get_width(win)
        if col == 0 then
          left = math.max(left, width + 1)
        elseif col + width >= vim.o.columns then
          right = math.max(right, width + 1)
        end
      end
    end
  end
  return left, right
end

local function update()
  if not M.enabled or vim.o.tabline ~= format then
    return
  end
  if scan then
    collect()
  end
  local current, visible = api.nvim_get_current_buf(), {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    visible[api.nvim_win_get_buf(win)] = true
  end
  local cells, active = {}, 1
  for index, buf in ipairs(order) do
    local state = buf == current and "Current" or visible[buf] and "Visible" or ""
    local prefix = (M.options.numbers and index .. " " or "") .. (pinned[buf] and "* " or "")
    local suffix = (entries[buf].modified and " [+]" or "") .. (entries[buf].readonly and " [RO]" or "")
    if diagnostics[buf] and diagnostics[buf] ~= "" then
      suffix = suffix .. " " .. diagnostics[buf]
    end
    local entry = entries[buf]
    local key = state .. "\n" .. prefix .. "\n" .. suffix
    if entry.key ~= key then
      local name = bar.truncate(entry.name, M.options.max_name_length)
      local text = " " .. prefix .. name .. suffix .. " "
      local hl = "UiToolsBuffer" .. state
      local rendered = "%"
        .. buf
        .. "@v:lua.require'ui_tools.bufferline'.click@"
        .. bar.label(text, hl)
        .. "%X"
      if M.options.close_buttons then
        rendered = rendered
          .. "%"
          .. buf
          .. "@v:lua.require'ui_tools.bufferline'.close_click@"
          .. bar.label("× ", hl)
          .. "%X"
        text = text .. "× "
      end
      entry.cell = { text = text, hl = hl, rendered = rendered, buf = buf, width = bar.width(text) }
      entry.key = key
    end
    cells[index] = entry.cell
    if buf == current then
      active = index
    end
  end
  local left, right = sidebar()
  -- Leave room for both overflow indicators; keep the active buffer in view.
  local available = math.max(0, vim.o.columns - left - right)
  if available < 8 then
    left, right, available = 0, 0, vim.o.columns
  end
  local budget = math.max(1, available - 4)
  local first, last, used = active, active, cells[active] and cells[active].width or 0
  while first > 1 and used + cells[first - 1].width <= budget do
    first, used = first - 1, used + cells[first - 1].width
  end
  while last < #cells and used + cells[last + 1].width <= budget do
    last, used = last + 1, used + cells[last + 1].width
  end
  local result = { bar.label(string.rep(" ", left), "UiToolsBufferFill") }
  if first > 1 then
    result[#result + 1] = bar.label("‹ ", "UiToolsBufferFill")
  end
  for i = first, last do
    local cell = cells[i]
    if cell then
      if cell.width > budget then
        -- One compact clickable label; never cut a statusline format or UTF-8 byte.
        result[#result + 1] = "%"
          .. cell.buf
          .. "@v:lua.require'ui_tools.bufferline'.click@"
          .. bar.label(bar.truncate(cell.text, budget), cell.hl)
          .. "%X"
      else
        result[#result + 1] = cell.rendered
      end
    end
  end
  if last < #cells then
    result[#result + 1] = bar.label(" ›", "UiToolsBufferFill")
  end
  result[#result + 1] = "%#UiToolsBufferFill#%=" .. string.rep(" ", right)
  local next_output = table.concat(result)
  local changed = output ~= next_output
  output = next_output
  if vim.o.showtabline == shown then
    local next_shown = #order <= M.options.auto_hide and 0 or 2
    if next_shown ~= shown then
      shown = next_shown
      bar.preserve_views(function()
        vim.o.showtabline = shown
      end)
      changed = false -- The geometry redraw already used the new string.
    end
  end
  if changed and vim.v.vim_did_enter == 1 then
    vim.cmd("redrawtabline")
  end
end

local function request(structure)
  scan = scan or structure
  if queue then
    queue.request()
  end
end

function M.render()
  return M.enabled and output or ""
end

function M.refresh()
  if not M.enabled then
    return
  end
  scan = true
  for _, buf in ipairs(order) do
    if api.nvim_buf_is_valid(buf) then
      diagnostics[buf] = count(buf)
    end
  end
  update()
end

function M.items()
  if M.enabled then
    update()
  end
  local result = {}
  for i, buf in ipairs(order) do
    result[i] = { buf = buf, name = entries[buf].name, pinned = pinned[buf] == true }
  end
  return result
end

function M.go(index)
  if not M.enabled then
    return false
  end
  update()
  local buf = order[index]
  if not buf then
    return false
  end
  api.nvim_set_current_buf(buf)
  update()
  return true
end

function M.cycle(delta)
  if not M.enabled then
    return false
  end
  update()
  if #order == 0 then
    return false
  end
  local index = vim.fn.index(order, api.nvim_get_current_buf())
  return M.go((index + delta) % #order + 1)
end

function M.move(delta)
  if not M.enabled then
    return false
  end
  update()
  local buf = api.nvim_get_current_buf()
  local index = vim.fn.index(order, buf) + 1
  if index == 0 then
    return false
  end
  local target = math.max(1, math.min(#order, index + delta))
  -- Pinned and ordinary buffers form separate, stable ordering groups.
  while target ~= index and (pinned[order[target]] == true) ~= (pinned[buf] == true) do
    target = target + (target > index and -1 or 1)
  end
  table.remove(order, index)
  table.insert(order, target, buf)
  update()
  return true
end

function M.pin(buf)
  if not M.enabled then
    return false
  end
  update()
  buf = buf or api.nvim_get_current_buf()
  if not entries[buf] then
    return false
  end
  pinned[buf], scan = not pinned[buf], true
  update()
  return pinned[buf]
end

function M.close(buf, force)
  if not M.enabled then
    return false
  end
  update()
  buf = buf or api.nvim_get_current_buf()
  if not entries[buf] then
    return false
  end
  if not force and (pinned[buf] or vim.bo[buf].modified) then
    return false, pinned[buf] and "Buffer is pinned" or "Buffer has unsaved changes"
  end
  local name = api.nvim_buf_get_name(buf)
  local cursor = { 1, 0 }
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      cursor = api.nvim_win_get_cursor(win)
      if win == api.nvim_get_current_win() then
        break
      end
    end
  end
  local replacement
  local index = vim.fn.index(order, buf) + 1
  replacement = order[index + 1] or order[index - 1]
  local created = replacement == nil
  if created then
    replacement = api.nvim_create_buf(true, false)
  end
  local changed = {}
  local ok, err = pcall(function()
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == buf then
        -- Respect fixed windows, and roll back if any window rejects replacement.
        assert(not vim.wo[win].winfixbuf, "Window has winfixbuf set")
        local cursor = api.nvim_win_get_cursor(win)
        api.nvim_win_set_buf(win, replacement)
        changed[#changed + 1] = { win = win, cursor = cursor }
      end
    end
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_delete(buf, { force = force == true })
    end
  end)
  if not ok then
    for _, item in ipairs(changed) do
      if api.nvim_win_is_valid(item.win) and api.nvim_buf_is_valid(buf) then
        pcall(api.nvim_win_set_buf, item.win, buf)
        pcall(api.nvim_win_set_cursor, item.win, item.cursor)
      end
    end
    if created and api.nvim_buf_is_valid(replacement) and not vim.bo[replacement].modified then
      pcall(api.nvim_buf_delete, replacement, { force = false })
    end
  elseif name ~= "" then
    closed[#closed + 1] = { name = name, index = index, cursor = cursor }
    if #closed > 20 then
      table.remove(closed, 1)
    end
  end
  scan = true
  update()
  return ok, err
end

-- Select once so closing a buffer cannot change the meaning of left/right or visible.
function M.close_many(scope, force)
  if not M.enabled then
    return false, "Bufferline is disabled"
  end
  local items, current, visible = M.items(), api.nvim_get_current_buf(), {}
  local position
  for i, item in ipairs(items) do
    if item.buf == current then
      position = i
    end
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    visible[api.nvim_win_get_buf(win)] = true
  end
  if (scope == "left" or scope == "right") and not position then
    return false, "Current buffer is not in the buffer bar"
  end
  local select = {
    all = function()
      return true
    end,
    others = function(item)
      return item.buf ~= current
    end,
    left = function(_, i)
      return i < position
    end,
    right = function(_, i)
      return i > position
    end,
    unpinned = function(item)
      return not item.pinned
    end,
    hidden = function(item)
      return not visible[item.buf]
    end,
  }
  assert(select[scope], "Unknown buffer close scope: " .. tostring(scope))
  local targets, failures = {}, {}
  for i, item in ipairs(items) do
    if select[scope](item, i) then
      targets[#targets + 1] = item
    end
  end
  for _, item in ipairs(targets) do
    -- Autocommands from an earlier close may have already removed a target.
    if eligible(item.buf) then
      local ok, err = M.close(item.buf, force)
      if not ok then
        failures[#failures + 1] = item.name .. ": " .. (err or "Could not close buffer")
      end
    end
  end
  return #failures == 0, #failures > 0 and table.concat(failures, "\n") or nil
end

-- Restore file buffers from disk, without retaining their text in memory.
-- Only successful closes enter history; a failed switch leaves history intact.
function M.restore()
  if not M.enabled or #closed == 0 then
    return false
  end
  local item = closed[#closed]
  local ok, err = pcall(function()
    local buf = vim.fn.bufadd(item.name)
    api.nvim_set_current_buf(buf)
    vim.bo[buf].buflisted = true
    scan = true
    update()
    local index = vim.fn.index(order, buf) + 1
    if index > 0 and not pinned[buf] then
      table.remove(order, index)
      local first = 1
      while pinned[order[first]] do
        first = first + 1
      end
      table.insert(order, math.max(first, math.min(item.index, #order + 1)), buf)
    end
    api.nvim_win_set_cursor(0, { math.min(item.cursor[1], api.nvim_buf_line_count(buf)), item.cursor[2] })
    update()
  end)
  if ok then
    table.remove(closed)
  end
  return ok, err
end

function M.click(buf, _, button)
  if not M.enabled then
    return
  end
  if button == "m" then
    M.close(buf)
  elseif button == "l" and eligible(buf) then
    api.nvim_set_current_buf(buf)
    update()
  end
end

function M.close_click(buf, _, button)
  if button == "l" or button == "m" then
    M.close(buf)
  end
end

function M.setup(opts)
  M.disable()
  opts = vim.tbl_deep_extend("force", {
    refresh = 30,
    auto_hide = 1,
    max_name_length = 28,
    numbers = false,
    close_buttons = true,
    diagnostics = false,
    exclude = {},
    sidebar_filetypes = {},
    force = false,
  }, opts or {})
  assert(type(opts.refresh) == "number" and opts.refresh >= 0, "bufferline.refresh must be nonnegative")
  assert(type(opts.auto_hide) == "number" and opts.auto_hide >= -1, "bufferline.auto_hide must be >= -1")
  assert(
    type(opts.max_name_length) == "number" and opts.max_name_length >= 1,
    "bufferline.max_name_length must be positive"
  )
  M.options = opts
  if vim.o.tabline ~= "" and not opts.force then
    return false
  end
  previous = { tabline = vim.o.tabline, showtabline = vim.o.showtabline }
  M.enabled, scan, shown = true, true, vim.o.showtabline
  vim.o.tabline = format
  queue = bar.scheduler(opts.refresh, update)
  require("ui_tools.theme").bind("bufferline", highlights)
  local group = util.group("Bufferline")
  api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout", "BufFilePost", "FileType" }, {
    group = group,
    callback = function()
      request(true)
    end,
  })
  api.nvim_create_autocmd("BufModifiedSet", {
    group = group,
    callback = function(args)
      if entries[args.buf] and api.nvim_buf_is_valid(args.buf) then
        entries[args.buf].modified = vim.bo[args.buf].modified
        request(false)
      end
    end,
  })
  api.nvim_create_autocmd({
    "BufEnter",
    "WinEnter",
    "WinClosed",
    "TabEnter",
    "VimResized",
    "WinResized",
    "ColorScheme",
  }, {
    group = group,
    callback = function()
      request(false)
    end,
  })
  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "buflisted", "buftype", "filetype", "readonly" },
    callback = function()
      request(true)
    end,
  })
  if opts.diagnostics then
    api.nvim_create_autocmd("DiagnosticChanged", {
      group = group,
      callback = function(args)
        if entries[args.buf] then
          diagnostics[args.buf] = count(args.buf)
          request(false)
        end
      end,
    })
  end
  require("ui_tools.bufferline_commands").setup(M)
  M.refresh()
  return true
end

function M.disable()
  require("ui_tools.bufferline_commands").disable()
  require("ui_tools.theme").unbind("bufferline")
  M.enabled = false
  if queue then
    queue.cancel()
    queue = nil
  end
  pcall(api.nvim_del_augroup_by_name, "UiToolsBufferline")
  if previous then
    if vim.o.tabline == format then
      vim.o.tabline = previous.tabline
    end
    if vim.o.showtabline == shown then
      vim.o.showtabline = previous.showtabline
    end
  end
  previous, shown, output = nil, nil, ""
  order, entries, pinned, diagnostics = {}, {}, {}, {}
  closed = {}
end

return M
