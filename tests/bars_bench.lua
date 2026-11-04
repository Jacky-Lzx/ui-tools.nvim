-- Optional reproducible microbenchmark; no absolute timing assertion.
-- nvim --headless -n -u NONE -i NONE --noplugin -l tests/bars_bench.lua
dofile("tests/helpers.lua")
local api = vim.api
local function now()
  return vim.uv.hrtime()
end
local buffers = {}
vim.bo.buflisted = false
for i = 1, 500 do
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "/tmp/ui-tools-bench/project-" .. i .. "/src/init.lua")
  buffers[i] = buf
end
api.nvim_set_current_buf(buffers[250])
local bufferline, statusline = require("ui_tools.bufferline"), require("ui_tools.statusline")
local start = now()
bufferline.setup({ auto_hide = -1 })
print(string.format("500 buffers: initial buffer bar build %.2f ms", (now() - start) / 1e6))
local samples = {}
for i = 1, 100 do
  start = now()
  bufferline.go(i)
  samples[i] = (now() - start) / 1e6
end
table.sort(samples)
print(string.format("500 buffers: switch p50 %.3f ms, p95 %.3f ms", samples[50], samples[95]))
start = now()
statusline.setup()
print(string.format("500 buffers: status bar setup %.2f ms", (now() - start) / 1e6))
for _, entry in ipairs({
  { "tabline", vim.o.tabline, { use_tabline = true, maxwidth = 120 } },
  { "statusline", vim.wo.statusline, { winid = 0, maxwidth = 120 } },
}) do
  start = now()
  for _ = 1, 1000 do
    api.nvim_eval_statusline(entry[2], entry[3])
  end
  print(string.format("Native %s evaluation: %.3f ms average", entry[1], (now() - start) / 1e9))
end
require("ui_tools").disable()
