-- Buffer annotations are refreshed outside redraw callbacks. Only rows visible
-- in eligible windows are scanned; folds and hidden buffers do not add work.
local util = require("ui_tools.util")
local M = {}

function M.new(name)
  local self = { ns = vim.api.nvim_create_namespace("UiTools" .. name), attached = {}, marked = {} }
  local generation, pending = 0, false

  function self.queue()
    if not self.enabled or pending then
      return
    end
    pending = true
    local token = generation
    vim.defer_fn(function()
      if token == generation then
        pending = false
        self.refresh()
      end
    end, self.options.refresh)
  end

  local function collect()
    local visible = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if util.eligible(win, buf, self.options) then
        visible[buf] = visible[buf] or {}
        vim.api.nvim_win_call(win, function()
          local row, last = vim.fn.line("w0"), vim.fn.line("w$")
          while row <= last do
            local closed = vim.fn.foldclosed(row)
            if closed == -1 then
              visible[buf][row - 1] = win
              row = row + 1
            else
              row = vim.fn.foldclosedend(row) + 1
            end
          end
        end)
      end
    end
    return visible
  end

  function self.refresh()
    if not self.enabled then
      return
    end
    local visible = collect()
    self.visible = visible
    for buf in pairs(self.marked) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
      end
    end
    self.marked = {}
    for buf, rows in pairs(visible) do
      if not self.attached[buf] then
        self.attached[buf] = vim.api.nvim_buf_attach(buf, false, {
          on_lines = self.queue,
          on_reload = self.queue,
          on_detach = function()
            self.attached[buf], self.marked[buf] = nil, nil
          end,
        })
      end
      self.marked[buf] = true
      for row, win in pairs(rows) do
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        if #line <= self.options.max_line_length then
          self.paint(buf, row, line, win)
        end
      end
    end
    if self.on_refresh then
      self.on_refresh()
    end
    util.redraw()
  end

  function self.disable()
    self.enabled = false
    generation, pending = generation + 1, false
    pcall(vim.api.nvim_del_augroup_by_name, "UiTools" .. name)
    for buf in pairs(self.marked) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
      end
    end
    self.marked = {}
    self.visible = {}
    if self.on_refresh then
      self.on_refresh()
    end
    util.redraw()
  end

  function self.start(opts, paint)
    self.disable()
    assert(opts.refresh >= 0 and opts.refresh % 1 == 0, name .. ".refresh must be a nonnegative integer")
    assert(opts.max_line_length > 0, name .. ".max_line_length must be positive")
    self.options, self.paint, self.enabled = opts, paint, opts.enabled ~= false
    local group = util.group(name)
    vim.api.nvim_create_autocmd({
      "BufWinEnter",
      "BufWinLeave",
      "TabEnter",
      "WinEnter",
      "WinClosed",
      "WinScrolled",
      "VimResized",
      "TextChanged",
      "TextChangedI",
      "TextChangedP",
      "InsertLeave",
      "FileType",
      "Syntax",
      "OptionSet",
      "ColorScheme",
    }, { group = group, callback = self.queue })
    -- Native fold commands need not move the cursor or emit OptionSet.
    vim.api.nvim_create_autocmd("SafeState", {
      group = group,
      callback = function()
        if self.enabled and not vim.deep_equal(collect(), self.visible) then
          self.queue()
        end
      end,
    })
    self.refresh()
  end

  return self
end

return M
