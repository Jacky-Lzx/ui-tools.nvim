"""Exercise native tabline input, mouse hit regions, resize and burst editing."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Bufferline UI timed out")))
signal.alarm(45)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def screen():
    lua("vim.wait(60); vim.cmd('redraw!')")
    return "".join(char for char, _ in ui.grid[0])


def keys(value):
    ui.request("nvim_input", [value])
    lua("return 1")


try:
    ui.request("nvim_ui_attach", [100, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.mouse='a'; vim.o.hidden=true
      line=require('ui_tools.bufferline'); vim.bo.buflisted=false; buffers={}
      for _, name in ipairs({'first.lua','中文%evil.lua','last.lua'}) do
        local b=vim.api.nvim_create_buf(true,false)
        vim.api.nvim_buf_set_name(b,'/tmp/ui-tools-bar-ui/'..name)
        buffers[#buffers+1]=b
      end
      vim.api.nvim_set_current_buf(buffers[1])
      require('ui_tools').setup({bufferline={numbers=true,auto_hide=-1}})
      vim.keymap.set('n',']b','<Cmd>BufferNext<CR>')
      vim.keymap.set('n','[b','<Cmd>BufferPrevious<CR>')
    """)
    text = screen()
    assert all(name in text for name in ("first.lua", "中文%evil.lua", "last.lua")), text
    keys("]b")
    assert lua("return vim.api.nvim_get_current_buf()==buffers[2]")
    text = screen()
    col = next(i for i in range(len(ui.grid[0])) if "".join(c for c, _ in ui.grid[0][i:i+4]) == "last")
    ui.request("nvim_input_mouse", ["left", "press", "", 0, 0, col])
    ui.request("nvim_input_mouse", ["left", "release", "", 0, 0, col])
    lua("return 1")
    assert lua("return vim.api.nvim_get_current_buf()==buffers[3]")

    # Continuous input must not trigger buffer scans or delayed data collection.
    lua("""
      scans=0; original=vim.api.nvim_list_bufs
      vim.api.nvim_list_bufs=function(...) scans=scans+1; return original(...) end
    """)
    keys("i" + "abcdefghij" * 50 + "<Esc>")
    assert "[+]" in screen()
    assert lua("return scans") == 0
    assert lua("return #vim.api.nvim_get_current_line()") == 500

    # Closing modified text through the close button must be refused.
    text = screen()
    last_start = text.index("last.lua")
    col = next(i for i in range(last_start, len(ui.grid[0])) if ui.grid[0][i][0] == "×")
    ui.request("nvim_input_mouse", ["left", "press", "", 0, 0, col])
    ui.request("nvim_input_mouse", ["left", "release", "", 0, 0, col])
    assert lua("return vim.api.nvim_buf_is_valid(buffers[3]) and vim.bo.modified")
    lua("vim.bo.modified=false")
    ui.request("nvim_input_mouse", ["left", "press", "", 0, 0, col])
    ui.request("nvim_input_mouse", ["left", "release", "", 0, 0, col])
    assert lua("return not vim.api.nvim_buf_is_valid(buffers[3])")

    # Enter Ex commands through real UI input; closing others preserves splits.
    keys(":BufferFirst<CR>:vsplit<CR>:BufferLast<CR>")
    assert lua("return vim.api.nvim_get_current_buf()==buffers[2] and #vim.api.nvim_list_wins()==2")
    keys(":BufferCloseAllButCurrent<CR>")
    assert lua("return not vim.api.nvim_buf_is_valid(buffers[1]) and vim.api.nvim_get_current_buf()==buffers[2] and #vim.api.nvim_list_wins()==2")
    assert "first.lua" not in screen() and "中文%evil.lua" in screen()
    keys(":BufferRestore<CR>")
    assert lua("return vim.api.nvim_buf_get_name(0):match('/first.lua$')~=nil")
    assert "first.lua" in screen()
    keys(":BufferClose<CR>:only<CR>")
    assert lua("return vim.api.nvim_get_current_buf()==buffers[2] and #vim.api.nvim_list_wins()==1")

    lua("""
      for i=1,60 do
        local b=vim.api.nvim_create_buf(true,false)
        vim.api.nvim_buf_set_name(b,'/tmp/ui-tools-bar-ui/overflow-'..i..'.lua')
        tail=b
      end
      vim.api.nvim_set_current_buf(tail)
    """)
    ui.request("nvim_ui_try_resize", [24, 10])
    text = screen()
    assert "overflow-60" in text and "‹" in text, text
    ui.request("nvim_ui_try_resize", [8, 8])
    assert "…" in screen(), screen()
    ui.request("nvim_ui_try_resize", [100, 24])
    assert "overflow-60.lua" in screen()
    keys("[b]b")
    assert lua("return vim.api.nvim_get_current_buf()==tail")
    lua("""
      vim.cmd('topleft 20vnew'); vim.bo.filetype='bar_sidebar'; vim.bo.buflisted=false
      require('ui_tools').setup({bufferline={auto_hide=-1,sidebar_filetypes={bar_sidebar=true}}})
      vim.cmd('wincmd l')
    """)
    text = screen()
    assert text.startswith(" " * 21), text
    assert text[21:].strip(), text
    lua("vim.cmd('wincmd h'); vim.cmd('close')")
    assert not screen().startswith(" " * 21)
    lua("""
      vim.cmd('only'); vim.o.splitkeep='screen'
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[b].buflisted then vim.bo[b].modified=false; vim.api.nvim_buf_delete(b,{force=false}) end
      end
      vim.cmd('enew'); vim.bo.buflisted=true
      local lines={}; for i=1,200 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      vim.api.nvim_win_set_cursor(0,{30,2}); vim.cmd('normal! zz')
      line.setup({auto_hide=1}); saved_cursor=vim.api.nvim_win_get_cursor(0)
      saved_view=vim.fn.winsaveview(); vim.api.nvim_create_buf(true,false)
    """)
    screen()
    assert lua("return vim.deep_equal(saved_cursor,vim.api.nvim_win_get_cursor(0)) and saved_view.topline==vim.fn.winsaveview().topline")
    lua("require('ui_tools').disable()")
    assert lua("return vim.o.tabline == ''")
    print("bufferline native UI commands, mouse, keys, 500-character burst, overflow and resize passed")
finally:
    ui.close()
