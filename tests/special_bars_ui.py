"""Exercise special-buffer bars in native rendered windows and normal editors."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Special bars UI timed out")))
signal.alarm(50)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def settle():
    lua("vim.wait(70); vim.cmd('redraw!')")


def bars(win):
    settle()
    row, col, width, height = lua("local w=" + win + "; local p=api.nvim_win_get_position(w); return {p[1],p[2],api.nvim_win_get_width(w),api.nvim_win_get_height(w)}")
    return ["".join(c for c, _ in ui.grid[r][col:col + width]) for r in (row, row + height)]


def keys(text):
    ui.request("nvim_input", [text])
    settle()


try:
    ui.request("nvim_ui_attach", [140, 26, {"rgb": True, "ext_linegrid": True}])
    lua("""
      api=vim.api; vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.hidden=true
      api.nvim_buf_set_name(0,'/tmp/ui-tools-special/editor.lua'); vim.bo.filetype='lua'
      api.nvim_buf_set_lines(0,0,-1,false,{'one','two'}); vim.bo.modified=false
      source=api.nvim_get_current_buf(); editor=api.nvim_get_current_win()
      calls=0
      local function provider(ctx)
        assert(vim.bo.filetype==ctx.filetype and vim.api.nvim_get_current_win()==ctx.win)
        assert(ctx.buf==api.nvim_get_current_buf())
        calls=calls+1
        return (ctx.active and 'ACTIVE ' or 'IDLE ')..ctx.cursor[1]..' 100%'
      end
      opts={
        statusline={filetypes={panel={text=provider,align='right'}}},
        winbar={exclude={'panel'},filetypes={panel={text=provider,align='center'}}},
      }
      require('ui_tools').setup(opts)
      buf=api.nvim_create_buf(false,true); vim.bo[buf].filetype='panel'
      api.nvim_buf_set_lines(buf,0,-1,false,{'first','second','third'})
      panel=api.nvim_open_win(buf,true,{split='left',win=-1,width=32})
    """)
    top, bottom = bars("panel")
    assert top.strip() == bottom.strip() == "ACTIVE 1 100%", (top, bottom)
    assert top.index("ACTIVE") == (len(top) - len(top.strip())) // 2, top
    assert bottom.endswith("ACTIVE 1 100% "), bottom
    assert "editor.lua" in bars("editor")[0]
    keys("j")
    assert "ACTIVE 2 100%" in bars("panel")[0]
    keys("<C-w>l")
    assert bars("panel")[0].strip() == bars("panel")[1].strip() == "IDLE 2 100%"
    assert "NORMAL" in bars("editor")[1]

    lua("""
      calls=0
      for i=1,100 do
        api.nvim_eval_statusline(vim.wo[panel].winbar,{winid=panel,use_winbar=true})
        api.nvim_eval_statusline(vim.wo[panel].statusline,{winid=panel})
      end
    """)
    assert lua("return calls") == 0, "Profile providers ran during rendering"

    # Buffer declarations override filetype defaults, including exclusion.
    lua("""
      vim.b[buf].ui_tools_winbar={text='Files',align='center'}
      vim.b[buf].ui_tools_statusline='file-tools'
      require('ui_tools.winbar').refresh(); require('ui_tools.statusline').refresh()
    """)
    top, bottom = bars("panel")
    assert top.strip() == "Files" and bottom.strip() == "file-tools", (top, bottom)
    assert top.index("Files") == (len(top) - 5) // 2, top


    lua("vim.b[buf].ui_tools_winbar={text='中文%{evil} very long heading',align='center'}; require('ui_tools.winbar').refresh()")
    top = bars("panel")[0]
    assert "%{evil}" in top, top
    ui.request("nvim_ui_try_resize", [65, 18])
    lua("api.nvim_win_set_width(panel,16)")
    top = bars("panel")[0]
    assert "…" in top and lua("return vim.v.errmsg") == "", top
    ui.request("nvim_ui_try_resize", [140, 26])
    lua("api.nvim_win_set_width(panel,32)")

    # One window can show ordinary and special buffers without leaking layouts.
    lua("api.nvim_set_current_win(panel); api.nvim_set_current_buf(source)")
    assert "editor.lua" in bars("panel")[0] and "NORMAL" in bars("panel")[1]
    lua("api.nvim_set_current_buf(buf)")
    assert bars("panel")[1].strip() == "file-tools"
    lua("""
      vim.b[buf].ui_tools_winbar=false; require('ui_tools.winbar').refresh()
    """)
    assert lua("return vim.wo[panel].winbar") == ""
    lua("""
      vim.b[buf].ui_tools_winbar={text='Files',align='center'}
      require('ui_tools.winbar').refresh()
      vim.b[buf].ui_tools_disable=true
      require('ui_tools.winbar').refresh(); require('ui_tools.statusline').refresh()
    """)
    assert lua("return vim.wo[panel].winbar") == ""
    lua("vim.b[buf].ui_tools_disable=nil; require('ui_tools').setup(opts)")
    assert bars("panel")[0].strip() == "Files"

    # Invalid declarations and failed callbacks stay local to the special bar.
    lua("vim.b[buf].ui_tools_winbar={align='broken'}; require('ui_tools.winbar').refresh()")
    assert bars("panel")[0].strip() == ""
    assert lua("return require('ui_tools.winbar').errors[panel] ~= nil")
    lua("""
      vim.b[buf].ui_tools_winbar=nil; vim.b[buf].ui_tools_statusline=nil
      opts.winbar.filetypes.panel.text=function() error('bad special provider') end
      opts.statusline.filetypes.panel.text=function() return nil end
      require('ui_tools').setup(opts)
    """)
    assert bars("panel")[0].strip() == bars("panel")[1].strip() == ""
    assert lua("return require('ui_tools.winbar').errors[panel]:find('bad special provider',1,true) ~= nil")
    assert "editor.lua" in bars("editor")[0]

    # Existing and later owners are preserved, and disable releases owned bars.
    lua("""
      vim.wo[panel].winbar='external top'; vim.wo[panel].statusline='external bottom'
      require('ui_tools.winbar').refresh(); require('ui_tools.statusline').refresh()
      require('ui_tools').disable()
    """)
    assert lua("return vim.wo[panel].winbar=='external top' and vim.wo[panel].statusline=='external bottom'")
    assert lua("return vim.wo[editor].winbar=='' and not vim.wo[editor].statusline:find('ui_tools',1,true)")
    assert lua("return vim.v.errmsg") == ""
    print("special bars native UI: centered titles, minimal footers, callbacks, buffer overrides, escaping, resize, switching, errors and ownership passed")
finally:
    ui.close()
