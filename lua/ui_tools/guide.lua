local M = {}
local util = require("ui_tools.util")
local render = require("ui_tools.render")

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "guide options must be a table")
  opts = vim.deepcopy(opts or {})
  opts = vim.tbl_deep_extend("force", { columns = { 121 }, char = "│" }, opts or {})
  util.cell(opts.char, "guide.char")
  for _, column in ipairs(opts.columns) do
    assert(
      type(column) == "number" and column >= 1 and column % 1 == 0,
      "guide columns must be positive integers"
    )
  end
  return opts
end

function M.setup(opts)
  return M._setup(M.resolve(opts))
end

function M._setup(resolved)
  M.disable()
  local opts = resolved
  M.options = opts
  util.hl({ UiToolsGuide = "NonText" })
  render.register("guide", function(ctx)
    if not util.eligible(ctx.win, ctx.buf, opts) then
      return
    end
    local widths = {}
    vim.api.nvim_win_call(ctx.win, function()
      for row, line in pairs(ctx:read_lines()) do
        widths[row] = vim.fn.strdisplaywidth(ctx.foldtext[row] or line)
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
