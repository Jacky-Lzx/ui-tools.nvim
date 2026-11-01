local M = { sources = {}, errors = {} }
local ns = vim.api.nvim_create_namespace("UiToolsDecorations")
local frames = {}

function M.mark(ctx, row, column, char, hl, priority)
  local col = column - ctx.leftcol
  if col < 0 or col >= ctx.width - ctx.textoff then
    return
  end
  vim.api.nvim_buf_set_extmark(ctx.buf, ns, row, 0, {
    ephemeral = true,
    virt_text = { { char, hl } },
    virt_text_pos = "overlay",
    virt_text_win_col = col,
    hl_mode = "combine",
    priority = priority or 10,
  })
end

local function context(win, buf, top, bottom)
  local info = vim.fn.getwininfo(win)[1]
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  return {
    win = win,
    buf = buf,
    top = top,
    bottom = bottom,
    width = info.width,
    height = info.height,
    textoff = info.textoff,
    leftcol = view.leftcol,
    cursor = vim.api.nvim_win_get_cursor(win),
    lines = vim.api.nvim_buf_get_lines(buf, top, bottom, false),
  }
end

function M.register(name, prepare)
  M.sources[name] = prepare
  if not next(M.sources) then
    vim.api.nvim_set_decoration_provider(ns, {})
  else
    vim.api.nvim_set_decoration_provider(ns, {
      on_start = function()
        frames = {}
      end,
      on_win = function(_, win, buf, top, bottom)
        local ctx = context(win, buf, top, bottom)
        local draws = {}
        for key, source in pairs(M.sources) do
          local ok, draw = pcall(source, ctx)
          if ok and draw then
            draws[#draws + 1] = { key, draw }
          elseif not ok then
            M.errors[key] = tostring(draw)
          end
        end
        frames[win] = draws
        return #draws > 0
      end,
      on_line = function(_, win, _, row)
        for _, draw in ipairs(frames[win] or {}) do
          local ok, err = pcall(draw[2], row)
          if not ok then
            M.errors[draw[1]] = tostring(err)
          end
        end
      end,
    })
  end
  require("ui_tools.util").redraw()
end

return M
