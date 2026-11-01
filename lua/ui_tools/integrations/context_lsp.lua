-- Optional LSP action provider. Callbacks can route to a user's preferred UI.
local M = {}

local methods = {
  { "definition", "Go to definition", "textDocument/definition" },
  { "references", "Find references", "textDocument/references" },
  { "hover", "Hover documentation", "textDocument/hover" },
  { "rename", "Rename symbol", "textDocument/rename" },
  { "code_action", "Code actions", "textDocument/codeAction" },
  { "format", "Format", "textDocument/formatting" },
}

function M.items(ctx, opts)
  opts = opts or {}
  local items = {}
  local clients = vim.lsp.get_clients({ bufnr = ctx.buf })
  for _, spec in ipairs(methods) do
    local id, label, method = unpack(spec)
    if id == "format" and ctx.selection then
      method, label = "textDocument/rangeFormatting", "Format selection"
    end
    local supported = false
    for _, client in ipairs(clients) do
      if client:supports_method(method, ctx.buf) then
        supported = true
        break
      end
    end
    local modifies = id == "rename" or id == "code_action" or id == "format"
    if supported and (not ctx.selection or id == "code_action" or id == "format") then
      items[#items + 1] = {
        id = id,
        label = label,
        group = "lsp",
        shortcut = opts.shortcuts and opts.shortcuts[id] or nil,
        enabled = not modifies or vim.bo[ctx.buf].modifiable and not vim.bo[ctx.buf].readonly,
        action = function()
          local callback = opts.actions and opts.actions[id]
          if callback then
            callback(ctx)
          else
            vim.lsp.buf[id]()
          end
        end,
      }
      -- No assumed shortcut is displayed: mappings may be customized or absent.
    end
  end
  if #vim.diagnostic.get(ctx.buf, { lnum = ctx.cursor[1] - 1 }) > 0 then
    items[#items + 1] = {
      id = "diagnostic",
      label = "Show diagnostics",
      group = "lsp",
      shortcut = opts.shortcuts and opts.shortcuts.diagnostic or nil,
      action = function()
        require("ui_tools.context_menu.context").suspend()
        if opts.actions and opts.actions.diagnostic then
          opts.actions.diagnostic(ctx)
        else
          vim.diagnostic.open_float({ scope = "line" })
        end
      end,
    }
  end
  return items
end

function M.setup(opts)
  return require("ui_tools.context_menu").register("lsp", function(ctx)
    return M.items(ctx, opts)
  end)
end

return M
