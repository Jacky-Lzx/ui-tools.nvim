local M = { enabled = false, dimmed = false }
local util = require("ui_tools.util")
local render = require("ui_tools.render")
local session
local closing = false

local function size(value, maximum)
  if value > 0 and value <= 1 then
    value = math.floor(maximum * value)
  end
  return math.max(1, math.min(maximum, math.floor(value)))
end

local function dimensions(mode, opts)
  local height = math.max(1, vim.o.lines - vim.o.cmdheight - 1)
  local width = vim.o.columns
  local w = mode == "zoom" and width or size(opts.width, width)
  local h = mode == "zoom" and height or size(opts.height, height)
  return {
    relative = "editor",
    row = math.floor((height - h) / 2),
    col = math.floor((width - w) / 2),
    width = w,
    height = h,
    style = "minimal",
    border = "none",
    zindex = 50,
  }
end

local function resize()
  if not session then
    return
  end
  if vim.api.nvim_win_is_valid(session.win) then
    vim.api.nvim_win_set_config(session.win, dimensions(session.mode, session.options))
  end
  if vim.api.nvim_win_is_valid(session.backdrop) then
    vim.api.nvim_win_set_config(session.backdrop, {
      relative = "editor",
      row = 0,
      col = 0,
      width = vim.o.columns,
      height = math.max(1, vim.o.lines - vim.o.cmdheight),
    })
  end
end

function M.close()
  if not session or closing then
    return
  end
  closing = true
  local current = session
  session = nil
  local buf, view = current.last_buf, current.last_view
  if vim.api.nvim_win_is_valid(current.win) then
    buf = vim.api.nvim_win_get_buf(current.win)
    view = vim.api.nvim_win_call(current.win, vim.fn.winsaveview)
  end
  -- Adopt before closing: a focused buffer may have bufhidden=wipe.
  if
    vim.api.nvim_win_is_valid(current.source)
    and buf
    and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_get_buf(current.source) == current.buf
  then
    local ok = pcall(vim.api.nvim_win_set_buf, current.source, buf)
    if ok and view then
      vim.api.nvim_win_call(current.source, function()
        vim.fn.winrestview(view)
      end)
    elseif not ok and vim.api.nvim_win_is_valid(current.win) then
      -- Keep the editor open if Neovim refuses to hide an unsaved source buffer.
      session, closing = current, false
      vim.notify("ui-tools: save or hide the source buffer before leaving focus mode", vim.log.levels.WARN)
      return false
    end
  end
  if vim.api.nvim_win_is_valid(current.win) then
    pcall(vim.api.nvim_win_close, current.win, true)
  end
  if vim.api.nvim_win_is_valid(current.backdrop) then
    pcall(vim.api.nvim_win_close, current.backdrop, true)
  end
  if vim.api.nvim_buf_is_valid(current.backdrop_buf) then
    pcall(vim.api.nvim_buf_delete, current.backdrop_buf, { force = true })
  end
  if vim.api.nvim_win_is_valid(current.source) then
    if vim.api.nvim_win_get_tabpage(current.source) == vim.api.nvim_get_current_tabpage() then
      vim.api.nvim_set_current_win(current.source)
    end
  end
  closing = false
  util.redraw()
  return true
end

function M.state()
  return session and { mode = session.mode, win = session.win, source = session.source } or nil
end

