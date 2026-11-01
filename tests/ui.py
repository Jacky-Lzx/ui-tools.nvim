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
    print("UI: visible indentation, independent splits, typing and cleanup passed")
finally:
    ui.close()
    signal.alarm(0)
