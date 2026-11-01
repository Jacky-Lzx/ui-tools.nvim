local M = {}

function M.cell(value, name)
  assert(
    type(value) == "string" and not value:find("[\r\n\t]") and vim.fn.strdisplaywidth(value) == 1,
    (name or "character") .. " must occupy one display cell"
  )
  return value
end

function M.eligible(win, buf, opts)
  return vim.api.nvim_win_is_valid(win)
    and vim.bo[buf].buftype == ""
    and (vim.api.nvim_win_get_config(win).relative == "" or vim.w[win].ui_tools_focus == true)
    and not vim.wo[win].diff
    and not vim.tbl_contains(
      opts.exclude or { "help", "checkhealth", "lazy", "NvimTree" },
      vim.bo[buf].filetype
    )
    and vim.api.nvim_buf_line_count(buf) <= (opts.max_lines or 100000)
    and vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) <= (opts.max_bytes or 10 * 1024 * 1024)
    and vim.b[buf].ui_tools_disable ~= true
end

function M.redraw()
  -- Public command works on all supported releases; schedule outside redraw callbacks.
  if M.pending then
    return
  end
  M.pending = true
  vim.schedule(function()
    M.pending = false
    vim.cmd("redraw!")
  end)
end

function M.group(name)
  return vim.api.nvim_create_augroup("UiTools" .. name, { clear = true })
end

function M.hl(groups)
  for name, link in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

return M
