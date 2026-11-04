# ui-tools.nvim

Independent visual helpers for Neovim 0.11+. No runtime dependencies. Each module
is explicitly enabled; requiring the plugin does not install UI or mappings.

```lua
require("ui_tools").setup({
  dashboard = true,
  bufferline = true,
  statusline = true,
  winbar = true,
  fold = true,
  indent = { only_scope = true, chunk = true },
  statuscolumn = true,
  guide = { columns = { 121 } },
  feedback = { yank = true },
  focus = { width = 100, height = 0.9, dim = true },
  scrollbar = true,
  context_menu = true,
  colors = true,
  todo = true,
})
```

With lazy.nvim use `main = "ui_tools"` and the same table as `opts`.
See [examples/lazy.lua](examples/lazy.lua) for a local checkout spec with Zen,
Zoom, scope dimming, current-line pulse and optional GitTools markers.
Disable competing renderers (for example Snacks indent) when enabling a module.
No colorscheme or icon font is required. Override `UiTools*` highlight groups
through your colorscheme; plugin defaults use standard highlight links.

## Color previews

`colors = true` shows an inline `■` before each color literal, without changing
source text. Disable nvim-highlight-colors/colorizer before enabling this module.

```lua
require("ui_tools").setup({
  colors = {
    style = "inline", -- "inline", "eol", "foreground", "background"
    symbol = "■", -- one display cell; no icon font needed
    names = true, -- CSS names, case insensitive; false limits previews to literals/custom names
    custom = { brand = "#89b4fa", accent = "hsl(270 80% 65%)" },
    refresh = 30, -- milliseconds; edit bursts are coalesced without waiting for InsertLeave
    max_line_length = 4096, -- bytes; longer lines are skipped
    priority = 150,
    exclude = { "help", "checkhealth", "lazy", "NvimTree" },
    max_lines = 100000,
    max_bytes = 10 * 1024 * 1024,
  },
})
require("ui_tools").toggle("colors")
require("ui_tools.colors").refresh() -- after changing buffer-local exclusions/highlights manually
```

