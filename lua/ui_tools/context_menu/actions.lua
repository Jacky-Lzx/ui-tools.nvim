local M = {}
local context = require("ui_tools.context_menu.context")

local function copy(text, regtype)
  vim.fn.setreg('"', text, regtype or "v")
  -- A clipboard provider is optional (for example over SSH).
  if vim.fn.has("clipboard") == 1 or vim.g.clipboard then
    vim.fn.setreg("+", text, regtype or "v")
  end
end

function M.items(ctx)
  local items = {}
  local writable = vim.bo[ctx.buf].modifiable and not vim.bo[ctx.buf].readonly
  local function add(id, label, action, group, enabled)
    items[#items + 1] = { id = id, label = label, action = action, group = group, enabled = enabled }
  end
  if ctx.selection then
    add("copy", "Copy", function()
      context.normal("y")
      copy(ctx.selection.text, vim.fn.getregtype('"'))
    end, "edit")
    add("cut", "Cut", function()
      context.normal("d")
      copy(ctx.selection.text, vim.fn.getregtype('"'))
    end, "edit", writable)
    add("search", "Search selection", function()
      context.suspend()
      local text = table.concat(ctx.selection.text, "\n")
      local pattern = "\\V" .. text:gsub("\\", "\\\\"):gsub("\n", "\\n")
      vim.fn.setreg("/", pattern)
      vim.o.hlsearch = true
      vim.v.hlsearch = 1
      vim.fn.search(pattern, "w")
    end, "search")
  else
    add("copy", "Copy line", function()
      context.normal("yy")
      copy(vim.fn.getreg('"', 1, true), "V")
    end, "edit")
  end
  add("paste", "Paste", function()
    local reg = (vim.fn.has("clipboard") == 1 or vim.g.clipboard) and "+" or '"'
    if ctx.mode:sub(1, 1) == "i" then
      -- Insert-mode paste inserts before the clicked character.
      vim.api.nvim_put(vim.fn.getreg(reg, 1, true), vim.fn.getregtype(reg), false, true)
    else
      context.normal('"' .. reg .. "p")
    end
  end, "edit", writable)
  if not ctx.selection then
    local tree = vim.fn.undotree()
    add("undo", "Undo", function()
      vim.cmd.undo()
    end, "edit", writable and tree.seq_cur > 0)
    add("redo", "Redo", function()
      vim.cmd.redo()
    end, "edit", writable and tree.seq_cur < tree.seq_last)
  end
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  if name ~= "" and vim.bo[ctx.buf].buftype == "" then
    local relative = vim.fn.fnamemodify(name, ":.")
    add("path", "Copy relative path", function()
      context.suspend()
      copy(relative)
    end, "file")
    add("location", "Copy path:line", function()
      context.suspend()
      copy(relative .. ":" .. ctx.cursor[1])
    end, "file")
  end
  return items
end

return M
