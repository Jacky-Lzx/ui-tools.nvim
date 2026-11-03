"""Exercise dashboard rendering, real key dispatch, resizing and startup guards."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Dashboard UI timed out")))
signal.alarm(40)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def keys(text):
    ui.request("nvim_input", [text])
    lua("return 1")


def screen():
    lua("vim.cmd('redraw!')")
    return "\n".join("".join(c for c, _ in row) for row in ui.grid)


def check_colors():
    screen()
    assert lua("return not vim.wo.cursorline")
    row = ui.grid[lua("return d.state().rows[1]") - 1]
    for char, color in [("", 0x66CCAA), ("F", 0x6699FF), ("f", 0xDD88CC)]:
        col = next(i for i, (text, _) in enumerate(row) if text == char)
        attrs = ui.attrs[row[col][1]]
        assert attrs.get("foreground") == color, (char, attrs)
        assert attrs.get("background", ui.bg) == ui.bg, (char, attrs)
    for col in (0, len(row) - 1):
        assert ui.attrs[row[col][1]].get("background", ui.bg) == ui.bg


try:
    ui.request("nvim_ui_attach", [100, 40, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.wo.number=true; vim.wo.wrap=true; vim.wo.cursorline=true
      vim.api.nvim_set_hl(0,'CursorLine',{bg=0xff0000})
      vim.api.nvim_set_hl(0,'Function',{fg=0x6699ff})
      vim.api.nvim_set_hl(0,'DiagnosticHint',{fg=0x66ccaa})
      vim.api.nvim_set_hl(0,'Special',{fg=0xdd88cc})
      source=vim.api.nvim_get_current_buf()
      ui=require('ui_tools'); d=require('ui_tools.dashboard')
      ui.setup({dashboard={header='中文 dashboard',footer='ready',keys={
        {key='f',icon=' ',desc='Find File',action=function() picked=(picked or 0)+1 end},
        {key='n',desc='New File',action='enew | startinsert'},
        {key='x',desc='Hidden',enabled=false,action='qa!'},
      }}})
    """)
    lua("vim.wait(50)")
    assert lua("return vim.bo.filetype") == "ui_tools_dashboard"
    text = screen()
    assert "中文 dashboard" in text and "Find File" in text and "[f]" in text and "ready" in text, text
    assert "Hidden" not in text, text
    check_colors()
    keys("f")
    assert lua("return picked") == 1
    keys("j<Up><CR>")
    assert lua("return picked") == 2
    ui.request("nvim_ui_try_resize", [22, 10])
    lua("vim.wait(50)")
    text = screen()
    assert "Find File" in text and "[n]" in text, text
    check_colors()
    keys("n")
    assert lua("return vim.fn.mode()") == "i"
    assert lua("return d.state() == nil and vim.wo.number and vim.wo.wrap and vim.wo.cursorline")
    keys("hello<Esc>")
    assert lua("return vim.api.nvim_get_current_line()") == "hello"

    # Side-by-side art stays beside the menu and shrinks on a live UI resize.
    ui.request("nvim_ui_try_resize", [100, 30])
    lua("""
      ui.dashboard({layout='horizontal',header=table.concat({
        '+------------------+', '|   /\\\\     /\\\\     |',
        '|  (  o   o  )     |', '+------------------+'},'\\n')})
      vim.wait(30)
    """)
    text = screen()
    assert "Find File" in text and "+------------------+" in text, text
    assert lua("local s=d.state(); local line=vim.api.nvim_buf_get_lines(s.buf,s.rows[1]-1,s.rows[1],false)[1]; return line:find('|',1,true)<line:find('Find File',1,true)")
    check_colors()
    keys("j")
    ui.request("nvim_ui_try_resize", [24, 12])
    lua("vim.wait(30)")
    assert lua("return d.state().selected") == 2
    assert lua("return d.state().layout.header_height > 0")
    assert "[f]" in screen() and "[n]" in screen(), screen()
    check_colors()
    ui.request("nvim_ui_try_resize", [100, 30])
    lua("vim.wait(30)")
    assert "+------------------+" in screen(), screen()
    assert lua("return d.state().selected") == 2
    keys("<CR>")
    assert lua("return d.state() == nil")
    keys("left layout<Esc>")
    assert lua("return vim.api.nvim_get_current_line()") == "left layout"

    # UTF-8 art before the action column must use byte offsets for the cursor.
    lua("ui.dashboard({layout='horizontal',header='中文⣿⣿⣿\\n中文⣿⣿⣿'})")
    assert "中文⣿⣿⣿" in screen() and "Find File" in screen(), screen()
    keys("j")
    assert lua("local s=d.state(); return vim.api.nvim_win_get_cursor(s.win)[2] == s.cols[2]")
    keys("<Esc>")

    # Repeated setup and later UIEnter must never cover modified text or file args.
    lua("ui.setup({dashboard=true}); vim.wait(30)")
    assert lua("return d.state() == nil")
    lua("vim.cmd('enew!'); vim.cmd('argadd README.md'); ui.setup({dashboard=true}); vim.wait(30)")
    assert lua("return d.state() == nil")
    lua("vim.cmd('argdelete *'); vim.cmd('vsplit'); ui.setup({dashboard=true}); vim.wait(30)")
    assert lua("return d.state() == nil")
    lua("vim.cmd('only'); ui.dashboard({keys={}})")
    keys("<Esc>")
    assert lua("return d.state() == nil and vim.wo.number")
    print("dashboard UI startup, Unicode, keys, resize and window restoration passed")
finally:
    ui.close()
