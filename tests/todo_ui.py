"""Check badges, native/custom gutters, actual syntax/TS filtering and edits."""
import os
import signal
from pathlib import Path
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("TODO UI timed out")))
signal.alarm(45)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def screen():
    lua("vim.wait(90); vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])
    return "\n".join("".join(c[0] for c in row) for row in ui.grid)


def at(row, word):
    screen()
    text = "".join(c[0] for c in ui.grid[row])
    # Test source rows use ASCII before the tag; Unicode is tested separately.
    col = text.index(word)
    return ui.attrs[ui.grid[row][col][1]]


try:
    ui.request("nvim_ui_attach", [100, 26, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.laststatus=0; vim.o.ruler=false
      vim.wo.number=false; vim.wo.signcolumn='yes'; vim.wo.wrap=false
      vim.api.nvim_set_hl(0,'Normal',{fg='#ffffff',bg='#101010'})
      vim.api.nvim_set_hl(0,'DiagnosticInfo',{fg='#00aaff'})
      vim.api.nvim_set_hl(0,'DiagnosticError',{fg='#ff0000'})
      vim.cmd('syntax on'); vim.bo.filetype='lua'; vim.bo.syntax='lua'
      vim.api.nvim_buf_set_lines(0,0,-1,false,{
        '-- TODO(lzx): implement #00ff00', 'local s = "TODO: ordinary string"',
        '-- NOTE: context FIXME: broken', '-- plain'
      })
      tools=require('ui_tools'); tools.setup({todo=true,colors=true}); todo=require('ui_tools.todo')
    """)
    assert at(0, "TODO").get("background") == 0x00AAFF
    assert at(1, "TODO").get("background") != 0x00AAFF
    assert at(2, "FIXME").get("background") == 0xFF0000
    assert "✓" in screen().splitlines()[0] and "!" in screen().splitlines()[2]
    assert "■ #00ff00" in screen()
    lua("""
      require('ui_tools.statuscolumn').setup({layout={'sign','number'}})
    """)
    assert "✓" in screen().splitlines()[0]
    # Removing the annotations must invalidate the statuscolumn sign cache now.
    lua("tools.toggle('todo')")
    assert "✓" not in screen(), screen()
    lua("tools.toggle('todo')")
    assert "✓" in screen()
    ui.request("nvim_input", ["4GA TODO: typing"])
    assert "✓" in screen().splitlines()[3]
    assert lua("return vim.fn.mode()") == "i"
    ui.request("nvim_input", ["<Esc>0d$ilocal s = 'TODO: string'"])
    assert "✓" not in screen().splitlines()[3]
    ui.request("nvim_input", ["<Esc>uu"])
    assert "TODO: typing" in screen()
    assert "✓" in screen().splitlines()[3]
    lua("""
      vim.api.nvim_set_hl(0,'DiagnosticInfo',{fg='#cc44ff'})
      vim.api.nvim_exec_autocmds('ColorScheme',{pattern='test'})
    """)
    assert at(0, "TODO").get("background") == 0xCC44FF
    # Exercise real Tree-sitter when a parser is available, without adding a dependency.
    site = Path(os.environ.get("UI_TOOLS_PARSER_DIR", Path.home() / ".local/share/nvim/site"))
    if site.is_dir():
        ui.request("nvim_exec_lua", ["vim.opt.rtp:append(...)", [str(site)]])
    has_ts = lua("return pcall(vim.treesitter.start,0,'lua')")
    if has_ts:
        screen()
        assert "✓" in screen().splitlines()[0]
        assert at(1, "TODO").get("background") != 0xCC44FF
        lua("""
          vim.api.nvim_buf_set_lines(0,0,-1,false,{
            'local x = "TODO: string" -- FIXME: real',
            '--[[ TODO: block ]] local s = "after"',
            '-- TODO: 中文 #abc'
          })
        """)
        assert at(0, "TODO").get("background") != 0xCC44FF
        assert at(0, "FIXME").get("background") == 0xFF0000
        assert at(1, "TODO").get("background") == 0xCC44FF
        assert at(1, "after").get("foreground") != 0xCC44FF
        ui.request("nvim_input", ["3G0d$ilocal s = 'TODO: string'"])
        assert "✓" not in screen().splitlines()[2]
        ui.request("nvim_input", ["<Esc>"])
        print("todo Tree-sitter: real parser, block/trailing comments, strings and insert edits passed")
    else:
        print("SKIP optional TODO Tree-sitter checks (set UI_TOOLS_PARSER_DIR)")
    lua("""
      if vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] then vim.treesitter.stop() end
      vim.bo.filetype='text'
      local lines={}; for i=1,2000 do lines[i]='TODO: item '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines); vim.api.nvim_win_set_cursor(0,{1,0})
    """)
    screen()
    assert lua("return #vim.api.nvim_buf_get_extmarks(0,todo.ns,0,-1,{type='sign'})") < 30
    ui.request("nvim_input", ["1000G"])
    assert "item 1000" in screen()
    lua("vim.cmd('vsplit'); vim.cmd('normal! gg')")
    assert lua("vim.wait(80); return #vim.api.nvim_buf_get_extmarks(0,todo.ns,0,-1,{type='sign'})") > 30
    lua("tools.disable(); vim.wait(100)")
    assert "✓" not in screen() and "■" not in screen()
    print("todo UI: badges, syntax strings, signs/statuscolumn, insert/undo, theme, viewport, splits and cleanup passed")
finally:
    ui.close()
    signal.alarm(0)
