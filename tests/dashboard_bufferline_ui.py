"""Retire only the startup placeholder after dashboard actions replace it."""
import os
from pathlib import Path
import signal
import tempfile
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Dashboard buffer lifecycle timed out")))
signal.alarm(40)


class Dashboard:
    def __init__(self, path, manual=False, globalstatus=False, statusline=True):
        env = dict(os.environ, UI_TOOLS_DASHBOARD_FILE=str(path))
        self.ui = Capture(env)
        self.ui.request("nvim_ui_attach", [100, 24, {"rgb": True, "ext_linegrid": True}])
        self.lua("""
          vim.opt.rtp:prepend(vim.fn.getcwd()); vim.o.hidden=true
          api=vim.api; source=api.nvim_get_current_buf(); target=vim.env.UI_TOOLS_DASHBOARD_FILE
          ui=require('ui_tools'); d=require('ui_tools.dashboard'); buffers=require('ui_tools.bufferline')
          function choose()
            local buf=vim.fn.bufadd(target); vim.bo[buf].buflisted=true
            api.nvim_set_current_buf(buf)
          end
        """)
        self.lua("""
          vim.o.laststatus=%s
          ui.setup({bufferline={auto_hide=-1},statusline=%s,dashboard={autostart=%s, keys={
            {key='f',desc='Find File',action=choose},
            {key='n',desc='New File',action='enew | startinsert'},
          }}})
          %s
          vim.wait(60)
        """ % (3 if globalstatus else 2,
               ("{globalstatus=true}" if globalstatus else "true") if statusline else "false",
               "false" if manual else "true", "d.open()" if manual else ""))
        assert self.lua("return d.state() ~= nil")
        assert self.lua("return vim.o.laststatus") == 0
        assert self.lua("return api.nvim_win_get_position(0)[1]+api.nvim_win_get_height(0)==vim.o.lines-vim.o.cmdheight")

    def lua(self, code):
        return self.ui.request("nvim_exec_lua", [code, []])

    def keys(self, value):
        self.ui.request("nvim_input", [value])
        self.lua("vim.wait(60)")

    def close(self):
        self.ui.close()


with tempfile.TemporaryDirectory(prefix="ui-tools-dashboard-buffers-") as directory:
    target = Path(directory) / "picked.txt"
    target.write_text("picked file\n")
    for case in ("picked", "close", "other_empty", "edited_source", "cleared_source", "visible_source", "manual", "new"):
        test = Dashboard(target, manual=case == "manual")
        try:
            if case == "close":
                test.lua("d.close(); vim.wait(60)")
                assert test.lua("return api.nvim_get_current_buf()==source and vim.bo[source].buflisted")
                assert test.lua("return vim.o.laststatus") == 2
                continue
            if case == "other_empty":
                test.lua("user_empty=api.nvim_create_buf(true,false)")
            if case in ("edited_source", "cleared_source"):
                test.lua("api.nvim_buf_set_lines(source,0,-1,false,{'keep my work'})")
            if case == "cleared_source":
                test.lua("api.nvim_buf_set_lines(source,0,-1,false,{''}); vim.bo[source].modified=false")
            if case == "visible_source":
                test.lua("source_win=api.nvim_open_win(source,false,{split='right',win=0})")
            if case == "new":
                test.keys("n")
                assert test.lua("return not api.nvim_buf_is_valid(source) and vim.fn.mode()=='i'")
                test.keys("my new text<Esc>")
                assert test.lua("return api.nvim_get_current_line()=='my new text' and vim.bo.modified")
                continue
            test.keys("f")
            assert test.lua("return d.state()==nil and api.nvim_get_current_line()=='picked file'")
            assert test.lua("return vim.o.laststatus") == 2
            if case in ("picked", "other_empty"):
                assert test.lua("return not api.nvim_buf_is_valid(source)"), test.lua("return buffers.items()")
            if case == "picked":
                assert test.lua("return #buffers.items()") == 1
                assert test.lua("return not buffers.render():find('No Name',1,true)")
            if case == "other_empty":
                assert test.lua("return api.nvim_buf_is_valid(user_empty) and vim.bo[user_empty].buflisted")
                assert test.lua("return #buffers.items()") == 2
            if case in ("edited_source", "cleared_source", "visible_source", "manual"):
                assert test.lua("return api.nvim_buf_is_valid(source) and vim.bo[source].buflisted")
            if case == "edited_source":
                assert test.lua("return vim.bo[source].modified and api.nvim_buf_get_lines(source,0,1,false)[1]=='keep my work'")
            if case == "visible_source":
                assert test.lua("return api.nvim_win_get_buf(source_win)==source")
        finally:
            test.close()
    for globalstatus in (False, True):
        for statusline in (False, True):
            test = Dashboard(target, globalstatus=globalstatus, statusline=statusline)
            try:
                # A provider refresh must not reclaim laststatus while the dashboard owns it.
                test.lua("require('ui_tools.statusline').refresh(); vim.wait(60)")
                assert test.lua("return vim.o.laststatus") == 0
                test.keys("f")
                assert test.lua("return vim.o.laststatus") == (3 if globalstatus else 2)
                if statusline:
                    assert test.lua("return vim.wo.statusline:find('ui_tools.statusline',1,true) ~= nil")
                test.lua("d.open(); vim.o.laststatus=1; d.close(); vim.wait(60)")
                assert test.lua("return vim.o.laststatus") == 1
                test.lua("d.open(); ui.disable(); vim.wait(60)")
                assert test.lua("return vim.o.laststatus") == 1
            finally:
                test.close()
    print("dashboard buffer UI: picked/new file retires startup placeholder; user buffers, edits, splits and close are preserved")
