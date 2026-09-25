#!/usr/bin/env bash
# mt5-check.sh — weekday health check for the live MT5 terminal on the VPS.
#
# Checks that mt5.service is up, that the VPS EA loaded after the terminal's
# last start, and that the terminal is not stuck in a LiveUpdate restart loop.
# All well: stays silent (a quiet success ping). Anything wrong: a short report
# is emailed. The VPS cannot send mail itself (DigitalOcean blocks SMTP ports
# 25/465/587), so the email goes out over HTTPS through healthchecks.io: the
# script sends a /fail ping carrying the report and healthchecks.io emails it.
# A dead VPS sends no ping at all, which healthchecks.io also emails about.
#
# Config: ~/.mt5-check.conf (sourced), e.g.
#   HC_PING=https://hc-ping.com/<uuid>    # the check's ping URL
#   # optional second channel (ntfy.sh needs an account token to send email):
#   # NOTIFY_EMAIL=you@example.com  NTFY_TOPIC=mt5-check-<random>  NTFY_TOKEN=tk_...
#
# healthchecks.io check: schedule type Cron "30 9 * * 1-5" in your time zone (not UTC),
# grace 1 h, and "notify when up" turned off on the email integration.
#
# Install (see README, "Health check"):
#   chmod +x ~/mt5-check.sh
#   crontab -e   ->   30 23 * * 0-4 ~/mt5-check.sh   (VPS is UTC: 09:30 UTC+10 Mon-Fri)
#   ~/mt5-check.sh --test                             (sends a test email)

CONF="${MT5_CHECK_CONF:-$HOME/.mt5-check.conf}"
[ -f "$CONF" ] && . "$CONF"
MT5="$HOME/.wine/drive_c/Program Files/XM Global MT5"
EA="ichimoku-h4-m1-vps-ea"
REPORT=""
fail() { REPORT+="- $*"$'\n'; }
readlog() { iconv -f UTF-16LE -t UTF-8 "$1" 2>/dev/null; }

notify() {  # notify <title> <body>: email the report through every configured channel
  local rc=0
  if [ -n "$HC_PING" ]; then
    curl -fsS -m 20 --data-raw "$1"$'\n\n'"$2" "$HC_PING/fail" >/dev/null || rc=1
  fi
  if [ -n "$NTFY_TOPIC" ] && [ -n "$NTFY_TOKEN" ]; then
    curl -fsS -m 20 -H "Authorization: Bearer $NTFY_TOKEN" -H "Email: $NOTIFY_EMAIL" \
      -H "Title: $1" -H "Tags: warning" --data-raw "$2" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || rc=1
  fi
  return $rc
}

[ -z "$HC_PING" ] && [ -z "$NTFY_TOKEN" ] && { echo "mt5-check: set HC_PING (or NTFY_TOKEN + NTFY_TOPIC + NOTIFY_EMAIL) in $CONF" >&2; exit 2; }

if [ "$1" = "--test" ]; then
  notify "MT5 health check: test" "Test email from mt5-check.sh on $(hostname) at $(date -u '+%F %H:%M UTC'). From now on you only hear from it when MT5 or the EA is not loading."
  rc=$?
  # Put the check back to healthy so only real failures alert from here on
  [ -n "$HC_PING" ] && sleep 5 && curl -fsS -m 10 "$HC_PING" >/dev/null
  exit $rc
fi

if ! systemctl is-active --quiet mt5; then
  fail "mt5.service is not running ($(systemctl is-active mt5))"
  SINCE=$(date -d '2 days ago' +%Y%m%d)
else
  START=$(systemctl show mt5 -p ActiveEnterTimestamp --value)
  SINCE=$(date -d "$START - 1 day" +%Y%m%d)      # every log since the service last started
  UP=$(( $(date +%s) - $(date -d "$START" +%s) ))
fi

# Terminal logs from SINCE to today, oldest first
LOGTXT=$(for f in "$MT5"/logs/[0-9]*.log; do
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
  [ -n "$HC_PING" ] && curl -fsS -m 10 "$HC_PING" >/dev/null
  exit 0
fi
BODY="MT5 on $(hostname) at $(date -u '+%F %H:%M UTC'):"$'\n'"$REPORT"$'\n'"Last terminal log lines:"$'\n'"$(printf '%s\n' "$LOGTXT" | tail -15)"
notify "MT5 is NOT loading on the VPS" "$BODY"
exit 1
