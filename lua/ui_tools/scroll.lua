local M = { enabled = false }
local api = vim.api
local states, mappings, group, busy = {}, {}, nil, false
local keys = { "<C-d>", "<C-u>", "<C-f>", "<C-b>", "<C-e>", "<C-y>" }
local function view(win)
  return api.nvim_win_call(win, vim.fn.winsaveview)
end
local function valid(win, state)
  return api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == state.buf
end
local function restore(win, target)
  api.nvim_win_call(win, function()
    vim.fn.winrestview(target)
  end)
end
local function cancel(win, finish)
  local state = states[win]
  if not state then
    return
  end
  if state.handle then
    state.handle:cancel()
  end
  states[win] = nil
  if finish and valid(win, state) then
    restore(win, state.target)
  end
end
function M.settle()
  for win in pairs(states) do
    cancel(win, true)
  end
end
local function folded(win, first, last)
  if last - first > 1000 then
    return true
  end
  return api.nvim_win_call(win, function()
    for line = first, last do
      if vim.fn.foldclosed(line) >= 0 then
        return true
      end
    end
    return false
  end)
end

-- Compute the exact native destination from the preceding pending destination.
-- This avoids interpreting delayed WinScrolled events as additional user input.
function M.scroll(key, count)
  local win = api.nvim_get_current_win()
  local previous = view(win)
  busy = true
  cancel(win, true)
  local ok, err = pcall(
    vim.cmd.normal,
    { args = { (count and count > 0 and tostring(count) or "") .. vim.keycode(key) }, bang = true }
  )
  if not ok then
    busy = false
    error(err)
  end
  local target, buf = view(win), api.nvim_win_get_buf(win)
  local animate = require("ui_tools.animate")
  if
    not M.enabled
    or not animate.enabled
    or previous.topline == target.topline
    or vim.wo[win].wrap
    or vim.wo[win].diff
    or vim.bo[buf].buftype ~= ""
    or vim.b[buf].bigfile
    or folded(
      win,
      math.min(previous.topline, target.topline),
      math.min(
        api.nvim_buf_line_count(buf),
        math.max(previous.topline, target.topline) + api.nvim_win_get_height(win)
      )
    )
  then
    busy = false
    return
  end
  restore(win, previous)
  local state = { buf = buf, target = target, rendered = view(win) }
  states[win] = state
  local height = api.nvim_win_get_height(win)
  state.handle = animate.run({
    from = 0,
    to = 1,
    duration = (M.options or {}).duration or 140,
    step = function(progress)
      if not valid(win, state) then
        cancel(win, false)
        return
      end
      local frame = vim.deepcopy(target)
      frame.topline = math.floor(previous.topline + (target.topline - previous.topline) * progress + 0.5)
      frame.lnum = math.floor(previous.lnum + (target.lnum - previous.lnum) * progress + 0.5)
      if progress < 1 then
        local margin = math.min(vim.wo[win].scrolloff, math.floor((height - 1) / 2))
        frame.lnum =
          math.max(frame.topline + margin, math.min(frame.lnum, frame.topline + height - 1 - margin))
      end
      restore(win, frame)
      state.rendered = view(win)
    end,
    done = function()
      if valid(win, state) then
        restore(win, target)
      end
      states[win] = nil
    end,
  })
  busy = false
end

local function global_mapping(key)
  local raw = vim.keycode(key)
  for _, mapping in ipairs(api.nvim_get_keymap("n")) do
    if vim.keycode(mapping.lhs) == raw or mapping.lhsrawalt == raw then
      return mapping
    end
  end
  return {}
end
function M.setup(opts)
  M.disable()
  M.options, M.enabled = opts or {}, true
  group = api.nvim_create_augroup("UiToolsScroll", { clear = true })
  for _, key in ipairs(M.options.mappings == true and keys or {}) do
    -- Existing mappings retain ownership. Buffer-local mappings also win over
    -- these optional global defaults, just as they do over native keys.
    if not next(global_mapping(key)) then
      local callback = function()
        M.scroll(key, vim.v.count)
      end
      vim.keymap.set("n", key, callback, { silent = true, desc = "Smooth native scroll" })
      mappings[key] = callback
    end
  end
  api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
    group = group,
    callback = function()
      if busy then
        return
      end
      for win, state in pairs(states) do
        if not valid(win, state) then
          cancel(win, false)
        else
          local actual = view(win)
          if
            actual.topline ~= state.rendered.topline
            or actual.lnum ~= state.rendered.lnum
            or actual.col ~= state.rendered.col
          then
            cancel(win, false)
          end
        end
      end
    end,
  })
  api.nvim_create_autocmd({ "InsertEnter", "CmdlineEnter" }, { group = group, callback = M.settle })
  api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    callback = function(ev)
      for win, state in pairs(states) do
        if state.buf == ev.buf then
          cancel(win, false)
        end
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      cancel(tonumber(ev.match), false)
    end,
  })
end
function M.disable()
  M.enabled = false
  if group then
    pcall(api.nvim_del_augroup_by_id, group)
    group = nil
  end
  M.settle()
  for key, callback in pairs(mappings) do
    local mapping = global_mapping(key)
    if mapping.callback == callback then
      pcall(vim.keymap.del, "n", key)
    end
  end
  mappings = {}
end
return M
