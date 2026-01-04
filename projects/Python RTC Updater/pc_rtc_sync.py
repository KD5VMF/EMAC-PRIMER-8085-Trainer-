#!/usr/bin/env python3
"""
pc_rtc_sync.py

Sends a one-line time/date update to the EMAC PRIMER 8085 clock program over serial.

8085 expects (ASCII, no echo):
  !UYYMMDDWHHMMSS<CR>

Where:
  YY = 00..99  (program displays as 20YY)
  MM = 01..12
  DD = 01..31
  W  = 1..7 (1=Sun, 2=Mon, ... 7=Sat)
  HH = 00..23
  MM = 00..59
  SS = 00..59

8085 replies:
  OK<CR><LF>   or   ERR<CR><LF>

Windows 11 quick start:
  py -m pip install pyserial
  py pc_rtc_sync.py --port COM4 --once

Tip: Use --align to send right after a second boundary for better accuracy.
"""

from __future__ import annotations
import argparse
import datetime as dt
import time

import serial  # pyserial


def dow_1_sun_7_sat(t: dt.datetime) -> int:
    # Python weekday(): Mon=0..Sun=6  => 1=Sun..7=Sat
    return ((t.weekday() + 1) % 7) + 1


def build_cmd(t: dt.datetime) -> str:
    yy = t.year % 100
    mo = t.month
    da = t.day
    w = dow_1_sun_7_sat(t)
    hh = t.hour
    mm = t.minute
    ss = t.second
    return f"!U{yy:02d}{mo:02d}{da:02d}{w:d}{hh:02d}{mm:02d}{ss:02d}\r"


def align_to_next_second(slack_s: float = 0.02) -> None:
    # Sleep until just after the next whole second tick.
    now = time.time()
    frac = now - int(now)
    wait = (1.0 - frac) + slack_s
    if wait > 0:
        time.sleep(wait)


def send_once(ser: serial.Serial, use_utc: bool, align: bool) -> None:
    if align:
        align_to_next_second()

    t = dt.datetime.utcnow() if use_utc else dt.datetime.now()
    cmd = build_cmd(t)
    print("TX:", cmd.strip() + "<CR>")

    ser.reset_input_buffer()
    ser.write(cmd.encode("ascii", errors="strict"))
    ser.flush()

    # Read response line (OK / ERR). Timeout controls max wait.
    resp = ser.readline().decode("ascii", errors="replace").strip()
    print("RX:", resp if resp else "(no response)")


def main() -> int:
    ap = argparse.ArgumentParser(description="Sync EMAC PRIMER 8085 RTC clock over serial.")
    ap.add_argument("--port", required=True, help="Serial port, e.g. COM4")
    ap.add_argument("--baud", type=int, default=38400, help="Baud rate (default: 38400)")
    ap.add_argument("--once", action="store_true", help="Send one update and exit")
    ap.add_argument("--interval", type=float, default=0.0, help="Repeat every N seconds (0=off)")
    ap.add_argument("--utc", action="store_true", help="Send UTC instead of local time")
    ap.add_argument("--align", action="store_true", help="Align sends to just after a second tick")
    ap.add_argument("--timeout", type=float, default=1.0, help="Read timeout seconds (default: 1.0)")
    args = ap.parse_args()

    with serial.Serial(
        port=args.port,
        baudrate=args.baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=args.timeout,
        write_timeout=args.timeout,
    ) as ser:
        if args.once or args.interval <= 0:
            send_once(ser, use_utc=args.utc, align=args.align)
            return 0

        print(f"Syncing every {args.interval:g} seconds. Ctrl+C to stop.")
        try:
            while True:
                send_once(ser, use_utc=args.utc, align=args.align)
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\nStopped.")
            return 0


if __name__ == "__main__":
    raise SystemExit(main())
