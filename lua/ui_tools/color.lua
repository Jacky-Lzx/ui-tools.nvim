-- Pure color parsing. Ranges use zero-based byte columns, like Neovim extmarks.
local M = {}
local names = require("ui_tools.color_names")

local function clamp(n, max)
  return math.max(0, math.min(n, max))
end

local function hex(r, g, b, a)
  return {
    hex = ("#%02x%02x%02x"):format(
      math.floor(clamp(r, 255) + 0.5),
      math.floor(clamp(g, 255) + 0.5),
      math.floor(clamp(b, 255) + 0.5)
    ),
    alpha = a or 1,
  }
end

local function number(s, scale)
  local value, percent = s:match("^([+-]?%d*%.?%d+)(%%?)$")
  if value then
    return percent == "%" and tonumber(value) * scale / 100 or tonumber(value)
  end
end

function M.parse(value, custom)
  value = vim.trim(value):lower()
  if custom and custom[value] then
    value = custom[value]:lower()
  end
  if value == "transparent" then
    return hex(0, 0, 0, 0)
  end
  value = names[value] or value
  local digits = value:match("^#(%x+)$") or value:match("^0x(%x+)$")
  if digits then
    if #digits == 3 or #digits == 4 then
      digits = digits:gsub(".", "%0%0")
    end
    if #digits == 6 or #digits == 8 then
      return hex(
        tonumber(digits:sub(1, 2), 16),
        tonumber(digits:sub(3, 4), 16),
        tonumber(digits:sub(5, 6), 16),
        #digits == 8 and tonumber(digits:sub(7, 8), 16) / 255 or 1
      )
    end
    return
  end
  local fn, body = value:match("^(%a+)%((.-)%)$")
  if fn ~= "rgb" and fn ~= "rgba" and fn ~= "hsl" and fn ~= "hsla" then
    return
  end
  -- Accept legacy commas or CSS space/slash notation, never a mixture.
  local parts = {}
  if body:find(",", 1, true) then
    if body:find("/", 1, true) then
      return
    end
    for part in (body .. ","):gmatch("(.-),") do
      parts[#parts + 1] = vim.trim(part)
    end
  else
    local channels, alpha = body:match("^(.-)%s*/%s*([^/]+)$")
    if body:find("/", 1, true) and not channels then
      return
    end
    for part in (channels or body):gmatch("%S+") do
      parts[#parts + 1] = part
    end
    if alpha then
      parts[#parts + 1] = vim.trim(alpha)
    end
  end
  if #parts ~= 3 and #parts ~= 4 then
    return
  end
  local a = 1
  if #parts == 4 then
    a = number(parts[4], 1)
  end
  if not a then
    return
  end
  a = clamp(a, 1)
  if fn:sub(1, 3) == "rgb" then
    local r, g, b = number(parts[1], 255), number(parts[2], 255), number(parts[3], 255)
    if r and g and b then
      return hex(r, g, b, a)
    end
    return
  end
  local hue, unit = parts[1]:match("^([+-]?%d*%.?%d+)(%a*)$")
  local units = { [""] = 1, deg = 1, turn = 360, rad = 180 / math.pi, grad = 0.9 }
  if not hue or not units[unit] or not parts[2]:match("%%$") or not parts[3]:match("%%$") then
    return
  end
  local s, l = number(parts[2], 1), number(parts[3], 1)
  if not s or not l then
    return
  end
  s, l = clamp(s, 1), clamp(l, 1)
  local h = (tonumber(hue) * units[unit] % 360) / 60
  local c = (1 - math.abs(2 * l - 1)) * s
  local x, m = c * (1 - math.abs(h % 2 - 1)), l - c / 2
  local rgb = ({ { c, x, 0 }, { x, c, 0 }, { 0, c, x }, { 0, x, c }, { x, 0, c }, { c, 0, x } })[math.floor(h) + 1]
  return hex((rgb[1] + m) * 255, (rgb[2] + m) * 255, (rgb[3] + m) * 255, a)
end

function M.scan(line, opts)
  opts = opts or {}
  local result, lower = {}, line:lower()
  local function add(first, last)
    local before, after = lower:sub(first - 1, first - 1), lower:sub(last + 1, last + 1)
    if first > 1 and before:match("[%w_#%-]") or after:match("[%w_%-]") then
      return
    end
    for _, item in ipairs(result) do
      if first - 1 < item.end_col and last > item.col then
        return
      end
    end
    local color = M.parse(lower:sub(first, last), opts.custom)
    if color then
      color.col, color.end_col = first - 1, last
      result[#result + 1] = color
    end
  end
  for first, _, last in lower:gmatch("()(%a+%b())()") do
    add(first, last - 1)
  end
  for first, _, last in lower:gmatch("()(#%x+)()") do
    add(first, last - 1)
  end
  for first, _, last in lower:gmatch("()(0x%x+)()") do
    add(first, last - 1)
  end
  if opts.names ~= false or opts.custom then
    for first, word, last in lower:gmatch("()([%a_][%w_%-]*)()") do
      if
        opts.names ~= false and (names[word] or word == "transparent") or opts.custom and opts.custom[word]
      then
        add(first, last - 1)
      end
    end
  end
  table.sort(result, function(a, b)
    return a.col < b.col
  end)
  return result
end

function M.blend(color, background)
  if color.alpha == 1 then
    return color.hex
  end
  local out = "#"
  for i = 2, 6, 2 do
    local fg, bg = tonumber(color.hex:sub(i, i + 1), 16), tonumber(background:sub(i, i + 1), 16)
    out = out .. ("%02x"):format(math.floor(fg * color.alpha + bg * (1 - color.alpha) + 0.5))
  end
  return out
end

return M
