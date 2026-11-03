-- Pure window-sized layout; columns are display cells, marks use byte offsets.
local M = {}
local function width(text)
  return vim.fn.strdisplaywidth(text)
end

local function fit(text, limit)
  text = tostring(text):gsub("[\r\n\t]", " ")
  if width(text) <= limit then
    return text
  end
  local result = ""
  for i = 0, vim.fn.strchars(text) - 1 do
    local next_text = result .. vim.fn.strcharpart(text, i, 1)
    if width(next_text) > limit then
      break
    end
    result = next_text
  end
  return result
end

local function art(text)
  local rows, first, last = {}, math.huge, 0
  for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local cells = {}
    for i = 0, vim.fn.strchars(line) - 1 do
      local char = vim.fn.strcharpart(line, i, 1)
      if char == "\t" then
        char = " "
      end
      local size = width(char)
      if size == 0 and #cells > 0 then
        cells[#cells].text = cells[#cells].text .. char
      else
        local col = #cells + 1
        cells[col] = { text = char, width = size }
        for _ = 2, size do
          cells[#cells + 1] = { text = " ", width = 1 }
        end
        if char ~= " " and char ~= "⠀" then
          first, last = math.min(first, col), math.max(last, col + size - 1)
        end
      end
    end
    rows[#rows + 1] = cells
  end
  local function blank(row)
    for _, cell in ipairs(row) do
      if cell.text ~= " " and cell.text ~= "⠀" then
        return false
      end
    end
    return true
  end
  while #rows > 0 and blank(rows[1]) do
    table.remove(rows, 1)
  end
  while #rows > 0 and blank(rows[#rows]) do
    table.remove(rows)
  end
  if last == 0 then
    return {}, 0
  end
  for i, row in ipairs(rows) do
    local cropped = {}
    for col = first, last do
      cropped[#cropped + 1] = row[col] or { text = " ", width = 1 }
    end
    rows[i] = cropped
  end
  return rows, last - first + 1
end

local function scale(rows, source_width, max_width, max_height)
  if #rows == 0 or max_width < 1 or max_height < 1 then
    return {}, 0
  end
  local ratio = math.min(1, max_width / source_width, max_height / #rows)
  local target_width = math.max(1, math.floor(source_width * ratio))
  local target_height = math.max(1, math.floor(#rows * ratio))
  local result = {}
  for y = 1, target_height do
    local source = rows[math.min(#rows, math.floor((y - 0.5) * #rows / target_height) + 1)]
    local line, x = "", 1
    while x <= target_width do
      local col = math.min(source_width, math.floor((x - 0.5) * source_width / target_width) + 1)
      local cell = source[col]
      local char = cell.width <= target_width - x + 1 and cell.text or " "
      line = line .. char
      x = x + math.max(1, width(char))
    end
    result[#result + 1] = line
  end
  return result, target_width
end

function M.build(opts, items, win_width, height)
  local rows, art_width = art(opts.header)
  local available = math.max(1, win_width - (win_width > 4 and 2 or 0))
  local menu_width, key_width = 1, 1
  for _, item in ipairs(items) do
    key_width = math.max(key_width, width("[" .. item.key .. "]"))
    menu_width =
      math.max(menu_width, width((item.icon or "") .. (item.desc or "")) + width("[" .. item.key .. "]") + 2)
  end
  local desired_menu = math.max(opts.width, menu_width)
  local footer = type(opts.footer) == "function" and opts.footer() or opts.footer
  -- Actions have priority in extremely short windows; remaining actions scroll natively.
  local footer_gap = footer and height >= #items + 2 and 2 or 0
  local body_height = math.max(1, height - footer_gap)
  local header, header_width, gap, menu_top, header_top, content_width
  local menu_col = 0
  local layout = opts.layout
  if layout == "horizontal" and #rows > 0 then
    gap = available > key_width + 2 and math.min(opts.gap, math.max(0, available - key_width - 2)) or 0
    local reserve = math.min(desired_menu, math.max(key_width, math.floor(available * 0.55)))
    header, header_width = scale(rows, art_width, available - reserve - gap, body_height)
    if header_width == 0 then
      gap = 0
    end
    menu_width = math.min(desired_menu, available - header_width - gap)
    menu_col = header_width + gap
    body_height = math.max(#header, #items)
    header_top = math.floor((body_height - #header) / 2)
    menu_top = math.floor((body_height - #items) / 2)
    content_width = header_width + gap + menu_width
  else
    gap = #rows > 0 and body_height > #items + 1 and math.min(opts.gap, body_height - #items - 1) or 0
    header, header_width = scale(rows, art_width, available, body_height - #items - gap)
    if #header == 0 then
      gap = 0
    end
    menu_width = math.min(desired_menu, available)
    content_width = math.max(menu_width, header_width)
    menu_col = math.floor((content_width - menu_width) / 2)
    header_top, menu_top = 0, #header + gap
    body_height = #header + gap + #items
  end
  local total = body_height + footer_gap
  content_width = math.max(1, content_width)
  local left = math.max(0, math.floor((win_width - content_width) / 2))
  local top = math.max(0, math.floor((height - total) / 2))
  local lines, marks, action_rows, action_cols = {}, {}, {}, {}
  for _ = 1, math.max(1, top + total) do
    lines[#lines + 1] = ""
  end
  local function put(row, col, text, hl)
    local line = lines[row]
    local padding = math.max(0, col - width(line))
    local start = #line + padding
    lines[row] = line .. string.rep(" ", padding) .. text
    marks[#marks + 1] = { row - 1, start, #lines[row], hl }
    return start
  end
  local header_col = layout == "horizontal" and left or left + math.floor((content_width - header_width) / 2)
  for i, line in ipairs(header) do
    put(top + header_top + i, header_col, line, "UiToolsDashboardHeader")
  end
  for i, item in ipairs(items) do
    local key = fit("[" .. item.key .. "]", menu_width)
    local desc = fit((item.icon or "") .. (item.desc or ""), math.max(0, menu_width - width(key) - 2))
    local text = desc .. string.rep(" ", math.max(0, menu_width - width(desc .. key))) .. key
    local row = top + menu_top + i
    action_cols[i] = put(row, left + menu_col, text, "UiToolsDashboardDesc")
    local icon = fit(item.icon or "", width(desc))
    if #icon > 0 then
      marks[#marks + 1] = { row - 1, action_cols[i], action_cols[i] + #icon, "UiToolsDashboardIcon" }
    end
    marks[#marks + 1] = { row - 1, #lines[row] - #key, #lines[row], "UiToolsDashboardKey" }
    action_rows[i] = row
  end
  if footer_gap > 0 then
    local text = fit(footer, available)
    put(top + total, math.max(0, math.floor((win_width - width(text)) / 2)), text, "UiToolsDashboardFooter")
  end
  return {
    lines = lines,
    marks = marks,
    rows = action_rows,
    cols = action_cols,
    col = left + menu_col,
    header_width = header_width,
    header_height = #header,
    layout = layout,
  }
end

return M
