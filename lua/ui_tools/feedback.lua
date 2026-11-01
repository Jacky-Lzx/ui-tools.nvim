local M = { enabled = false }
local util = require("ui_tools.util")
local ns = vim.api.nvim_create_namespace("UiToolsFeedback")
local handles = {}

local function position(buf, row, col)
  local count = vim.api.nvim_buf_line_count(buf)
  assert(type(row) == "number" and row % 1 == 0 and row >= 0 and row <= count, "feedback row outside buffer")
  local length = row == count and 0 or #vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  assert(
    type(col) == "number" and col % 1 == 0 and col >= 0 and col <= length,
    "feedback column outside line"
  )
end

function M.flash(opts)
  opts = vim.tbl_extend("force", { timeout = 200, hl = "UiToolsFlash", priority = 200 }, opts or {})
  assert(type(opts.timeout) == "number" and opts.timeout >= 0, "feedback.timeout must be nonnegative")
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  assert(vim.api.nvim_buf_is_loaded(buf), "feedback buffer must be loaded")
  local row, col, end_row, end_col
  local whole_line = opts.range == nil
  if opts.range then
    row, col, end_row, end_col = unpack(opts.range)
  else
    row = (opts.line or vim.api.nvim_win_get_cursor(0)[1]) - 1
    col, end_row, end_col = 0, row + (opts.count or 1), 0
  end
  position(buf, row, col)
  position(buf, end_row, end_col)
  assert(row < end_row or row == end_row and col < end_col, "feedback range must be nonempty and ordered")
  local handle = { buf = buf, ids = {}, active = true }
  if whole_line then
    for line = row, end_row - 1 do
      handle.ids[#handle.ids + 1] = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
        line_hl_group = opts.hl,
        priority = opts.priority,
      })
    end
  else
    handle.ids[1] = vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
      end_row = end_row,
      end_col = end_col,
      hl_group = opts.hl,
      priority = opts.priority,
    })
  end
  handles[handle] = true
  function handle:cancel()
    if not self.active then
      return
    end
    self.active = false
    if self.timer then
      self.timer:stop()
      self.timer:close()
      self.timer = nil
    end
    if vim.api.nvim_buf_is_valid(self.buf) then
      for _, id in ipairs(self.ids) do
        pcall(vim.api.nvim_buf_del_extmark, self.buf, ns, id)
      end
    end
    handles[self] = nil
  end
  function handle:is_active()
    return self.active and vim.api.nvim_buf_is_loaded(self.buf)
  end
  if opts.timeout > 0 then
    handle.timer = vim.uv.new_timer()
    handle.timer:start(
      opts.timeout,
      0,
      vim.schedule_wrap(function()
        handle:cancel()
      end)
    )
  end
  util.hl({ UiToolsFlash = "Visual" })
  M.watch()
  return handle
end

function M.watch()
  if M.watching then
    return
  end
  M.watching = true
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = util.group("Feedback"),
    callback = function(event)
      for handle in pairs(handles) do
        if handle.buf == event.buf then
          handle:cancel()
        end
      end
    end,
  })
end

function M.setup(opts)
  M.disable()
  M.options, M.enabled = opts or {}, true
  M.watch()
  util.hl({ UiToolsFlash = "Visual" })
  if M.options.yank then
    vim.api.nvim_create_autocmd("TextYankPost", {
      group = vim.api.nvim_create_augroup("UiToolsFeedback", { clear = false }),
      callback = function()
        vim.hl.on_yank({ higroup = M.options.hl or "UiToolsFlash", timeout = M.options.timeout or 200 })
      end,
    })
  end
end

function M.disable()
  for handle in pairs(handles) do
    handle:cancel()
  end
  M.enabled, M.watching = false, false
  pcall(vim.api.nvim_del_augroup_by_name, "UiToolsFeedback")
end

return M
