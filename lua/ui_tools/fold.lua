local M = { enabled = false }
local api = vim.api
local expression = "v:lua.require'ui_tools.fold'.text()"
local windows, blocked, previews = {}, {}, {}
local generation = 0
local keys = { "foldmethod", "foldexpr", "foldtext", "foldenable", "foldlevel", "fillchars" }

local function option(win, name)
  return api.nvim_get_option_value(name, { win = win, scope = "local" })
end

local function source(buf)
  if M.options.method == "auto" then
    local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
    if ok and parser then
      local found, query = pcall(vim.treesitter.query.get, parser:lang(), "folds")
      if found and query then
        return "expr", parser
      end
    end
  end
  return "indent"
end

local function eligible(win, buf)
  return api.nvim_win_get_config(win).relative == ""
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype ~= ""
    and vim.b[buf].ui_tools_disable ~= true
    and not vim.tbl_contains(M.options.exclude, vim.bo[buf].filetype)
end

local function release(win, state)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= state.buf then
    return
  end
  for _, key in ipairs(keys) do
    if state.applied[key] ~= nil and option(win, key) == state.applied[key] then
      api.nvim_set_option_value(key, state.before[key], { win = win, scope = "local" })
    end
  end
end

function M.attach(win)
  if not M.enabled or not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if vim.wo[win].diff then
    -- Native diff takes ownership; leaving diff needs a fresh initialization.
    if windows[win] and windows[win][buf] then
      windows[win][buf].invalid = true
    end
    return
  end
  if not eligible(win, buf) or blocked[win] and blocked[win][buf] then
    return
  end
  local method, parser = source(buf)
  windows[win] = windows[win] or {}
  local state = windows[win][buf]
  if state and not state.invalid then
    for _, key in ipairs({ "foldmethod", "foldexpr", "foldtext" }) do
      if state.applied[key] ~= nil and option(win, key) ~= state.applied[key] then
        blocked[win] = blocked[win] or {}
        blocked[win][buf] = true
        return
      end
    end
    if state.method == method then
      return
    end
  elseif not state and not M.options.force then
    local value = option(win, "foldtext")
    local native = api.nvim_get_option_info2("foldtext", {}).default
    if M.options.text and value ~= "" and value ~= native and value ~= expression then
      return
    end
    local expr = option(win, "foldexpr")
    if option(win, "foldmethod") == "expr" and expr ~= "0" and expr ~= "v:lua.vim.treesitter.foldexpr()" then
      return
    end
  end
  local before = state and state.before or {}
  if not state then
    for _, key in ipairs(keys) do
      before[key] = option(win, key)
    end
    -- New splits inherit the expression, but disabling must remove our owner.
    if before.foldtext == expression then
      before.foldtext = api.nvim_get_option_info2("foldtext", {}).default
    end
  end
  state = { buf = buf, method = method, before = before, applied = {} }
  windows[win][buf] = state
  local values = {
    foldmethod = method,
    foldexpr = method == "expr" and "v:lua.vim.treesitter.foldexpr()" or "0",
    foldenable = true,
    foldlevel = M.options.level == "open" and 99 or M.options.level,
  }
  if M.options.text then
    values.foldtext = expression
  end
  for key, value in pairs(values) do
    api.nvim_set_option_value(key, value, { win = win, scope = "local" })
    state.applied[key] = value
  end
  if next(M.options.fillchars) then
    api.nvim_win_call(win, function()
      vim.opt_local.fillchars:append(M.options.fillchars)
    end)
    state.applied.fillchars = option(win, "fillchars")
  end
  local current = generation
  local function initialize()
    vim.schedule(function()
      if not M.enabled or generation ~= current or not windows[win] or windows[win][buf] ~= state then
        return
      end
      if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then
        windows[win][buf] = nil
        return
      end
      if vim.wo[win].diff then
        state.invalid = true
        return
      end
      if option(win, "foldmethod") ~= state.method or option(win, "foldlevel") ~= state.applied.foldlevel then
        return
      end
      -- :normal in Select mode replaces the selected text before its commands.
      -- A parser callback can finish while a snippet is selecting a field.
      local mode = api.nvim_get_mode().mode
      if mode ~= "n" and mode:sub(1, 1) ~= "i" then
        if not state.waiting_mode then
          state.waiting_mode = api.nvim_create_autocmd("ModeChanged", {
            group = "UiToolsFold",
            pattern = { "*:n", "*:i" },
            once = true,
            callback = function()
              state.waiting_mode = nil
              initialize()
            end,
          })
        end
        return
      end
      local cursor = api.nvim_win_get_cursor(win)
      api.nvim_win_call(win, function()
        local view = vim.fn.winsaveview()
        -- FileType handlers can invalidate Tree-sitter's cache after attach.
        vim.cmd("normal! zX")
        if M.options.level == "open" then
          -- Use the real maximum depth so the first zm works immediately.
          vim.cmd("normal! zR")
        end
        vim.fn.winrestview(view)
      end)
      -- Initialization can finish in Insert mode; preserve the EOL byte column.
      api.nvim_win_set_cursor(win, cursor)
      state.applied.foldlevel = option(win, "foldlevel")
    end)
  end
  if parser then
    api.nvim_win_call(win, function()
      vim.treesitter.foldexpr(1)
    end)
    parser:parse(nil, function(err)
      if not err then
        initialize()
      end
    end)
  else
    initialize()
  end
