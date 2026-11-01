local M = {}
local util = require("ui_tools.util")
local render = require("ui_tools.render")

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", { columns = { 121 }, char = "│" }, opts or {})
  util.cell(opts.char, "guide.char")
  for _, column in ipairs(opts.columns) do
    assert(
      type(column) == "number" and column >= 1 and column % 1 == 0,
      "guide columns must be positive integers"
    )
  end
  M.options = opts
  util.hl({ UiToolsGuide = "NonText" })
  render.register("guide", function(ctx)
    if not util.eligible(ctx.win, ctx.buf, opts) then
      return
    end
    local widths = {}
    vim.api.nvim_win_call(ctx.win, function()
      local row = ctx.top
      while row < ctx.bottom do
        local closed = vim.fn.foldclosed(row + 1)
        if closed == row + 1 then
          widths[row] = vim.fn.strdisplaywidth(vim.fn.foldtextresult(row + 1))
          row = vim.fn.foldclosedend(row + 1)
        else
          widths[row] = vim.fn.strdisplaywidth(ctx.lines[row - ctx.top + 1] or "")
          row = row + 1
        end
      end
    end)
    return function(row)
      for _, column in ipairs(opts.columns) do
        if widths[row] and widths[row] < column then
          render.mark(ctx, row, column - 1, opts.char, "UiToolsGuide", 1)
        end
      end
    end
  end)
end

function M.disable()
  render.register("guide", nil)
end

return M
