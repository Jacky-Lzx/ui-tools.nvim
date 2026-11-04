"""Inspect actual color cells during typing, scrolling, folds and theme changes."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Colors UI timed out")))
signal.alarm(40)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def screen():
    lua("vim.wait(80); vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])
    return "\n".join("".join(c[0] for c in row) for row in ui.grid)


def symbols():
    screen()
    return [ui.attrs[a] for row in ui.grid for c, a in row if c == "■"]


try:
    ui.request("nvim_ui_attach", [100, 26, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.o.laststatus=0; vim.o.showtabline=0; vim.o.ruler=false
      vim.wo.number=false; vim.wo.signcolumn='no'; vim.wo.wrap=false
      vim.api.nvim_set_hl(0,'Normal',{fg='#ffffff',bg='#000000'})
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'中文 #ff0000 #00ff00 rgba(255 0 0 / .5)','plain'})
      tools=require('ui_tools'); tools.setup({colors=true}); colors=require('ui_tools.colors')
    """)
    attrs = symbols()
    assert [a.get("foreground") for a in attrs] == [0xFF0000, 0x00FF00, 0x800000], attrs
    assert "■ #ff0000 ■ #00ff00" in screen()
    ui.request("nvim_input", ["2GA #123456"])
    lua("vim.wait(90)")
    assert lua("return vim.fn.mode()") == "i"
    assert symbols()[-1].get("foreground") == 0x123456
    ui.request("nvim_input", ["<BS><BS><BS>abc"])
    lua("vim.wait(90)")
    assert symbols()[-1].get("foreground") == 0x123ABC
    ui.request("nvim_input", ["<Esc>"])
    lua("""
      vim.api.nvim_set_hl(0,'Normal',{fg='#000000',bg='#ffffff'})
      vim.api.nvim_exec_autocmds('ColorScheme',{pattern='test'})
    """)
    assert symbols()[2].get("foreground") == 0xFF8080, symbols()
    for style in ("eol", "foreground", "background"):
        lua(f"tools.setup({{colors={{style='{style}'}}}})")
        rendered = screen()
        assert ("■" in rendered) == (style == "eol"), rendered
        if style != "eol":
            row = ui.grid[0]
            col = next(i for i, cell in enumerate(row) if cell[0] == "#")
            attr = ui.attrs[row[col][1]]
            assert attr.get("background" if style == "background" else "foreground") == 0xFF0000, attr
    lua("""
      local lines={}; for i=1,2000 do lines[i]='#123456 line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      vim.api.nvim_win_set_cursor(0,{1,0}); tools.setup({colors=true})
      source=vim.api.nvim_get_current_buf()
    """)
    assert len(symbols()) < 30
    ui.request("nvim_input", ["1000G"])
    assert "line 1000" in screen()
    assert lua("return #vim.api.nvim_buf_get_extmarks(source,colors.ns,0,-1,{})") < 30
    lua("vim.cmd('vsplit'); vim.cmd('normal! gg')")
    assert len(symbols()) > 30
    lua("""
      vim.cmd('only'); vim.wo.foldmethod='manual'; vim.cmd('1,1999fold')
      vim.api.nvim_win_set_cursor(0,{1,0})
    """)
    assert len(symbols()) <= 1
    ui.request("nvim_input", ["zo"])
    assert len(symbols()) > 10
    lua("tools.toggle('colors')")
    assert not symbols()
    lua("tools.toggle('colors'); tools.disable(); vim.wait(100)")
    assert not symbols()
    print("colors UI: actual RGB cells, Unicode, insert edits, alpha/theme, styles, viewport, splits, folds and cleanup passed")
finally:
    ui.close()
    signal.alarm(0)
