local M = {}
local util = require("ui_tools.util")
local render = require("ui_tools.render")
local scope = require("ui_tools.scope")

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", {
    enabled = true,
    char = "│",
    only_scope = false,
    scope = true,
    chunk = true,
    max_scan = 400,
  }, opts or {})
  util.cell(opts.char, "indent.char")
  assert(opts.max_scan >= 1 and opts.max_scan % 1 == 0, "indent.max_scan must be a positive integer")
  M.options = opts
  util.hl({ UiToolsIndent = "Whitespace", UiToolsScope = "Special" })
  local group = util.group("Indent")
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "OptionSet" }, {
    group = group,
    callback = util.redraw,
  })
  render.register("indent", opts.enabled and function(ctx)
    if not util.eligible(ctx.win, ctx.buf, opts) then
      return
    end
    local block = (opts.scope or opts.only_scope or opts.chunk)
      and scope.find(ctx.buf, ctx.cursor[1], opts.max_scan)
    local step = vim.bo[ctx.buf].shiftwidth
    if step == 0 then
      step = vim.bo[ctx.buf].tabstop
    end
    local widths = {}
    for row, line in pairs(ctx:read_lines()) do
      widths[row] = line:find("%S") and scope.width(line, vim.bo[ctx.buf].tabstop) or false
    end
    local top = block and block.first
    if block then
      -- Keep the corner anchored to the block, including when its start is off-screen.
      local header = vim.api.nvim_buf_get_lines(ctx.buf, top - 1, top, false)[1] or ""
      if header:find("%S") and scope.width(header, vim.bo[ctx.buf].tabstop) <= block.column then
        top = top + 1
      end
    end
    return function(row)
      if ctx.foldtext[row] then
        return
      end
      local width = widths[row]
      if width == nil then
        return
      end
      if width == false then
        -- Blank lines use adjacent indentation, bounded by the visible range.
        local before, after = row - 1, row + 1
        while before >= ctx.top and widths[before] == false do
          before = before - 1
        end
        while after < ctx.bottom and widths[after] == false do
          after = after + 1
        end
        width = math.max(widths[before] or 0, widths[after] or 0)
      end
      if not opts.only_scope then
        for col = math.floor(ctx.leftcol / step) * step, math.min(width - 1, ctx.leftcol + ctx.width), step do
          render.mark(ctx, row, col, opts.char, "UiToolsIndent")
        end
      end
      if block and row + 1 >= block.first and row + 1 <= block.last then
        local char = opts.char
        if opts.chunk then
          char = row + 1 == top and "╭" or row + 1 == block.last and "╰" or "│"
        end
        -- Never replace source text at a block header's first nonblank cell.
        if width > block.column or widths[row] == false then
          render.mark(ctx, row, block.column, char, "UiToolsScope", 20)
        end
      end
    end
  end or nil)
end

function M.disable()
  pcall(vim.api.nvim_del_augroup_by_name, "UiToolsIndent")
  render.register("indent", nil)
end

return M
