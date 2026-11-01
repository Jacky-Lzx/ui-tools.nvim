"""Exercise actual rendered cells, splits, typing and renderer cleanup."""
import os
import signal
from rpc import Capture


signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("UI test timed out")))
signal.alarm(45)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def screen():
    lua("vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])
    return "\n".join("".join(cell[0] for cell in row) for row in ui.grid)


try:
    ui.request("nvim_ui_attach", [100, 30, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.o.laststatus = 0; vim.o.showtabline = 0; vim.o.ruler = false
      vim.bo.shiftwidth = 2; vim.bo.tabstop = 4
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'function main()', '  if ready then', '    run()', '', '    done()', '  end', 'end'
      })
      vim.api.nvim_win_set_cursor(0, {3, 4})
      tools = require('ui_tools'); tools.setup({indent = true})
    """)
    rendered = screen()
    assert "│" in rendered and "run()" in rendered, rendered
    lua("vim.cmd('vsplit'); vim.api.nvim_win_set_cursor(0, {6, 2})")
    assert "done()" in screen()
    ui.request("nvim_input", ["A -- typing<Esc>"])
    lua("vim.wait(50)")
    assert "typing" in screen()
    lua("tools.disable()")
    rendered = screen()
    # The native split separator also uses │; inspect the text columns only.
    text_cells = "".join(line[:45] + line[52:] for line in rendered.splitlines())
    assert "│" not in text_cells and "╰" not in text_cells, rendered
    assert lua("return next(require('ui_tools.render').errors) == nil")
    lua("""
      vim.cmd('only'); vim.wo.number = true; vim.wo.relativenumber = true
      vim.wo.signcolumn = 'yes:2'; vim.wo.foldcolumn = '1'; vim.wo.foldmethod = 'manual'
      vim.cmd('2,5fold'); vim.api.nvim_win_set_cursor(0, {1,0})
      tools.setup({statuscolumn = true})
      local ns = vim.api.nvim_create_namespace('GitToolsUITest')
      vim.api.nvim_buf_set_extmark(0, ns, 0, 0, {sign_text = '+', sign_hl_group = 'DiffAdd'})
      vim.diagnostic.set(vim.api.nvim_create_namespace('UiTestDiagnostics'), 0, {{lnum=0,col=0,message='test',severity=1}})
      require('ui_tools.statuscolumn').refresh()
      vim.wait(60)
    """)
    rendered = screen()
    assert "+" in rendered.splitlines()[0] and "▸" in rendered, rendered
    folded = next((r, line.index("▸")) for r, line in enumerate(rendered.splitlines()) if "▸" in line)
    ui.request("nvim_input_mouse", ["left", "press", "", 0, folded[0], folded[1]])
    ui.request("nvim_input_mouse", ["left", "release", "", 0, folded[0], folded[1]])
    lua("vim.wait(60)")
    assert lua("return vim.fn.foldclosed(2)") == -1, screen()
    assert "run()" in screen()
    lua("tools.disable()")
    assert lua("return vim.wo.statuscolumn") == ""
    lua("""
      vim.wo.number=false; vim.wo.relativenumber=false; vim.wo.signcolumn='no'; vim.wo.foldcolumn='0'
      vim.wo.wrap=false; vim.cmd('normal! zE'); vim.diagnostic.reset()
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'a','中文',string.rep('x',100)})
      tools.setup({guide={columns={9},char='┆'}})
      vim.api.nvim_win_set_cursor(0,{1,0})
    """)
    screen()
    assert ui.grid[0][8][0] == "┆", screen()
    assert ui.grid[1][8][0] == "┆", screen()
    assert ui.grid[2][8][0] == "x", screen()
    lua("""
      vim.o.sidescrolloff=0; vim.api.nvim_win_set_cursor(0,{3,30})
      vim.fn.winrestview({lnum=3,col=30,topline=1,leftcol=5})
    """)
    screen()
    assert ui.grid[0][3][0] == "┆", screen()
    lua("""
      vim.api.nvim_set_hl(0,'UiToolsFlash',{bg='#ff0000'})
      flash = tools.flash({line=1,timeout=0})
    """)
    screen()
    assert ui.attrs[ui.grid[0][0][1]].get('background') == 0xff0000
    lua("flash:cancel(); tools.disable()")
    assert "┆" not in screen()
    assert ui.attrs[ui.grid[0][0][1]].get('background') != 0xff0000
    assert lua("return next(require('ui_tools.render').errors) == nil")
    print("UI: indentation, splits, typing, sign layout, fold clicks, Unicode/scroll guides and feedback passed")
finally:
    ui.close()
    signal.alarm(0)
