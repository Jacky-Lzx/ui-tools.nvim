# ui-tools.nvim

Independent visual helpers for Neovim 0.11+. No runtime dependencies. Each module
is explicitly enabled; requiring the plugin does not install UI or mappings.

```lua
require("ui_tools").setup({
  indent = { only_scope = true, chunk = true },
  statuscolumn = true,
  guide = { columns = { 121 } },
  feedback = { yank = true },
  focus = { width = 100, height = 0.9, dim = true },
  scrollbar = true,
})
```

With lazy.nvim use `main = "ui_tools"` and the same table as `opts`.
See [examples/lazy.lua](examples/lazy.lua) for a local checkout spec with Zen,
Zoom, scope dimming, current-line pulse and optional GitTools markers.
Disable competing renderers (for example Snacks indent) when enabling a module.
No colorscheme or icon font is required. Override `UiTools*` highlight groups
through your colorscheme; plugin defaults use standard highlight links.

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
plugin UI; repeated `setup()` replaces previous configuration. No user keys are
installed. Renderer errors are available in `require("ui_tools.render").errors`.

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
Adjacent folds and folds sharing a start line retain their actual nesting.
Layered rendering uses LuaJIT's FFI to read Neovim's fold information (validated
on 0.11.5 and 0.12.6). The window-local native fold-column setting is restored on
disable unless another owner changed it.
Native `signcolumn`, `numberwidth` and `foldcolumn` control available gutter width;
use `signcolumn = "yes:1"`, `foldcolumn = "0"` for compact gutters. Explicitly
wider native column settings can still reserve additional space.

Git signs are classified by namespace/sign/highlight name using literal `git_patterns =
{ "GitTools", "gitsigns" }`. This module never requests or computes Git data.
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
