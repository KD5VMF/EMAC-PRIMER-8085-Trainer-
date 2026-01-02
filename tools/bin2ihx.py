#!/usr/bin/env python3
"""bin2ihx.py - minimal Intel HEX generator for 8-bit binaries.

Usage:
  python tools/bin2ihx.py input.bin output.hex --org 0xA000

Notes:
- Standard Intel HEX records (type 00 data, type 01 EOF).
- 16-bit addressing only (perfect for 8085 RAM programs like A000h).
"""

import argparse

def ihex_checksum(byte_values):
    s = sum(byte_values) & 0xFF
    return ((~s + 1) & 0xFF)

def write_record(f, addr, rectype, data):
    count = len(data)
    hi = (addr >> 8) & 0xFF
    lo = addr & 0xFF
    rec = [count, hi, lo, rectype] + list(data)
    cks = ihex_checksum(rec)
    f.write(':%02X%04X%02X%s%02X\n' % (
        count, addr & 0xFFFF, rectype,
        ''.join('%02X' % b for b in data),
        cks
    ))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input', help='input binary')
    ap.add_argument('output', help='output Intel HEX')
    ap.add_argument('--org', default='0x0000', help='origin address (e.g. 0xA000)')
    ap.add_argument('--chunk', type=int, default=16, help='bytes per record (default 16)')
    args = ap.parse_args()

    org = int(args.org, 0)
    with open(args.input, 'rb') as f:
        blob = f.read()

    addr = org
    with open(args.output, 'w', newline='\n') as out:
        for i in range(0, len(blob), args.chunk):
            chunk = blob[i:i+args.chunk]
            write_record(out, addr, 0x00, chunk)
            addr = (addr + len(chunk)) & 0xFFFF
        write_record(out, 0x0000, 0x01, b'')

if __name__ == '__main__':
    main()
