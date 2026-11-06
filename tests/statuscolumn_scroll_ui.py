"""Check every flushed scroll frame, including newly visible gutter signs/colors."""
import os
import re
import signal
import time
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Gutter scroll UI timed out")))
signal.alarm(25)


class ScrollCapture(Capture):
    def __init__(self, *args):
        self.frames = []
        super().__init__(*args)

    def redraw(self, events):
        for event in events:
            super().redraw([event])
            if event[0] == "flush":
                rows = []
                for row in self.grid:
                    text = "".join(char for char, _ in row)
                    match = re.search(r"line (\d+)", text)
                    if not match:
                        continue
                    number = int(match[1])
                    colors = [self.attrs[hl].get("foreground", self.fg)
                              for char, hl in row[:match.start()] if char.isdigit()]
                    rows.append((number, colors, row[0][0]))
                if rows:
                    self.frames.append(rows)


ui = ScrollCapture(os.environ.copy(), ["-u", "NONE", "-i", "NONE", "--noplugin"])


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def settle():
    # Read all queued redraw notifications, without forcing an extra redraw.
    time.sleep(0.08)
    lua("return 1")


def check_frames(label):
    assert ui.frames, (label, "No screen frames received")
    for frame in ui.frames:
        for number, colors, sign in frame:
            expected = [0x00FF00, 0x0000FF, 0xFF0000][(number - 1) % 3]
            assert colors and all(color == expected for color in colors), (label, number, colors)
            assert sign == ("E" if number % 7 == 0 else " "), (label, number, sign)


try:
    ui.request("nvim_ui_attach", [100, 30, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.wo.number=true; vim.wo.relativenumber=false; vim.wo.wrap=false
      vim.wo.signcolumn='yes:1'; vim.wo.foldmethod='manual'
      vim.o.scrolloff=5; vim.o.laststatus=0
      local lines={}; for i=1,500 do lines[i]='line '..i end
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      vim.api.nvim_set_hl(0,'UiToolsLineNr',{fg=0x444444})
      vim.api.nvim_set_hl(0,'UiToolsCursorLineNr',{fg=0xdddddd})
      local git=vim.api.nvim_create_namespace('GitToolsScrollTest')
      local diagnostic=vim.api.nvim_create_namespace('diagnostic.signs.ScrollTest')
      for index,kind in ipairs({'Add','Change','Delete'}) do
        vim.api.nvim_set_hl(0,'GitTools'..kind,{fg=({0x00ff00,0x0000ff,0xff0000})[index]})
      end
      for line=1,500 do
        local kind=({'Add','Change','Delete'})[(line-1)%3+1]
        vim.api.nvim_buf_set_extmark(0,git,line-1,0,{number_hl_group='GitTools'..kind,priority=6})
        if line%7==0 then
          vim.api.nvim_buf_set_extmark(0,diagnostic,line-1,0,{sign_text='E',sign_hl_group='DiagnosticSignError'})
        end
      end
      stc=require('ui_tools.statuscolumn')
      stc.setup({slot_width=1,separator=' ',git_numbers=true,
        folds={levels=true,columns=2,scope=true},
        layout={'diagnostic',{'sign','mark'},'number','fold'},git_patterns={'GitTools'}})
      function reset_scroll()
        vim.fn.winrestview({topline=100,lnum=110,col=0})
        stc.refresh()
      end
      reset_scroll()
    """)
    settle()
    for keys in ("<C-d>", "<C-u>", "<C-d><C-d><C-u>"):
        lua("reset_scroll()")
        settle()
        ui.frames = []
        ui.request("nvim_input", [keys])
        settle()
        check_frames(keys)
        expected_top = 86 if keys == "<C-u>" else 114
        assert lua("return vim.fn.line('w0')") == expected_top, (keys, "Native scroll position changed")
    print("gutter scroll UI: every Ctrl-D/U and burst frame preserves Git number colors and diagnostics")
finally:
    ui.close()
    signal.alarm(0)
