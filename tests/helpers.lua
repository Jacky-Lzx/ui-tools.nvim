vim.opt.rtp:prepend(vim.fn.getcwd())
local M = {}
function M.eq(expected, actual)
  assert(
    vim.deep_equal(expected, actual),
    "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end
function M.buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].tabstop = 4
  return buf
end
return M
