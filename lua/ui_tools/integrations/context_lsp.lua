-- Optional LSP action provider. Callbacks can route to a user's preferred UI.
local M = {}
local api = vim.api
local context = require("ui_tools.context_menu.context")

local methods = {
  { "definition", "Go to definition", "textDocument/definition" },
  { "references", "Find references", "textDocument/references" },
  { "hover", "Hover documentation", "textDocument/hover" },
  { "rename", "Rename symbol", "textDocument/rename" },
  { "code_action", "Code actions", "textDocument/codeAction" },
  { "format", "Format", "textDocument/formatting" },
}

local function location(result)
  if type(result) ~= "table" then
    return false
  end
  if type(result.uri) == "string" or type(result.targetUri) == "string" then
    return true
  end
  for _, value in ipairs(result) do
    if location(value) then
      return true
    end
  end
  return false
end

local function content(value)
  if type(value) == "string" then
    return value:find("%S") ~= nil
  elseif type(value) == "table" then
    if content(value.value) then
      return true
    end
    for _, part in ipairs(value) do
      if content(part) then
        return true
      end
    end
  end
  return false
end

local function available(id, result)
  if id == "definition" or id == "references" then
    return location(result)
  elseif type(result) ~= "table" then
    return false
  elseif id == "hover" then
    return content(result.contents)
  elseif id == "rename" then
    return result.defaultBehavior == true
      or result.range ~= nil
      or result.start ~= nil and result["end"] ~= nil
  elseif id == "code_action" then
    for _, action in ipairs(result) do
      if type(action) == "table" and type(action.title) == "string" and not action.disabled then
        return true
      end
    end
  end
  return false
end

