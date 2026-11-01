local M = { enabled = false, bars = {}, providers = {}, errors = {} }
local util = require("ui_tools.util")
local ns = vim.api.nvim_create_namespace("UiToolsScrollbar")
local queued, generation = false, 0
local search_cache = {}

function M.project(line, count, height)
  if count <= 1 or height <= 1 then
    return 1
  end
  return math.max(1, math.min(height, math.floor((line - 1) * (height - 1) / (count - 1)) + 1))
end

local function close(win)
  local bar = M.bars[win]
  if not bar then
    return
  end
  M.bars[win] = nil
  if vim.api.nvim_win_is_valid(bar.win) then
    pcall(vim.api.nvim_win_close, bar.win, true)
  end
  if vim.api.nvim_buf_is_valid(bar.buf) then
    pcall(vim.api.nvim_buf_delete, bar.buf, { force = true })
  end
end

local function diagnostics(ctx)
  local marks = {}
  local groups = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }
  for _, diagnostic in ipairs(vim.diagnostic.get(ctx.buf)) do
    local severity = diagnostic.severity or 1
    marks[#marks + 1] = { line = diagnostic.lnum + 1, hl = groups[severity], priority = 100 - severity }
  end
  return marks
end

local function search(ctx)
  if vim.v.hlsearch == 0 or not vim.o.hlsearch then
    return {}
  end
  local pattern = vim.fn.getreg("/")
  if pattern == "" then
    return {}
  end
  local key = table.concat({
    vim.api.nvim_buf_get_changedtick(ctx.buf),
    pattern,
    tostring(vim.o.ignorecase),
    tostring(vim.o.smartcase),
    tostring(vim.o.magic),
  }, "\001")
  if search_cache[ctx.buf] and search_cache[ctx.buf].key == key then
    return search_cache[ctx.buf].marks
  end
  local insensitive = vim.o.ignorecase and not (vim.o.smartcase and pattern:gsub("\\.", ""):find("%u"))
  local expression = (vim.o.magic and "\\m" or "\\M") .. (insensitive and "\\c" or "\\C") .. pattern
  local ok, regex = pcall(vim.regex, expression)
  if not ok then
    return {}
  end
  local marks, bytes = {}, 0
  local started = vim.uv.hrtime()
  local last = math.min(ctx.count, M.options.search_limit)
  local lines = vim.api.nvim_buf_get_lines(ctx.buf, 0, last, false)
  for row, line in ipairs(lines) do
    bytes = bytes + #line
    if bytes > 2 * 1024 * 1024 or (vim.uv.hrtime() - started) / 1e6 > M.options.search_timeout then
      break
    end
    if #line <= 4096 and regex:match_line(ctx.buf, row - 1) ~= nil then
      marks[#marks + 1] = { line = row, hl = "UiToolsSearch", priority = 70 }
      if #marks >= 1000 then
        break
      end
    end
  end
  search_cache[ctx.buf] = { key = key, marks = marks }
  return marks
end

local function collect(ctx)
  local result = {}
  local sources = {}
  if M.options.diagnostics then
    sources.diagnostics = diagnostics
  end
  if M.options.search then
    sources.search = search
  end
  for name, provider in pairs(M.providers) do
    sources[name] = provider.callback
  end
  for _, name in ipairs(vim.fn.sort(vim.tbl_keys(sources))) do
    local provider = sources[name]
    local ok, marks = pcall(provider, ctx)
    if ok and type(marks) == "table" then
      local valid, err = pcall(function()
        for _, mark in ipairs(marks) do
          assert(
            type(mark.line) == "number" and mark.line >= 1 and mark.line % 1 == 0,
            "mark.line must be a positive integer"
          )
          if mark.char then
            util.cell(mark.char, "scrollbar mark.char")
          end
          if mark.end_line then
            assert(
              type(mark.end_line) == "number" and mark.end_line % 1 == 0 and mark.end_line >= mark.line,
              "mark.end_line must follow mark.line"
            )
          end
          assert(mark.priority == nil or type(mark.priority) == "number", "mark.priority must be numeric")
          assert(mark.hl == nil or type(mark.hl) == "string", "mark.hl must be a highlight group name")
          local first = M.project(mark.line, ctx.count, ctx.height)
          local last = M.project(mark.end_line or mark.line, ctx.count, ctx.height)
          for row = first, last do
            local previous = result[row]
            if not previous or (mark.priority or 50) > (previous.priority or 50) then
              result[row] = mark
            end
          end
        end
      end)
      if valid then
        M.errors[name] = nil
      else
        M.errors[name] = tostring(err)
      end
    else
      M.errors[name] = tostring(marks)
    end
  end
  return result
end

local function draw(ctx)
  local bar = M.bars[ctx.win]
  if not bar or not vim.api.nvim_win_is_valid(bar.win) then
    close(ctx.win)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "win",
      win = ctx.win,
      row = 0,
      col = ctx.width - 1,
      width = 1,
      height = ctx.height,
      style = "minimal",
      border = "none",
      focusable = false,
      mouse = false,
      zindex = 60,
    })
    bar = { win = win, buf = buf }
    M.bars[ctx.win] = bar
    vim.wo[win].winblend = M.options.blend
    vim.wo[win].winhighlight = "Normal:UiToolsScrollbar,NormalFloat:UiToolsScrollbar"
  end
  local geometry = ctx.width .. ":" .. ctx.height
  if bar.geometry ~= geometry then
    vim.api.nvim_win_set_config(
      bar.win,
      { relative = "win", win = ctx.win, row = 0, col = ctx.width - 1, width = 1, height = ctx.height }
    )
    bar.geometry = geometry
  end
  local marks = collect(ctx)
  local first = M.project(ctx.top, ctx.count, ctx.height)
  local last = M.project(ctx.bottom, ctx.count, ctx.height)
  local lines, colors = {}, {}
  for row = 1, ctx.height do
    local mark = marks[row]
    local handle = row >= first and row <= last
    lines[row] = mark and (mark.char or M.options.mark) or handle and M.options.handle or " "
    colors[row] = mark and (mark.hl or "UiToolsSearch")
      or handle and "UiToolsScrollbarHandle"
      or "UiToolsScrollbar"
  end
  local key = table.concat(lines, "\n") .. "\000" .. table.concat(colors, "\n")
  if key ~= bar.key then
    vim.api.nvim_buf_set_lines(bar.buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(bar.buf, ns, 0, -1)
    for row, hl in ipairs(colors) do
      vim.api.nvim_buf_set_extmark(bar.buf, ns, row - 1, 0, { end_col = #lines[row], hl_group = hl })
    end
    bar.key = key
  end
end

function M.refresh()
  if not M.enabled then
    return
  end
  local wanted = {}
  local tab = vim.api.nvim_get_current_tabpage()
  local focus = package.loaded["ui_tools.focus"]
  focus = focus and focus.state()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if util.eligible(win, buf, M.options) and (not focus or focus.win == win) then
      local info = vim.fn.getwininfo(win)[1]
      local count = vim.api.nvim_buf_line_count(buf)
      if
        info.width >= M.options.min_width
        and (not M.options.hide_if_all_visible or info.topline > 1 or info.botline < count)
      then
        wanted[win] = true
        draw({
          win = win,
          buf = buf,
          width = info.width,
          height = info.height,
          count = count,
          top = info.topline,
          bottom = info.botline,
        })
      end
    end
  end
  for win in pairs(M.bars) do
    if not wanted[win] then
      close(win)
    end
  end
  for buf in pairs(search_cache) do
    if not vim.api.nvim_buf_is_loaded(buf) then
      search_cache[buf] = nil
    end
  end
end

local function schedule()
  if queued or not M.enabled then
    return
  end
  queued = true
  local current = generation
  vim.defer_fn(function()
    if current ~= generation then
      return
    end
    queued = false
    M.refresh()
  end, M.options.refresh)
end

function M.register(name, callback)
  assert(
    type(name) == "string" and name ~= "" and type(callback) == "function",
    "provider requires a name and callback"
  )
  local provider = { callback = callback }
  M.providers[name] = provider
  schedule()
  return function()
    if M.providers[name] == provider then
      M.providers[name], M.errors[name] = nil, nil
      schedule()
    end
  end
end

function M.setup(opts)
  M.disable()
  opts = vim.tbl_deep_extend("force", {
    handle = "┃",
    mark = "•",
    blend = 30,
    diagnostics = true,
    search = true,
    hide_if_all_visible = true,
    min_width = 20,
    refresh = 30,
    search_limit = 20000,
    search_timeout = 10,
  }, opts or {})
  util.cell(opts.handle, "scrollbar.handle")
  util.cell(opts.mark, "scrollbar.mark")
  assert(
    type(opts.blend) == "number" and opts.blend >= 0 and opts.blend <= 100,
    "scrollbar.blend must be 0..100"
  )
  for _, field in ipairs({ "min_width", "refresh", "search_limit", "search_timeout" }) do
    assert(
      type(opts[field]) == "number" and opts[field] >= 0,
      "scrollbar." .. field .. " must be nonnegative"
    )
  end
  M.options, M.enabled = opts, true
  util.hl({ UiToolsScrollbar = "NormalFloat", UiToolsScrollbarHandle = "Visual", UiToolsSearch = "Search" })
  local group = util.group("Scrollbar")
  vim.api.nvim_create_autocmd({
    "BufWinEnter",
    "WinEnter",
    "WinClosed",
    "WinScrolled",
    "WinResized",
    "VimResized",
    "TabEnter",
    "TextChanged",
    "TextChangedI",
    "DiagnosticChanged",
    "CmdlineLeave",
    "CursorMoved",
    "CursorMovedI",
    "OptionSet",
    "ColorScheme",
  }, { group = group, callback = schedule })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "GitToolsUpdate", callback = schedule })
  M.refresh()
end

function M.disable()
  M.enabled = false
  generation, queued = generation + 1, false
  pcall(vim.api.nvim_del_augroup_by_name, "UiToolsScrollbar")
  for win in pairs(M.bars) do
    close(win)
  end
  search_cache = {}
end

return M
