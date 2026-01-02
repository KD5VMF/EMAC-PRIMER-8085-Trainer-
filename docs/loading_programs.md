# Loading and running programs

The projects here are written as **8085 ASM** and are intended to be loaded at **A000h**.

Typical usage:
- Load your assembled Intel HEX into RAM starting at A000h (method depends on your ROM monitor).
- Start execution:
  - `G A000`

## Recommended order
1) RTC test: confirms your M48T35 seconds tick
2) Runtime HHMMSS: uses the RTC seconds as a clean 1-second ticker
3) 8155 runtime: alternate ticker method (if you prefer)