Supports `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `0xRRGGBB`, RGB/RGBA,
HSL/HSLA (commas or CSS space/slash notation), percentages, hue units, all CSS
named colors, and `transparent`. Eight-digit hex uses trailing alpha, including
`0x` values. Names are matched as whole tokens in all filetypes; set `names = false`
if ordinary words such as `red` are distracting. CSS variable references,
Tailwind classes, computed expressions and LSP document colors are not resolved.
Alpha is composited over `Normal` (black/white according to `background` when
the theme has a transparent background), and refreshes on theme changes.
Background style uses contrasting black/white text.

Only visible, unfolded rows across windows are scanned; hidden buffers lose
their marks. Decorations belong to the buffer and are shared by its windows.
Special buffers, diff windows, unrelated floats, large files and
`vim.b.ui_tools_disable = true` are excluded from scanning. No mappings are installed.

## TODO annotations

`todo = true` adds colored keyword badges, comment text and native signs. Disable
todo-comments.nvim's visual renderer before enabling it; project search/pickers
remain the responsibility of selection-tools or your other search integration.

```lua
require("ui_tools").setup({
  todo = {
    style = "badge", -- or "foreground"
    after = true, -- color the description up to the next tag/comment boundary
    signs = true,
    sign_priority = 8, -- diagnostics normally take precedence
    comments_only = true,
    prose = { "markdown", "text", "gitcommit" }, -- allow tags outside comments in these filetypes
    keywords = {
      -- Entries merge with defaults; false disables a category and its aliases.
      TODO = { icon = "✓", hl = "DiagnosticInfo", rank = 50 },
      SECURITY = { icon = "!", hl = "DiagnosticError", rank = 100, alt = { "SEC" } },
      -- NOTE = false,
    },
    refresh = 30,
    max_line_length = 4096,
    priority = 160,
    -- exclude, max_lines and max_bytes use the same defaults as colors.
  },
})
require("ui_tools").toggle("todo")
require("ui_tools.todo").refresh()
```

Default categories are FIX (FIXME, BUG, FIXIT, ISSUE), TODO, HACK, WARN (WARNING,
XXX), PERF (OPTIM, PERFORMANCE, OPTIMIZE), NOTE (INFO), and TEST (TESTING, PASSED,
FAILED). Tags are uppercase whole words followed by a colon; `TODO(owner):` is
also supported. All tags on a line get their own badge. The highest `rank` wins
the single sign on that line (FIX 90, WARN 80, HACK 70, TODO 50, PERF 40, TEST 30,
NOTE 20); equal ranks keep the first tag. Signs are single-cell text symbols and
work with both Neovim's native sign column and ui-tools' `sign` slot.

Code comments are identified by the active Tree-sitter highlighter, including
injected languages, or Vim syntax when no Tree-sitter highlighter is active.
Without either source of syntax information, code tags are left unmarked. Set
`comments_only = false` to recognize tags anywhere. Prose filetypes allow tags
throughout the document, including fenced code. This module does not start a
parser, enable syntax highlighting, install mappings, or search the project.

Foreground groups `UiToolsTodoFIX`, `UiToolsTodoTODO`, etc. link to the configured
`hl`. Badge groups `UiToolsTodoBadgeFIX`, etc. derive a background from that
highlight and choose contrasting text; both refresh with the theme. Set an
entry's `badge_hl` to your own highlight group to control the badge completely.
Viewport bounds, fold handling, buffer exclusions and cleanup match `colors`.

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
or Tab/Shift-Tab to select, Enter to execute, and Escape to quit Neovim (unsaved
buffers prevent quitting). Reserve these navigation keys for navigation when
defining item keys.

Both layouts fit automatically on resize: blank borders around the art are
trimmed, spacing contracts, and the art scales down proportionally by character
sampling to fit the remaining display cells. Wide characters stay intact.
The menu keeps its shortcut labels; long descriptions and the footer are
truncated to fit. In extremely short windows, actions take priority over the
footer and art, and the menu scrolls. It refreshes on `VeryLazy`/`LazyVimStarted`, so
the footer can display lazy.nvim startup statistics. Window options are restored
when leaving or disabling the dashboard, preserving later option changes. Source
buffers retain unsaved text. The dashboard temporarily hides the statusline
(`laststatus = 0`) and restores its previous setting on exit, unless a later owner
changed it. The command-area ruler is hidden/restored the same way. No global
mappings are changed.
When leaving the automatic startup dashboard, its original empty placeholder is
removed only if it remains unchanged and no window uses it. Closing the dashboard
back to that buffer keeps it; manually opened dashboards preserve their source.
The dashboard disables cursorline while open. Colors use
`UiToolsDashboardHeader`, `UiToolsDashboardDesc` (Function),
`UiToolsDashboardIcon` (DiagnosticHint), `UiToolsDashboardKey` and
`UiToolsDashboardFooter`. Override these highlight groups in your colorscheme.

## Buffer bar

`bufferline = true` replaces the native tabline with an ordered list of listed
buffers, across tabpages. This includes listed special buffers such as
`checkhealth` reports, terminals, and plugin-managed buffers. Unlisted buffers
(such as private picker and dashboard buffers), excluded filetypes, and buffers
with `vim.b.ui_tools_disable = true` remain hidden.
It has no dependency on barbar, devicons or an icon font. Disable your previous
tabline plugin before enabling it. Existing
nonempty `tabline` values are preserved unless `force = true`.

```lua
require("ui_tools").setup({
  bufferline = {
    auto_hide = 1, -- hide with <= 1 buffers; -1 always shows the bar
    numbers = false, -- display positions for go(index)
    close_buttons = true,
    diagnostics = false, -- optional cached E/W/I/H counts
    max_name_length = 28, -- display cells, not bytes
    sidebar_filetypes = { NvimTree = true }, -- offset left/right edge sidebars
    exclude = {}, -- filetypes; vim.b.ui_tools_disable also applies
    refresh = 30, -- coalesce event bursts, in milliseconds
    force = false,
  },
})
local buffers = require("ui_tools.bufferline")
vim.keymap.set("n", "[b", function() buffers.cycle(-1) end)
vim.keymap.set("n", "]b", function() buffers.cycle(1) end)
vim.keymap.set("n", "<A-w>", function() buffers.close() end)
-- Other API calls: buffers.go(3), move(-1), move(1), pin(), close(buf, force).
vim.keymap.set("n", "<A-u>", function() buffers.restore() end)
-- buffers.items() returns ordered { buf, name, pinned } records.
```

Left click switches buffers; middle click or the close button closes one. Enable
native mouse input with `vim.opt.mouse = "a"` to use these. No mappings are
installed automatically. Enabling the module registers these commands; existing
commands with the same name are preserved:

| Command | Action |
| --- | --- |
| `:BufferNext [count]`, `:BufferPrevious [count]` | Cycle through buffers (default: 1 step). |
| `:BufferFirst`, `:BufferLast`, `:BufferGoto {index}` | Jump to a position in the bar (indices start at 1). |
| `:BufferMoveNext [count]`, `:BufferMovePrevious [count]` | Move within the current pinned/unpinned group. |
| `:BufferPin` | Toggle the current buffer's pin. |
| `:BufferClose[!]` | Close the current buffer. |
| `:BufferRestore` | Restore the last closed named ordinary file buffer from disk. |
| `:BufferCloseAllButCurrent[!]` | Close all other buffers. |
| `:BufferCloseBuffersLeft[!]`, `:BufferCloseBuffersRight[!]` | Close buffers on that side of the current position. |
| `:BufferCloseAllButPinned[!]` | Close unpinned buffers. |
| `:BufferCloseAllButVisible[!]` | Close buffers not displayed in any window, across tabpages. |
| `:BufferCloseAll[!]` | Close every buffer in the bar. |

Batch commands snapshot their targets in bar order, skip protected buffers, and
report any failures while continuing to close other targets. `!` overrides pin
and unsaved-change protection for selected targets; it does not override
`winfixbuf`. Only buffers in the bar are batch targets, including listed special
buffers; unlisted, excluded, and disabled buffers are never targeted. The Lua API
`buffers.close_many(scope, force)` accepts `"all"`, `"others"`, `"left"`, `"right"`,
`"unpinned"`, or `"hidden"`, and returns `ok, reason`. Disabling the module removes
only its own commands.

Switching obeys native modified-buffer protection. `close()` returns
`false, reason` for modified or
pinned buffers; `close(buf, true)` explicitly overrides both protections. Closing
preserves splits, respects `winfixbuf`, and supplies an empty editing buffer when
the last buffer closes. Pinned buffers stay together at the start; movement is
limited to the buffer's pinned/unpinned group. Order and pins last until disable
or setup, and are not persisted to sessions.
`restore()` reopens the last successfully closed named ordinary file buffer from
disk, restores its position in the bar and cursor, and keeps up to 20 names in memory. It does
not recover discarded unsaved edits, unnamed buffers, or special buffers.
Closing a special buffer leaves the file restore history intact. Switching
protection still applies, and a failed restore leaves history intact.

Duplicate basenames use the shortest unique path suffix. Long names and narrow
windows truncate safely by display cell. Overflow indicators keep the current
buffer visible. Current, visible-in-split and other buffers use
`UiToolsBufferCurrent`, `UiToolsBufferVisible` and `UiToolsBuffer`; unused space
uses `UiToolsBufferFill`. Native tabpages still work through Neovim's tab commands;
the bar displays buffers rather than tabpage buttons.

Render returns a prebuilt string. Buffer-list/path scans run on structural events,
not on cursor motion or typing; labels are cached, and diagnostics update only on
diagnostic changes. There is no animation, repeating timer, filesystem scan or
process launch. `buffers.refresh()` explicitly rebuilds after custom changes.
Disable restores `tabline` and `showtabline` only while their values are still
owned by the module; later changes by another owner are preserved.

## Status bar

`statusline = true` installs a native statusline in normal windows, with mode
colors derived from your colorscheme. It works independently of the buffer bar
and does not require lualine, an icon plugin, Git tooling or an LSP client.
Disable your existing statusline plugin before enabling it.

```lua
require("ui_tools").setup({
  statusline = {
    globalstatus = false, -- true uses one global bar (laststatus=3)
    refresh = 30, -- milliseconds; event bursts share one update
    force = false, -- preserve existing custom statuslines by default
    exclude = { "ui_tools_dashboard" },
    component_separator = "", -- e.g. "│"
    section_separator = "",
    sections = {
      a = { "mode" },
      b = { "branch", "diff", "diagnostics" },
      c = { { "filename", path = "relative" } },
      x = { "recording", "lsp" },
      y = { "encoding", "fileformat", "filetype", "progress" },
      z = { "location" },
    },
    inactive_sections = { c = { "filename" }, z = { "location" } },
  },
})
```

Sections `a`, `b`, `c` align left; `x`, `y`, `z` align right. An explicitly supplied
section replaces that section's defaults; `{}` removes it. The example above
shows the defaults. `cwd` is also available. `filename.path` accepts `relative`,
`absolute` or `tail`. Filename components include modified/read-only indicators.
`location` uses one-based line and byte column. `progress` shows Top, Bot or a
percentage; `lsp` lists attached client names. The recording indicator shows the
active register. Components that have no data disappear.
`diagnostics` uses your native diagnostic sign symbols followed by each count,
falling back to E/W/I/H. Override them per component with
`{ "diagnostics", symbols = { error = "✖", warn = "▲", info = "●", hint = "◆" } }`.

`branch` and `diff` read `b:git_tools_status` or `b:gitsigns_status_dict` supplied
by an existing provider. They refresh on `User GitToolsUpdate`/`GitSignsUpdate`.
The bar never runs Git or starts a provider. Without a provider these components
are empty. `require("ui_tools.statusline").refresh()` explicitly refreshes all
displayed buffer data and custom components after other external changes.
Use `statusline.update()` to schedule only custom-component updates without
invalidating diagnostic, LSP or file snapshots.

Custom components return plain text, with statusline metacharacters escaped:

```lua
statusline = {
  sections = {
    x = {
      {
        function(ctx) return "project: " .. ctx.filetype end,
        color = "Special", -- highlight group name
        priority = 60, -- larger values stay visible longer when space runs out
        max_width = 24, -- display cells, optional
        cond = function(ctx) return ctx.active end,
        fmt = function(text, ctx) return text:upper() end,
      },
    },
  },
}
```

Callbacks receive `win`, `buf`, `active`, `mode`, `cursor`, `lines`, `width`,
`filetype` and `cwd`, and run in the target window's context. `cond`, `fmt`,
`color`, `priority` and `max_width` also work on built-in components. Keep callbacks
fast and free of side effects: they run during coalesced event updates, including
cursor/edit events when custom callbacks are present. They never run from the
render expression. An error hides only that component; inspect
`require("ui_tools.statusline").errors` for the latest update's failures.

Mode, recording, progress and location read bounded native state during redraw.
Other built-in data is cached per displayed buffer and updated by the relevant
events. Hidden buffers are not scanned. There is no idle polling, subprocess,
file read or diagnostic/LSP query in the render path. Narrow windows shorten the
filename and then omit lower-priority components. Text is truncated by display
cell without splitting UTF-8 or statusline syntax. Run the optional local
microbenchmark with
`nvim --headless -n -u NONE -i NONE --noplugin -l tests/bars_bench.lua`.

Colors use `UiToolsStatus`, `UiToolsStatusAlt`, `UiToolsStatusInactive`,
`UiToolsStatusDiff`, `UiToolsStatusError/Warn/Info/Hint` and
`UiToolsStatusNormal/Insert/Visual/Replace/Command/Terminal`. The final group names
are alternatives, e.g. `UiToolsStatusInsert`. Override them in your colorscheme.
Mode and location blocks use black text on their colorscheme-derived accent background.
Inactive splits use `UiToolsStatusInactive` throughout. Existing custom local or
global statuslines are preserved unless `force = true`. Disable restores local
statuslines and `laststatus` only while their values are still owned; later
owners' changes are preserved. Newly inherited splits return to the global
statusline. Window bars are managed separately by `winbar`.

## Window bars

`winbar = true` shows a filename and cached LSP client names above each normal
editing window, including inactive splits. Each window uses its own width and
cursor. Special buffers, floating windows and `vim.b.ui_tools_disable` buffers
are skipped. Enable optional breadcrumbs through a provider callback:

```lua
require("ui_tools").setup({
  winbar = {
    filename = true,
    filename_width = 0.45, -- maximum fraction of the window width
    lsp = true,
    refresh = 30, -- coalesce deferred lifecycle/LSP events
    force = false, -- preserve an existing winbar owner
    exclude = { "ui_tools_dashboard" }, -- filetypes
    breadcrumbs = function(ctx)
      local tools = package.loaded["lsp-tools"]
      return tools and tools.breadcrumbs({ winid = ctx.win }) or ""
    end,
  },
})
```

The optional callback receives `{ win, buf, width, cursor }` and returns native
statusline syntax. Escape untrusted text with `require("ui_tools.bar").escape()`;
the example's lsp-tools API already escapes symbol names. Callbacks should read
cached state and must not start requests or load providers during redraw.
Failures are isolated in `require("ui_tools.winbar").errors`, indexed by window.
The plugin itself never loads a breadcrumb provider.

Filenames and LSP client names are escaped. Long filenames truncate by display
cell, and native overflow truncates breadcrumbs before the filename. Client
snapshots update on attach/detach or explicit `winbar.refresh()`, never on cursor
motion or typing. `WinBar` and `WinBarNC` follow the optional theme-tools palette.
An inherited split adopts its own bar; custom owners, including later deliberate
clears, are respected. Disable restores only still-owned window-local options.
Visibility changes preserve editing cursors/views, and transient autocmd/float
windows defer updates until the editing context returns.

## Folding and previews

`fold = true` manages native folds in normal, non-diff editing windows. With a
Tree-sitter parser and folds query it uses `vim.treesitter.foldexpr()`; otherwise
it falls back to indent folding. Parsers and queries remain externally managed.

```lua
require("ui_tools").setup({
  fold = {
    method = "auto", -- or "indent"
    level = "open", -- initialize at the real maximum depth, or a numeric level
    text = true, -- retain syntax colors and append the hidden-line count
    suffix = "  … %d", -- use "  󰁂 %d" for the personal icon style
    fillchars = { fold = " ", foldopen = "▾", foldsep = "│", foldclose = "▸" },
    exclude = {}, -- filetypes; vim.b.ui_tools_disable also applies
    force = false, -- preserve an existing custom foldtext/foldexpr provider
    preview = { border = "rounded", max_width = 100, max_height = 20, max_lines = 200 },
  },
})
vim.keymap.set("n", "zK", function() require("ui_tools.fold").preview() end)
```

The module installs no mappings. Native `zM`, `zR`, `zm`, `zr`, `za`, `zo`, `zc`,
`zx` and `zX` continue to work. With `level = "open"`, the first `zm` immediately
closes a level; revisiting a window does not reset the user's fold state. New
splits initialize independently. The statuscolumn module continues to own the
gutter; this module does not change `foldcolumn` or global fold defaults.

Fold text uses display-cell widths for tabs and wide characters, keeps bounded
Tree-sitter/syntax highlights and counts hidden lines excluding the header.
Previewing a closed fold keeps editing focus; invoking it again focuses the
preview. Escape closes it. Cursor movement, entering Insert mode or hiding the
source closes the preview through Neovim's native floating-preview lifecycle.
Large previews are limited by `max_lines`, with truncation shown in the title.

Initialization preserves the cursor/view and Insert-mode byte column. Disable
cancels pending initialization, closes owned previews and restores still-owned
options in displayed windows. Later custom owners are respected. Use
`require("ui_tools").toggle("fold")` to toggle the module.

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
attached Neovim UI and inspect its actual redraw grid. Annotation tests also drive
a real terminal with a PTY and check RGB output and continuous insert-mode edits.
Use `NVIM_BIN=/path/to/nvim sh tests/run.sh` to test another Neovim release.
The statusline and winbar Lua suites require an attached UI; run them individually
with `python3 tests/lua_ui.py tests/statusline.lua --width 240` and
`python3 tests/lua_ui.py tests/winbar.lua --width 180`. The harness resizes through
the UI API and checks a normal Neovim exit, including cleanup after assertions.
Do not enlarge `columns` in headless tests that redraw the native tabline: on
Neovim 0.12.6 this can leave native screen/click-table allocations at the old size.
For an optional full-configuration annotation check, run
`UI_TOOLS_CONFIG=/path/to/nvim/init.lua python3 tests/annotations_pty.py`.
It enables the modules and disables the old color/TODO renderers only inside
the test process; it does not edit the configuration. Tree-sitter tests use an
available Lua parser; set `UI_TOOLS_PARSER_DIR` to its runtime directory if needed.

When theme-tools.nvim is active, UI highlights, statusline mode colors and buffer
colors follow its shared semantic palette. This integration is optional and does
not load theme-tools itself. It supports either setup order and detaches on
`disable()`. Without theme-tools, standard Neovim highlight defaults remain.
Use theme-tools palette overrides to customize shared colors.

## Shared icon display

When theme-tools.nvim is configured, icons follow its shared icon API and
`:ThemeToolsIcons` selection (mini.icons, nvim-web-devicons, ASCII, or hidden).
Open views refresh when the display changes. Provider installation and updates
belong to theme-tools; no extra icon dependency is needed for this integration.
Without theme-tools, existing standalone defaults remain available.
Local icon-disable options still apply. Configure shared overrides through
`require("theme_tools").setup({ icons = { overrides = { ... } } })`.
