#!/usr/bin/env bash
# mt5-run.sh — the main process of mt5.service on the VPS.
#
# Why: when MetaTrader updates, the terminal systemd started exits 0 and the
# updater relaunches a new terminal on its own. With terminal64.exe as the
# service's main process, systemd saw that exit and restarted it, and every
# restart found the relaunched terminal already running, printed "terminal
# process already started" and exited 0 again: a restart every ~18 s, 2,800
# times from 2026-09-28 to 09-29, while the orphaned terminal traded on.
#
# This wrapper never hands its lifetime to the terminal. It starts MT5 only
# when no terminal (and no LiveUpdate helper) is running, then keeps watching:
# if the terminal exits, it waits out an update hand-off before relaunching.
# Because the wrapper stays up, systemd no longer restarts anything, and the
# default KillMode=control-group is safe again (the updater is not killed,
# since the main process does not exit), so `systemctl stop mt5` stops MT5.
#
# Install (see README, "The VPS host"):
#   cp tools/mt5-run.sh ~/mt5-run.sh && chmod +x ~/mt5-run.sh
#   drop-in /etc/systemd/system/mt5.service.d/override.conf:
#     [Service]
#     ExecStart=
#     ExecStart=/home/neo/mt5-run.sh

MT5="${MT5_DIR:-$HOME/.wine/drive_c/Program Files/XM Global MT5}"
WINE="${WINE:-wine}"
ARGS=(/portable /profile:ichimoku-live)
GRACE="${MT5_GRACE:-180}"   # seconds to wait for an updater to relaunch the terminal
POLL=15

log() { echo "mt5-run: $*"; }                       # goes to journalctl -u mt5
running() { pgrep -if 'XM Global MT5.*(terminal64\.exe|liveupdate)' >/dev/null; }

trap 'log "stopping"; exit 0' TERM INT

while true; do
  if running; then
    sleep "$POLL"
    continue
  fi
  # Nothing running: give a just-exited terminal's updater time to relaunch it
  for ((t = 0; t < GRACE; t += 5)); do running && break; sleep 5; done
  running && continue
  log "no terminal running, starting MT5"
  cd "$MT5" || { log "missing $MT5"; sleep 60; continue; }
  "$WINE" "$MT5/terminal64.exe" "${ARGS[@]}" &
  wait $!
  log "terminal64.exe exited with $?"
done
