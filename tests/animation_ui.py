"""Verify native scrolling, intermediate frames, burst input and window teardown."""
import os
import signal
import time
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError('animation UI timed out')))
signal.alarm(30)
ui = Capture(os.environ.copy(), ['-u', 'NONE', '-i', 'NONE', '--noplugin'])
try:
    ui.request('nvim_ui_attach', [100, 30, {'rgb': True, 'ext_linegrid': True}])
    def lua(code):
        return ui.request('nvim_exec_lua', [code, []])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.o.scrolloff = 5
      vim.o.wrap = false
      vim.o.laststatus = 0
      local lines = {}; for i = 1, 500 do lines[i] = 'line ' .. i end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      require('ui_tools').setup({})
      function reset_scroll()
        require('ui_tools.scroll').disable()
        vim.fn.winrestview({topline=50, lnum=60, col=0})
        vim.cmd('redraw!')
      end
      reset_scroll()
    """)
    def view():
        return lua('local v=vim.fn.winsaveview(); return {v.topline,v.lnum}')
    def key(keys):
        ui.request('nvim_input', [keys])
        time.sleep(0.015)
    key('<C-d>')
    native = view()
    assert native[0] > 50, native
    lua("reset_scroll(); require('ui_tools.animate').setup({}); require('ui_tools.scroll').setup({duration=220})")
    key('<C-d>')
    intermediate = view()
    assert 50 <= intermediate[0] < native[0], (intermediate, native)
    time.sleep(0.3)
    assert view() == native, (view(), native)
    lua('reset_scroll()')
    key('<C-d><C-d>')
    burst = view()
    lua("reset_scroll(); require('ui_tools.scroll').setup({duration=220})")
    key('<C-d>')
    key('<C-d>')
    time.sleep(0.35)
    assert view() == burst, ('burst', view(), burst)
    lua("reset_scroll(); require('ui_tools.scroll').setup({duration=220})")
    key('<C-d>')
    lua("require('ui_tools.animate').disable()")
    assert view() == native, ('settle', view(), native)
    lua("reset_scroll(); require('ui_tools.animate').setup({}); require('ui_tools.scroll').setup({duration=220})")
    key('<C-d>')
    lua("vim.cmd('enew!'); vim.api.nvim_buf_set_lines(0,0,-1,false,{'replacement'})")
    time.sleep(0.3)
    assert lua('return vim.api.nvim_get_current_line()') == 'replacement'
    lua("vim.cmd('buffer #'); reset_scroll(); require('ui_tools.scroll').setup({duration=220})")
    key('<C-u>')
    time.sleep(0.3)
    reverse = view()
    lua("reset_scroll()")
    key('<C-u>')
    assert view() == reverse, ('reverse', view(), reverse)
    lua("reset_scroll(); require('ui_tools.scroll').setup({duration=220})")
    key('<C-d>')
    key('j')
    moved = view()
    time.sleep(0.3)
    assert view() == moved, ('cursor interruption', moved, view())
    lua("require('ui_tools').disable()")
    print('UI animation: native scroll semantics, visible intermediate frames, exact final cursor/view, burst input, disable and buffer replacement passed')
finally:
    ui.close()
    signal.alarm(0)
