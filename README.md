# ui-tools.nvim

Independent visual helpers for Neovim 0.11+. No runtime dependencies. Each module
is explicitly enabled; requiring the plugin does not install UI or mappings.

```lua
require("ui_tools").setup({
  indent = { only_scope = true, chunk = true },
  statuscolumn = true,
  guide = { columns = { 121 } },
  feedback = { yank = true },
})
```

With lazy.nvim use `main = "ui_tools"` and the same table as `opts`.
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
windows, diff windows and buffers over `max_lines = 100000` are excluded.
Set `vim.b.ui_tools_disable = true` to opt a buffer out. Each decoration module
accepts an `exclude` filetype list. Horizontal scrolling is accounted for.

`require("ui_tools").toggle("indent")` toggles a module. `disable()` removes
plugin UI; repeated `setup()` replaces previous configuration. No user keys are
installed. Renderer errors are available in `require("ui_tools.render").errors`.

## Status column

`statuscolumn = true` displays `layout = { "mark", "sign", "number", "fold", "git" }`.
Reorder or omit entries to change the layout. It respects native `number` and
`relativenumber`, suppresses duplicate labels on wrapped/virtual lines, selects
the highest-priority sign per slot, and shows buffer-local letter marks.
Fold icons (`folds.open = "▾"`, `folds.closed = "▸"`) respond to left clicks.
Native `signcolumn`, `numberwidth` and `foldcolumn` control available gutter width;
use e.g. `signcolumn = "yes:2"`, `foldcolumn = "1"` for a wide layout.

Git signs are classified by namespace/sign name using literal `git_patterns =
{ "GitTools", "gitsigns" }`. This module never requests or computes Git data.
Sign snapshots refresh on diagnostics, edits, window events and `GitToolsUpdate`,
coalesced with `refresh = 30` milliseconds. Call
`require("ui_tools.statuscolumn").refresh()` after other sign/mark updates.

Existing nonempty status columns are preserved unless `force = true`. Disable
restores each window's previous value only while the plugin still owns it.

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

## Development

Run `sh tests/run.sh` (Neovim, Python 3 and StyLua required). Tests include an
attached Neovim UI and inspect its actual redraw grid.
