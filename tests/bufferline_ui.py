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
      vim.keymap.set('n',']b',function() line.cycle(1) end)
      vim.keymap.set('n','[b',function() line.cycle(-1) end)
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
    lua("require('ui_tools').disable()")
    assert lua("return vim.o.tabline == ''")
    print("bufferline native UI mouse, keys, 500-character burst, overflow and resize passed")
finally:
    ui.close()
