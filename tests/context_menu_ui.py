"""Exercise real mouse dispatch, visual selections and menu redraws."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Menu UI test timed out")))
signal.alarm(40)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def keys(text):
    ui.request("nvim_input", [text])
    lua("return 1")


def click(row, col, button="right"):
    ui.request("nvim_input_mouse", [button, "press", "", 0, row, col])
    lua("return 1")
    ui.request("nvim_input_mouse", [button, "release", "", 0, row, col])
    lua("return 1")


def state():
    return lua("local s=menu.state(); return s and {win=s.win,buf=s.buf,ctx=s.context,selected=s.items[s.selected] and s.items[s.selected].id}")


def screen():
    lua("vim.cmd('redraw!')")
    return "\n".join("".join(c for c, _ in row) for row in ui.grid)


try:
    ui.request("nvim_ui_attach", [80, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.o.mouse='a'; vim.o.mousetime=500; vim.o.laststatus=0; vim.o.showmode=false
      clipboard_lines={}; clipboard_type='v'
      vim.g.clipboard={name='menu-test',cache_enabled=0,
        copy={['+']=function(lines,kind) clipboard_lines=lines; clipboard_type=kind end,
              ['*']=function() end},
        paste={['+']=function() return {clipboard_lines,clipboard_type} end,
               ['*']=function() return {{},'v'} end}}
      vim.wo.number=false; vim.wo.relativenumber=false; vim.wo.signcolumn='no'; vim.wo.foldcolumn='0'
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'alpha beta gamma','second line','third line'})
      source=vim.api.nvim_get_current_win(); source_buf=vim.api.nvim_get_current_buf()
      require('ui_tools').setup({context_menu=true})
      menu=require('ui_tools.context_menu')
    """)
    screen()
    click(1, 4)
    assert state()["ctx"]["cursor"] == [2, 4], state()
    assert "Copy line" in screen(), screen()
    keys("<CR>")
    assert state() is None
    assert lua("return vim.fn.getreg('\"')") == "second line\n"
    assert lua("return vim.api.nvim_get_current_win()") == lua("return source")

    # Right click inside a live Visual selection keeps its original extent.
    lua("vim.api.nvim_win_set_cursor(source,{1,0})")
    keys("v4l")
    assert lua("return vim.fn.mode()") == "v"
    click(0, 2)
    assert state()["ctx"]["selection"]["text"] == ["alpha"], state()
    assert lua("return #vim.fn.getmatches(source)") == 1
    assert "Search selection" in screen()
    keys("<Esc>")
    assert lua("return vim.fn.mode()") == "v"
    assert lua("return #vim.fn.getmatches(source)") == 0
    click(0, 2)
    keys("<CR>")
    assert lua("return vim.fn.getreg('\"')") == "alpha"
    assert lua("return vim.api.nvim_buf_get_lines(source_buf,0,1,false)") == ["alpha beta gamma"]

    # Outside the selection, use the clicked text rather than the old selection.
    keys("v2l")
    click(1, 2)
    assert "selection" not in state()["ctx"], state()
    assert state()["ctx"]["cursor"] == [2, 2]
    keys("<Esc>")

    # Reversed exclusive and linewise selections preserve native yank semantics.
    lua("vim.o.selection='exclusive'; vim.api.nvim_win_set_cursor(source,{1,5})")
    keys("v5h")
    click(0, 2)
    selected = state()["ctx"]["selection"]["text"]
    keys("<CR>")
    assert lua("return vim.fn.getreg('\"',1,true)") == selected, selected
    lua("vim.o.selection='inclusive'; vim.api.nvim_win_set_cursor(source,{1,0})")
    keys("Vj")
    click(1, 7)
    assert state()["ctx"]["selection"]["type"] == "V"
    keys("<CR>")
    assert lua("return vim.fn.getregtype('\"')") == "V"

    # Blockwise text uses display columns, including tabs and wide characters.
    lua("vim.bo.tabstop=4; vim.api.nvim_buf_set_lines(source_buf,0,-1,false,{'\\t中alpha','\\t文bravo'}); vim.api.nvim_win_set_cursor(source,{1,1})")
    keys("<C-v>jl")
    click(0, 4)
    selected = state()["ctx"]["selection"]["text"]
    assert state()["ctx"]["selection"]["type"] == "\x16"
    keys("<CR>")
    assert lua("return vim.fn.getreg('\"',1,true)") == selected
    assert lua("return vim.fn.getregtype('\"')").startswith("\x16")
    lua("vim.o.virtualedit='all'; vim.api.nvim_buf_set_lines(source_buf,0,-1,false,{'\\talpha','\\tbravo'}); vim.api.nvim_win_set_cursor(source,{1,0})")
    keys("0l<C-v>lj")
    click(0, 1)
    assert state()["ctx"]["selection"]["text"] == ["  ", "  "], state()
    keys("<CR>")
    assert lua("return vim.fn.getreg('\"',1,true)") == ["  ", "  "]
    lua("vim.o.virtualedit=''")

    # Cancelling from Insert mode resumes at the clicked insertion point.
    lua("vim.api.nvim_buf_set_lines(source_buf,0,-1,false,{'alpha beta gamma','second line'}); vim.api.nvim_win_set_cursor(source,{1,0})")
    keys("i")
    click(0, 6)
    assert state()["ctx"]["mode"] == "i", state()
    keys("<Esc>")
    assert lua("return vim.fn.mode()") == "i"
    keys("X<Esc>")
    assert lua("return vim.api.nvim_buf_get_lines(source_buf,0,1,false)") == ["alpha Xbeta gamma"]
    lua("clipboard_lines={'ZZ'}; clipboard_type='v'")
    keys("i")
    click(0, 6)
    keys("<Down><CR>")
    assert lua("return vim.fn.mode()") == "i"
    keys("Q<Esc>")
    assert lua("return vim.api.nvim_buf_get_lines(source_buf,0,1,false)") == ["alpha ZZQXbeta gamma"]

    # Search treats punctuation literally and leaves the selection intact until chosen.
    lua("vim.api.nvim_buf_set_lines(source_buf,0,-1,false,{'a.* a.*'}); vim.api.nvim_win_set_cursor(source,{1,0})")
    keys("v2l")
    click(0, 1)
    keys("<Down><Down><CR>")
    assert lua("return vim.fn.getreg('/')") == "\\Va.*"
    assert lua("return vim.api.nvim_win_get_cursor(source)") == [1, 4]

    # Another split is the action target, even if the old window has a selection.
    lua("vim.cmd('vsplit'); other=vim.api.nvim_get_current_win(); vim.cmd('enew'); vim.api.nvim_buf_set_lines(0,0,-1,false,{'other split'}); vim.api.nvim_set_current_win(source)")
    keys("v2l")
    pos = lua("local p=vim.fn.screenpos(other,1,2); return {p.row-1,p.col-1}")
    click(*pos)
    assert state()["ctx"]["win"] == lua("return other"), state()
    assert "selection" not in state()["ctx"]
    keys("<CR>")
    assert lua("return vim.fn.getreg('\"')") == "other split\n"

    # Async insertion retains selection by item ID; stale handles do nothing.
    lua("""
      menu.setup({builtin=false,lsp=false})
      remove=menu.register('async',function(ctx,sink)
        pending=sink
        return {{id='a',label='First',action=function() picked='a' end},
          {id='b',label='Second',action=function() picked='b' end}}
      end)
      menu.open()
    """)
    keys("<Down>")
    assert state()["selected"] == "b"
    lua("old=pending; pending.update({{id='x',label='Inserted',action=function() end},{id='a',label='First',action=function() end},{id='b',label='Second ready',action=function() picked='ready' end}})")
    assert state()["selected"] == "b", state()
    assert "Second ready" in screen()
    keys("<CR>")
    assert lua("return picked") == "ready"
    lua("menu.open(); old.update({{id='stale',label='STALE'}})")
    assert "STALE" not in screen()
    keys("<Esc>")
    lua("remove()")

    # Mouse activation, disabled rows, screen edges and outside-click dismissal.
    lua("""
      remove=menu.register('click',function()
        return {{id='off',label='Unavailable',enabled=false,action=function() error('disabled') end},
          {id='ok',label='Run action',action=function(ctx) picked=ctx.buf end}}
      end)
      menu.open()
    """)
    assert state()["selected"] == "ok"
    pos = lua("local s=menu.state(); local p=vim.fn.screenpos(s.win,2,2); return {p.row-1,p.col-1}")
    click(*pos, button="left")
    assert state() is None
    assert lua("return picked") == lua("return vim.api.nvim_get_current_buf()")
    click(20, 78)
    assert state() is not None
    assert "Run action" in screen(), screen()
    cfg = lua("local c=vim.api.nvim_win_get_config(menu.state().win); return {c.row,c.col,c.height,c.width}")
    assert cfg[0] + cfg[2] + 2 <= 24 and cfg[1] + cfg[3] + 2 <= 80, cfg
    click(0, 0, button="left")
    assert state() is None

    # Manual window close and source edits retire the session without executing.
    lua("menu.open(); vim.api.nvim_win_close(menu.state().win,true)")
    assert state() is None
    lua("menu.open(); vim.api.nvim_buf_set_lines(menu.state().context.buf,0,1,false,{'changed'})")
    keys("<CR>")
    assert state() is None
    lua("remove(); require('ui_tools').disable()")
    assert lua("return vim.tbl_count(menu.errors)") == 0, lua("return menu.errors")
    print("context menu UI: mouse targets, visual selections, async updates and teardown passed")
finally:
    ui.close()
    signal.alarm(0)
