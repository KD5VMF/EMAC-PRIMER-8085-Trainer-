#!/usr/bin/env bash
# Example launcher for Linux / Raspberry Pi.
# NOTE: Close minicom/screen/picocom first! Python needs exclusive access.
# Example:
#   ./run_linux.sh /dev/ttyUSB0

set -euo pipefail

PORT="${1:-}"
if [[ -z "$PORT" ]]; then
  echo "Usage: $0 /dev/ttyUSB0"
  exit 1
fi

python3 pc_rtc_sync.py --port "$PORT" --baud 38400 --align --interval 5
