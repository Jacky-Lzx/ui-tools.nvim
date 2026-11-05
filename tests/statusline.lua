local t = dofile("tests/helpers.lua")
local api = vim.api
local ui = require("ui_tools")
local line = require("ui_tools.statusline")
local root = vim.fn.getcwd()
local directory = assert(vim.uv.fs_realpath("/tmp"))
local filename = directory .. "/ui-tools-statusline/中文%{evil}.lua"
assert(
  #api.nvim_list_uis() > 0 and vim.o.columns == 240,
  "Run python3 tests/lua_ui.py tests/statusline.lua --width 240"
)
local function text(win, width)
  win = win or api.nvim_get_current_win()
  return api.nvim_eval_statusline(vim.wo[win].statusline, { winid = win, maxwidth = width or 240 }).str
end
local function settle()
  vim.wait(60)
end
local a = t.buffer({ "one", "two", "three" })
api.nvim_buf_set_name(a, filename)
vim.bo.filetype = "lua"
vim.bo.modified = false
vim.b.git_tools_status = { head = "feature/%branch", added = 2, changed = 3, removed = 1 }
local before = {
  statusline = api.nvim_get_option_value("statusline", { scope = "local", win = 0 }),
  global = vim.go.statusline,
  laststatus = vim.o.laststatus,
}
local ns = api.nvim_create_namespace("ui-tools-statusline-test")
vim.diagnostic.set(ns, a, {
  { lnum = 0, col = 0, message = "error", severity = 1 },
  { lnum = 1, col = 0, message = "warning", severity = 2 },
})
local clients = vim.lsp.get_clients
local queries = 0
vim.lsp.get_clients = function(args)
  if not args then
    return {}
  end
  queries = queries + 1
  t.eq(a, args.bufnr)
  return { { name = "lua_ls" }, { name = "lua_ls" }, { name = "test_ls" } }
end
ui.setup({ statusline = { globalstatus = true } })
t.eq(3, vim.o.laststatus)
t.eq(before.global, vim.go.statusline)
local value = text()
for _, fragment in ipairs({
  "NORMAL",
  "中文%{evil}.lua",
  "feature/%branch",
  "+2 ~3 -1",
  "E1 W1",
  "lua_ls, test_ls",
  "utf-8",
  "lua",
  "1:1",
}) do
  assert(value:find(fragment, 1, true), fragment .. ": " .. value)
end
t.eq(1, queries)
for _, fragment in ipairs({
  " NORMAL",
  " feature/%branch",
  " " .. directory .. "/ui-tools-statusline/",
  "",
  "",
  "│",
}) do
  assert(value:find(fragment, 1, true), fragment .. ": " .. value)
end

-- Cursor redraws read only bounded native state, never providers or filesystem APIs.
local get_clients, count, list_bufs, system =
  vim.lsp.get_clients, vim.diagnostic.count, api.nvim_list_bufs, vim.fn.system
local function forbidden()
  error("expensive provider in statusline render")
end
local icon_get, get_hl, set_hl = require("ui_tools.icons").get, api.nvim_get_hl, api.nvim_set_hl
require("ui_tools.icons").get, api.nvim_get_hl, api.nvim_set_hl = forbidden, forbidden, forbidden
vim.lsp.get_clients, vim.diagnostic.count, api.nvim_list_bufs, vim.fn.system =
  forbidden, forbidden, forbidden, forbidden
for row = 1, 3 do
  api.nvim_win_set_cursor(0, { row, 1 })
  assert(text():find(row .. ":2", 1, true))
end
vim.lsp.get_clients, vim.diagnostic.count, api.nvim_list_bufs, vim.fn.system =
  get_clients, count, list_bufs, system
require("ui_tools.icons").get, api.nvim_get_hl, api.nvim_set_hl = icon_get, get_hl, set_hl
t.eq(1, queries)
vim.b.git_tools_status = { head = "updated", added = 4 }
api.nvim_exec_autocmds("User", { pattern = "GitToolsUpdate" })
settle()
value = text()
assert(value:find("updated", 1, true) and value:find("+4", 1, true))
assert(not value:find("feature/%branch", 1, true))
t.eq(1, queries)
vim.diagnostic.reset(ns, a)
settle()
assert(not text():find("E1", 1, true))
t.eq(1, queries)
vim.lsp.get_clients = clients

