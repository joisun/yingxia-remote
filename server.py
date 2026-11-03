#!/usr/bin/env python3
"""Serve a LAN remote for Yingxia's frontmost Mac window."""

import json
import os
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


PORT = 8765
PAGE = (Path(__file__).parent / "index.html").read_bytes()
ICONS = Path(__file__).parent / "icons"
TARGET_BUNDLE_ID = "com.jo32.yingxia.mac"
KEY_CODES = {
    "up": 126,
    "down": 125,
    "left": 123,
    "right": 124,
    "select": 36,
    "back": 53,
    "play": 49,
    "fullscreen": 3,
    "mute": 46,
}
VOLUME_COMMANDS = {"volume_up": 5, "volume_down": -5}
HELPER = None
HIGHLIGHT = None
selection = None
menu_open = False
selection_lock = threading.Lock()


class RemoteHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path.startswith("/icons/"):
            name = url.path.removeprefix("/icons/")
            icon = ICONS / name
            if name != Path(name).name or icon.suffix != ".svg" or not icon.is_file():
                self.send_error(404)
                return
            body = icon.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/svg+xml")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if url.path == "/status":
            self.send_text(200, "已连接")
            return
        if url.path != "/":
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def do_POST(self):
        url = urlsplit(self.path)
        if url.path != "/command":
            self.send_error(404)
            return
        expected_host = f"{self.server.server_address[0]}:{PORT}"
        if self.headers.get("Host") != expected_host:
            self.send_text(403, "请通过服务打印的地址访问遥控器")
            return
        origin = self.headers.get("Origin")
        if origin and origin != f"http://{expected_host}":
            self.send_text(403, "仅允许从遥控器页面操作")
            return
        if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
            self.send_text(415, "仅接受 JSON 指令")
            return

        if self.headers.get("Content-Length", "").isdigit() is False:
            self.send_error(400)
            return
        length = int(self.headers["Content-Length"])
        if length > 100:
            self.send_error(413)
            return

        try:
            request = json.loads(self.rfile.read(length))
            command = request["command"]
            mode = request["mode"]
            if mode not in ("browse", "player"):
                raise ValueError("invalid mode")
            if command in VOLUME_COMMANDS:
                self.send_volume(VOLUME_COMMANDS[command])
                return
            if mode == "player" and command not in KEY_CODES and command != "activate":
                raise ValueError("invalid command")
            if mode == "browse" and command not in ("up", "down", "left", "right", "select", "back", "context", "activate"):
                raise ValueError("invalid command")
        except (ValueError, KeyError, TypeError):
            self.send_error(400)
            return

        if command == "activate":
            self.send_activate(mode)
            return
        if mode == "browse":
            self.send_browse_command(command)
            return

        target = subprocess.run([HELPER, "activate", "player"], capture_output=True, text=True, timeout=5)
        if target.returncode:
            self.send_text(409, target.stderr.strip() or "没有正在播放的窗口")
            return
        update_highlight(None)
        key_code = KEY_CODES["play"] if command == "select" else KEY_CODES[command]
        result = run_key(key_code)
        if result.returncode:
            if "(9001)" in result.stderr:
                self.send_response(409)
                message = "请先将映匣窗口切到 Mac 前台"
            else:
                self.send_response(500)
                message = result.stderr.strip() or "无法发送按键；请检查辅助功能权限。"
        else:
            self.send_response(200)
            message = "ok"
        body = message.encode("utf-8")
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, status, message):
        body = message.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_browse_command(self, command):
        global selection, menu_open
        with selection_lock:
            if menu_open and command != "context":
                result = run_key(KEY_CODES[command])
                if result.returncode:
                    self.send_text(409, result.stderr.strip() or "无法操作菜单")
                    return
                if command in ("select", "back"):
                    menu_open = False
                self.send_text(200, "菜单操作：" + command)
                return
            if command == "back":
                arguments = ["back"]
            else:
                x, y = selection if selection is not None else ("none", "none")
                action = {"select": "press", "context": "context"}.get(command, "move")
                arguments = [action, command, str(x), str(y)]
            result = subprocess.run([HELPER, *arguments], capture_output=True, text=True, timeout=10)
            if result.returncode:
                self.send_response(409)
                message = result.stderr.strip() or "无法操作映匣主窗口"
            else:
                self.send_response(200)
                target = json.loads(result.stdout)
                selection = (target["x"], target["y"]) if command in ("up", "down", "left", "right") else None
                if command == "context":
                    menu_open = True
                update_highlight(target if selection else None)
                label = target["label"]
                if len(label) > 24:
                    label = label[:24] + "…"
                verb = "已选中" if selection else ("已发送右键" if command == "context" else "已操作")
                message = f"{verb}：{label}"
        body = message.encode("utf-8")
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_activate(self, mode):
        global selection, menu_open
        result = subprocess.run([HELPER, "activate", mode], capture_output=True, text=True, timeout=5)
        left_fullscreen = False
        if mode == "browse" and "全屏播放器正在遮挡主窗口" in result.stderr:
            player = subprocess.run([HELPER, "activate", "player"], capture_output=True, text=True, timeout=5)
            if player.returncode == 0 and run_key(KEY_CODES["back"]).returncode == 0:
                time.sleep(0.45)
                result = subprocess.run([HELPER, "activate", "browse"], capture_output=True, text=True, timeout=5)
                left_fullscreen = result.returncode == 0
        if result.returncode:
            self.send_text(409, result.stderr.strip() or "无法切换映匣窗口")
            return
        selection = None
        menu_open = False
        update_highlight(None)
        message = result.stdout.strip()
        if left_fullscreen:
            message += "（已退出播放全屏）"
        self.send_text(200, message)

    def send_volume(self, change):
        script = (
            'set currentVolume to output volume of (get volume settings)\n'
            f'set nextVolume to currentVolume + ({change})\n'
            'if nextVolume < 0 then set nextVolume to 0\n'
            'if nextVolume > 100 then set nextVolume to 100\n'
            'set volume output volume nextVolume\n'
            'return output volume of (get volume settings)'
        )
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=5)
        if result.returncode:
            self.send_text(409, result.stderr.strip() or "当前音频设备不支持调节 Mac 音量")
            return
        self.send_text(200, "Mac 音量：" + result.stdout.strip() + "%")


