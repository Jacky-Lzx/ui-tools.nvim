local M =
  { windows = {}, cache = {}, widths = {}, fold_options = {}, fold_widths = {}, views = {}, enabled = false }
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

local function sign_text(sign)
  -- Neovim pads sign_text to two cells. Numhl/linehl-only marks have no glyph.
  return sign and (sign.sign_text or ""):gsub("%s+$", "") or ""
end

local function kinds(entry)
  return type(entry) == "table" and entry or { entry }
end

local function prepare_folds(win, inherited)
  if not M.options.folds.levels then
    return
  end
  if not M.fold_options[win] then
    local previous = {
      foldcolumn = inherited and vim.go.foldcolumn or vim.wo[win].foldcolumn,
      fillchars = inherited and ""
        or vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" }),
    }
    vim.api.nvim_set_option_value(
      "foldcolumn",
      "auto:" .. M.options.folds.max_depth,
      { win = win, scope = "local" }
    )
    vim.api.nvim_win_call(win, function()
      local chars = vim.opt.fillchars:get()
      chars.foldopen, chars.foldclose, chars.foldsep =
        M.options.folds.open, M.options.folds.closed, M.options.folds.sep
      vim.opt_local.fillchars = chars
    end)
    previous.applied_column = vim.wo[win].foldcolumn
    previous.applied_chars = vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" })
    M.fold_options[win] = previous
  end
  -- %C delegates exact starts, shared starts and nesting to Neovim's fold tree.
  M.fold_widths[win] = vim.api.nvim_eval_statusline("%C", { winid = win, use_statuscol_lnum = 1 }).width
end

local function measure(rows, win)
  local widths = { total = 0 }
  for index, entry in ipairs(M.options.layout) do
    if entry ~= "number" then
      local width = M.options.slot_width
      if M.options.folds.levels and vim.tbl_contains(kinds(entry), "fold") then
        width = math.max(width, M.fold_widths[win] or 0)
      end
      for _, row in pairs(rows) do
        for _, kind in ipairs(kinds(entry)) do
          if kind == "sign" or kind == "diagnostic" or kind == "git" then
            width = math.max(width, vim.fn.strdisplaywidth(sign_text(row[kind])))
          end
        end
      end
      widths[index], widths.total = width, widths.total + width
    else
      widths[index] = 0
    end
  end
  return widths
end

local function release(win)
  local previous = M.windows[win]
  if previous and vim.api.nvim_win_is_valid(win) and vim.wo[win].statuscolumn == format then
    vim.wo[win].statuscolumn = previous
  end
  local folds = M.fold_options[win]
  if folds and vim.api.nvim_win_is_valid(win) then
    if vim.wo[win].foldcolumn == folds.applied_column then
      vim.api.nvim_set_option_value("foldcolumn", folds.foldcolumn, { win = win, scope = "local" })
    end
    if vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" }) == folds.applied_chars then
      vim.api.nvim_set_option_value("fillchars", folds.fillchars, { win = win, scope = "local" })
    end
  end
  M.windows[win], M.cache[win], M.widths[win] = nil, nil, nil
  M.fold_options[win], M.fold_widths[win] = nil, nil
  M.views[win] = nil
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
    elseif
      M.windows[win] ~= nil
      or vim.wo[win].statuscolumn == ""
      or vim.wo[win].statuscolumn == format
      or opts.force
    then
      local inherited = M.windows[win] == nil and vim.wo[win].statuscolumn == format
      if M.windows[win] == nil then
        -- Splits and per-buffer window options can inherit our format without
        -- a registry entry. Adopt them, but never restore an orphaned format.
        M.windows[win] = vim.wo[win].statuscolumn == format and "" or vim.wo[win].statuscolumn
        vim.wo[win].statuscolumn = format
      end
      if vim.wo[win].statuscolumn == format then
        prepare_folds(win, inherited)
        local first, last = unpack(vim.api.nvim_win_call(win, function()
          return { vim.fn.line("w0"), vim.fn.line("w$") }
        end))
        M.views[win] = { first, last }
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
          local namespace = names[details.ns_id] or ""
          local name = namespace .. " " .. (details.sign_name or "") .. " " .. (details.sign_hl_group or "")
          local kind = "sign"
          for _, pattern in ipairs(opts.git_patterns) do
            if name:find(pattern, 1, true) then
              kind = "git"
              break
            end
          end
          if sign_text(details) ~= "" then
            rows[row] = rows[row] or {}
            local function retain(slot)
              local previous = rows[row][slot]
              if not previous or (details.priority or 0) > (previous.priority or 0) then
                rows[row][slot] = details
              end
            end
            retain(kind)
            if
              namespace:find(".diagnostic.signs", 1, true)
              or (details.sign_hl_group or ""):match("^DiagnosticSign")
            then
              retain("diagnostic")
            end
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
        local widths = measure(rows, win)
        local previous = M.widths[win]
        M.widths[win] = widths
        if previous and widths.total < previous.total then
          -- Neovim otherwise retains a previously wider status column.
          vim.wo[win].statuscolumn = format
        end
      end
    end
  end
  for win in pairs(M.windows) do
    if not vim.api.nvim_win_is_valid(win) then
      M.windows[win], M.cache[win], M.widths[win] = nil, nil, nil
      M.fold_options[win], M.fold_widths[win] = nil, nil
      M.views[win] = nil
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

