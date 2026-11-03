# ui-tools.nvim

Independent visual helpers for Neovim 0.11+. No runtime dependencies. Each module
is explicitly enabled; requiring the plugin does not install UI or mappings.

```lua
require("ui_tools").setup({
  dashboard = true,
  indent = { only_scope = true, chunk = true },
  statuscolumn = true,
  guide = { columns = { 121 } },
  feedback = { yank = true },
  focus = { width = 100, height = 0.9, dim = true },
  scrollbar = true,
  context_menu = true,
})
```

With lazy.nvim use `main = "ui_tools"` and the same table as `opts`.
See [examples/lazy.lua](examples/lazy.lua) for a local checkout spec with Zen,
Zoom, scope dimming, current-line pulse and optional GitTools markers.
Disable competing renderers (for example Snacks indent) when enabling a module.
No colorscheme or icon font is required. Override `UiTools*` highlight groups
through your colorscheme; plugin defaults use standard highlight links.

## Dashboard

`dashboard = true` opens a centered start screen when Neovim starts with an empty
buffer and an attached UI. File arguments, piped input, modified buffers, named
buffers, special buffers and existing splits suppress automatic opening. Disable
your previous dashboard before enabling this module.

```lua
require("ui_tools").setup({
  dashboard = {
    autostart = true,
    width = 60, -- expands for the header, bounded by the window
    layout = "vertical", -- "vertical": art above actions; "horizontal": art beside actions
    gap = 2, -- preferred spacing, reduced automatically when needed
    header = "N E O V I M", -- multiline text is supported
    keys = {
      { key = "f", desc = "Find File", action = function()
        require("selection_tools").files()
      end },
      { key = "n", desc = "New File", action = "enew | startinsert" },
      { key = "q", desc = "Quit", action = "qa" },
    },
    footer = function() return "Welcome" end, -- string, function or false
  },
})
require("ui_tools").dashboard() -- manually open; also works without setup
require("ui_tools.dashboard").close()
```

Actions are Ex commands or callbacks. Each item accepts an optional `icon` and
`enabled` boolean/callback. Picker and session integrations belong in these
callbacks; the dashboard has no runtime dependencies. Defaults provide New File,
Quit and a Neovim version footer. Item keys are buffer-local. Use `j`/`k`, arrows
or Tab/Shift-Tab to select, Enter to execute, and Escape to return to the source
buffer. Reserve these navigation keys for navigation when defining item keys.

Both layouts fit automatically on resize: blank borders around the art are
trimmed, spacing contracts, and the art scales down proportionally by character
sampling to fit the remaining display cells. Wide characters stay intact.
The menu keeps its shortcut labels; long descriptions and the footer are
truncated to fit. In extremely short windows, actions take priority over the
footer and art, and the menu scrolls. It refreshes on `VeryLazy`/`LazyVimStarted`, so
the footer can display lazy.nvim startup statistics. Window options are restored
when leaving or disabling the dashboard, preserving later option changes. Source
buffers retain unsaved text. No global display options or mappings are changed.
The dashboard disables cursorline while open. Colors use
`UiToolsDashboardHeader`, `UiToolsDashboardDesc` (Function),
`UiToolsDashboardIcon` (DiagnosticHint), `UiToolsDashboardKey` and
`UiToolsDashboardFooter`. Override these highlight groups in your colorscheme.

## Indentation and current block

`indent = true` draws indentation guides and highlights the block around the
cursor. Options: `char = "│"`, `only_scope = false`, `scope = true`,
`chunk = true`, `max_scan = 400`. The visual scope is determined by indentation,
including tabs and blank lines, with a bounded scan around the cursor. It is
not a language syntax scope and registers no textobjects or navigation keys.
The closing line dedented to the parent's level lies outside the visual block.

Rendering is per window and limited to visible lines. Special buffers, floating
windows, diff windows and buffers over `max_lines = 100000` or
`max_bytes = 10485760` (10 MiB) are excluded. Plugin-owned focus windows are included.
Set `vim.b.ui_tools_disable = true` to opt a buffer out. Each decoration module
accepts an `exclude` filetype list. Horizontal scrolling is accounted for.

`require("ui_tools").toggle("indent")` toggles a module. `disable()` removes
plugin UI; repeated `setup()` replaces previous configuration. Only the opt-in
context menu installs mouse mappings. Renderer errors are available in
`require("ui_tools.render").errors`.

## Context menu

`context_menu = true` enables right-click menus in Normal, Visual and Insert mode.
Enable native mouse input with `vim.opt.mouse = "a"` if it is disabled. The menu
targets the clicked window and text position. Clicking inside an existing Visual
selection preserves its extent, including reversed, exclusive, linewise and
blockwise selections. Clicking elsewhere starts a context at that position.

