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
      api.nvim_set_hl(0,'DiagnosticError',{fg=0xff6677})
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
    assert " NORMAL" in status() and "" in status() and "" in status(), status()
    base = lua("return api.nvim_get_hl(0,{name='UiToolsStatus',link=false}).bg")
    alt = lua("return api.nvim_get_hl(0,{name='UiToolsStatusAlt',link=false}).bg")
    assert base is not None and alt is not None and base != alt
    edge_col = next(i for i, (c, _) in enumerate(ui.grid[-2]) if c == "")
    assert ui.attrs[ui.grid[-2][edge_col][1]].get("foreground") == 0x88AAFF
    assert ui.attrs[ui.grid[-2][edge_col][1]].get("background") == base
    # The wide filename precedes encoding; locate cells rather than string offsets.
    encoding = next(i for i in range(len(row)-4) if "".join(c for c, _ in ui.grid[-2][i:i+5]) == "utf-8")
    assert ui.attrs[ui.grid[-2][encoding][1]].get("background") == alt
    keys("i")
    assert "INSERT" in status(), screen()
    col = next(i for i, (c, _) in enumerate(ui.grid[-2]) if c == "I")
    assert ui.attrs[ui.grid[-2][col][1]].get("background") == 0x88FF88
    assert ui.attrs[ui.grid[-2][col][1]].get("foreground") == 0x000000
    assert ui.attrs[ui.grid[-2][edge_col][1]].get("foreground") == 0x88FF88

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
    lua("vim.lsp.get_clients=function() return {{name='test_ls'}} end; line.refresh()")
    keys("qq")
    assert "● REC @q" in status(), status()
    row = ui.grid[-2]
    start = next(i for i, (c, _) in enumerate(row) if c == "●")
    badge = ui.attrs[row[start][1]]
    assert badge.get("foreground") == 0xFF6677 and badge.get("bold"), badge
    assert badge.get("background") not in (base, alt), badge
    assert all(ui.attrs[row[i][1]] == badge for i in range(start, start + len("● REC @q")))
    # The badge is its own surface, including beside LSP in the same section.
    for index, foreground, background in (
        (start - 2, badge["background"], base),
        (start + len("● REC @q") + 1, base, badge["background"]),
    ):
        assert row[index][0] == "", row
        attr = ui.attrs[row[index][1]]
        assert attr.get("foreground") == foreground and attr.get("background") == background, attr
    ui.request("nvim_ui_try_resize", [42, 12])
    assert "● REC @q" in status(), status()
    ui.request("nvim_ui_try_resize", [150, 24])
    lua("line.setup({globalstatus=true,icons=false})")
    assert "REC @q" in status() and "●" not in status(), status()
    lua("line.setup({globalstatus=true})")
    assert "● REC @q" in status(), status()
    keys("jq")
    assert "REC @q" not in status(), status()
    assert not any(ui.attrs[a].get("background") == badge["background"] for _, a in ui.grid[-2])
    lua("vim.lsp.get_clients=old_clients; line.refresh()")

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
    # Git/diagnostic foreground colors must not punch holes in the section background.
    row = ui.grid[-2]
    for label in ("main", "+2", "E1"):
        index = next(i for i in range(len(row)-len(label)+1) if "".join(c for c, _ in row[i:i+len(label)]) == label)
        assert ui.attrs[row[index][1]].get("background") == alt
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