local function folds_changed()
  if not M.enabled or not M.options.folds.levels then
    return
  end
  -- Native fold clicks/commands need not move the cursor or emit WinScrolled.
  -- Probe after input settles; refresh only when geometry or the viewport changed.
  for win in pairs(M.fold_options) do
    if vim.api.nvim_win_is_valid(win) and vim.wo[win].statuscolumn == format then
      local width = vim.api.nvim_eval_statusline("%C", { winid = win, use_statuscol_lnum = 1 }).width
      local view = vim.api.nvim_win_call(win, function()
        return { vim.fn.line("w0"), vim.fn.line("w$") }
      end)
      if width ~= M.fold_widths[win] or not vim.deep_equal(view, M.views[win]) then
        schedule()
        return
      end
    end
  end
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
end

local function symbol(kind, win, row)
  if kind == "fold" then
    if vim.wo[win].foldenable then
      if vim.fn.foldclosed(vim.v.lnum) == vim.v.lnum then
        return M.options.folds.closed, "FoldColumn"
      end
      local previous = vim.v.lnum > 1 and vim.fn.foldlevel(vim.v.lnum - 1) or 0
      if vim.fn.foldlevel(vim.v.lnum) > previous then
        return M.options.folds.open, "FoldColumn"
      end
    end
  elseif kind == "mark" then
    if row.mark then
      return row.mark, "UiToolsMark"
    end
  elseif vim.wo[win].signcolumn ~= "no" then
    local sign = row[kind]
    local text = sign_text(sign)
    if text ~= "" then
      return text, sign.sign_hl_group
    end
  end
end

function M.render()
  if not M.enabled then
    return ""
  end
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local row = (M.cache[win] or {})[vim.v.lnum] or {}
  local widths = M.widths[win] or {}
  local result = {}
  for index, entry in ipairs(M.options.layout) do
    if entry == "number" then
      result[#result + 1] = part("number", win, row)
    else
      local text, hl, native
      local choices = kinds(entry)
      if vim.v.virtnum == 0 then
        for _, kind in ipairs(choices) do
          if
            kind == "fold"
            and M.options.folds.levels
            and vim.wo[win].foldenable
            and vim.fn.foldlevel(vim.v.lnum) > 0
          then
            text, native = "%C", true
            break
          end
          text, hl = symbol(kind, win, row)
          if text then
            break
          end
        end
      end
      text = text or ""
      local width = widths[index] or M.options.slot_width
      if native then
        text = "%#FoldColumn#%C%*" .. string.rep(" ", math.max(0, width - (M.fold_widths[win] or 0)))
      else
        text = label(text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text))), hl)
      end
      -- A click function must cover the same column on every rendered row.
      if vim.tbl_contains(choices, "fold") and not M.options.folds.levels then
        text = "%@v:lua.require'ui_tools.statuscolumn'.click@" .. text .. "%T"
      end
      result[#result + 1] = text
    end
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
    layout = { { "diagnostic", "sign", "mark" }, "number", { "fold", "git" } },
    slot_width = 1,
    git_patterns = { "GitTools", "gitsigns" },
    folds = { open = "▾", closed = "▸", sep = "│", levels = false, max_depth = 9 },
    refresh = 30,
    force = false,
  }, opts or {})
  assert(type(opts.refresh) == "number" and opts.refresh >= 0, "statuscolumn.refresh must be nonnegative")
  assert(
    type(opts.slot_width) == "number" and opts.slot_width >= 1 and opts.slot_width % 1 == 0,
    "statuscolumn.slot_width must be a positive integer"
  )
  for _, entry in ipairs(opts.layout) do
    local choices = kinds(entry)
    assert(#choices > 0, "statuscolumn groups must not be empty")
    for _, kind in ipairs(choices) do
      assert(
        vim.tbl_contains({ "mark", "sign", "diagnostic", "number", "fold", "git" }, kind),
        "Unknown statuscolumn item: " .. tostring(kind)
      )
      assert(type(entry) ~= "table" or kind ~= "number", "number must occupy its own statuscolumn slot")
    end
  end
  util.cell(opts.folds.open, "folds.open")
  util.cell(opts.folds.closed, "folds.closed")
  util.cell(opts.folds.sep, "folds.sep")
  assert(type(opts.folds.levels) == "boolean", "folds.levels must be boolean")
  assert(
    type(opts.folds.max_depth) == "number"
      and opts.folds.max_depth >= 1
      and opts.folds.max_depth <= 9
      and opts.folds.max_depth % 1 == 0,
    "folds.max_depth must be an integer from 1 to 9"
  )
  util.hl({ UiToolsMark = "Special" })
  M.options, M.enabled = opts, true
  local group = util.group("Statuscolumn")
  vim.api.nvim_create_autocmd("SafeState", { group = group, callback = folds_changed })
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
    "InsertLeave",
    "CmdlineLeave",
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
  M.cache, M.widths = {}, {}
  util.redraw()
end

return M
