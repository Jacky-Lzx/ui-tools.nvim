local M = require("ui_tools.annotations").new("Todo")
local util = require("ui_tools.util")
local keywords = {}
local defaults = {
  FIX = { icon = "!", hl = "DiagnosticError", alt = { "FIXME", "BUG", "FIXIT", "ISSUE" }, rank = 90 },
  TODO = { icon = "✓", hl = "DiagnosticInfo", rank = 50 },
  HACK = { icon = "~", hl = "DiagnosticWarn", rank = 70 },
  WARN = { icon = "!", hl = "DiagnosticWarn", alt = { "WARNING", "XXX" }, rank = 80 },
  PERF = { icon = "»", hl = "Special", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" }, rank = 40 },
  NOTE = { icon = "i", hl = "DiagnosticHint", alt = { "INFO" }, rank = 20 },
  TEST = { icon = "?", hl = "Identifier", alt = { "TESTING", "PASSED", "FAILED" }, rank = 30 },
}

-- Return the end of the comment containing this byte column. Never guess from
-- punctuation: a quoted "TODO:" must remain ordinary code/string text.
local function comment_end(buf, row, col, line, win)
  if not M.options.comments_only or vim.tbl_contains(M.options.prose, vim.bo[buf].filetype) then
    return #line
  end
  if vim.treesitter.highlighter.active[buf] then
    local parser = vim.treesitter.get_parser(buf)
    if parser then
      parser:parse({ row, row + 1 })
    end
    local ok, node =
      pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col }, ignore_injections = false })
    if ok then
      while node do
        if node:type():lower():find("comment", 1, true) then
          local _, _, last, column = node:range()
          return last == row and column or #line
        end
        node = node:parent()
      end
    end
    -- Queries can identify comments even when a grammar uses a different name.
    local captured, captures = pcall(vim.treesitter.get_captures_at_pos, buf, row, col)
    if captured then
      for _, capture in ipairs(captures) do
        if capture.capture:match("^comment") then
          return #line
        end
      end
    end
    return
  end
  return vim.api.nvim_win_call(win, function()
    local function is_comment(column)
      for _, id in ipairs(vim.fn.synstack(row + 1, column + 1)) do
        local name = vim.fn.synIDattr(id, "name"):lower()
        local link = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name"):lower()
        if name:find("comment", 1, true) or link == "comment" then
          return true
        end
      end
      return false
    end
    if not is_comment(col) then
      return
    end
    local last = col + 1
    while last < #line and is_comment(last) do
      last = last + 1
    end
    return last
  end)
end

-- Lexical matching is public so consumers can use the same keywords without
-- depending on the visual renderer. It does not perform comment filtering.
function M.scan(line)
  local result = {}
  for first, word, last in line:gmatch("()%f[%w_]([A-Z][A-Z0-9_]*)()") do
    local keyword = keywords[word]
    if keyword then
      local from = last
      if line:sub(from, from) == "(" then
        local owner = line:sub(from):match("^%b()")
        from = owner and from + #owner or #line + 1
      end
      local suffix = line:sub(from):match("^(%s*:)")
      if suffix then
        result[#result + 1] =
          { col = first - 1, end_col = from + #suffix - 1, keyword = keyword, text = word }
      end
    end
  end
  return result
end

local function highlights()
  for name, item in pairs(M.options.keywords) do
    if item then
      local fg = vim.api.nvim_get_hl(0, { name = item.hl, link = false }).fg
        or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg
        or (vim.o.background == "light" and 0x000000 or 0xffffff)
      local r, g, b = math.floor(fg / 65536), math.floor(fg / 256) % 256, fg % 256
      vim.api.nvim_set_hl(0, "UiToolsTodo" .. name, { link = item.hl })
      vim.api.nvim_set_hl(0, "UiToolsTodoBadge" .. name, {
        bg = fg,
        fg = (r * 299 + g * 587 + b * 114) >= 128000 and "#000000" or "#ffffff",
        bold = true,
      })
    end
  end
  M.queue()
end

local function refresh_column()
  local column = package.loaded["ui_tools.statuscolumn"]
  if column and column.enabled then
    column.refresh()
  end
end

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "todo options must be a table")
  opts = vim.deepcopy(opts or {})
  opts = vim.tbl_deep_extend("force", {
    enabled = true,
    keywords = defaults,
    comments_only = true,
    prose = { "markdown", "text", "gitcommit" },
    style = "badge",
    after = true,
    signs = true,
    sign_priority = 8,
    priority = 160,
    refresh = 30,
    max_line_length = 4096,
  }, opts or {})
  assert(vim.tbl_contains({ "badge", "foreground" }, opts.style), "Invalid todo.style")
  local lookup = {}
  for name, item in pairs(opts.keywords) do
    assert(name:match("^[A-Z][A-Z0-9_]*$"), "TODO keywords must be uppercase identifiers")
    if item then
      assert(
        type(item) == "table" and type(item.hl) == "string" and type(item.rank) == "number",
        "TODO keywords need hl and rank"
      )
      util.cell(item.icon, "todo.keywords." .. name .. ".icon")
      lookup[name] = name
    end
  end
  for name, item in pairs(opts.keywords) do
    if item then
      for _, alt in ipairs(item.alt or {}) do
        assert(alt:match("^[A-Z][A-Z0-9_]*$"), "TODO aliases must be uppercase identifiers")
        if opts.keywords[alt] == nil then
          assert(not lookup[alt], "Duplicate TODO alias: " .. alt)
          lookup[alt] = name
        end
      end
    end
  end
  require("ui_tools.annotations").validate(opts, "todo")
  return opts, lookup
end

function M.setup(opts)
  local resolved, derived = M.resolve(opts)
  M.disable()
  opts = resolved
  keywords = derived
  -- Native signs must be visible to ui-tools' cached statuscolumn as well.
  M.on_refresh = refresh_column
  M.start(opts, function(buf, row, line, win)
    local matches = {}
    for _, item in ipairs(M.scan(line)) do
      local last = comment_end(buf, row, item.col, line, win)
      if last and item.end_col <= last then
        item.last = last
        matches[#matches + 1] = item
      end
    end
    local sign
    for index, item in ipairs(matches) do
      local spec = opts.keywords[item.keyword]
      local fg = "UiToolsTodo" .. item.keyword
      local badge = spec.badge_hl or "UiToolsTodoBadge" .. item.keyword
      vim.api.nvim_buf_set_extmark(buf, M.ns, row, item.col, {
        end_col = item.end_col,
        hl_group = opts.style == "badge" and badge or fg,
        priority = opts.priority,
      })
      if opts.after then
        local last = math.min(item.last, matches[index + 1] and matches[index + 1].col or #line)
        if last > item.end_col then
          vim.api.nvim_buf_set_extmark(buf, M.ns, row, item.end_col, {
            end_col = last,
            hl_group = fg,
            priority = opts.priority - 1,
          })
        end
      end
      if not sign or spec.rank > opts.keywords[sign.keyword].rank then
        sign = item
      end
    end
    if opts.signs and sign then
      vim.api.nvim_buf_set_extmark(buf, M.ns, row, sign.col, {
        sign_text = opts.keywords[sign.keyword].icon,
        sign_hl_group = "UiToolsTodo" .. sign.keyword,
        priority = opts.sign_priority,
      })
    end
  end)
  require("ui_tools.theme").bind("todo", highlights)
end

local stop = M.disable
function M.disable()
  require("ui_tools.theme").unbind("todo")
  stop()
end

return M
