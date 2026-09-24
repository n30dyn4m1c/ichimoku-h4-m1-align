#!/usr/bin/env bash
# mt5-check.sh — weekday health check for the live MT5 terminal on the VPS.
#
# Pings a healthchecks.io check: a silent success ping when mt5.service is up
# and the VPS EA loaded after the terminal's last start, or a /fail ping with a
# short report (which healthchecks.io emails) when it is not. If the VPS itself
# is down, the missing ping triggers the email instead.
#
# Install on the VPS (see README, "Health check"):
#   echo 'https://hc-ping.com/<your-uuid>' > ~/.mt5-check-ping
#   chmod +x ~/mt5-check.sh
#   crontab -e   ->   0 10 * * 1-5 ~/mt5-check.sh    (hour in the VPS's time zone)

PING="${MT5_CHECK_PING:-$(cat "$HOME/.mt5-check-ping" 2>/dev/null)}"
MT5="$HOME/.wine/drive_c/Program Files/XM Global MT5"
EA="ichimoku-h4-m1-vps-ea"
REPORT=""
fail() { REPORT+="- $*"$'\n'; }
readlog() { iconv -f UTF-16LE -t UTF-8 "$1" 2>/dev/null; }

[ -z "$PING" ] && { echo "mt5-check: no ping URL (set MT5_CHECK_PING or ~/.mt5-check-ping)" >&2; exit 2; }

if ! systemctl is-active --quiet mt5; then
  fail "mt5.service is not running ($(systemctl is-active mt5))"
  SINCE=$(date -d '2 days ago' +%Y%m%d)
else
  START=$(systemctl show mt5 -p ActiveEnterTimestamp --value)
  SINCE=$(date -d "$START - 1 day" +%Y%m%d)      # every log since the service last started
  UP=$(( $(date +%s) - $(date -d "$START" +%s) ))
fi

# Terminal logs from SINCE to today, oldest first
LOGTXT=$(for f in "$MT5"/logs/*.log; do
  d=$(basename "$f" .log); [[ "$d" > "$SINCE" || "$d" == "$SINCE" ]] && readlog "$f"
done)

if [ -z "$REPORT" ] && [ "${UP:-0}" -gt 300 ]; then
  # The EA must have loaded after the most recent terminal start
  AFTER=$(printf '%s\n' "$LOGTXT" | awk '/started for/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}')
  printf '%s' "$AFTER" | grep -q "expert $EA .*loaded successfully" \
    || fail "terminal is running but $EA has not loaded since its last start ($START)"
fi

# Update/restart loop: many LiveUpdate starts in yesterday's + today's logs
N=$(for d in "$(date -d yesterday +%Y%m%d)" "$(date +%Y%m%d)"; do
  f="$MT5/logs/$d.log"; [ -f "$f" ] && readlog "$f"; done | grep -c 'LiveUpdate start')
[ "$N" -gt 3 ] && fail "LiveUpdate started $N times since yesterday: possible update/restart loop"

if [ -z "$REPORT" ]; then
  curl -fsS -m 10 "$PING" >/dev/null
else
  BODY="MT5 on $(hostname) at $(date -u '+%F %H:%M UTC'):"$'\n'"$REPORT"$'\n'"Last terminal log lines:"$'\n'"$(printf '%s\n' "$LOGTXT" | tail -15)"
  curl -fsS -m 10 --data-raw "$BODY" "$PING/fail" >/dev/null
fi
