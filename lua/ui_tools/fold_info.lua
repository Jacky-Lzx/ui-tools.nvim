-- Neovim's fold_info() distinguishes adjacent folds and shared starts, which
-- foldlevel() alone cannot. The four-int ABI is shared by Neovim 0.11 and 0.12:
-- https://github.com/neovim/neovim/blob/v0.12.0/src/nvim/fold_defs.h
local M = {}
local window, info, ffi

function M.setup()
  if info then
    return
  end
  ffi = require("ffi")
  ffi.cdef([[
    typedef struct { int start; int level; int lowest; int lines; } UiToolsFoldInfo;
    typedef struct { int type; char *message; } UiToolsFoldError;
  ]])
  local symbol
  if ffi.os == "Windows" then
    ffi.cdef([[
      void *__stdcall GetModuleHandleA(const char *name);
      void *__stdcall GetProcAddress(void *module, const char *name);
    ]])
    local process = ffi.C.GetModuleHandleA(nil)
    symbol = function(name)
      return ffi.C.GetProcAddress(process, name)
    end
  else
    ffi.cdef([[
      void *dlopen(const char *name, int flags);
      void *dlsym(void *handle, const char *name);
    ]])
    local process = ffi.C.dlopen(nil, 1)
    assert(process ~= nil, "ui-tools: cannot access Neovim fold symbols")
    symbol = function(name)
      return ffi.C.dlsym(process, name)
    end
  end
  local find, get = symbol("find_window_by_handle"), symbol("fold_info")
  assert(find ~= nil and get ~= nil, "ui-tools: this Neovim build does not export fold information")
  window = ffi.cast("void *(*)(int, UiToolsFoldError *)", find)
  info = ffi.cast("UiToolsFoldInfo (*)(void *, int)", get)
end

function M.get(win, line)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local err = ffi.new("UiToolsFoldError", { -1, nil })
  local ptr = window(win, err)
  if ptr == nil then
    return
  end
  return info(ptr, line)
end

-- Find the header of an ancestor without moving the cursor or changing folds.
function M.header(win, line, level)
  for _ = 1, 128 do
    local fold = M.get(win, line)
    if not fold or fold.level < level or fold.start < 1 then
      return
    end
    local start = M.get(win, fold.start)
    if start.lowest <= level then
      return fold.start, start
    end
    if fold.start <= 1 then
      return
    end
    line = fold.start - 1
  end
end

return M
