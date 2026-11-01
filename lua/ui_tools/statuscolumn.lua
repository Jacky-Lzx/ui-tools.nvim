local M = { windows = {}, cache = {}, enabled = false }
local util = require("ui_tools.util")
local format = "%!v:lua.require'ui_tools.statuscolumn'.render()"
local generation = 0
local queued = false

local function escape(text)
  return (text or ""):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end

local function label(text, hl)
  -- Highlight names originate in Neovim; drop format metacharacters defensively.
  hl = (hl or "SignColumn"):gsub("[^%w_@.%-]", "")
  return "%#" .. hl .. "#" .. escape(text) .. "%*"
end

local function release(win)
  local previous = M.windows[win]
  if previous and vim.api.nvim_win_is_valid(win) and vim.wo[win].statuscolumn == format then
    vim.wo[win].statuscolumn = previous
  end
  M.windows[win], M.cache[win] = nil, nil
end

function M.refresh()
  if not M.enabled then
    return
  end
  local opts = M.options
  local names = {}
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    names[id] = name
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not util.eligible(win, buf, opts) or vim.w[win].ui_tools_statuscolumn_disable then
      release(win)
    elseif M.windows[win] ~= nil or vim.wo[win].statuscolumn == "" or opts.force then
      if M.windows[win] == nil then
        M.windows[win] = vim.wo[win].statuscolumn
        vim.wo[win].statuscolumn = format
      end
      if vim.wo[win].statuscolumn == format then
        local first, last = unpack(vim.api.nvim_win_call(win, function()
          return { vim.fn.line("w0"), vim.fn.line("w$") }
        end))
        local rows = {}
        for _, mark in
          ipairs(
            vim.api.nvim_buf_get_extmarks(
              buf,
              -1,
              { first - 1, 0 },
              { last - 1, -1 },
              { details = true, type = "sign" }
            )
          )
        do
          local details, row = mark[4], mark[2] + 1
          local name = (names[details.ns_id] or "") .. " " .. (details.sign_name or "")
          local kind = "sign"
          for _, pattern in ipairs(opts.git_patterns) do
            if name:find(pattern, 1, true) then
              kind = "git"
              break
            end
          end
          rows[row] = rows[row] or {}
          local previous = rows[row][kind]
          if not previous or (details.priority or 0) > (previous.priority or 0) then
            rows[row][kind] = details
          end
        end
        for _, mark in ipairs(vim.fn.getmarklist(buf)) do
          if mark.mark:match("^'[a-z]$") then
            local row = mark.pos[2]
            rows[row] = rows[row] or {}
            rows[row].mark = mark.mark:sub(2)
          end
        end
        M.cache[win] = rows
      end
    end
  end
  for win in pairs(M.windows) do
    if not vim.api.nvim_win_is_valid(win) then
      M.windows[win], M.cache[win] = nil, nil
    end
  end
  util.redraw()
end

local function schedule()
  if queued then
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

local function part(kind, win, row)
  if kind == "number" then
    if not vim.wo[win].number and not vim.wo[win].relativenumber then
      return ""
    end
    if vim.v.virtnum ~= 0 then
      return "%=" .. string.rep(" ", vim.wo[win].numberwidth)
    end
    local value = vim.v.lnum
    if vim.wo[win].relativenumber then
      value = vim.v.relnum == 0 and (vim.wo[win].number and vim.v.lnum or 0) or vim.v.relnum
    end
    local width = math.max(
      vim.wo[win].numberwidth - 1,
      #tostring(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)))
    )
    return label(string.format("%" .. width .. "d ", value), vim.v.relnum == 0 and "CursorLineNr" or "LineNr")
  end
  if kind == "fold" then
    local text = " "
    if vim.v.virtnum == 0 and vim.wo[win].foldenable then
      -- statuscolumn expressions execute in the target window's context.
      if vim.fn.foldclosed(vim.v.lnum) == vim.v.lnum then
        text = M.options.folds.closed
      elseif vim.fn.foldlevel(vim.v.lnum) > vim.fn.foldlevel(math.max(1, vim.v.lnum - 1)) then
        text = M.options.folds.open
      end
    end
    return "%@v:lua.require'ui_tools.statuscolumn'.click@" .. label(text, "FoldColumn") .. "%T"
  end
  if vim.v.virtnum ~= 0 then
    return "  "
  end
  if kind == "mark" then
    return label((row.mark or " ") .. " ", "UiToolsMark")
  end
  local sign = row[kind]
  if not sign then
    return "  "
  end
  local text = sign.sign_text or " "
  local width = vim.fn.strdisplaywidth(text)
  return label(text .. string.rep(" ", math.max(0, 2 - width)), sign.sign_hl_group)
end

function M.render()
  if not M.enabled then
    return ""
  end
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local row = (M.cache[win] or {})[vim.v.lnum] or {}
  local result = {}
  for _, kind in ipairs(M.options.layout) do
    result[#result + 1] = part(kind, win, row)
  end
  return table.concat(result)
end

function M.click(_, _, button)
  if button ~= "l" or not M.enabled then
    return
  end
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or mouse.line == 0 or M.windows[mouse.winid] == nil then
    return
  end
  vim.api.nvim_win_call(mouse.winid, function()
    -- Fold ranges may be nested; act at the clicked line rather than the cursor.
    local view = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(0, { mouse.line, 0 })
    if vim.fn.foldlevel(mouse.line) > 0 then
      vim.cmd("normal! za")
    end
    vim.fn.winrestview(view)
  end)
  schedule()
end

function M.setup(opts)
  M.disable()
  opts = vim.tbl_deep_extend("force", {
    layout = { "mark", "sign", "number", "fold", "git" },
    git_patterns = { "GitTools", "gitsigns" },
    folds = { open = "▾", closed = "▸" },
    refresh = 30,
    force = false,
  }, opts or {})
  assert(type(opts.refresh) == "number" and opts.refresh >= 0, "statuscolumn.refresh must be nonnegative")
  for _, kind in ipairs(opts.layout) do
    assert(
      vim.tbl_contains({ "mark", "sign", "number", "fold", "git" }, kind),
      "Unknown statuscolumn item: " .. tostring(kind)
    )
  end
  util.cell(opts.folds.open, "folds.open")
  util.cell(opts.folds.closed, "folds.closed")
  util.hl({ UiToolsMark = "Special" })
  M.options, M.enabled = opts, true
  local group = util.group("Statuscolumn")
  vim.api.nvim_create_autocmd({
    "BufWinEnter",
    "WinEnter",
    "WinScrolled",
    "WinResized",
    "TextChanged",
    "TextChangedI",
    "DiagnosticChanged",
    "CursorMoved",
    "ModeChanged",
    "OptionSet",
  }, { group = group, callback = schedule })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "GitToolsUpdate", callback = schedule })
  M.refresh()
end

function M.disable()
  M.enabled = false
  generation, queued = generation + 1, false
  pcall(vim.api.nvim_del_augroup_by_name, "UiToolsStatuscolumn")
  for win in pairs(M.windows) do
    release(win)
  end
  M.cache = {}
  util.redraw()
end

return M