Built-in actions include copy/cut/paste, undo/redo, literal selection search,
copy relative file path and copy `path:line`. Copy uses the system clipboard when
available and the unnamed register otherwise. Paste follows native Normal/Visual
semantics; in Insert mode it inserts before the clicked character and built-in
actions resume Insert mode. Read-only or
nonmodifiable buffers disable editing actions.

LSP definitions, references, hover and code actions appear only after an attached
client returns a nonempty result for the clicked position or selection. An empty
definition target, blank hover or list containing only disabled code actions
leaves its entry hidden. Opening the menu starts asynchronous probes; basic
actions remain usable, and arriving results preserve the selected item. Any
client's valid result makes the action available; another client's empty result
or error never hides it. Queries use each client's position encoding and, for
code actions, the original selection and that client's diagnostics.

Rename uses `prepareRename` when supported. Servers that offer rename without
this optional preflight retain their capability-based entry. Formatting is a
document/selection operation and also remains capability-based; the menu does
not compute formatting edits in advance. With a selection, only range operations
are offered. Line diagnostics appear when present. Pending probes are cancelled
on close or after one second; late or stale-buffer responses are ignored.
Choosing an entry invokes its action normally. The default actions use Neovim's
UI and have no plugin dependencies.

Navigate with arrows, `j`/`k`, Tab/Shift-Tab or the mouse wheel; Enter/Space or a
left click executes an item. Escape/`q`/Ctrl-C cancels and restores the original
selection or Insert mode. Clicking outside dismisses the menu and passes the
click through. The menu fits the screen and scrolls when necessary. Resizing,
leaving its window/tab and disabling the module close it. Changed source buffers
cannot execute stale actions.

```lua
require("ui_tools").setup({
  context_menu = {
    mouse = true, -- false leaves mappings alone; menu() still works
    builtin = true, -- basic editing, search and path actions
    lsp = true, -- native LSP provider; false omits the default provider
    border = "rounded",
    min_width = 24,
    max_width = 60,
    max_height = 16,
    exclude = { "lazy" }, -- filetypes; vim.b.ui_tools_disable also applies
  },
})
require("ui_tools").menu() -- keyboard entry at the current cursor, even without setup
```

The module owns global right-click mappings (including repeated clicks) while
enabled. Disable restores earlier mappings only if they are still owned by the
module. Buffer-local mappings take precedence and are never replaced. Existing
native `PopUp` menu definitions and global mouse/display options are untouched.

Register actions from configuration or other plugins:

```lua
local menu = require("ui_tools.context_menu")
local remove = menu.register("project", function(ctx, sink)
  -- ctx: win, buf, cursor={one-based line, zero-based byte column}, mode, tick
  -- ctx.selection: type, anchor/cursor (getpos format), text (lines), regions
  if vim.bo[ctx.buf].filetype ~= "lua" then
    return {}
  end
  return {
    {
      id = "check",
      label = "Check this file",
      group = "project", -- adjacent different groups get a separator
      shortcut = "<leader>tc", -- optional; display only an actually configured key
      action = function(context)
        -- Source window/buffer/cursor and Visual selection are restored here.
        vim.notify(vim.api.nvim_buf_get_name(context.buf))
      end,
    },
  }
end, { priority = 100 }) -- ascending priority, then registration order
remove() -- idempotent; removes only this registration
```

Providers return an item list or asynchronously call `sink.update(items)` to
replace their own list. Give items stable IDs: updates preserve the selected ID
when it is still enabled. A loading row can omit `action` and set `enabled=false`.
Use `sink.on_close(function() ... end)` to cancel requests or release resources.
Late callbacks from a closed/replaced menu or removed provider are ignored.
Treat the context as a read-only snapshot. Registrations survive disable/setup;
new/replaced providers are collected on the next opening. Unregistering immediately
retires visible actions. Provider/callback errors are available in `menu.errors`.
`menu.open()` returns a handle with `close()` and `is_active()`; `menu.close()`
dismisses the current menu. `menu.state()` exposes the active context and items
for inspection.

To use another LSP UI, register the optional adapter from configuration. It
replaces the default LSP provider without loading the target plugin on menu open:

```lua
local detach = require("ui_tools.integrations.context_lsp").setup({
  timeout_ms = 1000, -- availability probe deadline; also cancels outstanding requests
  actions = {
    definition = function() require("lsp-tools").lsp_definitions() end,
    references = function() require("lsp-tools").lsp_references() end,
    hover = function() require("lsp-tools").hover() end,
    rename = function() require("lsp-tools").rename() end,
    code_action = function() require("lsp-tools").code_action() end,
    diagnostic = function() require("lsp-tools").diagnostic() end,
    -- Unspecified actions use vim.lsp.buf; callbacks receive ctx.
  },
  shortcuts = { definition = "gd" }, -- supply your actual mappings
})
-- detach() removes the adapter; native LSP actions return on the next opening.
```

