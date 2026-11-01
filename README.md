# ui-tools.nvim

Independent visual helpers for Neovim 0.11+. No runtime dependencies. Each module
is explicitly enabled; requiring the plugin does not install UI or mappings.

```lua
require("ui_tools").setup({
  indent = { only_scope = true, chunk = true },
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

## Development

Run `sh tests/run.sh` (Neovim, Python 3 and StyLua required). Tests include an
attached Neovim UI and inspect its actual redraw grid.
