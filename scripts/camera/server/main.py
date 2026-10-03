#!/usr/bin/env python3
"""Serve the tablet's camera over HTTP for Home Assistant.

Run with a config file path, or none for the default:

    camera-server [/etc/camera-server.conf]

The device is opened once, at startup, and held for the life of the process --
see capture.py for why opening it per request is not safe on this hardware.
"""
import configparser
import logging
import os
import signal
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from capture import Capture, CaptureError, memfree_kb  # noqa: E402
from encode import Encoder  # noqa: E402
from handler import CameraHTTPServer, credentials_for  # noqa: E402

DEFAULT_CONFIG = "/etc/camera-server.conf"
DEFAULTS = {
    "server": {
        "bind": "0.0.0.0",
        "port": "8081",
        "username": "",
        "password": "",
        "max_streams": "2",
    },
    "camera": {
        "device": "/dev/video0",
        "input": "0",
        "width": "640",
        "height": "480",
        "settle_frames": "20",
        "rotate": "90",
        "gamma": "2.2",
        "quality": "70",
        "wait_for_device_s": "60",
    },
}

log = logging.getLogger("camera")


def load_config(path):
    config = configparser.ConfigParser()
    config.read_dict(DEFAULTS)
    if os.path.exists(path):
        config.read(path)
        log.info("configuration from %s", path)
    else:
        log.warning("%s is absent, running on defaults with no authentication", path)
    return config


def wait_for_device(path, seconds):
    """The camera modules load at boot through DKMS, but not necessarily first."""
    deadline = time.monotonic() + seconds
    while not os.path.exists(path):
        if time.monotonic() >= deadline:
            return False
        time.sleep(1)
    return True


def main(argv):
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s",
                        stream=sys.stderr)
    config = load_config(argv[1] if len(argv) > 1 else DEFAULT_CONFIG)
    server_config, camera_config = config["server"], config["camera"]

    device = camera_config["device"]
    if not wait_for_device(device, camera_config.getint("wait_for_device_s")):
        log.error("%s never appeared; are the camera modules installed?", device)
        return 1

    log.info("starting with MemFree %d MB", memfree_kb() // 1024)
    capture = Capture(
        device=device,
        input_index=camera_config.getint("input"),
        width=camera_config.getint("width"),
        height=camera_config.getint("height"),
        settle_frames=camera_config.getint("settle_frames"),
    )
    try:
        capture.probe()
        capture.start()
    except CaptureError as error:
        log.error("%s", error)
        return 1

    default_rotate = camera_config.getint("rotate")
    default_gamma = camera_config.getfloat("gamma")
    quality = camera_config.getint("quality")
    encoders = {}

    def encoder_for(rotate=None, gamma=None):
        """Encoders are cheap but not free -- the gamma table is built once each."""
        key = (default_rotate if rotate is None else rotate,
               default_gamma if gamma is None else gamma)
        if key not in encoders:
            encoders[key] = Encoder(width=capture.width, height=capture.height,
                                    stride=capture.stride, rotate=key[0],
                                    gamma=key[1], quality=quality)
        return encoders[key]

    encoder = encoder_for()
    if encoder.picture_bytes > capture.frame_bytes:
        log.error("the driver's %d-byte frames cannot hold a %d-byte picture",
                  capture.frame_bytes, encoder.picture_bytes)
        return 1

    credentials = credentials_for(server_config["username"], server_config["password"])
    if credentials is None:
        log.warning("no username or password set: anyone on the network can watch")

    address = (server_config["bind"], server_config.getint("port"))
    server = CameraHTTPServer(address, capture, encoder_for, credentials,
                              server_config.getint("max_streams"))

    def shutdown(signum, _frame):
        log.info("signal %d, shutting down", signum)
        capture.stop()
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    log.info("serving /snapshot and /stream on %s:%d", *address)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
