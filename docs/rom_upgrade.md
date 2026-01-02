# ROM upgrade (EMOS_200_M48T35_SAFE_v2025.hex)

This repo assumes you are running an updated ROM build that is safe for the M48T35 RAM/RTC
and matches your trainer configuration.

## Your ROM filename
You stated the ROM image you’ll use is:

- `EMOS_200_M48T35_SAFE_v2025.hex`

Place it here:
- `firmware/rom/EMOS_200_M48T35_SAFE_v2025.hex`

## Flashing (high level)
Because different PRIMER units use different EPROM/EEPROM programmers and socket types,
this repo does not hardcode a single flashing procedure.

General workflow:
1) Program the ROM device with `EMOS_200_M48T35_SAFE_v2025.hex`
2) Install it in the PRIMER ROM socket
3) Power on and confirm the monitor/EMOS comes up
4) Verify RAM is accessible across 8000–FFFF and that `FFF8–FFFF` responds

## Safety note
Avoid writing arbitrary values into `FFF8–FFFF` unless you know what you’re doing:
that’s the RTC register window.
