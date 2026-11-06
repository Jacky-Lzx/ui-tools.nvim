local M = require("ui_tools.annotations").new("Colors")
local color = require("ui_tools.color")
local util = require("ui_tools.util")
local groups = {}

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "colors options must be a table")
  opts = vim.deepcopy(opts or {})
  opts = vim.tbl_deep_extend("force", {
    enabled = true,
    style = "inline",
    symbol = "■",
    names = true,
    custom = {},
    refresh = 30,
    max_line_length = 4096,
    priority = 150,
  }, opts or {})
  assert(
    vim.tbl_contains({ "inline", "eol", "foreground", "background" }, opts.style),
    "Invalid colors.style"
  )
  util.cell(opts.symbol, "colors.symbol")
  local custom = {}
  for name, value in pairs(opts.custom) do
    assert(
      type(name) == "string" and name:match("^[%a_][%w_%-]*$") and color.parse(value),
      "Invalid custom color"
    )
    custom[name:lower()] = value
  end
  opts.custom = custom
  require("ui_tools.annotations").validate(opts, "colors")
  return opts
end

function M.setup(opts)
  return M._setup(M.resolve(opts))
end

function M._setup(resolved)
  M.disable()
  local opts = resolved
  groups = {}
  M.start(opts, function(buf, row, line)
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local background = ("#%06x"):format(normal.bg or (vim.o.background == "light" and 0xffffff or 0))
    local eol = {}
    for _, item in ipairs(color.scan(line, opts)) do
      local rgb = color.blend(item, background)
      local group = "UiToolsColor" .. opts.style .. rgb:sub(2)
      if not groups[group] then
        local def = { fg = rgb }
        if opts.style == "background" then
          local r, g, b =
            tonumber(rgb:sub(2, 3), 16), tonumber(rgb:sub(4, 5), 16), tonumber(rgb:sub(6, 7), 16)
          def = { bg = rgb, fg = (r * 299 + g * 587 + b * 114) >= 128000 and "#000000" or "#ffffff" }
        end
        vim.api.nvim_set_hl(0, group, def)
        groups[group] = true
      end
      local mark = { priority = opts.priority }
      if opts.style == "inline" then
        mark.virt_text, mark.virt_text_pos = { { opts.symbol .. " ", group } }, "inline"
      elseif opts.style == "eol" then
        eol[#eol + 1] = { " " .. opts.symbol, group }
      else
        mark.end_col, mark.hl_group = item.end_col, group
      end
      if opts.style ~= "eol" then
        vim.api.nvim_buf_set_extmark(buf, M.ns, row, item.col, mark)
      end
    end
    if #eol > 0 then
      vim.api.nvim_buf_set_extmark(
        buf,
        M.ns,
        row,
        0,
        { virt_text = eol, virt_text_pos = "eol", priority = opts.priority }
      )
    end
  end)
  require("ui_tools.theme").bind("colors", function()
    groups = {}
    M.queue()
  end)
end

local stop = M.disable
function M.disable()
  require("ui_tools.theme").unbind("colors")
  stop()
end

return M
