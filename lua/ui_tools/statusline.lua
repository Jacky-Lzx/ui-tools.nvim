local M = { enabled = false, errors = {} }
local api = vim.api
local bar = require("ui_tools.bar")
local util = require("ui_tools.util")
local icons = require("ui_tools.icons")
local format = "%!v:lua.require'ui_tools.statusline'.render()"
local windows, blocked, cache, frames, dirty = {}, {}, {}, {}, {}
local buffers = {}
local queue, previous_laststatus, applied_laststatus, all_dirty, custom
local sections = { "a", "b", "c", "x", "y", "z" }
local defaults = {
  a = { "mode" },
  b = { "branch", "diff", "diagnostics" },
  c = { "filename" },
  x = { "recording", "lsp" },
  y = { "encoding", "fileformat", "filetype", "progress" },
  z = { "location" },
}
local inactive = { a = {}, b = {}, c = { "filename" }, x = {}, y = {}, z = { "location" } }
local priorities = {
  mode = 80,
  branch = 40,
  diff = 30,
  diagnostics = 70,
  filename = 100,
  recording = 110,
  lsp = 20,
  encoding = 10,
  fileformat = 10,
  filetype = 30,
  progress = 20,
  location = 90,
  cwd = 30,
}
local dynamic = { mode = true, progress = true, location = true, recording = true }
local modes = { "Normal", "Insert", "Visual", "Replace", "Command", "Terminal" }
local component_colors = {}

local function highlights(c)
  component_colors = {}
  if c then
    local bg = c.ui.bg ~= "NONE" and c.ui.bg or c.palette.bg
    local groups = {
      UiToolsStatus = { fg = c.ui.fg, bg = bg },
      UiToolsStatusAlt = { fg = c.ui.fg, bg = bar.blend(bg, c.ui.fg, 0.09) },
      UiToolsStatusInactive = { fg = c.ui.muted, bg = bg },
      UiToolsStatusDiff = { fg = c.git.change },
      UiToolsStatusError = { fg = c.diagnostic.error },
      UiToolsStatusWarn = { fg = c.diagnostic.warn },
      UiToolsStatusInfo = { fg = c.diagnostic.info },
      UiToolsStatusHint = { fg = c.diagnostic.hint },
    }
    for mode, color in pairs({
      Normal = c.ui.accent,
      Insert = c.palette.green,
      Visual = c.palette.purple,
      Replace = c.diagnostic.error,
      Command = c.palette.orange,
      Terminal = c.palette.cyan,
    }) do
      groups["UiToolsStatus" .. mode] = { fg = c.palette.bg, bg = color, bold = true }
    end
    for name, value in pairs(groups) do
      api.nvim_set_hl(0, name, value)
    end
  else
    util.hl({
      UiToolsStatusDiff = "Special",
      UiToolsStatusError = "DiagnosticError",
      UiToolsStatusWarn = "DiagnosticWarn",
      UiToolsStatusInfo = "DiagnosticInfo",
      UiToolsStatusHint = "DiagnosticHint",
    })
    local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
    local comment = api.nvim_get_hl(0, { name = "Comment", link = false })
    local bg = normal.bg or (vim.o.background == "light" and 0xffffff or 0x202020)
    local fg = normal.fg or (vim.o.background == "light" and 0x202020 or 0xffffff)
    -- Keep solid surfaces even with transparent or reversed native bars.
    api.nvim_set_hl(0, "UiToolsStatus", { default = true, fg = fg, bg = bg })
    api.nvim_set_hl(0, "UiToolsStatusAlt", {
      default = true,
      fg = fg,
      bg = bar.blend(bg, fg, 0.09),
    })
    api.nvim_set_hl(0, "UiToolsStatusInactive", {
      default = true,
      fg = comment.fg or bar.blend(bg, fg, 0.55),
      bg = bg,
    })
    for mode, source in pairs({
      Normal = "Function",
      Insert = "String",
      Visual = "Statement",
      Replace = "DiagnosticError",
      Command = "Constant",
      Terminal = "Special",
    }) do
      local accent = api.nvim_get_hl(0, { name = source, link = false })
      local color = accent.fg or fg
      api.nvim_set_hl(0, "UiToolsStatus" .. mode, {
        default = true,
        fg = 0x000000,
        bg = color,
        bold = true,
        reverse = color == nil,
      })
    end
  end
  -- All color resolution happens on theme changes, never during a redraw.
  local surfaces = vim.list_extend({ "", "Alt", "Inactive" }, modes)
  local muted = c and c.ui.muted or api.nvim_get_hl(0, { name = "Comment", link = false }).fg
  for _, from in ipairs(surfaces) do
    local a = api.nvim_get_hl(0, { name = "UiToolsStatus" .. from, link = false })
    api.nvim_set_hl(0, "UiToolsStatusDivider" .. from, { fg = muted or a.fg, bg = a.bg })
    for _, to in ipairs(surfaces) do
      local b = api.nvim_get_hl(0, { name = "UiToolsStatus" .. to, link = false })
      api.nvim_set_hl(0, "UiToolsStatusEdge" .. from .. "To" .. to, { fg = a.bg, bg = b.bg })
    end
  end
