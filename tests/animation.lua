local h = dofile("tests/helpers.lua")
local animate = require("ui_tools.animate")
local scroll = require("ui_tools.scroll")
assert(not animate.enabled and not scroll.enabled)
local values, done = {}, false
local instant = animate.run({
  from = 1,
  to = 9,
  step = function(v)
    values[#values + 1] = v
  end,
  done = function()
    done = true
  end,
})
h.eq({ 9 }, values)
assert(done and not instant:is_active())
animate.setup({})
values, done = {}, false
local handle = animate.run({
  duration = 120,
  from = 0,
  to = 10,
  step = function(v)
    values[#values + 1] = v
  end,
  done = function()
    done = true
  end,
})
assert(vim.wait(80, function()
  return #values >= 2
end))
assert(values[2] > 0 and values[2] < 10)
handle:cancel()
local count = #values
vim.wait(160)
assert(#values == count and not done and not handle:is_active())
local finished = animate.run({
  duration = 35,
  step = function() end,
  done = function()
    done = true
  end,
})
assert(vim.wait(300, function()
  return done
end) and not finished:is_active())
local pending = animate.run({ duration = 100, step = function() end })
animate.disable()
assert(not pending:is_active() and not animate.enabled)
require("ui_tools").setup({})
assert(not animate.enabled and not scroll.enabled)
local custom = function() end
vim.keymap.set("n", "<C-d>", custom)
scroll.setup({})
assert(vim.fn.maparg("<C-d>", "n", false, true).callback == custom)
assert(vim.fn.maparg("<C-u>", "n", false, true).callback)
vim.keymap.set("n", "<C-e>", custom)
scroll.disable()
assert(vim.fn.maparg("<C-u>", "n") == "")
assert(vim.fn.maparg("<C-d>", "n", false, true).callback == custom)
assert(vim.fn.maparg("<C-e>", "n", false, true).callback == custom)
vim.keymap.del("n", "<C-d>")
vim.keymap.del("n", "<C-e>")
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.keymap.set("n", "<C-u>", custom, { buffer = buf })
scroll.setup({})
scroll.disable()
local local_mapping = vim.fn.maparg("<C-u>", "n", false, true)
assert(local_mapping.buffer == 1 and local_mapping.callback == custom)
for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
  assert(mapping.desc ~= "Smooth native scroll", "A local mapping hid a leaked global animation map")
end
vim.api.nvim_buf_delete(buf, { force = true })
print("Animation defaults, intermediate values, completion, cancellation and timer cleanup passed")
