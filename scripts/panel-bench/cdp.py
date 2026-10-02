"""Evaluate JavaScript in Chromium or WebKitGTK over their debugging protocols.

Both speak JSON over a WebSocket, close enough that one client covers them, and
without one there is no way to compare browsers on the thing that matters: how
long a frame actually took inside the page. Python on this tablet has no
websockets module, so the handshake and framing are here.
"""

import base64
import json
import os
import socket
import struct
import urllib.request


class WebSocket:
    def __init__(self, url, timeout=60):
        rest = url.split("://", 1)[1]
        hostport, _, path = rest.partition("/")
        host, _, port = hostport.partition(":")
        self.socket = socket.create_connection((host, int(port or 80)), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.socket.sendall(
            f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n".encode()
        )
        self.buffer = b""
        while b"\r\n\r\n" not in self.buffer:
            self.buffer += self.socket.recv(4096)
        head, _, self.buffer = self.buffer.partition(b"\r\n\r\n")
        if b"101" not in head.split(b"\r\n")[0]:
            raise RuntimeError(f"websocket refused: {head.splitlines()[0]!r}")

    def _recv(self, count):
        while len(self.buffer) < count:
            chunk = self.socket.recv(65536)
            if not chunk:
                raise RuntimeError("websocket closed")
            self.buffer += chunk
        taken, self.buffer = self.buffer[:count], self.buffer[count:]
        return taken

    def send(self, text):
        payload = text.encode()
        header = bytes([0x81])
        mask = os.urandom(4)
        if len(payload) < 126:
            header += bytes([0x80 | len(payload)])
        elif len(payload) < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", len(payload))
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", len(payload))
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.socket.sendall(header + mask + masked)

    def receive(self):
        while True:
            first, second = self._recv(2)
            length = second & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv(8))[0]
            mask = self._recv(4) if second & 0x80 else None
            payload = self._recv(length)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            opcode = first & 0x0F
            if opcode == 1:
                return payload.decode()
            if opcode == 8:
                raise RuntimeError("websocket closed by the browser")


class Debugger:
    """Chromium's CDP and WebKit's inspector both answer Runtime.evaluate."""

    def __init__(self, port, match=None, timeout=60):
        targets = json.loads(
            urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=timeout).read()
        )
        pages = [t for t in targets if t.get("type", "page") == "page"
                 and (match is None or match in (t.get("url", "") + t.get("title", "")))]
        if not pages:
            raise RuntimeError(f"no page target among {[t.get('url') for t in targets]}")
        self.page = pages[0]
        self.socket = WebSocket(self.page["webSocketDebuggerUrl"], timeout)
        self.message_id = 0

    def evaluate(self, expression, await_promise=False):
        self.message_id += 1
        self.socket.send(json.dumps({
            "id": self.message_id,
            "method": "Runtime.evaluate",
            "params": {"expression": expression, "returnByValue": True,
                       "awaitPromise": await_promise},
        }))
        while True:
            message = json.loads(self.socket.receive())
            if message.get("id") != self.message_id:
                continue   # an event, not our answer
            if "error" in message:
                raise RuntimeError(json.dumps(message["error"]))
            result = message["result"]
            if "exceptionDetails" in result:
                raise RuntimeError(json.dumps(result["exceptionDetails"]))
            return result["result"].get("value")
