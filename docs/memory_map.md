# Memory map

Assumed for this repo:

- ROM: `0000–7FFF`
- RAM: `8000–FFFF`  (M48T35 Timekeeper SRAM/RTC)

## M48T35 RTC register window

The M48T35 places RTC registers in the top 8 bytes of its address space:
- Chip offsets: `7FF8–7FFF`

When the chip is mapped to `8000–FFFF`, that window appears at:
- CPU addresses: `FFF8–FFFF`

Common bytes:
- `FFF8` Control register
  - bit7 = WRITE latch (W)
  - bit6 = READ latch (R)
- `FFF9` Seconds register (packed BCD)
  - bit7 = STOP oscillator
  - bits6..4 = tens, bits3..0 = ones
- `FFFC` Day register (contains FT bit and some reserved bits)

The demo code uses:
- a brief READ latch while reading seconds
- STOP clearing if needed (first boot / factory state)
- FT/reserved clearing to keep the clock in “normal” mode
