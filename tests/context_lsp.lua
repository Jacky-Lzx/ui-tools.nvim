local h = dofile("tests/helpers.lua")
local menu = require("ui_tools.context_menu")
local adapter = require("ui_tools.integrations.context_lsp")
local api = vim.api
local buf = h.buffer({ "a😀中 foo", "second" })
api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/probe.lua")
api.nvim_win_set_cursor(0, { 1, 9 })
local original_clients, clients = vim.lsp.get_clients, {}
local original_client = vim.lsp.get_client_by_id
vim.lsp.get_clients = function(opts)
  if not opts or not opts.bufnr then
    return {}
  end
  h.eq(buf, opts.bufnr)
  return clients
end
vim.lsp.get_client_by_id = function(id)
  for _, value in ipairs(clients) do
    if value.id == id then
      return value
    end
  end
  return original_client(id)
end
menu.setup({ mouse = false })

local function client(id, encoding, supported)
  return {
    id = id,
    offset_encoding = encoding,
    server_capabilities = {},
    requests = {},
    cancelled = {},
    supports_method = function(_, method)
      return supported == nil or supported[method] == true
    end,
    request = function(self, method, params, callback, source)
      h.eq(buf, source)
      self.requests[#self.requests + 1] = { method = method, params = params, callback = callback }
      return true, #self.requests
    end,
    cancel_request = function(self, id)
      self.cancelled[#self.cancelled + 1] = id
    end,
  }
end
local function flush()
  vim.wait(20, function()
    return false
  end)
end
local function item(id)
  for _, entry in ipairs(menu.state().items) do
    if entry.id == id then
      return entry
    end
  end
end
local function request(c, method)
  for _, value in ipairs(c.requests) do
    if value.method == method then
      return value
    end
  end
  error("missing request " .. method)
end
local function reply(c, method, result, err)
  request(c, method).callback(err, result)
  flush()
end
local destination = {
  uri = "file:///destination.lua",
  range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
}

-- A capability alone must not expose positional operations, including null/error responses.
clients = { client(910, "utf-16") }
menu.open()
assert(item("format") and not item("definition") and not item("rename"))
reply(clients[1], "textDocument/definition", vim.NIL)
reply(clients[1], "textDocument/references", {}, { code = -32603, message = "failed" })
reply(clients[1], "textDocument/hover", { contents = { kind = "markdown", value = "  \n" } })
reply(clients[1], "textDocument/prepareRename", vim.NIL)
reply(clients[1], "textDocument/codeAction", { { title = "Unavailable", disabled = { reason = "no fix" } } })
for _, id in ipairs({ "definition", "references", "hover", "rename", "code_action" }) do
  assert(not item(id), id .. " should be hidden")
end
menu.close()

-- Any client may supply a result; another client's empty/error response cannot hide it.
clients = { client(911, "utf-16"), client(912, "utf-8") }
local diagnostic = {
  range = { start = { line = 0, character = 5 }, ["end"] = { line = 0, character = 8 } },
  message = "fix",
  data = { token = 7 },
}
vim.diagnostic.set(vim.lsp.diagnostic.get_namespace(911), buf, {
  { lnum = 0, col = 9, end_col = 12, message = "fix", user_data = { lsp = diagnostic } },
})
menu.open()
h.eq(5, request(clients[1], "textDocument/definition").params.position.character)
h.eq(9, request(clients[2], "textDocument/definition").params.position.character)
local code_params = request(clients[1], "textDocument/codeAction").params
h.eq({ line = 0, character = 5 }, code_params.range.start)
h.eq({ diagnostic }, code_params.context.diagnostics)
h.eq({}, request(clients[2], "textDocument/codeAction").params.context.diagnostics)
assert(request(clients[1], "textDocument/references").params.context.includeDeclaration)
reply(clients[1], "textDocument/definition", {})
assert(not item("definition"))
reply(
  clients[2],
  "textDocument/definition",
  { { targetUri = destination.uri, targetRange = destination.range } }
)
assert(item("definition"))
reply(clients[1], "textDocument/references", { destination })
reply(clients[2], "textDocument/references", {})
reply(clients[1], "textDocument/hover", { contents = { "", { language = "lua", value = "documentation" } } })
reply(clients[2], "textDocument/hover", nil, { code = -32603 })
reply(clients[1], "textDocument/prepareRename", { defaultBehavior = true })
reply(clients[2], "textDocument/prepareRename", vim.NIL)
reply(clients[1], "textDocument/codeAction", { { title = "Fix", command = "fix" } })
reply(clients[2], "textDocument/codeAction", {})
for _, id in ipairs({ "definition", "references", "hover", "rename", "code_action" }) do
  assert(item(id), id .. " should be visible")
end
h.eq("copy", menu.state().items[menu.state().selected].id)
menu.close()
vim.diagnostic.reset(vim.lsp.diagnostic.get_namespace(911), buf)

-- Close and timeout cancel pending requests; late replies cannot populate a new opening.
clients = { client(913, "utf-16") }
menu.open()
local old = clients[1]
menu.close()
h.eq(5, #old.cancelled)
clients = { client(914, "utf-16") }
local detach = adapter.setup({ timeout_ms = 5 })
menu.open()
old.requests[1].callback(nil, destination)
flush()
assert(not item("definition"))
h.eq(5, #clients[1].cancelled)
reply(clients[1], "textDocument/definition", destination)
assert(not item("definition"))
menu.close()
detach()

-- A server without prepareRename still offers rename; formatting is never pre-requested.
clients = { client(915, "utf-16", { ["textDocument/rename"] = true, ["textDocument/formatting"] = true }) }
menu.open()
assert(item("rename") and item("format"))
h.eq(0, #clients[1].requests)
menu.close()

-- Range probes use the original selection and the client's encoding, including exclusive ends.
clients = { client(916, "utf-16") }
local ctx = require("ui_tools.context_menu.context").capture()
ctx.selection = {
  regions = vim.fn.getregionpos({ buf, 1, 2, 0 }, { buf, 1, 9, 0 }, { type = "v", exclusive = true }),
}
local cancel
adapter.items(ctx, {}, {
  update = function() end,
  on_close = function(callback)
    cancel = callback
  end,
})
local range = request(clients[1], "textDocument/codeAction").params.range
h.eq({ line = 0, character = 1 }, range.start)
h.eq({ line = 0, character = 4 }, range["end"])
assert(#clients[1].requests == 1)
cancel()

-- A stale buffer cannot accept a result even if the transport ignores cancellation.
clients = { client(917, "utf-16") }
menu.open()
api.nvim_buf_set_lines(buf, 0, 1, false, { "changed" })
reply(clients[1], "textDocument/definition", destination)
assert(not item("definition"))
assert(#clients[1].cancelled > 0)
menu.close()
menu.disable()
h.eq({}, menu.errors)
vim.lsp.get_clients = original_clients
vim.lsp.get_client_by_id = original_client
print("context LSP: empty results, client union, encodings, diagnostics, cancellation and ranges passed")