## Status column

`statuscolumn = true` uses this compact layout:

```lua
layout = { { "diagnostic", "sign", "mark" }, "number", { "fold", "git" } }
```

Each nested group shares one slot: the first available item wins. Diagnostic
signs take precedence over other signs and marks; folds share the right slot
with Git. Symbol slots occupy one cell and expand for wider glyphs, then shrink
when those glyphs disappear. Flat entries remain supported for separate slots.
Set `slot_width = 2` to reserve two display cells for each symbol slot, including
the shared diagnostic/mark and fold/Git slots; line number width stays native.
Set `separator = " "` for one cell of breathing room before the code, or use
`"│"` for a divider. It uses `UiToolsStatusSeparator` and is not a fold button.
Line numbers use `UiToolsLineNr` and `UiToolsCursorLineNr`.
To give diagnostics and other symbols separate columns, use:

```lua
slot_width = 1,
layout = { "diagnostic", { "sign", "mark" }, "number", "fold" },
```

The first column shows the highest-priority diagnostic. The second shows the
highest-priority other sign, falling back to a letter mark. When the layout
includes `"diagnostic"`, `"sign"` excludes diagnostics so they cannot appear
twice or hide another sign. Without `"diagnostic"`, `"sign"` includes diagnostics
for compatibility. Each slot can expand for glyphs wider than one display cell.
Number/line highlight-only extmarks never mask a visible sign.
Reorder or omit entries to change the layout. It respects native `number` and
`relativenumber`, suppresses duplicate labels on wrapped/virtual lines, selects
the highest-priority sign of each kind, and shows buffer-local letter marks.
Fold icons (`folds.open = "▾"`, `folds.closed = "▸"`) respond to left clicks.
Enable `folds = { levels = true, columns = 2 }` for a fixed-width folding area.
`folds.columns` defaults to **2** and accepts integers from 1 to 9. With N columns,
the first N−1 show their corresponding outer levels; the last column combines
level N and every deeper fold. With one column, all levels share that column.
This width is independent of `slot_width`, and deeper folds never widen it.
Continuation lines use `folds.sep = "│"`. Click a column to operate on its fold;
the merged last column operates on the innermost visible fold at that line.
They use `UiToolsFoldSeparator`; enable `folds.scope = true` to highlight the
continuation of the cursor's innermost fold with `UiToolsFoldScope`. Arrows retain
`FoldColumn`. Scope highlighting is independent in each split.
Adjacent folds and folds sharing a start line retain their actual nesting.
Layered rendering uses LuaJIT's FFI to read Neovim's fold information (validated
on 0.11.5 and 0.12.6). The window-local native fold-column setting is restored on
disable unless another owner changed it.
Native `signcolumn`, `numberwidth` and `foldcolumn` control available gutter width;
use `signcolumn = "yes:1"`, `foldcolumn = "0"` for compact gutters. Explicitly
wider native column settings can still reserve additional space.

Git signs are classified by namespace/sign/highlight name using literal `git_patterns =
{ "GitTools", "gitsigns" }`. This module never requests or computes Git data.
Enable `git_numbers = true` to color line numbers using Git extmarks, including
number-highlight-only marks. The provider's number highlight takes precedence
over its sign highlight; the current line also stays bold. Use foreground-only
provider highlights for a transparent gutter. Remove `"git"` from the layout to
display changes solely through numbers:

```lua
statuscolumn = {
  slot_width = 2,
  separator = " ",
  git_numbers = true,
  folds = { levels = true, columns = 2, scope = true },
  layout = { { "diagnostic", "sign", "mark" }, "number", "fold" },
}
```

Sign snapshots refresh on diagnostics, edits, window events and `GitToolsUpdate`,
coalesced with `refresh = 30` milliseconds. Call
`require("ui_tools.statuscolumn").refresh()` after other sign/mark updates.

Existing nonempty status columns are preserved unless `force = true`. Disable
restores each window's previous value only while the plugin still owns it.
Windows that inherit this plugin's format through splits or buffer switching
are adopted automatically so their diagnostic/sign cache stays active.

## Column guides and transient feedback

`guide = { columns = { 81, 121 }, char = "│" }` draws guides only in empty
space beyond text. Columns are one-based display cells, accounting for tabs,
wide characters, horizontal scroll and folded text. Source text is never hidden.

`feedback = { yank = true, timeout = 200 }` optionally highlights yanked text.
The API works without enabling automatic yank feedback:

```lua
local ui = require("ui_tools")
ui.pulse() -- current line for 200 ms; map this to your own key
local flash = ui.flash({ buf = 0, line = 3, count = 2, timeout = 400 })
-- Zero-based rows and byte columns, with an exclusive end (Neovim convention):
ui.flash({ range = { 0, 0, 0, 6 }, hl = "Search" })
flash:cancel() -- idempotent; does not affect overlapping flashes
```

