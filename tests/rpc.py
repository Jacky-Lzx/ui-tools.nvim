"""Minimal dependency-free MessagePack client for an attached Neovim UI."""
import os
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def pack(value):
    if value is None:
        return b"\xc0"
    if isinstance(value, bool):
        return b"\xc3" if value else b"\xc2"
    if isinstance(value, int):
        return b"\xd3" + struct.pack(">q", value)
    if isinstance(value, str):
        raw = value.encode()
        return b"\xdb" + struct.pack(">I", len(raw)) + raw
    if isinstance(value, (list, tuple)):
        return b"\xdd" + struct.pack(">I", len(value)) + b"".join(map(pack, value))
    if isinstance(value, dict):
        return b"\xdf" + struct.pack(">I", len(value)) + b"".join(pack(k) + pack(v) for k, v in value.items())
    raise TypeError(type(value))


def unpack(stream):
    def read(count):
        result = stream.read(count)
        if len(result) != count:
            raise EOFError("Neovim's RPC stream closed")
        return result

    def number(fmt):
        return struct.unpack(fmt, read(struct.calcsize(fmt)))[0]

    head = read(1)[0]
    if head < 0x80:
        return head
    if head >= 0xE0:
        return head - 256
    if 0xA0 <= head <= 0xBF:
        return read(head & 31).decode()
    if 0x90 <= head <= 0x9F:
        return [unpack(stream) for _ in range(head & 15)]
    if 0x80 <= head <= 0x8F:
        return {unpack(stream): unpack(stream) for _ in range(head & 15)}
    if head in (0xC0, 0xC2, 0xC3):
        return {0xC0: None, 0xC2: False, 0xC3: True}[head]
    formats = {0xCA: ">f", 0xCB: ">d", 0xCC: ">B", 0xCD: ">H", 0xCE: ">I", 0xCF: ">Q", 0xD0: ">b", 0xD1: ">h", 0xD2: ">i", 0xD3: ">q"}
    if head in formats:
        return number(formats[head])
    sizes = {0xC4: ">B", 0xC5: ">H", 0xC6: ">I", 0xD9: ">B", 0xDA: ">H", 0xDB: ">I", 0xDC: ">H", 0xDD: ">I", 0xDE: ">H", 0xDF: ">I", 0xC7: ">B", 0xC8: ">H", 0xC9: ">I"}
    if head in sizes:
        size = number(sizes[head])
        if head in (0xDC, 0xDD):
            return [unpack(stream) for _ in range(size)]
        if head in (0xDE, 0xDF):
            return {unpack(stream): unpack(stream) for _ in range(size)}
        if head in (0xC7, 0xC8, 0xC9):
            read(1)  # Extension type; API handle values are not used here.
        raw = read(size)
        return raw.decode() if head in (0xD9, 0xDA, 0xDB) else raw
    if 0xD4 <= head <= 0xD8:
        read(1)
        return read(1 << (head - 0xD4))
    raise ValueError(f"Unsupported MessagePack prefix: {head:#x}")


class Capture:
    def __init__(self, env, args=None):
        self.process = subprocess.Popen([env.get("NVIM_BIN", "nvim"), "--embed", "-n", *(args if args is not None else ["--clean"])], cwd=ROOT, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.serial = 0
        self.grid = []
        self.attrs = {0: {}}
        self.fg, self.bg = 0xCDD6F4, 0x1E1E2E

    def redraw(self, events):
        for name, *calls in events:
            for args in calls:
                if name == "default_colors_set":
                    self.fg, self.bg = args[:2]
                elif name == "hl_attr_define":
                    self.attrs[args[0]] = args[1]
                elif name == "grid_resize" and args[0] == 1:
                    self.grid = [[(" ", 0)] * args[1] for _ in range(args[2])]
                elif name == "grid_clear" and args[0] == 1:
                    self.grid = [[(" ", 0)] * len(self.grid[0]) for _ in self.grid]
                elif name == "grid_line" and args[0] == 1:
                    _, row, col, cells, *_ = args
                    highlight = 0
                    for cell in cells:
                        char = cell[0]
                        if len(cell) > 1:
                            highlight = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            self.grid[row][col] = (char, highlight)
                            col += 1
                elif name == "grid_scroll" and args[0] == 1:
                    _, top, bottom, left, right, rows, cols = args
                    original = [row[:] for row in self.grid]
                    for row in range(top, bottom):
                        for col in range(left, right):
                            source_row, source_col = row + rows, col + cols
                            self.grid[row][col] = original[source_row][source_col] if top <= source_row < bottom and left <= source_col < right else (" ", 0)

    def request(self, method, args):
        self.serial += 1
        serial = self.serial
        self.process.stdin.write(pack([0, serial, method, args]))
        self.process.stdin.flush()
        while True:
            message = unpack(self.process.stdout)
            if message[0] == 2 and message[1] == "redraw":
                self.redraw(message[2])
            elif message[0] == 1 and message[1] == serial:
                if message[2] is not None:
                    raise RuntimeError(message[2])
                return message[3]

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()
        self.process.stderr.close()

