"""Annotation timers must preserve every native incremental-search frame."""
import os
import signal
from rpc import Capture


class SearchCapture(Capture):
    def __init__(self):
        super().__init__(os.environ.copy())
        self.current_row = None
        self.checked = 0
        self.bad = []

    def redraw(self, events):
        for event in events:
            super().redraw([event])
            if event[0] != "flush" or self.current_row is None:
                continue
            self.checked += 1
            source = []
            for row, cells in enumerate(self.grid):
                text = ''.join(c[0] for c in cells)
                col = text.find('normalized')
                if 10 < row < 30 and col >= 0:
                    source.append((row, col))
            for index, (row, col) in enumerate(source):
                char, attr = self.grid[row][col]
                expected = 0x00ff00 if index == self.current_row else 0xff0000
                actual = self.attrs.get(attr, {}).get("background")
                if char != "n" or actual != expected:
                    self.bad.append((row, char, actual))


def main():
    def timeout(*_):
        raise TimeoutError("annotation search UI timed out")

    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(20)
    ui = SearchCapture()

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def keys(value):
        ui.request("nvim_input", [value])
        lua("vim.wait(40)")

    try:
        ui.request("nvim_ui_attach", [100, 36, {"rgb": True, "ext_linegrid": True}])
        lua("""
            vim.opt.rtp:prepend(vim.fn.getcwd())
            vim.o.hlsearch,vim.o.incsearch=true,true
            vim.o.laststatus,vim.o.showtabline,vim.o.scrolloff=0,0,0
            vim.wo.number,vim.wo.relativenumber=false,false
            vim.wo.signcolumn='no'
            vim.api.nvim_set_hl(0,'Search',{bg=0xff0000})
            vim.api.nvim_set_hl(0,'IncSearch',{bg=0x00ff00})
            vim.api.nvim_set_hl(0,'CurSearch',{bg=0x0000ff})
            local lines={};for i=1,30 do lines[i]='' end
            lines[16],lines[21]='normalized -- TODO: #12ab34','normalized -- TODO: #12ab34'
            vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
            colors=require('ui_tools.colors');colors.setup({refresh=1,style='foreground'})
            todo=require('ui_tools.todo');todo.setup({refresh=1,comments_only=false})
            require('ui_tools.statuscolumn').setup()
            require('ui_tools.statusline').setup()
            require('ui_tools.winbar').setup()
            require('ui_tools.bufferline').setup({auto_hide=2})
            require('ui_tools.indent').setup()
            refreshes=0
            for _,m in ipairs({colors,todo}) do
                local old=m.on_refresh
                m.on_refresh=function() refreshes=refreshes+1;if old then old() end end
            end
            local b=vim.api.nvim_create_buf(false,true)
            vim.api.nvim_open_win(b,false,{relative='editor',row=3,col=10,width=30,height=1,style='minimal'})
            vim.api.nvim_create_autocmd('CmdlineChanged',{callback=function()
                colors.queue();todo.queue()
                vim.schedule(function()
                    require('ui_tools.statuscolumn').refresh()
                    require('ui_tools.statusline').update()
                    require('ui_tools.winbar').refresh()
                    require('ui_tools.bufferline').refresh()
                    require('ui_tools.util').redraw()
                end)
            end})
        """)
        for kind in ("/", "?"):
            for ending in ("<CR>", "<Esc>"):
                lua("vim.api.nvim_win_set_cursor(0,{" + ("1" if kind == "/" else "30") + ",0})")
                keys(kind + "norm")
                before = lua("return refreshes")
                ui.current_row = 0 if kind == "/" else 1
                ui.checked, ui.bad = 0, []
                for key in ("a", "l", "i", "z", "e", "d", "<BS>", "<BS>", "ed"):
                    keys(key)
                ui.current_row = None
                assert ui.checked > 0, "no incremental-search frames captured"
                assert not ui.bad, ui.bad[:8]
                assert lua("return refreshes") == before, "annotations refreshed during search"
                keys(ending)
                assert lua("return refreshes") > before, "annotations did not resume after search"
                assert lua("return #vim.api.nvim_buf_get_extmarks(0,colors.ns,0,-1,{})") == 2
                assert lua("return #vim.api.nvim_buf_get_extmarks(0,todo.ns,0,-1,{})") > 0
        print("search UI: / and ? keep stable colors through typing, deletion and timers; annotations resume after confirm/cancel")
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == "__main__":
    main()