local native_signs = vim.diagnostic.config().signs
vim.diagnostic.config({ signs = { text = { [1] = "", [2] = "", [3] = "", [4] = "󰌶" } } })
vim.diagnostic.set(ns, a, {
  { lnum = 0, col = 0, message = "warning", severity = 2 },
  { lnum = 1, col = 0, message = "warning", severity = 2 },
  { lnum = 0, col = 0, message = "hint", severity = 4 },
  { lnum = 1, col = 0, message = "hint", severity = 4 },
  { lnum = 2, col = 0, message = "hint", severity = 4 },
})
settle()
assert(text():find("2 󰌶3", 1, true), text())
line.setup({
  globalstatus = true,
  sections = { b = { { "diagnostics", symbols = { warn = "▲", hint = "◆" } } } },
})
assert(text():find("▲2 ◆3", 1, true), text())
vim.diagnostic.reset(ns, a)
vim.diagnostic.config({ signs = native_signs })
line.setup({ globalstatus = true })

-- Plain separators and icon opt-outs keep font-free/custom layouts available.
line.setup({
  globalstatus = true,
  icons = false,
  component_separator = "|",
  section_separator = ">",
  sections = { a = { { "mode", icon = "N%" } }, c = { { "filename", icon = false } } },
})
value = text()
assert(value:find("N% NORMAL", 1, true), value)
assert(not value:find("", 1, true) and not value:find("", 1, true), value)
assert(value:find(">", 1, true) and value:find("|", 1, true), value)
line.setup({ globalstatus = true })

-- Each window uses its own buffer metadata, cursor and active/inactive sections.
vim.cmd("vsplit")
local left, right = api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#"))
local b = t.buffer({ "different" })
api.nvim_buf_set_name(b, directory .. "/ui-tools-statusline/other.txt")
-- A buffer can restore its saved native window-local option before the deferred
-- BufWinEnter update. It must not permanently surrender the bar to that value.
api.nvim_set_option_value("statusline", "", { win = left, scope = "local" })
settle()
assert(vim.wo[left].statusline:find("ui_tools.statusline", 1, true))
assert(text(left):find("other.txt", 1, true), text(left))
assert(text(right):find("中文%{evil}.lua", 1, true), text(right))
assert(not text(right):find("NORMAL", 1, true), text(right))
-- Separate inactive sections still need a same-surface separator. Its palette
-- must also survive theme refreshes without doing highlight work in render().
local function inactive_edge()
  local edge = api.nvim_get_hl(0, { name = "UiToolsStatusEdgeInactiveToInactive", link = false })
  local base = api.nvim_get_hl(0, { name = "UiToolsStatusInactive", link = false })
  t.eq(base.bg, edge.fg)
  t.eq(base.bg, edge.bg)
end
inactive_edge()
api.nvim_exec_autocmds("ColorScheme", {})
inactive_edge()
-- Relative filenames follow each split's local directory, including when both
-- splits display the same buffer. User callbacks also see that split's vim.b.
api.nvim_win_set_buf(left, a)
api.nvim_win_call(left, function()
  vim.cmd("lcd " .. vim.fn.fnameescape(directory))
end)
api.nvim_win_call(right, function()
  vim.cmd("lcd " .. vim.fn.fnameescape(directory))
end)
line.refresh()
assert(text(left):find("ui-tools-statusline/中文%{evil}.lua", 1, true), text(left))
assert(not text(left):find(directory .. "/", 1, true), text(left))
api.nvim_win_call(right, function()
  vim.cmd("lcd /")
end)
line.refresh()
assert(text(right):find(filename:sub(2), 1, true), text(right))
assert(not text(left):find(directory .. "/", 1, true), text(left))
line.setup({
  sections = {
    c = {
      function(ctx)
        return tostring(vim.api.nvim_get_current_buf() == ctx.buf)
      end,
    },
  },
})
assert(text(left):find("true", 1, true))
api.nvim_win_set_buf(left, b)
api.nvim_win_call(left, function()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
end)
api.nvim_win_call(right, function()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
end)
line.refresh()
ui.disable()
t.eq(before.statusline, api.nvim_get_option_value("statusline", { scope = "local", win = left }))
t.eq(before.statusline, api.nvim_get_option_value("statusline", { scope = "local", win = right }))
t.eq(before.laststatus, vim.o.laststatus)

