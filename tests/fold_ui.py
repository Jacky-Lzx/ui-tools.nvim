"""Exercise native folding input, preview focus, splits and initial insert text."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Fold UI timed out")))
signal.alarm(45)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def keys(value):
    ui.request("nvim_input", [value])
    lua("return 1")


def screen():
    lua("vim.wait(80); vim.cmd('redraw!')")
    return "\n".join("".join(char for char, _ in row) for row in ui.grid)


try:
    ui.request("nvim_ui_attach", [110, 28, {"rgb": True, "ext_linegrid": True}])
    lua("""
      api=vim.api; vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.hidden=true
      vim.o.shiftwidth=2; vim.o.splitkeep='screen'
      api.nvim_buf_set_lines(0,0,-1,false,{
        'local function outer()', '  if true then', "    print('你好')",
        "    print('second')", '  end', 'end', 'return outer'
      })
      vim.bo.filetype='lua'; vim.bo.modified=false
      vim.treesitter.start(0)
      ui=require('ui_tools'); fold=require('ui_tools.fold')
      ui.setup({fold={suffix='  ::%d'},statuscolumn={folds={levels=true,columns=2}}})
      source=api.nvim_get_current_win(); buffer=api.nvim_get_current_buf()
      vim.keymap.set('n','zK',function() fold.preview() end)
    """)
    screen()
    assert lua("return vim.wo.foldmethod=='expr' and vim.wo.foldlevel==2")
    keys("zm")
    text = screen()
    assert "if true then  ::3" in text and "print('你好')" not in text, text
    keys("zM")
    text = screen()
    assert "local function outer()  ::5" in text, text
    keys("zK")
    text = screen()
    assert "print('你好')" in text and "Lines 1–6" in text, text
    assert lua("return api.nvim_get_current_win()==source")
    lua("preview=vim.b.lsp_floating_preview")
    keys("zK")
    assert lua("return api.nvim_get_current_win()==preview")
    keys("<Esc>")
    screen()
    assert lua("return not api.nvim_win_is_valid(preview) and api.nvim_get_current_win()==source")
    keys(":vsplit<CR>")
    screen()
    lua("other=api.nvim_get_current_win()")
    assert lua("return vim.wo[other].foldlevel==2 and vim.wo[source].foldlevel==0")
    assert "print('你好')" in screen()
    keys("<C-w>l")
    assert lua("return api.nvim_get_current_win()==source and vim.fn.foldclosed(3)==1")
    keys("zR2zm2zr")
    screen()
    assert lua("return vim.wo.foldlevel==2 and vim.fn.foldclosed(3)==-1")
    keys(":split<CR>zM")
    screen()
    assert lua("return #api.nvim_tabpage_list_wins(0)==3")
    ui.request("nvim_ui_try_resize", [60, 20])
    screen()
    assert lua("local i=vim.fn.getwininfo(api.nvim_get_current_win())[1]; return vim.fn.strdisplaywidth(vim.fn.foldtextresult(1))<=math.max(0,i.width-i.textoff)")
    keys("<C-w>=")
    text = screen()
    assert "::5" in text, (text, lua("return {level=vim.wo.foldlevel,text=vim.wo.foldtext,method=vim.wo.foldmethod,cursor=api.nvim_win_get_cursor(0)}"))
    keys(":only<CR>:enew<CR>")

    # Finish initialization while the first editing burst enters Insert mode.
    lua("""
      api.nvim_buf_set_lines(0,0,-1,false,{'prefix '}); vim.bo.modified=false
      api.nvim_win_set_cursor(0,{1,#'prefix '}); vim.bo.filetype='lua'
      vim.cmd('startinsert!')
    """)
    keys("abcdefghij" * 50)
    screen()
    keys("<Esc>")
    assert lua("return api.nvim_get_current_line()") == "prefix " + "abcdefghij" * 50
    lua("""
      vim.cmd('enew!'); api.nvim_buf_set_lines(0,0,-1,false,{'outer','  中文 body','  more','last'})
      vim.bo.filetype='unknown_fold_fixture'; vim.bo.modified=false
    """)
    screen()
    assert lua("return vim.wo.foldmethod=='indent'")
    keys("zM")
    text = screen()
    assert "::" in text, text
    keys(":diffthis<CR>")
    screen()
    assert lua("return vim.wo.foldmethod=='diff'")
    keys(":diffoff<CR>")
    screen()
    assert lua("return vim.wo.foldmethod=='indent' and vim.wo.foldlevel~=99")
    lua("ui.disable()")
    assert lua("return not fold.enabled and vim.v.errmsg==''")
    print("fold native UI: nested keys, preview focus, splits, resize, insert burst, indent and diff passed")
finally:
    ui.close()
