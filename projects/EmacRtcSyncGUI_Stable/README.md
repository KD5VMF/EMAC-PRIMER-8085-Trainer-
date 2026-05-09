# EMAC RTC Sync GUI

Clean fixed build for the EMAC PRIMER 8085 RTC sync program.

## What changed in this build

- The Save button is now **Save + Connect**.
- When you save, the program immediately tries to open the selected COM port.
- The serial port stays open after Save, Send Once, and Stop Repeating.
- Future sends reuse the already-open serial connection for a faster, always-ready feel.
- The port only closes when the program exits, or when the COM/baud/DTR/RTS settings require a reopen.
- Layout is kept simple and aligned.
- Startup still defaults to LOCAL time. UTC does not come back sticky on startup.
- Safe Timing is enabled by default.
- Safe Timing now waits for the 8085's once-per-second screen burst to finish before sending.
- Sends the `!UYYMMDDWHHMMSS<CR>` command one character at a time with a shorter, safer delay.
- Retries up to 5 times if the PC sees screen text but no `OK` or `ERR`.
- Uses the simple recommended defaults: 9600 baud, CR, DTR ON, RTS ON.

## Recommended use

1. Pick the correct COM port.
2. Use 9600 baud, CR, DTR ON, RTS ON.
3. Press **Save + Connect**.
4. Watch the log for:

```text
READY: Serial is open on COMx. Sends will reuse this open connection.
```

Then use **Send Once** or **Start Repeating**. The serial port should already be open and ready.

## Why keeping the port open may help

Opening and closing a serial port can toggle DTR/RTS on some adapters and can also lose timing while the 8085 clock program is busy updating the screen. This build opens the port once after saving and keeps it open, so repeated sync attempts are steadier.

## Recommended settings

```text
COM Port: COM6 or your real port
Baud:     9600
Ending:   CR
Timeout:  1.0
Repeat:   60
Safe Timing: ON
Time Mode: LOCAL / UTC unchecked
DTR: ON
RTS: ON
```

## Run

Double-click:

```text
build_run.bat
```

Or open `EmacRtcSyncGUI.sln` in Visual Studio and run the project.

## 8085 reference

The uploaded 8085 ASM file is included under:

```text
8085\pc_rtc_sync.ASM
```

## This version fixes the repeated ERR problem

The 8085 program prints a live ANSI clock update once per second. While that update is being transmitted, the 8085 is busy sending terminal text and is not polling the receive side as often. This version keeps the serial port open, watches for the screen update burst, waits for the line to go quiet, and then sends the small sync command while the parser is most likely ready.
