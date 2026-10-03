#!/usr/bin/env bash
#
# A dead man's switch for changes made over the tunnel.
#
#   safety-net.sh arm 10      restore networking in 10 minutes unless disarmed
#   safety-net.sh disarm      the change went fine, cancel it
#   safety-net.sh status      is one armed, and when does it fire
#
# The tablet is on a wall in someone else's home and is reachable only over its
# own Wi-Fi. Anything touching the radio, the network stack or a shared combo
# chip can therefore cut the only way back in, and the cost of that is a trip to
# another city rather than a lost session. So arm this first, make the change,
# and disarm when the way back is proven to still work.
#
# It escalates rather than rebooting straight away: unblock the radio, bounce
# NetworkManager, bounce the tunnel, and only reboot if the gateway is still
# unreachable after all of that. A reboot is known to recover this tablet and is
# the last resort, not the first move.

set -o errexit
set -o nounset
set -o pipefail

unit=safety-net
helper=/usr/local/sbin/restore-network

sudo=(sudo)
[[ -z ${SUDO_ASKPASS:-} ]] || sudo=(sudo -A)

usage() { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

install_helper() {
  "${sudo[@]}" tee "$helper" > /dev/null <<'HELPER'
#!/bin/bash
# Escalating recovery of remote access. Invoked only by the safety-net timer.
# systemd already routes stdout to the journal under this unit, so read it with
# `journalctl -u safety-net.service`, not by syslog identifier.
gateway=$(ip route show default | awk '/default/{print $3; exit}')
: "${gateway:=192.168.0.1}"

reachable() { ping -c2 -W2 "$gateway" > /dev/null 2>&1; }

echo "safety net fired; gateway $gateway"
rfkill unblock all || true
nmcli radio wifi on || true
sleep 5
reachable && { echo "radio unblock was enough"; exit 0; }

echo "restarting NetworkManager"
systemctl restart NetworkManager || true
sleep 25
reachable && { echo "NetworkManager restart was enough"; exit 0; }

echo "restarting cloudflared"
systemctl restart cloudflared || true
sleep 15
reachable && { echo "cloudflared restart was enough"; exit 0; }

echo "still no gateway, rebooting"
systemctl reboot
HELPER
  "${sudo[@]}" chmod 755 "$helper"
}

case "${1:-}" in
  arm)
    minutes=${2:-10}
    [[ $minutes =~ ^[0-9]+$ ]] || usage
    install_helper
    "${sudo[@]}" systemctl stop "$unit.timer" 2>/dev/null || true
    "${sudo[@]}" systemd-run --unit="$unit" --on-active="${minutes}min" \
        --timer-property=AccuracySec=5s --description="restore remote access" \
        "$helper" > /dev/null
    printf -- '--- armed: networking will be restored in %s minutes unless disarmed\n' "$minutes"
    ;;
  disarm)
    if "${sudo[@]}" systemctl stop "$unit.timer" 2>/dev/null; then
      printf -- '--- disarmed\n'
    else
      printf -- '--- nothing was armed\n'
    fi
    ;;
  status)
    if systemctl is-active --quiet "$unit.timer"; then
      systemctl list-timers "$unit.timer" --no-pager | head -2
    else
      printf -- '--- no safety net armed\n'
    fi
    ;;
  *) usage ;;
esac
