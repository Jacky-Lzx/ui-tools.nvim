#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ui-tools-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" XDG_DATA_HOME="$test_root/data"
export NVIM_LOG_FILE="$test_root/nvim.log" PYTHONDONTWRITEBYTECODE=1
export NVIM_BIN="${NVIM_BIN:-nvim}"
for suite in tests/animation.lua tests/colors.lua tests/todo.lua tests/indent.lua tests/fold.lua tests/statuscolumn.lua tests/feedback.lua tests/focus.lua tests/scrollbar.lua tests/context_menu.lua tests/context_lsp.lua tests/dashboard.lua tests/bufferline.lua tests/bufferline_special.lua tests/buffer_commands.lua tests/theme.lua tests/theme_overrides.lua; do
  "$NVIM_BIN" --headless -n -u NONE -i NONE --noplugin -l "$suite"
done
python3 tests/lua_ui.py tests/statusline.lua --width 240
python3 tests/lua_ui.py tests/winbar.lua --width 180
python3 tests/animation_ui.py
python3 tests/ui.py
python3 tests/colors_ui.py
python3 tests/todo_ui.py
python3 tests/annotations_pty.py
python3 tests/search_ui.py
python3 tests/statuscolumn_ui.py
python3 tests/statuscolumn_style_ui.py
python3 tests/statuscolumn_scroll_ui.py
if [ -d ../theme-tools.nvim ]; then
  python3 tests/theme_overrides_ui.py
fi
python3 tests/scrollbar_ui.py
python3 tests/scrollbar_cursor_ui.py
python3 tests/context_menu_ui.py
python3 tests/context_lsp_ui.py
python3 tests/dashboard_ui.py
python3 tests/dashboard_startup_ui.py
python3 tests/dashboard_bufferline_ui.py
python3 tests/bufferline_ui.py
python3 tests/statusline_ui.py
if [ -d ../theme-tools.nvim ]; then
  python3 tests/statusline_semantics_ui.py
fi
python3 tests/winbar_ui.py
python3 tests/special_bars_ui.py
python3 tests/fold_ui.py
stylua --check lua tests examples
