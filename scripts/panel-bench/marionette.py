"""Talk to Firefox over Marionette, so the page can be measured from inside.

Firefox listens on 2828 when started with MOZ_MARIONETTE=1. The wire format is
a JSON array prefixed by its length and a colon. This is the only way to get
real frame timing off this machine: scrot manages 14 captures a second, which
cannot tell 60 fps from 20.
"""

import json
import socket


class Marionette:
    def __init__(self, host="127.0.0.1", port=2828, timeout=60):
        self.socket = socket.create_connection((host, port), timeout=timeout)
        self.buffer = b""
        self.message_id = 0
        self.read_packet()  # the server greets first
        self.command("WebDriver:NewSession", {})
        self.command("WebDriver:SetTimeouts", {"script": 45000})

    def read_packet(self):
        while b":" not in self.buffer:
            self.buffer += self.socket.recv(65536)
        length, _, self.buffer = self.buffer.partition(b":")
        length = int(length)
        while len(self.buffer) < length:
            self.buffer += self.socket.recv(65536)
        packet, self.buffer = self.buffer[:length], self.buffer[length:]
        return json.loads(packet)

    def command(self, name, parameters):
        self.message_id += 1
        body = json.dumps([0, self.message_id, name, parameters]).encode()
        self.socket.sendall(b"%d:%s" % (len(body), body))
        while True:
            message = self.read_packet()
            if message[0] == 1 and message[1] == self.message_id:
                if message[2]:
                    raise RuntimeError(json.dumps(message[2]))
                return message[3]

    def script(self, source, asynchronous=False, args=None):
        name = "WebDriver:ExecuteAsyncScript" if asynchronous else "WebDriver:ExecuteScript"
        return self.command(name, {"script": source, "args": args or []})["value"]

    def close(self):
        try:
            self.command("WebDriver:DeleteSession", {})
        finally:
            self.socket.close()
