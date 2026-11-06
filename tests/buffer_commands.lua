local t = dofile("tests/helpers.lua")
local api = vim.api
local ui = require("ui_tools")
local line = require("ui_tools.bufferline")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.o.hidden = true
local warnings, notify = {}, vim.notify
vim.notify = function(message, level)
  t.eq(vim.log.levels.WARN, level)
  warnings[#warnings + 1] = message
end

local function start(names)
  ui.disable()
  for _, win in ipairs(api.nvim_list_wins()) do
    vim.wo[win].winfixbuf = false
  end
  vim.cmd("silent tabonly! | silent only!")
  for _, buf in ipairs(api.nvim_list_bufs()) do
    api.nvim_buf_delete(buf, { force = true })
  end
  vim.bo.buflisted = false
  local buffers = {}
  for _, name in ipairs(names) do
    local path = root .. "/" .. name .. ".txt"
    vim.fn.writefile({ name }, path)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.bo[buf].buflisted = true
    buffers[#buffers + 1] = buf
  end
  api.nvim_set_current_buf(buffers[1])
  local get_commands, scans = api.nvim_get_commands, 0
  api.nvim_get_commands = function(...)
    scans = scans + 1
    return get_commands(...)
  end
  ui.setup({ bufferline = { auto_hide = -1, exclude = { "excluded" } } })
  api.nvim_get_commands = get_commands
  assert(scans <= 2, "buffer commands repeatedly enumerated the global command table")
  warnings = {}
  return unpack(buffers)
end

local function order()
  return vim.tbl_map(function(item)
    return item.buf
  end, line.items())
end

local a, b, c, d = start({ "a", "b", "c", "d" })
vim.cmd("BufferNext 2")
t.eq(c, api.nvim_get_current_buf())
vim.cmd("BufferPrevious")
t.eq(b, api.nvim_get_current_buf())
vim.cmd("BufferFirst | BufferPrevious")
t.eq(d, api.nvim_get_current_buf())
vim.cmd("BufferGoto 2 | BufferMoveNext 2")
t.eq({ a, c, d, b }, order())
vim.cmd("BufferMovePrevious")
t.eq({ a, c, b, d }, order())
vim.cmd("BufferPin | BufferMoveNext 20")
t.eq({ b, a, c, d }, order())
vim.cmd("BufferPin")
assert(not line.items()[1].pinned)
vim.cmd("BufferLast")
t.eq(d, api.nvim_get_current_buf())
for _, command in ipairs({ "BufferGoto 0", "BufferNext -1", "BufferMoveNext 1.5", "BufferGoto nope" }) do
  vim.cmd(command)
  t.eq(d, api.nvim_get_current_buf())
  assert(warnings[#warnings]:find("Expected a positive integer", 1, true))
end
vim.cmd("BufferGoto 99")
assert(warnings[#warnings]:find("No buffer available", 1, true))

-- Bulk close includes listed special buffers, but preserves excluded/unlisted ones.
a, b, c, d = start({ "current", "pinned", "modified", "clean", "excluded", "special", "unlisted" })
local all = order()
line.pin(b)
api.nvim_buf_set_lines(c, 0, -1, false, { "unsaved text" })
vim.bo[all[5]].filetype = "excluded"
vim.bo[all[6]].buftype = "nofile"
vim.bo[all[7]].buflisted = false
line.refresh()
vim.cmd("BufferCloseAllButCurrent")
t.eq({ b, a, c }, order())
assert(not api.nvim_buf_is_valid(d))
assert(not api.nvim_buf_is_valid(all[6]))
t.eq("unsaved text", api.nvim_buf_get_lines(c, 0, -1, false)[1])
assert(#warnings == 1 and warnings[1]:find("pinned", 1, true) and warnings[1]:find("unsaved", 1, true))
vim.cmd("BufferCloseAllButCurrent!")
t.eq({ a }, order())
t.eq(a, api.nvim_get_current_buf())
for _, i in ipairs({ 5, 7 }) do
  assert(api.nvim_buf_is_valid(all[i]))
end

-- Left/right mean positions in the bar after reordering, rather than buffer IDs.
a, b, c, d = start({ "left", "middle", "right", "tail" })
vim.cmd("BufferGoto 2 | BufferMoveNext")
t.eq({ a, c, b, d }, order())
vim.cmd("BufferCloseBuffersLeft")
t.eq({ b, d }, order())
t.eq(b, api.nvim_get_current_buf())
vim.cmd("BufferCloseBuffersRight")
t.eq({ b }, order())
local special = api.nvim_create_buf(false, true)
api.nvim_set_current_buf(special)
vim.cmd("BufferCloseBuffersLeft!")
t.eq({ b }, order())
assert(warnings[#warnings]:find("Current buffer is not in the buffer bar", 1, true))

a, b, c = start({ "keep-pin", "delete-current", "delete-hidden" })
line.pin(a)
api.nvim_set_current_buf(b)
vim.cmd("BufferCloseAllButPinned!")
t.eq({ a }, order())
t.eq(a, api.nvim_get_current_buf())

-- Visibility is captured across tabpages before any target is closed.
a, b, c, d = start({ "tab-one", "tab-two", "hidden-one", "hidden-two" })
vim.cmd("tabnew")
vim.bo.buflisted = false
api.nvim_set_current_buf(b)
line.pin(c)
vim.cmd("BufferCloseAllButVisible!")
t.eq({ a, b }, order())
t.eq(2, #api.nvim_list_tabpages())
t.eq(b, api.nvim_get_current_buf())

-- A fixed window blocks only its target; other closes still succeed with bang.
a, b, c = start({ "source", "fixed", "close-after-failure" })
vim.cmd("vsplit")
local fixed = api.nvim_get_current_win()
api.nvim_win_set_buf(fixed, b)
vim.wo[fixed].winfixbuf = true
vim.cmd("wincmd p")
vim.cmd("BufferCloseAllButCurrent!")
t.eq({ a, b }, order())
t.eq(a, api.nvim_get_current_buf())
t.eq(b, api.nvim_win_get_buf(fixed))
t.eq(2, #api.nvim_list_wins())
assert(not api.nvim_buf_is_valid(c))
assert(#warnings == 1 and warnings[1]:find("winfixbuf", 1, true))

a, b, c = start({ "restore-source", "restore-second", "restore-last" })
vim.cmd("BufferCloseAllButCurrent | BufferRestore")
t.eq("restore-last", api.nvim_get_current_line())
t.eq({ a, api.nvim_get_current_buf() }, order())
vim.cmd("BufferPin | BufferClose")
assert(warnings[#warnings]:find("Buffer is pinned", 1, true))
vim.cmd("BufferClose!")
t.eq({ a }, order())
api.nvim_buf_set_lines(a, 0, -1, false, { "discard only with bang" })
vim.cmd("BufferCloseAll")
assert(api.nvim_buf_is_valid(a))
vim.cmd("BufferCloseAll!")
assert(not api.nvim_buf_is_valid(a))
t.eq(1, #line.items())
t.eq("", api.nvim_buf_get_name(0))
ui.disable()
local ok, err = line.close_many("all", true)
assert(not ok and err == "Bufferline is disabled")

-- Commands follow enable/disable and preserve both earlier and later owners.
t.eq(0, vim.fn.exists(":BufferCloseAllButCurrent"))
local external = function() end
api.nvim_create_user_command("BufferNext", external, {})
local conflict, message = pcall(ui.setup, { bufferline = true })
assert(not conflict and tostring(message):find("command already exists: BufferNext", 1, true))
local registered = api.nvim_get_commands({}).BufferNext
assert(not api.nvim_get_commands({}).BufferClose, "Conflict left partially registered commands")
api.nvim_del_user_command("BufferNext")
ui.setup({ bufferline = true })
api.nvim_create_user_command("BufferNext", external, {})
registered = api.nvim_get_commands({}).BufferNext
api.nvim_create_user_command("BufferCloseAllButCurrent", external, {})
ui.disable()
local remaining = api.nvim_get_commands({})
t.eq(registered, remaining.BufferNext)
assert(remaining.BufferCloseAllButCurrent)
assert(not remaining.BufferClose)
api.nvim_del_user_command("BufferNext")
api.nvim_del_user_command("BufferCloseAllButCurrent")
ui.setup({ bufferline = true })
ui.setup({ bufferline = true })
t.eq(2, vim.fn.exists(":BufferCloseAllButCurrent"))
ui.toggle("bufferline")
t.eq(0, vim.fn.exists(":BufferCloseAllButCurrent"))
ui.toggle("bufferline")
t.eq(2, vim.fn.exists(":BufferCloseAllButCurrent"))
ui.disable()
vim.o.tabline = "another owner"
assert(not line.setup())
t.eq(0, vim.fn.exists(":BufferCloseAllButCurrent"))
vim.o.tabline = ""
vim.notify = notify
vim.fn.delete(root, "rf")
print("buffer commands: navigation, bulk selection, protections, restore and ownership passed")
