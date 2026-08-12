#!/usr/bin/env bash
# Auto-deploy the VPS EAs when the repo's master branch changes.
# Polls the GitHub API for the latest commit SHA and runs deploy.sh only
# when the SHA differs from the last deployed one — so a cron job can
# call this every few minutes without re-downloading unchanged files.
# Usage:
#   ./auto-deploy.sh                # poll and deploy if changed (branch: master)
#   ./auto-deploy.sh <branch>       # poll a specific branch
#   STATE_FILE=/path ./auto-deploy.sh   # where the last-deployed SHA is stored
set -euo pipefail

REPO="n30dyn4m1c/ichimoku-h4-m1-align"
BRANCH="${1:-master}"
STATE_FILE="${STATE_FILE:-/tmp/last_deploy_sha}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/deploy.sh"

[[ -x "$DEPLOY" ]] || { echo "ERROR: deploy.sh not found next to this script" >&2; exit 1; }

SHA="$(curl -fsSL "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 || true)"
if [[ -z "$SHA" ]]; then
   echo "WARN: could not fetch latest SHA from GitHub — leaving everything as-is"
   exit 0
fi

LAST="$(cat "$STATE_FILE" 2>/dev/null || echo none)"
if [[ "$SHA" == "$LAST" ]]; then
   echo "No new push (last deployed: $SHA)"
   exit 0
fi

echo "New push detected: $LAST -> $SHA"
"$DEPLOY" "$BRANCH"
echo "$SHA" > "$STATE_FILE"
