"""Inspect independent diagnostic and Git colors, clipping and explicit overrides."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Status semantics timed out")))
signal.alarm(25)
ui = Capture(os.environ.copy(), ["-u", "NONE", "-i", "NONE", "--noplugin"])


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def frame():
    lua("vim.wait(40); vim.cmd('redraw!')")
    lua("return true")
    return ui.grid[-2]


def check(label, expected, bg):
    row = frame()
    for start in range(len(row) - len(label) + 1):
        if "".join(c for c, _ in row[start:start + len(label)]) == label:
            attrs = [ui.attrs[a] for _, a in row[start:start + len(label)]]
            assert all(a.get("foreground") == expected and a.get("background") == bg for a in attrs), (label, attrs)
            return
    raise AssertionError("missing " + label + ": " + "".join(c for c, _ in row))


try:
    ui.request("nvim_ui_attach", [130, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd()); vim.opt.rtp:append(vim.fn.getcwd()..'/../theme-tools.nvim')
      t=require('theme_tools'); t.setup({persist=false,catppuccin=false,dracula=false,
        default='theme-tools-mocha',themes={'theme-tools-mocha','theme-tools-dracula'},icons={default='none'}})
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'sample'})
      vim.b.git_tools_status={added=2,changed=3,removed=4}
      local ds={}; for severity=1,4 do ds[#ds+1]={lnum=0,col=0,severity=severity,message='sample'} end
      vim.diagnostic.set(vim.api.nvim_create_namespace('Semantics'),0,ds)
      line=require('ui_tools.statusline')
      opts={globalstatus=true,icons=false,sections={a={},b={'diff','diagnostics'},c={},x={},y={},z={}}}
      line.setup(opts)
    """)
    for theme in ("theme-tools-mocha", "theme-tools-dracula"):
        ui.request("nvim_exec_lua", ["assert(t.set(...)); vim.wait(40)", [theme]])
        c = lua("return t.palette()")
        bg = lua("return vim.api.nvim_get_hl(0,{name='UiToolsStatusAlt',link=false}).bg")
        for label, color in (("+2", c["git"]["add"]), ("~3", c["git"]["change"]), ("-4", c["git"]["delete"]),
                             ("E1", c["diagnostic"]["error"]), ("W1", c["diagnostic"]["warn"]),
                             ("I1", c["diagnostic"]["info"]), ("H1", c["diagnostic"]["hint"])):
            check(label, int(color[1:], 16), bg)
    lua("opts.sections.b={{'diff',color='DiagnosticHint'},{'diagnostics',fmt=function(s) return '['..s..']' end}};line.setup(opts)")
    c = lua("return t.palette()")
    bg = lua("return vim.api.nvim_get_hl(0,{name='UiToolsStatusAlt',link=false}).bg")
    for label in ("+2", "~3", "-4"):
        check(label, int(c["diagnostic"]["hint"][1:], 16), bg)
    lua("opts.sections.b={{'diff',max_width=3}};line.setup(opts)")
    row = frame()
    assert "+2…" in "".join(c for c, _ in row)
    check("+2", int(c["git"]["add"][1:], 16), bg)
    assert lua("return vim.v.errmsg") == ""
finally:
    ui.close()
print("status semantics UI: independent colors, solid surfaces, theme changes, explicit colors, formatters and UTF-8 clipping passed")
