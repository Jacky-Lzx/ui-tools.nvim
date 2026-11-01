"""Verify the actual cursor indicator during key input, insertion and splits."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Cursor UI test timed out")))
signal.alarm(20)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def frame():
    lua("vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])


def cursor_cell(win):
    frame()
    row, col = lua("""
      local win=...; local rail=bar.bars[win].win
      local pos=vim.api.nvim_win_get_position(rail)
      return {pos[1]+bar.project(vim.api.nvim_win_get_cursor(win)[1],
        vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)),vim.api.nvim_win_get_height(rail))-1,
        pos[2]}
    """.replace("local win=...", f"local win={win}"))
    char, attr = ui.grid[row][col]
    return char, ui.attrs[attr]


def keys(value):
    ui.request("nvim_input", [value])
    lua("vim.wait(100)")


try:
    ui.request("nvim_ui_attach", [100, 30, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.wo.wrap=false; vim.wo.signcolumn='no'
      vim.o.laststatus=0; vim.o.splitright=true; vim.wo.winbar='header'
      vim.api.nvim_set_hl(0,'Normal',{fg='#ffffff',bg='#123456'})
      vim.api.nvim_set_hl(0,'UiToolsScrollbar',{bg='NONE',blend=100})
      vim.api.nvim_set_hl(0,'UiToolsScrollbarHandle',{bg='#000000',blend=0})
      vim.api.nvim_set_hl(0,'UiToolsScrollbarCursor',{fg='#ff8800'})
      local lines={}; for i=1,300 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      tools=require('ui_tools'); tools.setup({scrollbar={handle=' ',blend=100,search=false,diagnostics=false}})
      bar=require('ui_tools.scrollbar'); source=vim.api.nvim_get_current_win()
      bar.register('collision',function()
        return {{line=1,char='!',hl='Error',priority=9999},{line=100,char='!',hl='Error',priority=9999}}
      end)
      bar.refresh()
    """)
    source = lua("return source")
    char, attrs = cursor_cell(source)
    assert char == "●", (char, attrs)
    assert attrs.get("foreground") == 0xff8800 and attrs.get("background") == 0, attrs
    keys("100G")
    char, attrs = cursor_cell(source)
    assert char == "●" and attrs.get("background") == 0, (char, attrs)
    assert lua("return vim.api.nvim_buf_get_lines(bar.bars[source].buf,0,1,false)[1]") == "!"
    # Check while Insert mode is still active; CursorMovedI/TextChangedI must refresh it.
    keys("o" + "\n" * 20 + "inserted text")
    assert lua("return vim.api.nvim_get_mode().mode:sub(1,1)") == "i"
    assert cursor_cell(source)[0] == "●"
    keys("<Esc>")
    lua("""
      vim.cmd('vsplit'); other=vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_cursor(source,{1,0})
      vim.api.nvim_win_set_cursor(other,{vim.api.nvim_buf_line_count(0),0})
      bar.refresh()
    """)
    other = lua("return other")
    assert cursor_cell(source)[0] == "●"
    assert cursor_cell(other)[0] == "●"
    lua("tools.setup({scrollbar={cursor=false}})")
    assert cursor_cell(source)[0] != "●"
    assert cursor_cell(other)[0] != "●"
    assert lua("return next(bar.errors)==nil")
    lua("tools.disable()")
    print("cursor UI: movement, Insert mode, collision priority, black background and independent splits passed")
finally:
    ui.close()
    signal.alarm(0)