`timeout = 0` lasts until cancellation, buffer unload or plugin disable. A handle
also has `is_active()`. Text is never changed; each flash tracks edits through
extmarks. Line flashes affect all windows displaying the target buffer.

## Zen, Zoom and dimming

`ui.zen()` toggles a centered editing window; `ui.zoom()` toggles a full-width
editing window. Switching between modes is supported. Both APIs work without
setup, or use `focus = { width = 100, height = 0.9, backdrop = 60, dim = true }`.
Widths/heights from 0 to 1 are proportions; larger values are cell counts.
Per-call overrides such as `ui.zen({ width = 80 })` are also accepted.

The focused window edits the same buffer. Original splits, window sizes, local
options and folds stay in place beneath it. Focus has its own fold state. On
exit, the focused buffer and view return to the source window if its buffer is
unchanged. A modified buffer is never discarded to force this transfer. If
Neovim refuses it, save the source buffer or enable `hidden`, then exit again.
Manual window close, tab leave, resize and plugin disable clean up focus UI.
The backdrop is a non-interactive float; no global display options are changed.

Zen hides its line/sign/fold columns; Zoom retains those settings. Guides remain
available in both modes. `ui.dim()` toggles dimming outside the indentation
scope in the current window; `ui.dim(false)` disables it. Zen uses dimming by
default. Customize `UiToolsDim` and `UiToolsBackdrop` through highlight groups.
`require("ui_tools.focus").close()` exits either mode; `state()` reports mode,
focused window and source window. No keys are installed.

## Scrollbar and marker providers

`scrollbar = true` shows a one-cell bar at the right edge of each editing window.
It overlays the rightmost text cell, never changes buffer content, and is hidden
when all lines are visible or the window is narrower than `min_width = 20`.
The bar is not focusable or clickable. Set `hide_if_all_visible = false` to keep
it visible. Options: `handle = "┃"`, `mark = "•"`, `blend = 30`, `refresh = 30`.
Positions are projected by buffer line number, including when text wraps or folds.

The cursor is shown as `●` on each window's bar and follows movement in Normal
and Insert mode. It takes precedence when sharing a cell with another marker.
Set `cursor = false` to hide it or change `cursor_char` to another single-cell
symbol. Its foreground uses `UiToolsScrollbarCursor`; the handle background is
preserved underneath it.

For an opaque black handle on a transparent track, set `handle = " "`,
`blend = 100`, and define these highlights in your colorscheme callback:

```lua
vim.api.nvim_set_hl(0, "UiToolsScrollbar", { bg = "NONE", blend = 100 })
vim.api.nvim_set_hl(0, "UiToolsScrollbarHandle", { bg = "#000000", blend = 0 })
```

Foreground-only marker groups retain the handle/track background underneath them.

Diagnostics and search markers are enabled by default (`diagnostics = true`,
`search = true`). The highest-priority marker wins a cell: diagnostics over
search, with error diagnostics above warnings. Built-in search uses the last
search register and respects `hlsearch`, case and magic settings. It matches
within individual lines, scanning at most `search_limit = 20000` lines, 2 MiB
and `search_timeout = 10` ms between lines; lines above 4096 bytes are skipped.
At most 1000 matching lines are retained and cached until text/pattern changes.
Multiline searches require an external provider.

```lua
local scrollbar = require("ui_tools.scrollbar")
local remove = scrollbar.register("bookmarks", function(ctx)
  -- ctx: buf, win, count, top, bottom, cursor (one-based line), width, height
  return { { line = 30, end_line = 35, char = "!", hl = "Special", priority = 80 } }
end)
scrollbar.refresh() -- call after external data changes
remove() -- unregister only this registration

-- Optional GitTools integration: reads existing hunks, never loads GitTools.
local detach_git = require("ui_tools.integrations.git_tools").setup()
```

Provider line numbers and `end_line` are one-based and inclusive. Markers must
use a single display cell. Provider errors are isolated in `scrollbar.errors`.
Registrations survive disable/setup; built-in providers can be replaced by name.
No polling timer runs: window, edit, diagnostic, command-line and GitTools events
schedule coalesced refreshes. Hidden tabs and closed windows release their bars.
Focus mode displays only the focused window's bar.

## Development

Run `sh tests/run.sh` (Neovim, Python 3 and StyLua required). Tests include an
attached Neovim UI and inspect its actual redraw grid.
Use `NVIM_BIN=/path/to/nvim sh tests/run.sh` to test another Neovim release.
The full behavior and UI suites have been run locally on Neovim 0.11.5 and 0.12.6.
