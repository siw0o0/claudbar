#!/usr/bin/env python3
"""Open a Claude Code session's chat in the Claude desktop app.

Usage: open.py <CLI session id>

The app's deep link takes its own session id (local_...), found by the session file that holds
the CLI session id. The link goes straight to the running app over Chromium's singleton socket,
the way a second app instance hands over its command line, which skips starting that instance
(over a second). Without the socket it falls back to xdg-open.
"""
import glob
import json
import os
import re
import socket
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/Claude")


def local_id(cli_id):
    pattern = re.compile(r'"cliSessionId"\s*:\s*"%s"' % re.escape(cli_id))
    files = glob.glob(os.path.join(CONFIG, "claude-code-sessions", "*", "*", "local_*.json"))
    for path in sorted(files, key=os.path.getmtime, reverse=True):
        try:
            with open(path, encoding="utf-8") as f:
                if pattern.search(f.read()):
                    return os.path.basename(path)[:-len(".json")]
        except OSError:
            continue
    return None


def hand_over(url):
    # START \0 cwd \0 argc \0 argv... : what Electron's second instance sends; the app answers ACK.
    argv = [b"claudbar", url.encode()]
    message = b"\0".join([b"START", os.getcwd().encode(), str(len(argv)).encode()] + argv)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        s.connect(os.path.join(CONFIG, "SingletonSocket"))
        s.sendall(message)
        s.shutdown(socket.SHUT_WR)
        return s.recv(16).startswith(b"ACK")


def main():
    cli_id = sys.argv[1] if len(sys.argv) > 1 else ""
    if not re.fullmatch(r"[0-9a-f-]{36}", cli_id):
        return
    session = local_id(cli_id)
    if session is None:
        return  # a terminal session: no chat in the app
    url = "claude://code/continue?session=%s&source=claudbar" % session
    try:
        handed = hand_over(url)
    except OSError:
        handed = False
    if not handed:
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Tells the widget a chat was opened, so it brings the app's window forward.
    print("opened")


if __name__ == "__main__":
    main()
