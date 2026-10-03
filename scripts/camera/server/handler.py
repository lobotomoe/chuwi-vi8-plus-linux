"""HTTP surface: one still, one MJPEG stream, one health report.

Home Assistant's MJPEG IP Camera integration wants exactly this pair of URLs --
a `multipart/x-mixed-replace` stream and an optional still -- and detects basic
auth by itself, so there is nothing custom on the Home Assistant side.

The sensor runs at a fixed ~28 fps and rejects VIDIOC_S_PARM, so a requested
frame rate is served by skipping frames here. Capture costs the same either
way; what a lower rate buys back is JPEG encoding, which is software because
this ISP has no JPEG path at all.
"""
import base64
import hmac
import json
import logging
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

log = logging.getLogger("camera.http")

BOUNDARY = "frame"
MIN_FPS = 1.0
MAX_FPS = 15.0
# The sensor delivers ~28 fps, so anything older than this means it stopped.
STALE_FRAME_S = 5.0


class CameraHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, capture, encoder_for, credentials, max_streams):
        self.capture = capture
        # Rotation and gamma are per request rather than per process on purpose:
        # changing them in the config would mean restarting, and a restart closes
        # the capture device. Reopening it is the one operation on this hardware
        # that can fail in a way only a reboot clears.
        self.encoder_for = encoder_for
        self.credentials = credentials
        self.stream_slots = threading.BoundedSemaphore(max_streams)
        super().__init__(address, CameraRequestHandler)


class CameraRequestHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "chuwi-camera/1.0"
    sys_version = ""

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)

    def _authorized(self):
        expected = self.server.credentials
        if expected is None:
            return True
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            offered = base64.b64decode(header[6:], validate=True)
        except (ValueError, TypeError):
            return False
        return hmac.compare_digest(offered, expected)

    def _deny(self):
        body = b"unauthorized\n"
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="camera"')
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self._authorized():
            self._deny()
            return
        route = urlparse(self.path)
        query = parse_qs(route.query)
        if route.path in ("/snapshot", "/snapshot.jpg"):
            self._snapshot(query)
        elif route.path in ("/stream", "/stream.mjpeg"):
            self._stream(query)
        elif route.path == "/healthz":
            self._healthz()
        else:
            self._send(404, "text/plain", b"try /snapshot, /stream or /healthz\n")

    def _encoder(self, query):
        """The default encoder, or one overridden by ?rotate= and ?gamma=."""
        rotate = query.get("rotate", [None])[0]
        gamma = query.get("gamma", [None])[0]
        try:
            return self.server.encoder_for(
                None if rotate is None else int(rotate),
                None if gamma is None else float(gamma))
        except ValueError as error:
            raise ValueError(f"bad rotate or gamma: {error}") from error

    def _snapshot(self, query):
        try:
            encoder = self._encoder(query)
        except ValueError as error:
            self._send(400, "text/plain", str(error).encode() + b"\n")
            return
        frame, _ = self.server.capture.wait_for_frame(after=0, timeout=10.0)
        if frame is None:
            self._send(503, "text/plain", b"no frame from the capture device yet\n")
            return
        self._send(200, "image/jpeg", encoder.to_jpeg(frame))

    def _healthz(self):
        status = self.server.capture.status()
        healthy = is_healthy(status)
        body = json.dumps({"ok": healthy, **status}, indent=2).encode() + b"\n"
        self._send(200 if healthy else 503, "application/json", body)

    def _requested_fps(self, query):
        raw = query.get("fps", ["5"])[0]
        try:
            fps = float(raw)
        except ValueError:
            return None
        return min(MAX_FPS, max(MIN_FPS, fps))

    def _stream(self, query):
        fps = self._requested_fps(query)
        if fps is None:
            self._send(400, "text/plain", b"fps must be a number\n")
            return
        try:
            encoder = self._encoder(query)
        except ValueError as error:
            self._send(400, "text/plain", str(error).encode() + b"\n")
            return
        if not self.server.stream_slots.acquire(blocking=False):
            self._send(503, "text/plain",
                       b"too many streams already running on this tablet\n")
            return
        try:
            self._pump_stream(fps, encoder)
        finally:
            self.server.stream_slots.release()

    def _pump_stream(self, fps, encoder):
        self.send_response(200)
        self.send_header("Content-Type",
                         f"multipart/x-mixed-replace; boundary={BOUNDARY}")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        capture = self.server.capture
        interval = 1.0 / fps
        seen = 0
        sent = 0
        started = time.monotonic()
        try:
            while True:
                frame, seen = capture.wait_for_frame(after=seen, timeout=10.0)
                if frame is None:
                    log.warning("stream stalled waiting for a frame")
                    return
                jpeg = encoder.to_jpeg(frame)
                self.wfile.write(
                    f"--{BOUNDARY}\r\nContent-Type: image/jpeg\r\n"
                    f"Content-Length: {len(jpeg)}\r\n\r\n".encode())
                self.wfile.write(jpeg)
                self.wfile.write(b"\r\n")
                sent += 1
                # Hold the requested rate without drifting: sleep against the
                # stream's own clock rather than per-frame encode time.
                behind = started + sent * interval - time.monotonic()
                if behind > 0:
                    time.sleep(behind)
                else:
                    started = time.monotonic() - sent * interval
        except (BrokenPipeError, ConnectionResetError):
            log.info("client closed the stream after %d frames", sent)


def is_healthy(status):
    """Whether the capture is still delivering.

    Written out rather than `status["last_frame_age_s"] or STALE_FRAME_S`,
    which reads a genuine age of 0.0 as missing and calls a camera unhealthy at
    the exact moment it has just delivered a frame. None means no frame yet.
    """
    age = status["last_frame_age_s"]
    return bool(status["capture_alive"]) and age is not None and age < STALE_FRAME_S


def credentials_for(username, password):
    """The expected Authorization payload, or None when auth is off."""
    if not username and not password:
        return None
    return f"{username}:{password}".encode()