-- Respect existing global/local providers, including later owners after force.
vim.go.statusline = "external global"
line.setup()
t.eq("external global", vim.wo.statusline)
t.eq(before.laststatus, vim.o.laststatus)
line.disable()
vim.go.statusline = before.global
vim.wo[left].statusline = "external local"
line.setup()
t.eq("external local", vim.wo[left].statusline)
assert(vim.wo[right].statusline:find("ui_tools.statusline", 1, true))
line.disable()
t.eq("external local", vim.wo[left].statusline)
line.setup({ force = true })
vim.wo[left].statusline = "later owner"
api.nvim_exec_autocmds("WinEnter", {})
settle()
t.eq("later owner", vim.wo[left].statusline)
vim.o.laststatus = 1
line.disable()
t.eq("later owner", vim.wo[left].statusline)
t.eq(1, vim.o.laststatus)
vim.wo[left].statusline = ""
vim.o.laststatus = before.laststatus
vim.cmd("only")

-- Custom component output is escaped/cached, callbacks fail independently, and
-- an empty section actually removes its defaults.
local calls = 0
line.setup({
  sections = {
    a = {},
    b = {},
    c = {
      {
        function(ctx)
          calls = calls + 1
          assert(ctx.buf == b)
          return "custom%#Error#"
        end,
        color = "Special",
        priority = 100,
      },
      function()
        error("broken component")
      end,
      {
        "filename",
        cond = function()
          return false
        end,
      },
    },
    x = {},
    y = {},
    z = { {
      "location",
      fmt = function(v)
        return "pos " .. v
      end,
    } },
  },
})
assert(text():find("custom%#Error#", 1, true), text())
assert(not text():find("NORMAL", 1, true))
assert(not text():find("other.txt", 1, true))
assert(next(line.errors))
local previous_calls = calls
for _ = 1, 100 do
  text()
end
t.eq(previous_calls, calls)
for _ = 1, 30 do
  api.nvim_exec_autocmds("CursorMoved", {})
end
settle()
t.eq(previous_calls + 1, calls)
line.update()
settle()
t.eq(previous_calls + 2, calls)
assert(text():find("pos 1:1", 1, true))
line.disable()

-- Exclusions, inherited splits, repeated setup and pending callbacks restore cleanly.
ui.setup({ statusline = true })
vim.cmd("vsplit")
settle()
ui.setup({ statusline = { exclude = { "excluded" } } })
vim.bo.filetype = "excluded"
settle()
assert(not vim.wo.statusline:find("ui_tools.statusline", 1, true))
vim.bo.filetype = "text"
settle()
assert(vim.wo.statusline:find("ui_tools.statusline", 1, true))
api.nvim_exec_autocmds("DiagnosticChanged", { buffer = b })
ui.setup({ statusline = { sections = { a = {} } } })
settle()
assert(not text():find("NORMAL", 1, true))
ui.toggle("statusline")
assert(not line.enabled)
ui.toggle("statusline")
assert(line.enabled)
ui.disable()
t.eq(before.global, vim.go.statusline)
t.eq(before.laststatus, vim.o.laststatus)
for _, win in ipairs(api.nvim_list_wins()) do
  t.eq("", api.nvim_get_option_value("statusline", { scope = "local", win = win }))
end

-- A window ID alone is resolved in the current tab by getcwd(). Updates cover
-- hidden tabs too, and must preserve each window's local/tab-local directory.
vim.cmd("only")
local source_win = api.nvim_get_current_win()
local seen = {}
line.setup({
  sections = { c = {
    "cwd",
    function(ctx)
      seen[ctx.win] = ctx.cwd
      return ""
    end,
  } },
  inactive_sections = { c = { "cwd" } },
})
vim.cmd("tabnew")
vim.cmd("tcd /tmp")
local tab_win = api.nvim_get_current_win()
local tab_cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
vim.cmd("tabnew")
vim.cmd("lcd /")
local local_win = api.nvim_get_current_win()
local function check_directories()
  local current = api.nvim_get_current_win()
  line.refresh()
  settle()
  t.eq(current, api.nvim_get_current_win())
  t.eq(vim.fn.fnamemodify(root, ":~"), seen[source_win])
  t.eq("/", seen[local_win])
  assert(text(source_win):find(seen[source_win], 1, true), text(source_win))
  t.eq("", vim.v.errmsg)
end
check_directories()
t.eq(tab_cwd, seen[tab_win])
vim.cmd("tabmove 0")
check_directories()
api.nvim_set_current_win(source_win)
check_directories()
api.nvim_win_close(tab_win, true)
check_directories()
vim.cmd("tabonly!")
settle()
line.disable()
print("statusline providers, caches, window context, ownership, callbacks and lifecycle passed")
