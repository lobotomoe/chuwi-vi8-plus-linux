#!/usr/bin/env bash
#
# Install the camera HTTP service on the tablet.
#
#   SUDO_ASKPASS=$HOME/.local/bin/sudo-askpass ./install.sh
#
# Copies the Python modules to /usr/local/lib/camera-server, writes a config
# with a freshly generated password on first run, installs a systemd unit and
# starts it. Re-running updates the code and leaves the existing config and its
# password alone, so Home Assistant does not need reconfiguring.
#
# The unit starts at boot on purpose. The ISP powers up when the device is
# opened, and that power-on needs MemFree -- see capture.py. Early boot is when
# this tablet has memory to spare; once the kiosk browser is up it does not.

set -o errexit
set -o nounset
set -o pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lib=/usr/local/lib/camera-server
conf=/etc/camera-server.conf
unit=/etc/systemd/system/camera-server.service
service_user=${SERVICE_USER:-chuwi}

log() { printf -- '--- %s\n' "$*"; }

# With SUDO_ASKPASS set, sudo reads the password from that helper instead of the
# terminal, which is what keeps it out of command lines and shell history.
sudo=(sudo)
[[ -z ${SUDO_ASKPASS:-} ]] || sudo=(sudo -A)

for module in main.py capture.py encode.py handler.py; do
  [[ -f "$here/$module" ]] || { echo "missing $here/$module" >&2; exit 1; }
done

if ! python3 -c 'import PIL' 2>/dev/null; then
  log "installing python3-pil"
  "${sudo[@]}" apt-get install -y -q python3-pil
fi
command -v v4l2-ctl > /dev/null || "${sudo[@]}" apt-get install -y -q v4l-utils

log "code -> $lib"
"${sudo[@]}" mkdir -p "$lib"
"${sudo[@]}" install -m 644 "$here"/{capture.py,encode.py,handler.py} "$lib/"
"${sudo[@]}" install -m 755 "$here/main.py" "$lib/main.py"

if [[ -f $conf ]]; then
  log "keeping the existing $conf"
else
  password=$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')
  log "writing $conf with a generated password"
  "${sudo[@]}" tee "$conf" > /dev/null <<CONF
# Camera HTTP service. Home Assistant's MJPEG IP Camera integration reads
# http://<tablet>:8081/stream and http://<tablet>:8081/snapshot from here and
# detects the basic auth by itself.
[server]
bind = 0.0.0.0
port = 8081
username = camera
password = $password
max_streams = 2

[camera]
device = /dev/video0
# Input 0 is the front sensor, 1 the rear one. Only one can be live: the ISP
# exposes a single capture node with the two sensors as inputs, and changing
# this needs a restart of the service.
input = 0
width = 640
height = 480
settle_frames = 20
# The panel is mounted rotated; this turns the frame upright for a viewer.
rotate = 90
# There is no 3A in this driver, so this gamma curve is the only brightness
# control that exists. 1.0 disables it.
gamma = 2.2
quality = 70
CONF
  "${sudo[@]}" chown "root:$service_user" "$conf"
  "${sudo[@]}" chmod 640 "$conf"
fi

log "unit -> $unit"
"${sudo[@]}" tee "$unit" > /dev/null <<UNIT
[Unit]
Description=Serve the tablet camera over HTTP for Home Assistant
Documentation=file:$lib/main.py
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$service_user
ExecStart=/usr/bin/python3 $lib/main.py $conf
Restart=on-failure
# Long enough that a restart loop cannot keep hammering the ISP with opens.
RestartSec=30
MemoryMax=256M
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

"${sudo[@]}" systemctl daemon-reload

# At boot there is memory to spare and this is unnecessary. Installing into a
# running session is the other case: the kiosk browser and the page cache leave
# under 100 MB genuinely free, the service refuses to open the ISP that low, and
# the caches are what it is waiting for. alloc_pages_bulk() will not reclaim
# them itself.
log "freeing page cache so the first open has memory"
sync
"${sudo[@]}" sh -c 'echo 3 > /proc/sys/vm/drop_caches'

"${sudo[@]}" systemctl enable camera-server.service
# restart, not start: re-running this script is how the code gets updated, and
# the running process would otherwise keep serving the old modules.
"${sudo[@]}" systemctl restart camera-server.service
log "waiting for the first frame"
for _ in $(seq 1 30); do
  sleep 1
  state=$(systemctl is-active camera-server.service || true)
  [[ $state == active ]] || continue
  # shellcheck disable=SC2016  # $2 is an awk field, which needs the single quotes.
  credentials=$("${sudo[@]}" awk -F'= *' '/^(username|password) *=/{print $2}' "$conf" | paste -sd: -)
  if curl -fsS -u "$credentials" --max-time 5 http://127.0.0.1:8081/healthz > /dev/null 2>&1; then
    log "healthy"
    curl -fsS -u "$credentials" http://127.0.0.1:8081/healthz
    break
  fi
done

log "credentials for Home Assistant:"
# shellcheck disable=SC2016  # $1 and $2 are awk fields, not shell variables.
"${sudo[@]}" awk -F'= *' '/^(username|password) *=/{printf "    %s: %s\n", $1, $2}' "$conf"
log "URLs: http://$(hostname -I | awk '{print $1}'):8081/stream and /snapshot"
