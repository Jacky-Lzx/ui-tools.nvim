-- Indentation-based visual scope. No parsers, textobjects or editing mappings.
local M = {}

function M.width(line, tabstop)
  local col = 0
  for char in line:match("^[ \t]*"):gmatch(".") do
    col = char == "\t" and (col + tabstop - col % tabstop) or col + 1
  end
  return col
end

function M.find(buf, row, limit)
  local count = vim.api.nvim_buf_line_count(buf)
  local first, last = math.max(1, row - limit), math.min(count, row + limit)
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local ts = vim.bo[buf].tabstop
  local function width(n)
    local line = lines[n - first + 1]
    return line and line:find("%S") and M.width(line, ts) or nil
  end
  -- On an empty line, borrow the nearest nonblank line within the scan budget.
  local target = row
  if not width(target) then
    for distance = 1, limit do
      if row - distance >= first and width(row - distance) then
        target = row - distance
        break
      end
      if row + distance <= last and width(row + distance) then
        target = row + distance
        break
      end
    end
  end
  local level = width(target)
  if not level then
    return
  end
  local following = target + 1
  while following <= last and not width(following) do
    following = following + 1
  end
  local header = following <= last and width(following) > level
  local body = header and width(following) or level
  if body == 0 then
    return
  end
  local start = target
  if not header then
    while start > first do
      local value = width(start - 1)
      start = start - 1
      if value and value < body then
        break
      end
    end
  end
  local finish = header and following or target
  while finish < last do
    local value = width(finish + 1)
    if value and value < body then
      break
    end
    finish = finish + 1
  end
  while finish > target and not width(finish) do
    finish = finish - 1
  end
  local parent = width(start)
  local step = vim.bo[buf].shiftwidth
  if step == 0 then
    step = ts
  end
  return {
    first = start,
    last = finish,
    column = parent and parent < body and parent or math.max(0, body - step),
    body = body,
  }
end

return M
