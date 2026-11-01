#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ui-tools-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" XDG_DATA_HOME="$test_root/data"
export NVIM_LOG_FILE="$test_root/nvim.log" PYTHONDONTWRITEBYTECODE=1
for suite in tests/indent.lua tests/statuscolumn.lua tests/feedback.lua; do
  nvim --headless -n -u NONE -i NONE --noplugin -l "$suite"
done
python3 tests/ui.py
stylua --check lua tests
