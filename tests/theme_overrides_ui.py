"""Check theme-owned gutter and scrollbar colors in composited UI cells."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Theme ownership UI timed out")))
signal.alarm(20)
ui = Capture(os.environ.copy(), ["-u", "NONE", "-i", "NONE", "--noplugin"])


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def check(number, handle):
    lua("vim.cmd('redraw!')")
    lua("return true")
    digits = [ui.attrs[attr] for char, attr in ui.grid[0][:6] if char == "1"]
    assert digits and all(a.get("foreground") == number for a in digits), digits
    attr = ui.attrs[ui.grid[0][79][1]]
    assert attr.get("background", ui.bg) == handle, attr


try:
    ui.request("nvim_ui_attach", [80, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.opt.rtp:append(vim.fn.getcwd()..'/../theme-tools.nvim')
      vim.wo.wrap=false; vim.wo.number=true; vim.wo.signcolumn='no'; vim.o.laststatus=0
      local lines={}; for i=1,300 do lines[i]='source line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      t=require('theme_tools')
      t.setup({persist=false,catppuccin=false,dracula=false,icons={default='none'},
        default='theme-tools-mocha',themes={'theme-tools-mocha','theme-tools-dracula'}})
      opts={statuscolumn={layout={'number'},separator=' '},
        scrollbar={handle=' ',blend=100,search=false,diagnostics=false,cursor=false}}
      u=require('ui_tools'); u.setup(opts)
      vim.wait(60)
    """)
    check(0xB4BEFE, 0x000000)
    lua("u.setup(opts); t.refresh_palette(); vim.wait(60)")
    check(0xB4BEFE, 0x000000)
    lua("""
      original=require('theme_tools.colors').snapshot()
      assert(t.set('theme-tools-dracula')); vim.wait(60)
    """)
    check(0xF1FA8C, 0x3E4452)
    lua("require('theme_tools.colors').restore(original); vim.wait(60)")
    check(0xB4BEFE, 0x000000)
    lua("""
      vim.api.nvim_set_hl(0,'UiToolsCursorLineNr',{fg='#abcdef',bold=true})
      vim.api.nvim_set_hl(0,'UiToolsScrollbarHandle',{bg='#123456',blend=0})
      t.refresh_palette(); u.setup(opts); vim.wait(60)
    """)
    check(0xABCDEF, 0x123456)
finally:
    ui.close()
print("theme ownership UI: personal colors, setup, theme switches, preview restore and user overrides passed")
