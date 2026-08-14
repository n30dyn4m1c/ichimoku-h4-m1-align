#!/usr/bin/env bash
# Deploy the VPS EAs to the local MT5 (Wine) Experts folder.
# Usage:
#   ./deploy.sh            # deploy from master
#   ./deploy.sh <branch>   # deploy from a specific branch
#   MT5_DATA=/path ./deploy.sh   # skip auto-detection, use this Experts dir
set -euo pipefail

BRANCH="${1:-master}"
REPO_URL="https://raw.githubusercontent.com/n30dyn4m1c/ichimoku-h4-m1-align/${BRANCH}"
EAS=(ichimoku-h4-m1-vps-ea.mq5)

# Locate the MT5 Experts folder (Wine data or install dir), unless overridden.
if [[ -z "${MT5_DATA:-}" ]]; then
   EXPERTS="$(find "$HOME" -type d -path "*MQL5/Experts" 2>/dev/null | head -1)"
else
   EXPERTS="$MT5_DATA"
fi
if [[ -z "$EXPERTS" ]]; then
   echo "ERROR: MQL5/Experts folder not found under $HOME" >&2
   echo "Set MT5_DATA=/path/to/MQL5/Experts to override." >&2
   exit 1
fi

echo "Deploying from branch: $BRANCH"
echo "Target folder: $EXPERTS"

for ea in "${EAS[@]}"; do
   out="$EXPERTS/$ea"
   if ! curl -fsSL -o "$out" "$REPO_URL/$ea"; then
      echo "ERROR: download failed for $ea" >&2
      exit 1
   fi
   echo "OK   $ea ($(stat -c%s "$out") bytes)"
done

echo
echo "Done. In MetaEditor: refresh Navigator, compile the file (F7), reload the EA."