end

-- Read public highlight queries once per folded line, rather than once per byte.
local function highlights(buf, row, limit)
  local result, priorities = {}, {}
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not ok or not parser or not vim.treesitter.highlighter.active[buf] then
    return result
  end
  parser:for_each_tree(function(tree, language)
    local query = vim.treesitter.query.get(language:lang(), "highlights")
    if not query then
      return
    end
    for id, node, metadata in query:iter_captures(tree:root(), buf, row, row + 1) do
      local range = vim.treesitter.get_range(node, buf, metadata[id])
      local first, col, last, end_col = range[1], range[2], range[4], range[5]
      if first <= row and last >= row then
        local from = first < row and 0 or col
        local to = last > row and limit or end_col
        local priority = tonumber(metadata.priority or (metadata[id] or {}).priority) or 100
        for byte = from, math.min(to, limit) - 1 do
          if priority >= (priorities[byte] or 0) then
            result[byte] = "@" .. query.captures[id] .. "." .. language:lang()
            priorities[byte] = priority
          end
        end
      end
    end
  end)
  return result
end

function M.text()
  local line = vim.fn.getline(vim.v.foldstart)
  if not M.enabled then
    return line
  end
  local suffix = M.options.suffix:format(vim.v.foldend - vim.v.foldstart)
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local width = math.max(0, info.width - info.textoff)
  if vim.fn.strdisplaywidth(suffix) > width then
    suffix = tostring(vim.v.foldend - vim.v.foldstart)
    suffix = suffix:sub(1, width)
  end
  local available = math.max(0, width - vim.fn.strdisplaywidth(suffix))
  local chunks, used, byte = {}, 0, 0
  local colors =
    highlights(vim.api.nvim_get_current_buf(), vim.v.foldstart - 1, math.min(#line, available * 4))
  for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local size = vim.fn.strdisplaywidth(char, used)
    if used + size > available then
      break
    end
    local color = colors[byte]
    if not color then
      local id = vim.fn.synID(vim.v.foldstart, byte + 1, true)
      color = id ~= 0 and vim.fn.synIDattr(id, "name") or "Folded"
    end
    local text = char == "\t" and string.rep(" ", size) or char
    local previous = chunks[#chunks]
    if previous and previous[2] == color then
      previous[1] = previous[1] .. text
    else
      chunks[#chunks + 1] = { text, color }
    end
    used, byte = used + size, byte + #char
  end
  chunks[#chunks + 1] = { suffix, "MoreMsg" }
  return chunks
end

function M.preview()
  if not M.enabled then
    return
  end
  local first = vim.fn.foldclosed(".")
  if first == -1 then
    return
  end
  local last = vim.fn.foldclosedend(".")
  local opts = M.options.preview
  local stop = math.min(last, first + opts.max_lines - 1)
  local contents = api.nvim_buf_get_lines(0, first - 1, stop, false)
  local title = (" Lines %d–%d%s "):format(
    first,
    last,
    stop < last and (" (first %d shown)"):format(opts.max_lines) or ""
  )
  local buf, win = vim.lsp.util.open_floating_preview(contents, vim.bo.filetype, {
    border = opts.border,
    title = title,
    focus_id = "ui_tools_fold_preview",
    wrap = false,
    max_width = math.max(1, math.min(opts.max_width, vim.o.columns - 4)),
    max_height = math.max(1, math.min(opts.max_height, vim.o.lines - 4)),
    close_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufHidden" },
  })
  previews[win] = buf
  vim.keymap.set("n", "<Esc>", "<Cmd>close<CR>", { buffer = buf, silent = true, nowait = true })
  return buf, win
end

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "fold options must be a table")
  opts = vim.deepcopy(opts or {})
  local config = vim.tbl_deep_extend("force", {
    method = "auto",
    level = "open",
    text = true,
    suffix = "  … %d",
    fillchars = { fold = " ", foldopen = "▾", foldsep = "│", foldclose = "▸" },
    exclude = {},
    force = false,
    preview = { border = "rounded", max_width = 100, max_height = 20, max_lines = 200 },
  }, opts or {})
  assert(config.method == "auto" or config.method == "indent", "fold.method must be auto or indent")
  assert(
    config.level == "open" or type(config.level) == "number" and config.level >= 0 and config.level % 1 == 0,
    "fold.level must be open or a nonnegative integer"
  )
  assert(
    type(config.text) == "boolean" and type(config.force) == "boolean",
    "fold.text/force must be boolean"
  )
  assert(type(config.suffix) == "string" and pcall(string.format, config.suffix, 1), "Invalid fold.suffix")
  for _, key in ipairs({ "max_width", "max_height", "max_lines" }) do
    local value = config.preview[key]
    assert(
      type(value) == "number" and value >= 1 and value % 1 == 0,
      "fold.preview." .. key .. " must be a positive integer"
    )
  end
  for key, value in pairs(config.fillchars) do
    assert(
      vim.tbl_contains({ "fold", "foldopen", "foldclose", "foldsep" }, key),
      "Unknown fold fill character: " .. key
    )
    require("ui_tools.util").cell(value, "fold.fillchars." .. key)
  end
  return config
end

function M.setup(opts)
  return M._setup(M.resolve(opts))
end

function M._setup(resolved)
  M.disable()
  M.options = resolved
  M.enabled = true
  local group = require("ui_tools.util").group("Fold")
  api.nvim_create_autocmd({ "FileType", "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(event)
      if event.event == "FileType" then
        for _, win in ipairs(vim.fn.win_findbuf(event.buf)) do
          M.attach(win)
        end
      else
        M.attach(api.nvim_get_current_win())
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local win = tonumber(event.match)
      windows[win], blocked[win], previews[win] = nil, nil, nil
    end,
  })
  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "diff",
    callback = function()
      local win = api.nvim_get_current_win()
      local current = generation
      vim.schedule(function()
        if M.enabled and generation == current then
          M.attach(win)
        end
      end)
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      for _, states in pairs(windows) do
        states[event.buf] = nil
      end
      for _, states in pairs(blocked) do
        states[event.buf] = nil
      end
    end,
  })
  for _, win in ipairs(api.nvim_list_wins()) do
    M.attach(win)
  end
end

function M.disable()
  M.enabled = false
  generation = generation + 1
  pcall(api.nvim_del_augroup_by_name, "UiToolsFold")
  for win, buf in pairs(previews) do
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      api.nvim_win_close(win, true)
    end
  end
  for win, states in pairs(windows) do
    if api.nvim_win_is_valid(win) then
      local state = states[api.nvim_win_get_buf(win)]
      if state then
        release(win, state)
      end
    end
  end
  windows, blocked, previews = {}, {}, {}
end

return M
