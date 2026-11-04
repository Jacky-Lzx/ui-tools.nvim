"""Validate real statusline redraws, input/modes, macros, splits and narrow layouts."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Statusline UI timed out")))
signal.alarm(50)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def keys(value):
    ui.request("nvim_input", [value])
    lua("return 1")


def screen():
    lua("vim.wait(60); vim.cmd('redraw!')")
    return "\n".join("".join(c for c, _ in row) for row in ui.grid)


def status():
    screen()
    return "".join(c for c, _ in ui.grid[-2])


try:
    ui.request("nvim_ui_attach", [150, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.hidden=true; vim.o.showmode=false
      api=vim.api; line=require('ui_tools.statusline')
      api.nvim_buf_set_name(0,'/tmp/ui-tools-status-ui/中文%file.lua')
      api.nvim_buf_set_lines(0,0,-1,false,{'first','second','third'})
      vim.bo.filetype='lua'; vim.bo.modified=false
      -- Transparent Normal must not leave accent-block text inheriting white.
      api.nvim_set_hl(0,'Normal',{fg=0xcdd6f4})
      api.nvim_set_hl(0,'Function',{fg=0x88aaff})
      api.nvim_set_hl(0,'String',{fg=0x88ff88})
      require('ui_tools').setup({bufferline={auto_hide=-1},statusline={globalstatus=true}})
      source=api.nvim_get_current_buf()
    """)
    assert "NORMAL" in status() and "中文%file.lua" in status(), screen()
    col = next(i for i, (c, _) in enumerate(ui.grid[-2]) if c == "N")
    assert ui.attrs[ui.grid[-2][col][1]].get("background") == 0x88AAFF
    assert ui.attrs[ui.grid[-2][col][1]].get("foreground") == 0x000000
    # Grid columns include continuation cells for the wide filename glyphs.
    row = ui.grid[-2]
    location = next(i for i in range(len(row) - 2) if [c for c, _ in row[i:i + 3]] == ["1", ":", "1"])
    assert ui.attrs[ui.grid[-2][location][1]].get("background") == 0x88AAFF
    assert ui.attrs[ui.grid[-2][location][1]].get("foreground") == 0x000000
    keys("i")
    assert "INSERT" in status(), screen()
    col = next(i for i, (c, _) in enumerate(ui.grid[-2]) if c == "I")
    assert ui.attrs[ui.grid[-2][col][1]].get("background") == 0x88FF88
    assert ui.attrs[ui.grid[-2][col][1]].get("foreground") == 0x000000

    lua("""
      queries=0; old_count=vim.diagnostic.count; old_clients=vim.lsp.get_clients
      vim.diagnostic.count=function(...) queries=queries+1; return old_count(...) end
      vim.lsp.get_clients=function(...) queries=queries+1; return old_clients(...) end
    """)
    keys("abcdefghij" * 50 + "<Esc>")
    assert "[+]" in status() and "NORMAL" in status()
    assert lua("return queries") == 0
    keys("j0")
    assert "2:1" in status() and "66%" in status(), status()
    assert lua("return queries") == 0
    keys("v")
    assert "VISUAL" in status(), status()
    keys("<Esc>")
    keys("qq")
    assert "REC @q" in status(), status()
    keys("jq")
    assert "REC @q" not in status(), status()

    # Native per-window statuslines preserve each buffer and location.
    lua("""
      require('ui_tools').setup({bufferline={auto_hide=-1},statusline=true})
      vim.cmd('vsplit'); vim.cmd('enew'); api.nvim_buf_set_name(0,'/tmp/ui-tools-status-ui/other.txt')
      api.nvim_buf_set_lines(0,0,-1,false,{'different'})
    """)
    text = screen()
    assert "other.txt" in text and "中文%file.lua" in text, text
    keys("<C-w>l")
    assert "NORMAL" in screen()
    assert lua("return api.nvim_get_current_buf()==source")
    ui.request("nvim_ui_try_resize", [42, 12])
    text = screen()
    assert "file.lua" in text or "…" in text, text
    assert lua("return vim.v.errmsg") == ""
    ui.request("nvim_ui_try_resize", [16, 8])
    text = screen()
    assert "…" in text, text
    assert lua("return vim.v.errmsg") == ""
    ui.request("nvim_ui_try_resize", [150, 24])
    lua("vim.cmd('only'); line.setup({globalstatus=true})")
    assert "中文%file.lua" in status() and "NORMAL" in status()

    lua("""
      ns=api.nvim_create_namespace('status-ui-test')
      vim.diagnostic.set(ns,0,{{lnum=0,col=0,severity=1,message='issue'}})
      vim.b.git_tools_status={head='main',added=2}
      api.nvim_exec_autocmds('User',{pattern='GitToolsUpdate'})
    """)
    assert "E1" in status() and "main" in status() and "+2" in status(), status()
    lua("vim.diagnostic.reset(ns)")
    # :checkhealth opens a tab when the source buffer is nonempty. Deferred
    # updates must still resolve the source window's cwd in its original tab.
    for _ in range(2):
        keys(":checkhealth vim.lsp<CR>")
        text = screen()
        assert lua("return vim.bo.filetype") == "checkhealth", text
        assert lua("return #api.nvim_list_tabpages()") == 2
        assert "checkhealth" in status(), status()
        assert lua("return vim.v.errmsg") == ""
        keys(":tabclose<CR>")
        assert "中文%file.lua" in status(), status()
        assert lua("return api.nvim_get_current_buf()==source")
        assert lua("return vim.v.errmsg") == ""
    lua("require('ui_tools').disable()")
    assert lua("return not vim.wo.statusline:find('ui_tools',1,true)")
    print("statusline native UI modes, colors, macro, 500-character burst, splits, resize and checkhealth passed")
finally:
    ui.close()
