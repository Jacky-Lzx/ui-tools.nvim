local M = { enabled = false }
local handles = {}

function M.run(opts)
  assert(type(opts.step) == "function", "animation requires step(value)")
  local duration = opts.duration or (M.options or {}).duration or 140
  assert(type(duration) == "number" and duration >= 0, "animation duration must be nonnegative")
  local from, to = opts.from or 0, opts.to or 1
  local handle = { active = true, value = from }
  function handle:cancel()
    if not self.active then
      return
    end
    self.active = false
    handles[self] = nil
    if self.timer then
      self.timer:stop()
      self.timer:close()
      self.timer = nil
    end
  end
  function handle:is_active()
    return self.active
  end
  local function apply(value, done)
    if not handle.active then
      return
    end
    handle.value = value
    local ok, err = pcall(opts.step, value)
    if not ok or done then
      handle:cancel()
      if not ok then
        vim.schedule(function()
          vim.notify(tostring(err), vim.log.levels.ERROR, { title = "UI animation" })
        end)
      elseif opts.done then
        opts.done()
      end
    end
  end
  handles[handle] = true
  if not M.enabled or duration == 0 then
    apply(to, true)
    return handle
  end
  apply(from, false)
  if not handle.active then
    return handle
  end
  local start = vim.uv.hrtime()
  handle.timer = vim.uv.new_timer()
  handle.timer:start(
    16,
    16,
    vim.schedule_wrap(function()
      if not handle.active then
        return
      end
      local t = math.min(1, (vim.uv.hrtime() - start) / (duration * 1e6))
      local eased = 1 - (1 - t) ^ 3
      apply(from + (to - from) * eased, t == 1)
    end)
  )
  return handle
end

function M.setup(opts)
  M.disable()
  M.options, M.enabled = opts or {}, true
end

function M.disable()
  M.enabled = false
  for handle in pairs(handles) do
    handle:cancel()
  end
  -- A cancelled scroll must settle at its native destination.
  local scroll = package.loaded["ui_tools.scroll"]
  if scroll then
    scroll.settle()
  end
end
return M
