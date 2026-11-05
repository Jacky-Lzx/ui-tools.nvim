local M = {
  windows = {},
  cache = {},
  widths = {},
  fold_options = {},
  fold_widths = {},
  views = {},
  scopes = {},
  enabled = false,
}
local util = require("ui_tools.util")
local format = "%!v:lua.require'ui_tools.statuscolumn'.render()"
local generation = 0
local queued = false
local has_diagnostic_slot = false

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

local function sign_for(row, kind)
  if kind == "sign" and has_diagnostic_slot then
    return row.other_sign
  end
  return row[kind]
end

local function prepare_folds(win, inherited)
  if not M.options.folds.levels then
    return
  end
  if not M.fold_options[win] then
    local previous = { foldcolumn = inherited and vim.go.foldcolumn or vim.wo[win].foldcolumn }
    -- Draw the configured fixed-width area ourselves; keep native folding state.
    vim.api.nvim_set_option_value("foldcolumn", "0", { win = win, scope = "local" })
    previous.applied_column = "0"
    M.fold_options[win] = previous
  end
  M.fold_widths[win] = M.options.folds.columns
end

local function measure(rows)
  local widths = { total = 0 }
  for index, entry in ipairs(M.options.layout) do
    if entry ~= "number" then
      local fixed_fold = M.options.folds.levels and vim.tbl_contains(kinds(entry), "fold")
      local width = fixed_fold and M.options.folds.columns or M.options.slot_width
      if not fixed_fold then
        for _, row in pairs(rows) do
          for _, kind in ipairs(kinds(entry)) do
            if kind == "sign" or kind == "diagnostic" or kind == "git" then
              width = math.max(width, vim.fn.strdisplaywidth(sign_text(sign_for(row, kind))))
            end
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
  end
  M.windows[win], M.cache[win], M.widths[win] = nil, nil, nil
  M.fold_options[win], M.fold_widths[win] = nil, nil
  M.views[win] = nil
  M.scopes[win] = nil
end

function M.refresh()
  if not M.enabled or util.searching() then
    return
  end
  local opts = M.options
  local names, number_groups = {}, {}
  local function git_number_groups(sign)
    local source = sign.number_hl_group or sign.sign_hl_group
    if not opts.git_numbers or not source then
      return
    end
    if not number_groups[source] then
      local color = vim.api.nvim_get_hl(0, { name = source, link = false }).fg
      local name = "UiToolsGitNumber" .. source:gsub("[^%w_]", "_")
      vim.api.nvim_set_hl(0, name, { fg = color })
      vim.api.nvim_set_hl(0, name .. "Current", { fg = color, bold = true })
      number_groups[source] = { name, name .. "Current" }
    end
    return number_groups[source]
  end
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
        M.scopes[win] = nil
        if opts.folds.levels and opts.folds.scope and vim.wo[win].foldenable then
          local reader = require("ui_tools.fold_info")
          local line = vim.api.nvim_win_get_cursor(win)[1]
          local fold = reader.get(win, line)
          if fold and fold.level > 0 then
            M.scopes[win] = { start = reader.header(win, line, fold.level), level = fold.level }
          end
        end
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
          local name = namespace
            .. " "
            .. (details.sign_name or "")
            .. " "
            .. (details.sign_hl_group or "")
            .. " "
            .. (details.number_hl_group or "")
          local kind = "sign"
          for _, pattern in ipairs(opts.git_patterns) do
            if name:find(pattern, 1, true) then
              kind = "git"
              break
            end
          end
          if sign_text(details) ~= "" or (kind == "git" and details.number_hl_group) then
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
            elseif kind == "sign" then
              retain("other_sign")
            end
          end
        end
        for _, row in pairs(rows) do
          if row.git then
            row.git_numbers = git_number_groups(row.git)
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
        local widths = measure(rows)
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
      M.scopes[win] = nil
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
      local view = vim.api.nvim_win_call(win, function()
        return { vim.fn.line("w0"), vim.fn.line("w$") }
      end)
      if not vim.deep_equal(view, M.views[win]) then
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
    local current = vim.v.relnum == 0
    local hl = row.git_numbers and row.git_numbers[current and 2 or 1]
      or (current and "UiToolsCursorLineNr" or "UiToolsLineNr")
    return label(string.format("%" .. width .. "d ", value), hl)
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
    local sign = sign_for(row, kind)
    local text = sign_text(sign)
    if text ~= "" then
      return text, sign.sign_hl_group
    end
  end
end

