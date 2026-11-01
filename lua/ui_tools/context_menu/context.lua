local M = {}
local api = vim.api

function M.valid(ctx)
  return api.nvim_win_is_valid(ctx.win)
    and api.nvim_win_get_buf(ctx.win) == ctx.buf
    and api.nvim_buf_is_loaded(ctx.buf)
end

function M.unchanged(ctx)
  return M.valid(ctx) and api.nvim_buf_get_changedtick(ctx.buf) == ctx.tick
end

function M.capture()
  local ctx = {
    win = api.nvim_get_current_win(),
    buf = api.nvim_get_current_buf(),
    cursor = api.nvim_win_get_cursor(0),
    mode = vim.fn.mode(),
    tick = api.nvim_buf_get_changedtick(0),
  }
  if ctx.mode == "v" or ctx.mode == "V" or ctx.mode == "\22" then
    local first, last = vim.fn.getpos("v"), vim.fn.getpos(".")
    local opts = { type = ctx.mode, exclusive = vim.o.selection == "exclusive" }
    ctx.selection = {
      anchor = first,
      cursor = last,
      type = ctx.mode,
      exclusive = opts.exclusive,
      text = vim.fn.getregion(first, last, opts),
      regions = vim.fn.getregionpos(first, last, opts),
    }
  end
  return ctx
end

function M.contains(ctx, mouse)
  if not ctx.selection or ctx.win ~= mouse.winid then
    return false
  end
  -- getregionpos accounts for reversed/exclusive/line/block selections.
  for _, pair in ipairs(ctx.selection.regions) do
    local first, last = pair[1], pair[2]
    if mouse.line == first[2] and mouse.column >= first[3] and mouse.column <= last[3] then
      if ctx.selection.type ~= "\22" or first[4] == 0 and last[4] == 0 then
        return true
      end
      local col = vim.fn.virtcol({ mouse.line, mouse.column }, true)[1] + (mouse.coladd or 0)
      local left = vim.fn.virtcol({ first[2], first[3] }, true)[1] + first[4]
      local right = vim.fn.virtcol({ last[2], last[3] })
      if last[4] > 0 then
        right = vim.fn.virtcol({ last[2], last[3] }, true)[1] + last[4] - 1
      end
      if col >= left and col <= right then
        return true
      end
    end
  end
  return false
end

function M.normal(keys)
  vim.cmd.normal({ args = { api.nvim_replace_termcodes(keys, true, false, true) }, bang = true })
end

function M.suspend()
  M.normal("<Esc>")
  vim.cmd.stopinsert()
end

function M.restore(ctx, insert)
  if not M.valid(ctx) then
    return false
  end
  api.nvim_set_current_win(ctx.win)
  if not M.unchanged(ctx) then
    return false
  end
  if ctx.selection then
    vim.fn.setpos(".", ctx.selection.anchor)
    M.normal(ctx.selection.type)
    vim.fn.setpos(".", ctx.selection.cursor)
  else
    api.nvim_win_set_cursor(ctx.win, ctx.cursor)
    if insert and ctx.mode:sub(1, 1) == "i" then
      vim.cmd.startinsert()
    end
  end
  return true
end

return M
