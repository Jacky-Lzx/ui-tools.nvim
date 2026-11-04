"""Inspect every flushed startup frame, including the frame before scheduled work."""
import os
from pathlib import Path
import signal
import tempfile
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Dashboard startup timed out")))
signal.alarm(20)


class StartupCapture(Capture):
    def __init__(self, env, args):
        self.frames = []
        super().__init__(env, args)

    def redraw(self, events):
        for event in events:
            super().redraw([event])
            if event[0] == "flush":
                self.frames.append("\n".join("".join(c for c, _ in row) for row in self.grid))


with tempfile.TemporaryDirectory(prefix="ui-tools-startup-") as directory:
    init = Path(directory) / "init.lua"
    init.write_text("""
vim.opt.rtp:prepend(vim.fn.getcwd())
require('ui_tools').setup({dashboard={header='CUSTOM START SCREEN',footer=false},statusline=true})
-- Force a frame at the startup boundary, before any scheduled callbacks run.
vim.api.nvim_create_autocmd('VimEnter', {callback=function() vim.cmd('redraw!') end})
""")
    ui = StartupCapture(os.environ.copy(), ["-u", str(init), "-i", "NONE", "--noplugin"])
    try:
        ui.request("nvim_ui_attach", [100, 30, {"rgb": True, "ext_linegrid": True}])
        ui.request("nvim_exec_lua", ["vim.wait(50); return 1", []])
        assert all("Nvim is open source" not in frame and "NVIM v" not in frame for frame in ui.frames), ui.frames
        assert any("CUSTOM START SCREEN" in frame for frame in ui.frames), ui.frames
        assert ui.request("nvim_exec_lua", ["return vim.o.laststatus", []]) == 0
        assert ui.request("nvim_exec_lua", ["return vim.o.ruler", []]) is False
        assert all("[Scratch]" not in frame and "[No Name]" not in frame and "NORMAL" not in frame
                   for frame in ui.frames if "CUSTOM START SCREEN" in frame), ui.frames
        print("dashboard startup: custom screen renders without a builtin intro frame")
    finally:
        ui.close()
