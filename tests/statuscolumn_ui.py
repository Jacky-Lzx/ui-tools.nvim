"""Verify compact gutter geometry and native diagnostic signs on a real UI."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Status column UI test timed out")))
signal.alarm(20)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def frame():
    lua("vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])


def glyph(row, col=0):
    frame()
    return ui.grid[row][col][0]


def width():
    frame()
    return lua("return vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff")


try:
    ui.request("nvim_ui_attach", [90, 28, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.wo.number=true; vim.wo.relativenumber=false
      vim.wo.signcolumn='yes:1'; vim.wo.foldcolumn='0'; vim.wo.foldmethod='manual'
      local lines={}; for i=1,100 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      vim.diagnostic.config({signs={text={[1]='E',[2]='W',[3]='I',[4]='H'}},severity_sort=true,virtual_text=false})
      require('ui_tools').setup({statuscolumn=true}); stc=require('ui_tools.statuscolumn')
      ns=vim.api.nvim_create_namespace('NativeDiagnosticTest')
      vim.diagnostic.set(ns,0,{
        {lnum=1,col=0,severity=2,message='warning'},
        {lnum=1,col=0,severity=1,message='error'},
        {lnum=2,col=0,severity=2,message='warning on next line'},
      })
      vim.wait(80)
    """)
    assert width() == 6, width()
    assert glyph(1) == "E" and glyph(2) == "W"
    lua("""
      empty=vim.api.nvim_create_namespace('NumberOnly')
      vim.api.nvim_buf_set_extmark(0,empty,1,0,{number_hl_group='Error',priority=1000})
      competitor=vim.api.nvim_create_namespace('OtherSigns')
      vim.api.nvim_buf_set_extmark(0,competitor,1,0,{sign_text='X',sign_hl_group='Special',priority=900})
      vim.api.nvim_buf_set_mark(0,'a',2,0,{})
      git=vim.api.nvim_create_namespace('UnrelatedNamespace')
      vim.api.nvim_buf_set_extmark(0,git,2,0,{sign_text='+',sign_hl_group='GitToolsAdd'})
      stc.refresh()
    """)
    assert glyph(1) == "E", "A non-diagnostic sign/mark hid the diagnostic"
    assert glyph(2) == "W" and glyph(2, 5) == "+"
    assert width() == 6
    lua("vim.cmd('vsplit'); stc.refresh()")
    frame()
    assert lua("return stc.windows[vim.api.nvim_get_current_win()] ~= nil"), "Inherited column was not adopted"
    assert lua("return stc.cache[vim.api.nvim_get_current_win()][2].diagnostic.sign_hl_group") == "DiagnosticSignError"
    lua("vim.cmd('close'); stc.refresh()")
    frame()
    lua("vim.diagnostic.reset(ns,0); vim.wait(80)")
    assert glyph(1) == "X"
    lua("vim.api.nvim_buf_clear_namespace(0,competitor,0,-1); stc.refresh()")
    assert glyph(1) == "a", "Mark fallback disappeared"
    lua("""
      vim.api.nvim_buf_del_mark(0,'a')
      vim.api.nvim_buf_set_extmark(0,competitor,3,0,{sign_text='界',sign_hl_group='Special'})
      stc.refresh()
    """)
    assert width() == 7 and glyph(3) == "界", "Two-cell sign was clipped"
    lua("vim.api.nvim_buf_clear_namespace(0,competitor,0,-1); stc.refresh()")
    assert width() == 6, "Gutter failed to shrink after wide sign removal"
    lua("""
      vim.cmd('1,4fold'); stc.refresh()
    """)
    assert glyph(0, 5) == "▸"
    ui.request("nvim_input_mouse", ["left", "press", "", 0, 0, 5])
    ui.request("nvim_input_mouse", ["left", "release", "", 0, 0, 5])
    lua("vim.wait(80)")
    assert lua("return vim.fn.foldclosed(1)") == -1
    assert glyph(0, 5) == "▾", "First-line open fold icon missing"
    lua("""
      vim.cmd('normal! zE'); vim.wo.wrap=true
      vim.api.nvim_buf_set_lines(0,1,2,false,{string.rep('x',130)})
      vim.diagnostic.set(ns,0,{{lnum=1,col=0,severity=2,message='wrapped warning'}})
      vim.wait(80)
    """)
    assert glyph(1) == "W" and glyph(2) == " ", "Wrapped continuation repeated the diagnostic"
    lua("""
      vim.wo.wrap=false; vim.api.nvim_win_set_cursor(0,{70,0}); vim.cmd('normal! zt')
      vim.diagnostic.set(ns,0,{{lnum=70,col=0,severity=1,message='scrolled error'}})
      vim.wait(80)
    """)
    assert glyph(1) == "E", "New viewport lost its diagnostic signs"
    lua("require('ui_tools').disable()")
    print("status column UI: compact slots, diagnostics, numhl isolation, wide signs, shrink, clicks and scrolling passed")
finally:
    ui.close()
    signal.alarm(0)
