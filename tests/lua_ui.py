"""Run Lua assertions with a real UI and verify a clean Neovim exit.

Changing 'columns' in a headless process can leave Neovim 0.12's native
tabline click table at the old screen width. Resize through the UI instead.
"""
import argparse
import os
import signal
import tempfile
from rpc import Capture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, default=24)
    args = parser.parse_args()
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError(f"{args.suite} timed out")))
    signal.alarm(60)
    with tempfile.TemporaryDirectory(prefix="ui-tools-lua-") as directory:
        env = os.environ.copy()
        env.update({
            "XDG_STATE_HOME": directory + "/state",
            "XDG_CACHE_HOME": directory + "/cache",
            "XDG_DATA_HOME": directory + "/data",
            "NVIM_LOG_FILE": directory + "/nvim.log",
        })
        run(args, env)


def run(args, env):
    ui = Capture(env, ["-u", "NONE", "-i", "NONE", "--noplugin"])
    try:
        ui.request("nvim_ui_attach", [80, 24, {"rgb": True, "ext_linegrid": True}])
        ui.request("nvim_ui_try_resize", [args.width, args.height])
        ui.request("nvim_exec_lua", ["dofile(...)", [args.suite]])
        # Memory corruption may surface only during exit, after every Lua
        # assertion passed. Do not terminate the process before checking it.
        try:
            ui.request("nvim_command", ["qa!"])
        except EOFError:
            pass
        code = ui.process.wait(timeout=5)
        assert code == 0, f"{args.suite}: Neovim exited {code}: {ui.process.stderr.read().decode(errors='replace')}"
        print(f"{args.suite}: Lua assertions and clean UI exit passed ({args.width}x{args.height})")
    finally:
        ui.close()
        signal.alarm(0)


if __name__ == "__main__":
    main()
