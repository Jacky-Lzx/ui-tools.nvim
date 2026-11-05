local M = {}
local api = vim.api
local owned = {}

function M.setup(buffers)
  local existing, created = api.nvim_get_commands({}), {}
  local function register(name, action, opts)
    -- Coexist with commands supplied by another plugin or the user's config.
    if existing[name] then
      return
    end
    opts = vim.tbl_extend("force", { desc = "ui-tools: " .. name, force = false, bar = true }, opts or {})
    api.nvim_create_user_command(name, function(args)
      local ok, result, err = pcall(action, args)
      if not ok or err or result == false then
        vim.notify(
          "ui-tools: " .. (not ok and tostring(result) or err or "No buffer available for " .. name),
          vim.log.levels.WARN
        )
      end
    end, opts)
    created[name] = true
  end
  local function number(args)
    local value = args.args == "" and 1 or tonumber(args.args)
    assert(value and value >= 1 and value % 1 == 0, "Expected a positive integer")
    return value
  end
  register("BufferNext", function(args)
    return buffers.cycle(number(args))
  end, { nargs = "?" })
  register("BufferPrevious", function(args)
    return buffers.cycle(-number(args))
  end, { nargs = "?" })
  register("BufferMoveNext", function(args)
    return buffers.move(number(args))
  end, { nargs = "?" })
  register("BufferMovePrevious", function(args)
    return buffers.move(-number(args))
  end, { nargs = "?" })
  register("BufferGoto", function(args)
    return buffers.go(number(args))
  end, { nargs = 1 })
  register("BufferFirst", function()
    return buffers.go(1)
  end)
  register("BufferLast", function()
    return buffers.go(#buffers.items())
  end)
  register("BufferPin", function()
    buffers.pin() -- false also means a successful unpin.
  end)
  register("BufferClose", function(args)
    return buffers.close(nil, args.bang)
  end, { bang = true })
  register("BufferRestore", buffers.restore)
  for name, scope in pairs({
    BufferCloseAll = "all",
    BufferCloseAllButCurrent = "others",
    BufferCloseBuffersLeft = "left",
    BufferCloseBuffersRight = "right",
    BufferCloseAllButPinned = "unpinned",
    BufferCloseAllButVisible = "hidden",
  }) do
    register(name, function(args)
      return buffers.close_many(scope, args.bang)
    end, { bang = true })
  end
  if next(created) then
    local installed = api.nvim_get_commands({})
    for name in pairs(created) do
      owned[name] = installed[name]
    end
  end
end

function M.disable()
  if not next(owned) then
    return
  end
  local commands = api.nvim_get_commands({})
  for name, command in pairs(owned) do
    local current = commands[name]
    -- 0.12 exposes callback identity; 0.11 exposes the stored description/options.
    if current and vim.deep_equal(current, command) then
      api.nvim_del_user_command(name)
    end
  end
  owned = {}
end

return M
