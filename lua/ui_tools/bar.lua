-- Shared, dependency-free helpers for native tabline, statusline and winbar.
local M = {}

function M.text(value)
  return tostring(value or ""):gsub("[%z\1-\31\127]", " ")
end

function M.escape(value)
  return M.text(value):gsub("%%", "%%%%")
end

function M.highlight(name)
  return (name or "StatusLine"):gsub("[^%w_@.%-]", "")
end

function M.label(value, hl)
  return "%#" .. M.highlight(hl) .. "#" .. M.escape(value) .. "%*"
end

function M.width(value)
  return vim.fn.strdisplaywidth(value)
end

function M.truncate(value, width)
  width = math.max(0, width)
  if M.width(value) <= width then
    return value
  end
  if width == 0 then
    return ""
  end
  local low, high = 0, vim.fn.strchars(value)
  while low < high do
    local mid = math.ceil((low + high) / 2)
    if M.width(vim.fn.strcharpart(value, 0, mid)) <= width - 1 then
      low = mid
    else
      high = mid - 1
    end
  end
  return vim.fn.strcharpart(value, 0, low) .. "…"
end

-- Tabline/winbar visibility changes resize text windows. With splitkeep=screen
-- Neovim may move the logical cursor to preserve its screen row. Settle that
-- geometry synchronously, then restore the original document positions/views.
function M.preserve_views(callback)
  local views = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      views[win] =
        { buf = vim.api.nvim_win_get_buf(win), view = vim.api.nvim_win_call(win, vim.fn.winsaveview) }
    end
  end
  callback()
  -- Startup chrome changes must settle with the first normal redraw. Forcing
  -- one before VimEnter can expose the builtin intro before the dashboard.
  if vim.v.vim_did_enter == 1 then
    vim.cmd("redraw!")
  end
  for win, item in pairs(views) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == item.buf then
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(item.view)
      end)
    end
  end
end

-- One deferred callback per burst, with no repeating timer or idle work.
-- Cancelling also invalidates callbacks from a previous setup generation.
function M.scheduler(delay, callback)
  local generation, pending = 0, false
  return {
    request = function()
      if pending then
        return
      end
      pending = true
      local current = generation
      vim.defer_fn(function()
        if generation == current then
          pending = false
          callback()
        end
      end, delay)
    end,
    cancel = function()
      generation, pending = generation + 1, false
    end,
  }
end

return M
