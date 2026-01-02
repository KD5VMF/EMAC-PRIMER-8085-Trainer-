# M48T35 notes (practical)

## 1) STOP bit (seconds register, bit7)
If bit7 of the seconds register is set, the oscillator is stopped.
Many chips ship this way from the factory.

This repo’s code will:
- detect STOP
- enter WRITE latch
- clear STOP
- clear FT/reserved bits in the day register
- release WRITE latch

## 2) READ latch
Setting READ latch (control bit6) freezes the time registers so you can read them consistently.
You should release it quickly so the RTC keeps ticking.

## 3) FT / reserved bits
Depending on how the day register bits are handled, you can accidentally enable “test” behavior.
The repo code masks the day register to keep the clock in normal operation.

## Troubleshooting
If a program blinks 888888 forever, it means the seconds byte never changed.
Try:
- dump `FFF8–FFFF` twice a few seconds apart
- confirm `FFF9` changes
- confirm STOP bit cleared (FFF9 bit7 should be 0)