local function fold_cells(win, line)
  local fold = require("ui_tools.fold_info").get(win, line)
  if not fold or fold.level == 0 then
    return
  end
  local opts, cells, rendered = M.options.folds, {}, {}
  local scope = M.scopes[win]
  for column = 1, opts.columns do
    local char = " "
    if fold.level >= column then
      if fold.lines > 0 and (column == opts.columns or column == fold.level) then
        char = opts.closed
      elseif fold.start == line and (column == opts.columns or column >= fold.lowest) then
        char = opts.open
      else
        char = opts.sep
      end
    end
    cells[column] = char
    local hl = "FoldColumn"
    if char == opts.sep then
      hl = "UiToolsFoldSeparator"
      if scope and column == math.min(scope.level, opts.columns) and fold.level >= scope.level then
        if require("ui_tools.fold_info").header(win, line, scope.level) == scope.start then
          hl = "UiToolsFoldScope"
        end
      end
    end
    rendered[column] = label(char, hl)
  end
  return table.concat(cells), table.concat(rendered)
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
      local text, hl, rendered
      local choices = kinds(entry)
      if vim.v.virtnum == 0 then
        for _, kind in ipairs(choices) do
          if kind == "fold" and M.options.folds.levels then
            if vim.wo[win].foldenable then
              text, rendered = fold_cells(win, vim.v.lnum)
            end
            if text then
              hl = "FoldColumn"
            end
          else
            text, hl = symbol(kind, win, row)
          end
          if text then
            break
          end
        end
      end
      text = text or ""
      local width = widths[index] or M.options.slot_width
      if vim.fn.strdisplaywidth(text) > width then
        text = ""
      end
      text = rendered or label(text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text))), hl)
      -- Keep the same click handler/region on every row, including empty rows.
      if vim.tbl_contains(choices, "fold") then
        local id = M.options.folds.levels and tostring(index) or ""
        text = "%" .. id .. "@v:lua.require'ui_tools.statuscolumn'.click@" .. text .. "%T"
      end
      result[#result + 1] = text
    end
  end
  if M.options.separator then
    result[#result + 1] = label(M.options.separator, "UiToolsStatusSeparator")
  end
  return table.concat(result)
end

function M.click(column, _, button)
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
    if M.options.folds.levels then
      local offset = 0
      for index = 1, column - 1 do
        if M.options.layout[index] == "number" then
          if vim.wo.number or vim.wo.relativenumber then
            offset = offset + math.max(vim.wo.numberwidth - 1, #tostring(vim.api.nvim_buf_line_count(0))) + 1
          end
        else
          offset = offset + ((M.widths[mouse.winid] or {})[index] or M.options.slot_width)
        end
      end
      column = mouse.wincol - offset
      local reader = require("ui_tools.fold_info")
      local fold = reader.get(mouse.winid, mouse.line)
      if fold and column >= 1 and column <= M.options.folds.columns and fold.level >= column then
        local level = column == M.options.folds.columns and fold.level or column
        if fold.lines > 0 and level == fold.level then
          vim.cmd("normal! zo")
        else
          local header, active = reader.header(mouse.winid, mouse.line, level)
          if header then
            vim.api.nvim_win_set_cursor(0, { header, 0 })
            local count = active.level - level + (active.lines > 0 and 0 or 1)
            if count > 0 then
              vim.cmd("normal! " .. count .. "zc")
            end
          end
        end
      end
    elseif vim.fn.foldlevel(mouse.line) > 0 then
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
    separator = false,
    git_numbers = false,
    git_patterns = { "GitTools", "gitsigns" },
    folds = { open = "▾", closed = "▸", sep = "│", levels = false, columns = 2, scope = false },
    refresh = 30,
    force = false,
  }, opts or {})
  assert(type(opts.refresh) == "number" and opts.refresh >= 0, "statuscolumn.refresh must be nonnegative")
  assert(type(opts.git_numbers) == "boolean", "statuscolumn.git_numbers must be boolean")
  if opts.separator ~= false then
    util.cell(opts.separator, "statuscolumn.separator")
  end
  assert(
    type(opts.slot_width) == "number" and opts.slot_width >= 1 and opts.slot_width % 1 == 0,
    "statuscolumn.slot_width must be a positive integer"
  )
  has_diagnostic_slot = false
  for _, entry in ipairs(opts.layout) do
    local choices = kinds(entry)
    assert(#choices > 0, "statuscolumn groups must not be empty")
    for _, kind in ipairs(choices) do
      assert(
        vim.tbl_contains({ "mark", "sign", "diagnostic", "number", "fold", "git" }, kind),
        "Unknown statuscolumn item: " .. tostring(kind)
      )
      assert(type(entry) ~= "table" or kind ~= "number", "number must occupy its own statuscolumn slot")
      has_diagnostic_slot = has_diagnostic_slot or kind == "diagnostic"
    end
  end
  util.cell(opts.folds.open, "folds.open")
  util.cell(opts.folds.closed, "folds.closed")
  util.cell(opts.folds.sep, "folds.sep")
  assert(type(opts.folds.levels) == "boolean", "folds.levels must be boolean")
  assert(type(opts.folds.scope) == "boolean", "folds.scope must be boolean")
  assert(
    type(opts.folds.columns) == "number"
      and opts.folds.columns >= 1
      and opts.folds.columns <= 9
      and opts.folds.columns % 1 == 0,
    "folds.columns must be an integer from 1 to 9"
  )
  if opts.folds.levels then
    require("ui_tools.fold_info").setup()
  end
  util.hl({
    UiToolsMark = "Special",
    UiToolsStatusSeparator = "WinSeparator",
    UiToolsLineNr = "LineNr",
    UiToolsCursorLineNr = "CursorLineNr",
    UiToolsFoldSeparator = "LineNr",
    UiToolsFoldScope = "FoldColumn",
  })
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
    "CursorMovedI",
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
