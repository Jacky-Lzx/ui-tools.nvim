"""Exercise native per-window winbars, independent cursors and view preservation."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Winbar UI timed out")))
signal.alarm(45)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def keys(value):
    ui.request("nvim_input", [value])
    lua("return 1")


def rows():
    lua("vim.wait(60); vim.cmd('redraw!')")
    return ["".join(char for char, _ in row) for row in ui.grid]


def window_bar(name):
    row, col, width = lua("local p=api.nvim_win_get_position(" + name + "); return {p[1],p[2],api.nvim_win_get_width(" + name + ")}")
    rows()
    return "".join(char for char, _ in ui.grid[row][col:col + width])


try:
    ui.request("nvim_ui_attach", [140, 28, {"rgb": True, "ext_linegrid": True}])
    lua("""
      api=vim.api; vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.hidden=true
      vim.o.splitkeep='screen'
      api.nvim_buf_set_name(0,'/tmp/ui-tools-winbar-ui/left%file.lua')
      local lines={}; for i=1,200 do lines[i]='text '..i end
      api.nvim_buf_set_lines(0,0,-1,false,lines); vim.bo.modified=false
      api.nvim_win_set_cursor(0,{30,2}); vim.cmd('normal! zz')
      left=api.nvim_get_current_win(); source=api.nvim_get_current_buf()
      saved_view=vim.fn.winsaveview(); saved_cursor=api.nvim_win_get_cursor(0)
      winbar=require('ui_tools.winbar')
      opts={breadcrumbs=function(ctx) return 'scope_'..ctx.cursor[1] end}
      require('ui_tools').setup({winbar=opts})
    """)
    assert "left%file.lua" in window_bar("left")
    assert lua("return vim.deep_equal(saved_cursor,api.nvim_win_get_cursor(left)) and saved_view.topline==vim.fn.winsaveview().topline")
    lua("""
      vim.cmd('rightbelow vsplit'); right=api.nvim_get_current_win()
      vim.cmd('enew'); api.nvim_buf_set_name(0,'/tmp/ui-tools-winbar-ui/right%file.lua')
      api.nvim_buf_set_lines(0,0,-1,false,{'right text','more text'}); vim.bo.modified=false
    """)
    assert "left%file.lua" in window_bar("left") and "scope_30" in window_bar("left")
    assert "right%file.lua" in window_bar("right") and "scope_1" in window_bar("right")
    keys("<C-w>h")
    assert "right%file.lua" in window_bar("right")
    lua("api.nvim_win_set_buf(right,source); api.nvim_win_set_cursor(left,{1,0}); api.nvim_win_set_cursor(right,{2,0})")
    assert "scope_1" in window_bar("left") and "scope_2" in window_bar("right")
    lua("api.nvim_set_current_win(right); vim.cmd('rightbelow split'); lower=api.nvim_get_current_win(); api.nvim_win_set_cursor(lower,{3,0})")
    assert "scope_1" in window_bar("left")
    assert "scope_2" in window_bar("right")
    assert "scope_3" in window_bar("lower")
    ui.request("nvim_ui_try_resize", [90, 22])
    assert "left%file.lua" in window_bar("left")
    assert "scope_2" in window_bar("right") and "scope_3" in window_bar("lower")
    ui.request("nvim_ui_try_resize", [140, 28])

    lua("""
      queries=0; clients=vim.lsp.get_clients
      vim.lsp.get_clients=function(...) queries=queries+1; return clients(...) end
    """)
    keys("i" + "abcdefghij" * 50 + "<Esc>")
    rows()
    assert lua("return queries") == 0
    assert "left%file.lua" in window_bar("left") and "left%file.lua" in window_bar("right")
    lua("vim.lsp.get_clients=clients; vim.cmd('close'); api.nvim_set_current_win(left); vim.cmd('only')")
    keys(":checkhealth vim.lsp<CR>")
    rows()
    assert lua("return vim.bo.filetype=='checkhealth' and vim.wo.winbar==''")
    keys(":tabclose<CR>")
    assert "left%file.lua" in window_bar("left")
    lua("""
      require('ui_tools').setup({winbar=opts,dashboard={autostart=false,header='DASHBOARD',footer=false}})
      require('ui_tools').dashboard()
    """)
    rows()
    assert lua("return vim.wo.winbar==''")
    lua("require('ui_tools.dashboard').close()")
    assert "left%file.lua" in window_bar("left")
    lua("require('ui_tools').disable()")
    assert lua("return vim.wo.winbar=='' and vim.v.errmsg==''")
    print("winbar native UI: inactive splits, cursors, views, resize, burst edits, checkhealth and dashboard passed")
finally:
    ui.close()
