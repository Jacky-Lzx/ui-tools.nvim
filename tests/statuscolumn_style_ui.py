"""Exercise gutter colors, numhl-only Git marks and cursor fold scopes on a UI."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Gutter style UI timed out")))
signal.alarm(20)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def frame():
    lua("vim.cmd('redraw!')")
    ui.request("nvim_eval", ["1"])


def attrs(row, col):
    frame()
    return ui.attrs[ui.grid[row][col][1]]


try:
    ui.request("nvim_ui_attach", [90, 28, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.wo.number=true; vim.wo.relativenumber=true; vim.wo.foldmethod='manual'
      vim.wo.signcolumn='yes:1'; vim.wo.foldcolumn='0'
      local lines={}; for i=1,100 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      for name,color in pairs({UiToolsLineNr=0x444444,UiToolsCursorLineNr=0xdddddd,
        UiToolsFoldSeparator=0x333333,UiToolsFoldScope=0x888888,FoldColumn=0xaaaaaa,
        GitToolsAdd=0x00ff00,GitToolsChange=0x0000ff,GitToolsDelete=0xff0000}) do
        vim.api.nvim_set_hl(0,name,{fg=color,bold=name=='UiToolsCursorLineNr'})
      end
      require('ui_tools').setup({statuscolumn={slot_width=2,separator=' ',git_numbers=true,
        layout={{'diagnostic','sign','mark'},'number','fold'},folds={levels=true,scope=true}}})
      stc=require('ui_tools.statuscolumn')
      git=vim.api.nvim_create_namespace('GitToolsStyle')
      for index,kind in ipairs({'Add','Change','Delete'}) do
        vim.api.nvim_buf_set_extmark(0,git,index,0,{number_hl_group='GitTools'..kind,priority=6})
      end
      -- A glyph-only provider also works; its number-specific color wins when present.
      vim.api.nvim_buf_set_extmark(0,git,4,0,{sign_text='+',sign_hl_group='GitToolsAdd'})
      vim.api.nvim_buf_set_extmark(0,git,5,0,{sign_text='+',sign_hl_group='GitToolsAdd',number_hl_group='GitToolsDelete'})
      diagnostic=vim.api.nvim_create_namespace('diagnostic.signs.Style')
      vim.api.nvim_buf_set_extmark(0,diagnostic,1,0,{sign_text='E',sign_hl_group='DiagnosticSignError'})
      for _,range in ipairs({{2,18},{4,8},{11,15}}) do
        vim.cmd(range[1]..','..range[2]..'fold'); vim.cmd('normal! zR')
      end
      vim.api.nvim_win_set_cursor(0,{5,0}); stc.refresh()
    """)
    frame()
    assert lua("return vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff") == 9
    assert ui.grid[1][0][0] == "E", "Git number mark hid diagnostic"
    for row, color in [(1, 0x00FF00), (2, 0x0000FF), (3, 0xFF0000), (4, 0x00FF00), (5, 0xFF0000)]:
        assert attrs(row, 4).get("foreground") == color, (row, attrs(row, 4))
    assert attrs(4, 4).get("bold"), "Current Git line lost emphasis"
    assert attrs(1, 4).get("background", ui.bg) == ui.bg, "Git number lost transparency"
    assert attrs(6, 4).get("foreground") == 0x444444
    assert ui.grid[1][6][0] == "▾" and ui.grid[1][8][0] == " "
    assert ui.grid[1][9][0] == "l", "Gutter padding displaced source text"
    assert attrs(4, 6).get("foreground") == 0x333333, "Ancestor continuation too bright"
    assert attrs(4, 7).get("foreground") == 0x888888, "Current fold continuation not highlighted"
    assert attrs(11, 7).get("foreground") == 0x333333, "Adjacent fold borrowed cursor scope"
    ui.request("nvim_input", ["12G"])
    lua("return 1")
    lua("""
      assert(vim.wait(2000, function()
        local scope=stc.scopes[vim.api.nvim_get_current_win()]
        return scope and scope.start==11
      end, 10), 'Cursor movement did not refresh fold scope')
    """)
    assert attrs(4, 7).get("foreground") == 0x333333
    assert attrs(11, 7).get("foreground") == 0x888888, "Cursor movement did not update scope"
    lua("vim.api.nvim_buf_clear_namespace(0,git,0,-1); stc.refresh()")
    assert attrs(1, 4).get("foreground") == 0x444444, "Cleared Git color remained"
    assert attrs(11, 4).get("foreground") == 0xDDDDDD and attrs(11, 4).get("bold")
    lua("vim.cmd('vsplit'); vim.api.nvim_win_set_cursor(0,{5,0}); stc.refresh()")
    assert lua("""
      local scopes={}; for _,scope in pairs(stc.scopes) do scopes[scope.start]=true end
      return scopes[4] and scopes[11] or false
    """), "Splits shared a fold scope"
    lua("require('ui_tools').disable()")
    assert lua("return next(stc.scopes)==nil"), "Disabled scopes were retained"
    print("gutter style UI: transparent Git numbers, diagnostics, cursor emphasis, scope movement and splits passed")
finally:
    ui.close()
    signal.alarm(0)
