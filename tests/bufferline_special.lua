local t = dofile("tests/helpers.lua")
local api = vim.api
local line = require("ui_tools.bufferline")
vim.o.hidden = true
local path = vim.fn.tempname() .. ".txt"
vim.fn.writefile({ "saved file" }, path)
vim.cmd.edit(path)
local file = api.nvim_get_current_buf()
line.setup({ auto_hide = -1, exclude = { "excluded" } })

local function contains(buf)
  for _, item in ipairs(line.items()) do
    if item.buf == buf then
      return true
    end
  end
  return false
end

-- Listed buffers participate regardless of storage type, including reports,
-- plugin-managed writes, prompts and terminals. Private UI buffers stay hidden.
local special = {}
for _, kind in ipairs({ "nofile", "nowrite", "acwrite", "prompt", "terminal" }) do
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "ui-tools-special://" .. kind)
  if kind == "terminal" then
    api.nvim_open_term(buf, {})
  else
    vim.bo[buf].buftype = kind
  end
  special[#special + 1] = buf
end
local private = api.nvim_create_buf(false, true)
local excluded = api.nvim_create_buf(true, true)
vim.bo[excluded].filetype = "excluded"
local disabled = api.nvim_create_buf(true, true)
vim.b[disabled].ui_tools_disable = true
line.refresh()
assert(not contains(private) and not contains(excluded) and not contains(disabled))
for _, buf in ipairs(special) do
  assert(contains(buf), vim.bo[buf].buftype .. " missing from buffer bar")
  local index = vim.fn.index(
    vim.tbl_map(function(item)
      return item.buf
    end, line.items()),
    buf
  ) + 1
  assert(line.go(index))
  t.eq(buf, api.nvim_get_current_buf())
  t.eq("", vim.v.errmsg)
end
api.nvim_set_current_buf(file)

-- Native reports and help/quickfix buffers use the same listing policy.
vim.cmd("checkhealth vim.lsp")
local health = api.nvim_get_current_buf()
vim.wait(60)
assert(contains(health))
t.eq("nofile", vim.bo[health].buftype)
t.eq("checkhealth", vim.bo[health].filetype)
vim.cmd("help help")
local help = api.nvim_get_current_buf()
line.refresh()
t.eq(vim.bo[help].buflisted, contains(help))
vim.fn.setqflist({ { filename = path, lnum = 1, text = "test result" } })
vim.cmd("copen")
local quickfix = api.nvim_get_current_buf()
line.refresh()
t.eq(vim.bo[quickfix].buflisted, contains(quickfix))

-- Toggling listing eligibility removes/re-adds a special buffer on refresh.
vim.bo[health].buflisted = false
line.refresh()
assert(not contains(health))
vim.bo[health].buflisted = true
line.refresh()
assert(contains(health))

-- Only ordinary file buffers enter restore history. Closing a special buffer
-- must leave the previous file available to :BufferRestore.
api.nvim_set_current_buf(file)
assert(line.close(file))
for _, buf in ipairs(special) do
  assert(line.close(buf, true))
end
assert(line.close(health))
assert(line.restore())
t.eq(vim.uv.fs_realpath(path), api.nvim_buf_get_name(0))
t.eq({ "saved file" }, api.nvim_buf_get_lines(0, 0, -1, false))
assert(not line.restore(), "Special buffers must not enter file restore history")
t.eq("", vim.v.errmsg)
line.disable()
vim.fn.delete(path)
print("bufferline listed special buffers, native reports, navigation and file-only restore passed")
