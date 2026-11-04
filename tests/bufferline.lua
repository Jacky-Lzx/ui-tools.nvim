local t = dofile("tests/helpers.lua")
local api = vim.api
local ui = require("ui_tools")
local line = require("ui_tools.bufferline")
local bar = require("ui_tools.bar")
local function text()
  return api.nvim_eval_statusline(line.render(), { use_tabline = true, maxwidth = vim.o.columns }).str
end
local function named(name)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "/tmp/ui-tools-bufferline/" .. name)
  return buf
end
vim.bo.buflisted = false
local a, b, c = named("a/init.lua"), named("b/init.lua"), named("中文%{x}.txt")
api.nvim_set_current_buf(a)
local old_show = vim.o.showtabline
ui.setup({ bufferline = { numbers = true, diagnostics = true, auto_hide = -1 } })
assert(text():find("a/init.lua", 1, true) and text():find("b/init.lua", 1, true))
assert(text():find("中文%{x}.txt", 1, true), text())
t.eq(3, #line.items())
assert(line.go(2))
t.eq(b, api.nvim_get_current_buf())
assert(line.cycle(1))
t.eq(c, api.nvim_get_current_buf())
assert(line.cycle(1))
t.eq(a, api.nvim_get_current_buf())
line.move(1)
t.eq(b, line.items()[1].buf)
line.pin()
t.eq(a, line.items()[1].buf)
line.move(10)
t.eq(a, line.items()[1].buf)
local ok, err = line.close()
assert(not ok and err == "Buffer is pinned")
line.pin()
api.nvim_buf_set_lines(a, 0, -1, false, { "unsaved" })
ok, err = line.close()
assert(not ok and err == "Buffer has unsaved changes")
t.eq("unsaved", api.nvim_buf_get_lines(a, 0, -1, false)[1])
vim.cmd("vsplit")
local win, other = api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#"))
vim.wo[other].winfixbuf = true
ok, err = line.close(a, true)
assert(not ok and err:find("winfixbuf", 1, true))
t.eq(a, api.nvim_win_get_buf(win))
t.eq(a, api.nvim_win_get_buf(other))
vim.wo[other].winfixbuf = false
assert(line.close(a, true))
assert(not api.nvim_buf_is_valid(a))
t.eq(2, #api.nvim_list_wins())
assert(api.nvim_win_get_buf(win) ~= a and api.nvim_win_get_buf(other) ~= a)
vim.cmd("only")

local ns = api.nvim_create_namespace("ui-tools-bufferline-test")
vim.diagnostic.set(ns, b, { { lnum = 0, col = 0, message = "error", severity = 1 } })
vim.wait(60)
assert(text():find("E1", 1, true), text())
api.nvim_buf_set_name(b, "/tmp/ui-tools-bufferline/renamed.lua")
line.refresh()
assert(text():find("renamed.lua", 1, true) and not text():find("init.lua", 1, true))
vim.bo[c].buflisted = false
line.refresh()
t.eq(1, #line.items())
line.close(b)
line.refresh()
assert(#line.items() >= 1, "Closing the last buffer supplies an editing buffer")
local path = vim.fn.tempname() .. ".txt"
vim.fn.writefile({ "saved one", "saved two" }, path)
vim.cmd.edit(path)
api.nvim_win_set_cursor(0, { 2, 3 })
line.refresh()
assert(line.close())
local protected = api.nvim_get_current_buf()
vim.bo[protected].modified = true
vim.o.hidden = false
assert(not line.restore())
t.eq(protected, api.nvim_get_current_buf())
vim.bo[protected].modified = false
assert(line.restore())
t.eq(vim.uv.fs_realpath(path), api.nvim_buf_get_name(0))
t.eq({ "saved one", "saved two" }, api.nvim_buf_get_lines(0, 0, -1, false))
t.eq({ 2, 3 }, api.nvim_win_get_cursor(0))
vim.fn.delete(path)
vim.o.hidden = true

-- Render is a prebuilt string: no buffer scans, diagnostics, stat calls or processes.
local originals = { api.nvim_list_bufs, vim.diagnostic.count, vim.fn.system, vim.fn.systemlist }
local get_icon, get_hl = require("ui_tools.icons").get, api.nvim_get_hl
local function forbidden()
  error("expensive operation during render")
end
api.nvim_list_bufs, vim.diagnostic.count, vim.fn.system, vim.fn.systemlist =
  forbidden, forbidden, forbidden, forbidden
require("ui_tools.icons").get, api.nvim_get_hl = forbidden, forbidden
local start = vim.uv.hrtime()
for _ = 1, 10000 do
  line.render()
end
print(string.format("bufferline 10000 cached renders: %.2f ms", (vim.uv.hrtime() - start) / 1e6))
api.nvim_list_bufs, vim.diagnostic.count, vim.fn.system, vim.fn.systemlist = unpack(originals)
require("ui_tools.icons").get, api.nvim_get_hl = get_icon, get_hl

ui.disable()
t.eq("", vim.o.tabline)
t.eq(old_show, vim.o.showtabline)
vim.o.tabline = "external"
assert(line.setup() == false)
t.eq("external", vim.o.tabline)
assert(line.setup({ force = true }))
line.disable()
t.eq("external", vim.o.tabline)
line.setup({ force = true })
vim.o.tabline, vim.o.showtabline = "later owner", 1
line.disable()
t.eq("later owner", vim.o.tabline)
t.eq(1, vim.o.showtabline)
vim.o.tabline = ""
ui.setup({ bufferline = true })
api.nvim_create_buf(true, false) -- Queue a callback, then replace setup immediately.
ui.setup({ bufferline = { auto_hide = -1 } })
vim.wait(60)
assert(line.enabled and vim.o.showtabline == 2)
ui.toggle("bufferline")
assert(not line.enabled)
ui.toggle("bufferline")
assert(line.enabled)
ui.disable()

for width = 0, 20 do
  assert(bar.width(bar.truncate("中文á🙂%foo", width)) <= width)
end
print("bufferline ordering, safety, escaping, diagnostics, ownership and lifecycle passed")