end

local function mode()
  local value = api.nvim_get_mode().mode
  local first = value:sub(1, 1)
  if first == "i" then
    return "INSERT", "Insert"
  end
  if first == "R" then
    return "REPLACE", "Replace"
  end
  if first == "v" or first == "V" or first == "\22" or first == "s" or first == "S" or first == "\19" then
    return "VISUAL", "Visual"
  end
  if first == "c" or first == "r" or first == "!" then
    return "COMMAND", "Command"
  end
  if first == "t" then
    return "TERMINAL", "Terminal"
  end
  return "NORMAL", "Normal"
end

local function eligible(win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  local profile = bar.profile(buf, "statusline", M.options)
  return vim.b[buf].ui_tools_disable ~= true
    and profile ~= false
    and (profile ~= nil or not vim.tbl_contains(M.options.exclude, vim.bo[buf].filetype))
end

local function local_option(win)
  return api.nvim_get_option_value("statusline", { win = win, scope = "local" })
end

local function release(win)
  if windows[win] ~= nil and api.nvim_win_is_valid(win) and local_option(win) == format then
    api.nvim_set_option_value("statusline", windows[win], { win = win, scope = "local" })
  end
  windows[win], frames[win], buffers[win] = nil, nil, nil
end

local function synchronize()
  local default = api.nvim_get_option_info2("statusline", {}).default
  for _, win in ipairs(api.nvim_list_wins()) do
    if not eligible(win) then
      release(win)
    elseif windows[win] ~= nil and local_option(win) ~= format then
      local value = local_option(win)
      if buffers[win] ~= api.nvim_win_get_buf(win) and (value == "" or vim.wo[win].statusline == default) then
        -- Window-local options can return to a buffer's saved native value on
        -- :buffer, close or restore. Adopt that buffer without losing ownership.
        api.nvim_set_option_value("statusline", format, { win = win, scope = "local" })
      else
        -- A later custom owner wins, even when setup used force.
        windows[win], frames[win], buffers[win], blocked[win] = nil, nil, nil, true
      end
    elseif windows[win] == nil and not blocked[win] then
      local value, effective = local_option(win), vim.wo[win].statusline
      if value == format or effective == "" or effective == default or M.options.force then
        windows[win] = value == format and "" or value
        api.nvim_set_option_value("statusline", format, { win = win, scope = "local" })
      end
    end
    if windows[win] ~= nil then
      buffers[win] = api.nvim_win_get_buf(win)
    end
  end
  for win in pairs(windows) do
    if not api.nvim_win_is_valid(win) then
      release(win)
    end
  end
  for win in pairs(blocked) do
    if not api.nvim_win_is_valid(win) then
      blocked[win] = nil
    end
  end
  local dashboard = package.loaded["ui_tools.dashboard"]
  local dashboard_active = dashboard and dashboard.state() ~= nil
  if next(windows) and not previous_laststatus and not dashboard_active then
    previous_laststatus = vim.o.laststatus
    applied_laststatus = M.options.globalstatus and 3 or 2
    if vim.o.laststatus ~= applied_laststatus then
      bar.preserve_views(function()
        vim.o.laststatus = applied_laststatus
      end)
    end
  end
end

local function snapshot(buf, flags)
  local data = cache[buf] or {}
  if not cache[buf] or flags.all or flags.metadata then
    local name = api.nvim_buf_get_name(buf)
    data.absolute = name == "" and "[No Name]" or bar.text(name)
    data.tail = name == "" and "[No Name]" or bar.text(vim.fn.fnamemodify(name, ":t"))
    data.encoding = vim.bo[buf].fileencoding ~= "" and vim.bo[buf].fileencoding or vim.o.encoding
    data.fileformat, data.filetype = vim.bo[buf].fileformat, vim.bo[buf].filetype
    data.modified, data.readonly = vim.bo[buf].modified, vim.bo[buf].readonly
  end
  if not cache[buf] or flags.all or flags.diagnostics then
    data.diagnostics = vim.diagnostic.count(buf)
    local signs = vim.diagnostic.config().signs
    data.diagnostic_symbols = type(signs) == "table"
        and type(signs.text) == "table"
        and vim.deepcopy(signs.text)
      or {}
  end
  if not cache[buf] or flags.all or flags.lsp then
    local names, seen = {}, {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
      if not seen[client.name] then
        names[#names + 1], seen[client.name] = client.name, true
      end
    end
    table.sort(names)
    data.lsp = bar.text(table.concat(names, ", "))
  end
  if not cache[buf] or flags.all or flags.git then
    local git = vim.b[buf].git_tools_status or vim.b[buf].gitsigns_status_dict or {}
    data.branch = bar.text(git.head or "")
    local changes = {}
    for _, field in ipairs({ { "added", "+" }, { "changed", "~" }, { "removed", "-" } }) do
      local n = tonumber(git[field[1]]) or 0
      if n > 0 then
        changes[#changes + 1] = field[2] .. n
      end
    end
    data.diff = table.concat(changes, " ")
  end
  cache[buf] = data
  return data
end

local function value(kind, data, ctx, spec)
  if kind == "mode" then
    return ctx.mode
  end
  if kind == "location" then
    return ctx.cursor[1] .. ":" .. (ctx.cursor[2] + 1)
  end
  if kind == "progress" then
    if ctx.cursor[1] == 1 then
      return "Top"
    end
    if ctx.cursor[1] >= ctx.lines then
      return "Bot"
    end
    return math.floor(ctx.cursor[1] / ctx.lines * 100) .. "%"
  end
  if kind == "recording" then
    local register = vim.fn.reg_recording()
    return register == "" and "" or "REC @" .. register
  end
  if kind == "filename" then
    local text = spec.path == "absolute" and data.absolute
      or spec.path == "tail" and data.tail
      or bar.text(vim.fn.fnamemodify(data.absolute, ":~:."))
    return text .. (data.modified and " [+]" or "") .. (data.readonly and " [RO]" or "")
  end
  if kind == "diagnostics" then
    local parts, color = {}, nil
    local symbols = spec.symbols or data.diagnostic_symbols or {}
    local names = { "error", "warn", "info", "hint" }
    for severity, label in ipairs({ "E", "W", "I", "H" }) do
      if (data.diagnostics[severity] or 0) > 0 then
        local symbol = symbols[severity] or symbols[names[severity]] or label
        parts[#parts + 1] = bar.text(symbol) .. data.diagnostics[severity]
        color = color or "UiToolsStatus" .. ({ "Error", "Warn", "Info", "Hint" })[severity]
      end
    end
    return table.concat(parts, " "), color
  end
  if kind == "diff" then
    return data.diff, "UiToolsStatusDiff"
  end
  if kind == "cwd" then
    return ctx.cwd
  end
  return data[kind] or ""
end

local function context(win, active)
  local buf = api.nvim_win_get_buf(win)
  -- getcwd() defaults to the current tab, even when passed a window ID.
  local tabnr = api.nvim_tabpage_get_number(api.nvim_win_get_tabpage(win))
  local label = mode()
  return {
    win = win,
    buf = buf,
    active = active,
    mode = label,
    cursor = api.nvim_win_get_cursor(win),
    lines = api.nvim_buf_line_count(buf),
    width = M.options.globalstatus and vim.o.columns or api.nvim_win_get_width(win),
    cwd = bar.text(vim.fn.fnamemodify(vim.fn.getcwd(win, tabnr), ":~")),
    filetype = vim.bo[buf].filetype,
  }
end

local function surface(section, active, color)
  if not active then
    return "Inactive"
  end
  if section == "a" or section == "z" then
    return color
  end
  return (section == "b" or section == "y") and "Alt" or ""
end

local function component_color(source, section)
  if not source then
    return
  end
  source = bar.highlight(source)
  local result = {}
  for _, mode in ipairs(modes) do
    local background = surface(section, true, mode)
    local name = "UiToolsStatusComponent_" .. source .. "_" .. background
    if not component_colors[name] then
      local hl = api.nvim_get_hl(0, { name = source, link = false })
      local base = api.nvim_get_hl(0, { name = "UiToolsStatus" .. background, link = false })
      hl.bg, hl.reverse = base.bg, nil
      api.nvim_set_hl(0, name, hl)
      component_colors[name] = true
    end
    result[mode] = name
  end
  return result
end

local function component_icon(kind, data, spec)
  if spec.icon == false or not M.options.icons and spec.icon == nil then
    return ""
  end
  if type(spec.icon) == "string" then
    return spec.icon ~= "" and (bar.text(spec.icon) .. " ") or ""
  end
  if kind == "filename" or kind == "filetype" then
    return icons.prefix(
      kind == "filename" and "file" or "filetype",
      kind == "filename" and data.tail or data.filetype,
      ""
    )
  end
  local symbols = {
    mode = { "ui", "mode", "" },
    branch = { "git", "branch", "" },
    lsp = { "ui", "lsp", "" },
    location = { "ui", "location", "" },
    fileformat = { "ui", "line_ending", "↵" },
    cwd = { "directory", "cwd", "" },
  }
  local icon = symbols[kind]
  return icon and icons.prefix(unpack(icon)) or ""
end

local function compile(layout, data, ctx)
  local result = {}
  for section_index, section in ipairs(sections) do
    for index, spec in ipairs(layout[section]) do
      local kind = spec[1]
      local item = {
        kind = kind,
        section = section,
        side = section_index <= 3 and "left" or "right",
        priority = spec.priority or priorities[kind] or 50,
        color = spec.color,
        spec = spec,
      }
      local key = ctx.win .. ":" .. tostring(ctx.active) .. ":" .. section .. ":" .. index
      local function assemble()
        if spec.cond and not spec.cond(ctx) then
          return
        end
        item.icon = component_icon(kind, data, spec)
        if dynamic[kind] and not spec.fmt then
          item.dynamic = true
        else
          local text, color
          if type(kind) == "function" then
            text = kind(ctx)
          else
            text, color = value(kind, data, ctx, spec)
          end
          if spec.fmt then
            text = spec.fmt(text, ctx)
          end
          text = bar.text(text)
          text = text ~= "" and (item.icon .. text) or ""
          if spec.max_width then
            text = bar.truncate(text, spec.max_width)
          end
          item.text, item.escaped, item.width = text, bar.escape(text), bar.width(text)
          item.color = spec.color or color
        end
        item.colors = component_color(item.color, section)
        result[#result + 1] = item
      end
      -- Like native statusline expressions, user callbacks see the target
      -- window's vim.b/vim.bo, even when it is an inactive split.
      local ok, err
      if type(kind) == "function" or kind == "filename" or spec.cond or spec.fmt then
        ok, err = pcall(api.nvim_win_call, ctx.win, assemble)
      else
        ok, err = pcall(assemble)
      end
      if not ok then
        M.errors[key] = tostring(err)
      end
    end
  end
  return result
end

local function update()
  if not M.enabled then
    return
  end
  synchronize()
  local used = {}
  component_colors = {}
  M.errors = {}
  for win in pairs(windows) do
    local buf = api.nvim_win_get_buf(win)
    local profile = bar.profile(buf, "statusline", M.options)
    if profile ~= nil then
      local frame = { special = true }
      for _, state in ipairs({ "active", "inactive" }) do
        local ok, result = pcall(api.nvim_win_call, win, function()
          return bar.profile_text(profile, context(win, state == "active"))
        end)
        if not ok then
          M.errors[win .. ":" .. state] = tostring(result)
        end
        frame[state] = ok and result or { text = "", align = "left" }
      end
      frames[win] = frame
    else
      if not used[buf] then
        snapshot(buf, all_dirty and { all = true } or dirty[buf] or {})
        used[buf] = true
      end
      frames[win] = {
        active = compile(M.options.sections, cache[buf], context(win, true)),
        inactive = compile(M.options.inactive_sections, cache[buf], context(win, false)),
      }
    end
  end
  -- Keep only displayed buffers; thousands of hidden buffers cost nothing here.
  for buf in pairs(cache) do
    if not used[buf] then
      cache[buf] = nil
    end
  end
  dirty, all_dirty = {}, false
  if vim.v.vim_did_enter == 1 then
    vim.cmd("redrawstatus")
  end
end

local function request(kind, buf)
  if not M.enabled then
    return
  end
  if kind then
    if buf and buf > 0 then
      dirty[buf] = dirty[buf] or {}
      dirty[buf][kind] = true
    else
      for id in pairs(cache) do
        dirty[id] = dirty[id] or {}
        dirty[id][kind] = true
      end
    end
  end
  queue.request()
end

local function measure(nodes)
  local total = 0
  for i, node in ipairs(nodes) do
    local previous = nodes[i - 1]
    local spacing = previous
        and previous.side == node.side
        and (previous.section == node.section and M.options.component_width or M.options.section_width[node.side])
      or 0
    total = total + node.width + 2 + spacing
    if
      node.side == "left"
      and (not nodes[i + 1] or nodes[i + 1].side ~= "left")
      and node.surface ~= node.base
    then
      total = total + M.options.section_width.left
    elseif
      node.side == "right"
      and (not previous or previous.side ~= "right")
      and node.surface ~= node.base
    then
      total = total + M.options.section_width.right
    end
  end
  return total
end

local function shorten(node, width)
  -- Reuse clipped strings on cursor-only redraws of a narrow split.
  local item = node.item
  item.clipped = item.clipped or {}
  local key = width .. ":" .. node.text
  if not item.clipped[key] then
    -- The viewport changes have bounded cache size, even with dynamic providers.
    item.clipped = { [key] = bar.truncate(node.text, width) }
  end
  node.text = item.clipped[key]
  node.escaped, node.width = bar.escape(node.text), bar.width(node.text)
end

function M.render()
  if not M.enabled then
    return ""
  end
  local win = tonumber(vim.g.statusline_winid) or api.nvim_get_current_win()
  if not api.nvim_win_is_valid(win) then
    return ""
  end
  local frame = frames[win]
  if not frame then
    return "%<%f%=%l:%c "
  end
  local active = win == api.nvim_get_current_win()
  local layout = active and frame.active or frame.inactive
  local width = M.options.globalstatus and vim.o.columns or api.nvim_win_get_width(win)
  if frame.special then
    return bar.render_profile(layout, width, active and "UiToolsStatus" or "UiToolsStatusInactive")
  end
  local label, color = mode()
  local base_surface = active and "" or "Inactive"
  local buf = api.nvim_win_get_buf(win)
  local ctx = { mode = label, cursor = api.nvim_win_get_cursor(win), lines = api.nvim_buf_line_count(buf) }
  local nodes = {}
  for _, item in ipairs(layout) do
    local text, escaped, length = item.text, item.escaped, item.width
    if item.dynamic then
      text = bar.text(value(item.kind, {}, ctx, item.spec))
      text = text ~= "" and (item.icon .. text) or ""
      if item.spec.max_width then
        text = bar.truncate(text, item.spec.max_width)
      end
      escaped, length = bar.escape(text), bar.width(text)
    end
    if text and text ~= "" then
      nodes[#nodes + 1] = {
        text = text,
        escaped = escaped,
        width = length,
        section = item.section,
        side = item.side,
        priority = item.priority,
        item = item,
        surface = surface(item.section, active, color),
        base = base_surface,
      }
    end
  end
  if measure(nodes) > width then
    for _, node in ipairs(nodes) do
      if node.item.kind == "filename" then
        shorten(node, math.max(8, math.floor(width * 0.35)))
      end
    end
  end
  while #nodes > 1 and measure(nodes) > width do
    local drop = 1
    for i = 2, #nodes do
      if nodes[i].priority < nodes[drop].priority then
        drop = i
      end
    end
    table.remove(nodes, drop)
  end
  if #nodes == 1 and measure(nodes) > width then
    shorten(nodes[1], math.max(0, nodes[1].width - (measure(nodes) - width)))
  end
  local base = active and "UiToolsStatus" or "UiToolsStatusInactive"
  local result, right = { "%#" .. base .. "#" }, false
  local function edge(from, to, side)
    local glyph = M.options.section_separator[side]
    if glyph == "" then
      return
    end
    -- Right-pointing glyphs paint the departing surface; left-pointing ones
    -- paint the arriving surface. Both share the cached transition palette.
    local a, b = from, to
    if side == "right" then
      a, b = to, from
    end
    result[#result + 1] = "%#UiToolsStatusEdge" .. a .. "To" .. b .. "#" .. bar.escape(glyph)
  end
  for i, node in ipairs(nodes) do
    local previous = nodes[i - 1]
    if node.side == "right" and not right then
      result[#result + 1], right = "%#" .. base .. "#%=", true
      if node.surface ~= base_surface then
        edge(base_surface, node.surface, "right")
      end
    end
    if previous and previous.side == node.side then
      if previous.section == node.section then
        result[#result + 1] = "%#UiToolsStatusDivider"
          .. node.surface
          .. "#"
          .. bar.escape(M.options.component_separator)
      else
        edge(previous.surface, node.surface, node.side)
      end
    end
    local hl = active and node.item.colors and node.item.colors[color] or "UiToolsStatus" .. node.surface
    result[#result + 1] = "%#" .. bar.highlight(hl) .. "# " .. node.escaped .. " "
    if
      node.side == "left"
      and (not nodes[i + 1] or nodes[i + 1].side ~= "left")
      and node.surface ~= base_surface
    then
      edge(node.surface, base_surface, "left")
    end
  end
  if not right then
    result[#result + 1] = "%#" .. base .. "#%="
  end
  return table.concat(result)
end

function M.refresh()
  if M.enabled then
    all_dirty = true
    update()
  end
end

-- Re-evaluate custom components without invalidating provider snapshots.
function M.update()
  request()
end

local function normalize(layout)
  for _, section in ipairs(sections) do
    local items = {}
    for _, spec in ipairs(layout[section]) do
      if type(spec) ~= "table" then
        spec = { spec }
      end
      assert(
        type(spec[1]) == "function" or priorities[spec[1]],
        "Unknown statusline component: " .. tostring(spec[1])
      )
      assert(
        not spec.color or type(spec.color) == "string",
        "statusline component.color must be a highlight name"
      )
      assert(
        not spec.priority or type(spec.priority) == "number",
        "statusline component.priority must be a number"
      )
      assert(
        not spec.max_width or type(spec.max_width) == "number" and spec.max_width >= 1,
        "statusline component.max_width must be positive"
      )
      assert(not spec.cond or type(spec.cond) == "function", "statusline component.cond must be a function")
      assert(not spec.fmt or type(spec.fmt) == "function", "statusline component.fmt must be a function")
      assert(
        not spec.symbols or type(spec.symbols) == "table",
        "statusline component.symbols must be a table"
      )
      assert(
        spec.icon == nil or spec.icon == false or type(spec.icon) == "string",
        "statusline component.icon must be text or false"
      )
      items[#items + 1] = spec
      custom = custom or type(spec[1]) == "function" or spec.cond ~= nil or spec.fmt ~= nil
    end
    layout[section] = items
  end
  return layout
end

function M.setup(opts)
  M.disable()
  opts = opts or {}
  local config = vim.tbl_deep_extend("force", {
    refresh = 30,
    globalstatus = false,
    filetypes = {},
    force = false,
    exclude = { "ui_tools_dashboard" },
    icons = true,
    component_separator = "│",
    section_separator = { left = "", right = "" },
  }, opts)
  config.sections = vim.tbl_extend("force", vim.deepcopy(defaults), opts.sections or {})
  config.inactive_sections = vim.tbl_extend("force", vim.deepcopy(inactive), opts.inactive_sections or {})
  assert(type(config.refresh) == "number" and config.refresh >= 0, "statusline.refresh must be nonnegative")
  assert(type(config.globalstatus) == "boolean", "statusline.globalstatus must be boolean")
  assert(type(config.icons) == "boolean", "statusline.icons must be boolean")
  if type(config.section_separator) == "string" then
    config.section_separator = { left = config.section_separator, right = config.section_separator }
  end
  assert(
    type(config.component_separator) == "string"
      and type(config.section_separator) == "table"
      and type(config.section_separator.left) == "string"
      and type(config.section_separator.right) == "string",
    "statusline separators must be text or a { left, right } section pair"
  )
  config.component_separator = bar.text(config.component_separator)
  config.component_width, config.section_width = bar.width(config.component_separator), {}
  for _, side in ipairs({ "left", "right" }) do
    config.section_separator[side] = bar.text(config.section_separator[side])
    config.section_width[side] = bar.width(config.section_separator[side])
  end
  custom = bar.validate_profiles(config.filetypes)
  normalize(config.sections)
  normalize(config.inactive_sections)
  M.options, M.enabled, all_dirty = config, true, true
  queue = bar.scheduler(config.refresh, update)
  require("ui_tools.theme").bind("statusline", function(c)
    highlights(c)
    request()
  end)
  local group = util.group("Statusline")
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      request()
    end,
  })
  api.nvim_create_autocmd(
    { "WinEnter", "BufWinEnter", "WinClosed", "TabEnter", "VimResized", "WinResized" },
    {
      group = group,
      callback = function()
        request()
      end,
    }
  )
  api.nvim_create_autocmd({ "BufFilePost", "FileType", "BufWritePost", "BufModifiedSet" }, {
    group = group,
    callback = function(args)
      request("metadata", args.buf)
    end,
  })
  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "fileencoding", "encoding", "fileformat", "filetype", "readonly", "modified" },
    callback = function(args)
      if args.match == "encoding" then
        request("metadata")
      else
        request("metadata", args.buf)
      end
    end,
  })
  api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      request("metadata")
    end,
  })
  api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
      request("diagnostics", args.buf)
    end,
  })
  api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    group = group,
    callback = function(args)
      request("lsp", args.buf)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "GitToolsUpdate", "GitSignsUpdate", "ThemeToolsIconsChanged", "ThemeToolsReady" },
    callback = function(args)
      request((args.match == "GitToolsUpdate" or args.match == "GitSignsUpdate") and "git" or nil)
    end,
  })
  api.nvim_create_autocmd({ "ModeChanged", "RecordingEnter", "RecordingLeave" }, {
    group = group,
    callback = function()
      request()
    end,
  })
  if custom then
    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
      group = group,
      callback = function()
        request()
      end,
    })
  end
  update()
end

function M.disable()
  require("ui_tools.theme").unbind("statusline")
  M.enabled = false
  if queue then
    queue.cancel()
    queue = nil
  end
  pcall(api.nvim_del_augroup_by_name, "UiToolsStatusline")
  for win in pairs(windows) do
    release(win)
  end
  if previous_laststatus ~= nil and vim.o.laststatus == applied_laststatus then
    vim.o.laststatus = previous_laststatus
  end
  windows, blocked, cache, frames, dirty, M.errors = {}, {}, {}, {}, {}, {}
  buffers = {}
  previous_laststatus, applied_laststatus, all_dirty = nil, nil, false
end

return M
