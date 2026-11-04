"""Inspect composited scrollbar backgrounds with an actual Neovim UI."""
import os
import signal
from pathlib import Path
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Scrollbar UI test timed out")))
signal.alarm(20)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def cell(row):
    lua("vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])
    char, attr = ui.grid[row][79]
    return char, ui.attrs[attr]


def background(row):
    # The UI omits colors equal to its default background on some releases.
    return cell(row)[1].get("background", ui.bg)


try:
    ui.request("nvim_ui_attach", [80, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.wo.wrap=false; vim.wo.number=false; vim.wo.signcolumn='no'; vim.o.laststatus=0
      vim.api.nvim_set_hl(0,'Normal',{fg='#ffffff',bg='#123456'})
      vim.api.nvim_set_hl(0,'UiToolsScrollbar',{bg='NONE',blend=100})
      vim.api.nvim_set_hl(0,'UiToolsScrollbarHandle',{bg='#000000',blend=0})
      vim.api.nvim_set_hl(0,'MarkerTest',{fg='#00ffff'})
      local lines={}; for i=1,300 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      require('ui_tools').setup({scrollbar={handle=' ',blend=100,search=false,diagnostics=false,cursor=false}})
      bar=require('ui_tools.scrollbar')
    """)
    assert background(0) == 0x000000, cell(0)
    assert background(5) == 0x123456, cell(5)

    # Marker foregrounds must preserve the opaque handle and transparent track.
    lua("""
      remove=bar.register('test',function()
        return {{line=1,char='!',hl='MarkerTest'},{line=150,char='!',hl='MarkerTest'}}
      end)
      bar.refresh()
    """)
    char, attrs = cell(0)
    assert char == "!" and background(0) == 0x000000, (char, attrs)
    assert attrs.get("foreground") == 0x00ffff, attrs
    marker_row = lua("return bar.project(150,300,vim.api.nvim_win_get_height(0))-1")
    char, attrs = cell(marker_row)
    assert char == "!" and background(marker_row) == 0x123456, (char, attrs)
    assert background(5) == 0x123456, cell(5)

    # Transparency must follow the source window, including local decorations.
    lua("""
      vim.api.nvim_set_hl(0,'SourceBackground',{bg='#654321'})
      vim.api.nvim_buf_set_extmark(0,vim.api.nvim_create_namespace('ScrollbarSource'),5,0,
        {line_hl_group='SourceBackground'})
    """)
    assert background(5) == 0x654321, cell(5)
    lua("vim.api.nvim_win_set_cursor(0,{100,0}); vim.cmd('normal! zz'); bar.refresh()")
    # Moving the viewport clears the old black handle and places a new one.
    first = lua("return bar.project(vim.fn.line('w0'),300,vim.api.nvim_win_get_height(0))-1")
    assert background(first) == 0x000000, cell(first)
    lua("remove(); bar.refresh()")
    assert background(0) == 0x123456, cell(0)
    # Check a terminal-default transparent theme from a fresh UI session, too.
    ui.close()
    ui = Capture(os.environ.copy())
    ui.request("nvim_ui_attach", [80, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.wo.wrap=false; vim.wo.signcolumn='no'
      vim.api.nvim_set_hl(0,'Normal',{fg='#ffffff',bg='NONE'})
      local lines={}; for i=1,300 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
    """)
    transparent_background = background(5)
    lua("""
      vim.api.nvim_set_hl(0,'UiToolsScrollbar',{bg='NONE',blend=100})
      vim.api.nvim_set_hl(0,'UiToolsScrollbarHandle',{bg='#000000',blend=0})
      require('ui_tools').setup({scrollbar={handle=' ',blend=100,search=false,diagnostics=false,cursor=false}})
    """)
    assert background(5) == transparent_background, cell(5)
    lua("require('ui_tools').disable()")
    # Palette-driven handles must stay opaque with a fully transparent float.
    theme_root = Path(os.environ.get("THEME_TOOLS_DIR", Path.cwd().parent / "theme-tools.nvim"))
    if theme_root.is_dir():
        ui.request("nvim_exec_lua", ["vim.opt.rtp:append(...)", [str(theme_root)]])
        lua("""
          themes=require('theme_tools')
          themes.setup({persist=false,catppuccin=false,dracula=false,
            default='desert',themes={'desert','morning'}})
          require('ui_tools').setup({scrollbar={handle=' ',blend=100,search=false,diagnostics=false,cursor=false}})
          bar=require('ui_tools.scrollbar')
        """)
        for theme in ("desert", "morning", "desert"):
            ui.request("nvim_exec_lua", ["assert(themes.set(...)); vim.wait(50)", [theme]])
            expected = lua("return tonumber(themes.palette().ui.selection_bg:sub(2),16)")
            assert background(0) == expected, (theme, cell(0))
            assert background(5) != expected, (theme, cell(5))
        ui.request("nvim_input", ["100G"])
        lua("vim.wait(100)")
        first = lua("return bar.project(vim.fn.line('w0'),300,vim.api.nvim_win_get_height(0))-1")
        assert background(first) == expected, cell(first)
        assert background(0) != expected, cell(0)
        lua("require('ui_tools').disable()")
        print("scrollbar palette UI: opaque handle, theme switching and key scroll passed")
    print("scrollbar UI: black handle, transparent track/markers and scroll movement passed")
finally:
    ui.close()
    signal.alarm(0)
