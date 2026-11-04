"""Drive the real terminal path; optionally load a user's unchanged configuration.

UI_TOOLS_CONFIG=/path/to/nvim/init.lua python3 tests/annotations_pty.py
"""
import fcntl
import json
import os
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="ui-tools-annotations-") as directory:
    temp = Path(directory)
    fixture = temp / "annotations.lua"
    fixture.write_text('-- TODO: startup #123456\nlocal s = "TODO: ordinary string"\n-- plain\n')
    init = temp / "init.lua"
    init.write_text(r'''
      local root, temp, config = vim.env.UI_TOOLS_ROOT, vim.env.UI_TOOLS_TEMP, vim.env.UI_TOOLS_CONFIG
      if config and config ~= '' then
        vim.opt.rtp:prepend(vim.fs.dirname(config))
        dofile(config)
      else
        vim.cmd('syntax on')
        vim.o.termguicolors=true
      end
      vim.opt.rtp:prepend(root)
      vim.api.nvim_create_autocmd('VimEnter',{once=true,callback=function()
        vim.defer_fn(function()
          local ok, err = pcall(function()
            local old=package.loaded['nvim-highlight-colors']; if old then old.turnOff() end
            old=package.loaded['todo-comments']; if old then old.disable() end
            local ui=require('ui_tools')
            local opts=vim.deepcopy(ui.options or {})
            opts.colors=true; opts.todo=true
            ui.setup(opts)
            local buf=vim.api.nvim_get_current_buf()
            local timer=vim.uv.new_timer()
            timer:start(0,40,vim.schedule_wrap(function()
              if not vim.api.nvim_buf_is_valid(buf) then return end
              local colors, todo=require('ui_tools.colors'),require('ui_tools.todo')
              local data={
                mode=vim.fn.mode(), lines=vim.api.nvim_buf_get_lines(buf,0,-1,false),
                colors=#vim.api.nvim_buf_get_extmarks(buf,colors.ns,0,-1,{}),
                signs=#vim.api.nvim_buf_get_extmarks(buf,todo.ns,0,-1,{type='sign'}),
                ts=vim.treesitter.highlighter.active[buf]~=nil,
                errors=require('ui_tools.render').errors,
              }
              vim.fn.writefile({vim.json.encode(data)},temp..'/state.json')
            end))
          end)
          if not ok then vim.fn.writefile({tostring(err)},temp..'/error') end
        end,250)
      end})
    ''')
    env = os.environ.copy()
    env.update({"TERM": "xterm-256color", "UI_TOOLS_ROOT": str(ROOT), "UI_TOOLS_TEMP": directory,
                "NVIM_SMOKE_TEST": "1", "NVIM_LOG_FILE": str(temp / "nvim.log"),
                "NVIM_LAZY_LOCKFILE": str(temp / "lazy-lock.json"),
                "XDG_STATE_HOME": str(temp / "state"), "XDG_CACHE_HOME": str(temp / "cache")})
    config = env.get("UI_TOOLS_CONFIG")
    if config and (Path(config).parent / "lazy-lock.json").is_file():
        shutil.copyfile(Path(config).parent / "lazy-lock.json", temp / "lazy-lock.json")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
    process = subprocess.Popen([env.get("NVIM_BIN", "nvim"), "-n", "-i", "NONE", "-u", str(init), str(fixture)],
                               cwd=ROOT, env=env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    output = bytearray()

    def wait_for(predicate, timeout=6):
        deadline = time.monotonic() + timeout
        state = None
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError:
                    pass
            if (temp / "error").exists():
                raise AssertionError((temp / "error").read_text())
            try:
                state = json.loads((temp / "state.json").read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                continue
            if predicate(state):
                return state
        raise AssertionError(f"PTY state did not settle: {state}; tail={output[-1200:]!r}")

    try:
        initial = wait_for(lambda s: s["colors"] == 1 and s["signs"] == 1)
        os.write(master, b"3GA TODO: live #abcdef")
        wait_for(lambda s: s["mode"] == "i" and s["colors"] == 2 and s["signs"] == 2)
        # A continuous editing burst must keep the annotation scheduler working.
        os.write(master, b" ")
        for _ in range(20):
            os.write(master, b"x" * 10)
            select.select([master], [], [], 0.01)
        os.write(master, b" #00ff00")
        wait_for(lambda s: s["mode"] == "i" and s["colors"] == 3)
        os.write(master, b"\x1b:lua require('ui_tools').toggle('todo')\r")
        wait_for(lambda s: s["signs"] == 0 and s["colors"] == 3)
        os.write(master, b":lua require('ui_tools').toggle('todo')\r")
        wait_for(lambda s: s["signs"] == 2)
        os.write(master, b":lua require('ui_tools').disable()\r")
        final = wait_for(lambda s: s["colors"] == 0 and s["signs"] == 0)
        assert not final["errors"], final
        assert "■".encode() in output, "The terminal never rendered a color swatch"
        assert b"38;2;18;52;86" in output, "The terminal never emitted the expected truecolor RGB"
        label = "configured" if config else "clean"
        print(f"annotations PTY ({label}): real terminal RGB, insert updates, 200-character burst, independent toggles and cleanup passed; Tree-sitter={initial['ts']}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        os.close(master)