local function params(ctx, client, id)
  local encoding = client.offset_encoding or "utf-16"
  local function position(row, byte)
    local line = api.nvim_buf_get_lines(ctx.buf, row, row + 1, false)[1] or ""
    return {
      line = row,
      character = vim.lsp.util.character_offset(ctx.buf, row, math.min(byte, #line), encoding),
    }
  end
  local result = {
    textDocument = { uri = vim.uri_from_bufnr(ctx.buf) },
    position = position(ctx.cursor[1] - 1, ctx.cursor[2]),
  }
  if id == "references" then
    result.context = { includeDeclaration = true }
  elseif id == "code_action" then
    local range = { start = result.position, ["end"] = result.position }
    local first_row, first_col = ctx.cursor[1] - 1, ctx.cursor[2]
    local last_row, last_col = first_row, first_col
    if ctx.selection and #ctx.selection.regions > 0 then
      local regions = ctx.selection.regions
      local first, last = regions[1][1], regions[#regions][2]
      first_row, first_col = first[2] - 1, math.max(0, first[3] - 1)
      last_row, last_col = last[2] - 1, math.max(0, last[3] - 1)
      local line = api.nvim_buf_get_lines(ctx.buf, last_row, last_row + 1, false)[1]
      last_col = last_col + #vim.fn.strcharpart(line:sub(last_col + 1), 0, 1)
      range = { start = position(first_row, first_col), ["end"] = position(last_row, last_col) }
    end
    local diagnostics, namespaces = {}, {}
    namespaces[vim.lsp.diagnostic.get_namespace(client.id)] = true
    namespaces[vim.lsp.diagnostic.get_namespace(client.id, true)] = true
    if client._provider_foreach then
      client:_provider_foreach("textDocument/diagnostic", function(cap)
        namespaces[vim.lsp.diagnostic.get_namespace(client.id, true, cap.identifier)] = true
      end)
    end
    for namespace in pairs(namespaces) do
      for _, diagnostic in ipairs(vim.diagnostic.get(ctx.buf, { namespace = namespace })) do
        local after_start = (diagnostic.end_lnum or diagnostic.lnum) > first_row
          or (diagnostic.end_lnum or diagnostic.lnum) == first_row
            and (diagnostic.end_col or diagnostic.col) >= first_col
        local before_end = diagnostic.lnum < last_row
          or diagnostic.lnum == last_row and diagnostic.col <= last_col
        if after_start and before_end and diagnostic.user_data and diagnostic.user_data.lsp then
          diagnostics[#diagnostics + 1] = diagnostic.user_data.lsp
        end
      end
    end
    result.position = nil
    result.range = range
    result.context = { diagnostics = diagnostics, triggerKind = 1 }
  end
  return result
end

function M.items(ctx, opts, sink)
  opts = opts or {}
  local entries, queries = {}, {}
  local clients = vim.lsp.get_clients({ bufnr = ctx.buf })
  for _, spec in ipairs(methods) do
    local id, label, method = unpack(spec)
    if id == "format" and ctx.selection then
      method, label = "textDocument/rangeFormatting", "Format selection"
    end
    local entry = { visible = false }
    local modifies = id == "rename" or id == "code_action" or id == "format"
    entry.item = {
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
    if not ctx.selection or id == "code_action" or id == "format" then
      for _, client in ipairs(clients) do
        if client:supports_method(method, ctx.buf) then
          if
            id == "format"
            or id == "rename" and not client:supports_method("textDocument/prepareRename", ctx.buf)
          then
            -- Formatting is document/range-wide. Rename without prepare has no safe preflight.
            entry.visible = true
          else
            queries[#queries + 1] = {
              client = client,
              entry = entry,
              method = id == "rename" and "textDocument/prepareRename" or method,
            }
          end
        end
      end
    end
    entries[#entries + 1] = entry
  end
  if #vim.diagnostic.get(ctx.buf, { lnum = ctx.cursor[1] - 1 }) > 0 then
    entries[#entries + 1] = {
      visible = true,
      item = {
        id = "diagnostic",
        label = "Show diagnostics",
        group = "lsp",
        shortcut = opts.shortcuts and opts.shortcuts.diagnostic or nil,
        action = function()
          context.suspend()
          if opts.actions and opts.actions.diagnostic then
            opts.actions.diagnostic(ctx)
          else
            vim.diagnostic.open_float({ scope = "line" })
          end
        end,
      },
    }
  end
  local function items()
    local result = {}
    for _, entry in ipairs(entries) do
      if entry.visible then
        result[#result + 1] = entry.item
      end
    end
    return result
  end
  if sink and #queries > 0 then
    local stopped, timer, remaining = false, nil, #queries
    local function stop()
      if stopped then
        return
      end
      stopped = true
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      for _, query in ipairs(queries) do
        if not query.done then
          query.done = true
          if query.request_id then
            pcall(query.client.cancel_request, query.client, query.request_id)
          end
        end
      end
    end
    sink.on_close(stop)
    for _, query in ipairs(queries) do
      local ok, sent, request_id = pcall(function()
        return query.client:request(
          query.method,
          params(ctx, query.client, query.entry.item.id),
          function(err, result)
            vim.schedule(function()
              if stopped or query.done then
                return
              end
              query.done = true
              remaining = remaining - 1
              if not context.unchanged(ctx) then
                stop()
                return
              end
              if not err and available(query.entry.item.id, result) and not query.entry.visible then
                query.entry.visible = true
                sink.update(items())
              end
              if remaining == 0 then
                stop()
              end
            end)
          end,
          ctx.buf
        )
      end)
      if ok and sent then
        query.request_id = request_id
      else
        if not ok then
          require("ui_tools.context_menu").errors["lsp/" .. query.method] = tostring(sent)
        end
        query.done = true
        remaining = remaining - 1
      end
    end
    if remaining > 0 and not stopped then
      timer = vim.defer_fn(stop, opts.timeout_ms or 1000)
    end
  end
  return items()
end

function M.setup(opts)
  assert(
    not opts or opts.timeout_ms == nil or type(opts.timeout_ms) == "number" and opts.timeout_ms > 0,
    "timeout_ms must be a positive number"
  )
  return require("ui_tools.context_menu").register("lsp", function(ctx, sink)
    return M.items(ctx, opts, sink)
  end)
end

return M