function M.open(mode, overrides)
  assert(mode == "zen" or mode == "zoom", "Unknown focus mode")
  if not M.enabled then
    M.setup({})
  end
  if session then
    local same = session.mode == mode
    if M.close() == false then
      return
    end
    if same then
      return
    end
  end
  local source = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  assert(util.eligible(source, buf, M.options), "Focus mode requires a normal editing window")
  local opts = vim.tbl_deep_extend("force", M.options, overrides or {})
  assert(type(opts.width) == "number" and opts.width > 0, "focus.width must be positive")
  assert(type(opts.height) == "number" and opts.height > 0, "focus.height must be positive")
  assert(
    type(opts.backdrop) == "number" and opts.backdrop >= 0 and opts.backdrop <= 100,
    "focus.backdrop must be 0..100"
  )
  local view = vim.fn.winsaveview()
  local backdrop_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[backdrop_buf].bufhidden = "wipe"
  local backdrop = vim.api.nvim_open_win(backdrop_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(1, vim.o.lines - vim.o.cmdheight),
    style = "minimal",
    focusable = false,
    mouse = false,
    zindex = 49,
  })
  vim.wo[backdrop].winblend = opts.backdrop
  vim.wo[backdrop].winhighlight =
    "Normal:UiToolsBackdrop,NormalFloat:UiToolsBackdrop,EndOfBuffer:UiToolsBackdrop"
  local win = vim.api.nvim_open_win(buf, true, dimensions(mode, opts))
  session = {
    source = source,
    buf = buf,
    win = win,
    backdrop = backdrop,
    backdrop_buf = backdrop_buf,
    mode = mode,
    options = opts,
  }
  vim.w[win].ui_tools_focus = true
  vim.w[win].ui_tools_statuscolumn_disable = mode == "zen"
  for _, option in ipairs({
    "wrap",
    "linebreak",
    "breakindent",
    "list",
    "spell",
    "conceallevel",
    "concealcursor",
    "foldmethod",
    "foldexpr",
    "foldtext",
    "foldlevel",
    "foldenable",
    "scrolloff",
    "sidescrolloff",
    "number",
    "relativenumber",
    "numberwidth",
    "signcolumn",
    "foldcolumn",
    "cursorline",
  }) do
    vim.wo[win][option] = vim.wo[source][option]
  end
  if mode == "zen" then
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
  end
  vim.wo[win].statuscolumn = ""
  vim.wo[win].winhighlight = "Normal:Normal,NormalFloat:Normal"
  vim.fn.winrestview(view)
  util.redraw()
  return win
end

function M.dim(value)
  if not M.enabled then
    M.setup({})
  end
  M.dimmed = value == nil and not M.dimmed or value == true
  util.redraw()
  return M.dimmed
end

function M.resolve(opts)
  local config = vim.tbl_deep_extend(
    "force",
    { width = 100, height = 0.9, backdrop = 60, dim = true, max_scan = 400 },
    opts or {}
  )
  assert(type(config.width) == "number" and config.width > 0, "focus.width must be positive")
  assert(type(config.height) == "number" and config.height > 0, "focus.height must be positive")
  assert(
    type(config.backdrop) == "number" and config.backdrop >= 0 and config.backdrop <= 100,
    "focus.backdrop must be 0..100"
  )
  return config
end

function M.setup(opts)
  local config = M.resolve(opts)
  assert(M.disable() ~= false, "Cannot replace a blocked focus session")
  M.options = config
  M.enabled = true
  util.hl({ UiToolsDim = "Comment", UiToolsBackdrop = "NormalFloat" })
  local group = util.group("Focus")
  vim.api.nvim_create_autocmd("VimResized", { group = group, callback = resize })
  vim.api.nvim_create_autocmd(
    { "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" },
    { group = group, callback = util.redraw }
  )
  vim.api.nvim_create_autocmd("TabLeave", { group = group, callback = M.close })
  vim.api.nvim_create_autocmd({ "WinLeave", "BufWinLeave" }, {
    group = group,
    callback = function()
      if
        session
        and vim.api.nvim_get_current_win() == session.win
        and vim.api.nvim_win_is_valid(session.win)
      then
        session.last_buf = vim.api.nvim_win_get_buf(session.win)
        session.last_view = vim.fn.winsaveview()
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      if
        session
        and (
          tonumber(event.match) == session.win
          or tonumber(event.match) == session.source
          or tonumber(event.match) == session.backdrop
        )
      then
        -- WinClosed forbids more window closes in the same callback.
        local expected = session
        vim.schedule(function()
          if session == expected then
            M.close()
          end
        end)
      end
    end,
  })
  render.register("focus", function(ctx)
    local active = session and session.mode == "zen" and session.options.dim and ctx.win == session.win
    if not active and not (M.dimmed and ctx.win == vim.api.nvim_get_current_win()) then
      return
    end
    if not util.eligible(ctx.win, ctx.buf, M.options) then
      return
    end
    local block = require("ui_tools.scope").find(ctx.buf, ctx.cursor[1], M.options.max_scan)
    local first, last = block and block.first or ctx.cursor[1], block and block.last or ctx.cursor[1]
    local ns = vim.api.nvim_create_namespace("UiToolsDim")
    return function(row)
      if row + 1 < first or row + 1 > last then
        vim.api.nvim_buf_set_extmark(
          ctx.buf,
          ns,
          row,
          0,
          { ephemeral = true, line_hl_group = "UiToolsDim", priority = 150 }
        )
      end
    end
  end)
end

function M.disable()
  if M.close() == false then
    return false
  end
  M.enabled, M.dimmed = false, false
  pcall(vim.api.nvim_del_augroup_by_name, "UiToolsFocus")
  render.register("focus", nil)
end

return M