def run_key(key_code):
    script = (
        'tell application "System Events"\n'
        'set frontApp to first application process whose frontmost is true\n'
        f'if bundle identifier of frontApp is not "{TARGET_BUNDLE_ID}" then '
        'error "请先将映匣窗口切到 Mac 前台" number 9001\n'
        f'key code {key_code}\n'
        'end tell'
    )
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=5)


def update_highlight(target):
    if HIGHLIGHT is None or HIGHLIGHT.poll() is not None:
        return
    try:
        HIGHLIGHT.stdin.write(json.dumps(target or {}) + "\n")
        HIGHLIGHT.stdin.flush()
    except BrokenPipeError:
        pass


def local_ip():
    result = subprocess.run(["ipconfig", "getifaddr", "en0"], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit("未找到 Wi-Fi 地址，请先连接 Wi-Fi。")
    return result.stdout.strip()


if __name__ == "__main__":
    HELPER = os.path.join(tempfile.gettempdir(), f"yingxia-ax-remote-{os.getpid()}")
    highlight_binary = os.path.join(tempfile.gettempdir(), f"yingxia-highlight-{os.getpid()}")
    subprocess.run(["swiftc", str(Path(__file__).parent / "ax_remote.swift"), "-o", HELPER], check=True)
    subprocess.run(["swiftc", str(Path(__file__).parent / "highlight.swift"), "-o", highlight_binary], check=True)
    HIGHLIGHT = subprocess.Popen([highlight_binary], stdin=subprocess.PIPE, text=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ip = local_ip()
    server = ThreadingHTTPServer((ip, PORT), RemoteHandler)
    print(f"手机连接同一 Wi-Fi 后打开：http://{ip}:{PORT}/", flush=True)
    print("映匣需保持运行；可在手机遥控器中切换主界面和播放窗口。按 Ctrl+C 停止服务。", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("遥控器服务已停止。", flush=True)
    finally:
        server.server_close()
        HIGHLIGHT.stdin.close()
        HIGHLIGHT.wait(timeout=3)
        os.unlink(HELPER)
        os.unlink(highlight_binary)
