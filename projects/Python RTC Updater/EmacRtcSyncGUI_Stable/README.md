# EMAC RTC Sync

A small Windows C# utility for syncing the real-time clock on an **EMAC PRIMER 8085** system from the PC over a serial connection.

This project is designed for the EMAC PRIMER / EMOS setup running the matching 8085 assembly clock program. The PC utility sends a compact time command over the serial port, and the 8085 program updates the M48T35 Timekeeper RTC.

## What it does

- Opens and keeps the serial port connected for an always-ready sync system.
- Saves COM port, baud rate, DTR/RTS, timeout, repeat interval, and ending settings.
- Defaults to **local time** at startup for safety.
- Supports optional UTC mode, but UTC is not automatically restored as checked on startup.
- Sends the RTC update command in the format expected by the 8085 program.
- Waits for the 8085 live display output to become quiet before sending.
- Retries the sync command if the 8085 responds with `ERR`.
- Provides a live log window showing transmitted commands, decoded time, received responses, and troubleshooting details.

## Tested target setup

- EMAC PRIMER 8085 system
- M48T35 Timekeeper RTC mapped at the top of RAM
- UART already initialized by the EMAC monitor / EMOS environment
- Serial speed: **9600 baud**
- Command ending: **CR**
- DTR: **ON**
- RTS: **ON**
- PC app: Windows C# / .NET desktop application

## 8085 sync command format

The PC sends this ASCII command:

```text
!UYYMMDDWHHMMSS<CR>
```

Field meaning:

```text
YY  = year, 00-99
MM  = month, 01-12
DD  = day of month, 01-31
W   = day of week, 1-7, where 1 = Sunday
HH  = hour, 00-23
MM  = minute, 00-59
SS  = second, 00-59
```

Example:

```text
!U2605097105056<CR>
```

That decodes as:

```text
2026-05-09, day-of-week 7, 10:50:56
```

The 8085 program should return:

```text
OK
```

If the frame is bad or is received at the wrong time, it may return:

```text
ERR
```

## Why the quiet-window sending matters

The 8085 clock program continuously updates the terminal display. While it is printing the big clock screen, it is also only checking serial input at certain points in the main loop. If the PC sends the sync command in the middle of a display burst, the 8085 can receive a partial or damaged command and return `ERR`.

The current PC utility keeps the serial port open, watches the incoming screen output, waits for the display burst to settle, and then sends the sync frame during the quiet window.

## Recommended settings

Use these settings first:

```text
COM Port:       Your USB serial port, for example COM6
Baud:           9600
Timeout sec:    1.0
Repeat sec:     60
Ending:         CR
DTR:            ON
RTS:            ON
Safe Timing:    ON
UTC mode:       OFF for local time
```

## Basic use

1. Start the 8085 clock program on the EMAC PRIMER.
2. Open **EMAC RTC Sync** on the Windows PC.
3. Select the correct COM port.
4. Confirm baud is set to `9600`.
5. Leave ending set to `CR`.
6. Leave DTR and RTS checked.
7. Click **Save + Connect**.
8. Click **Send Once** to test.
9. If the 8085 returns `OK`, use repeating mode if desired.

## Buttons

### Save + Connect

Saves the selected settings and opens the serial port. The connection stays open so future sends are faster and more reliable.

### Send Once

Sends one time-sync command to the 8085.

### Start Repeating / Stop Repeating

Starts or stops automatic repeated syncs using the selected repeat interval.

### Clear Log

Clears the on-screen log only. It does not reset the 8085 or clear saved settings.

## Saved settings location

Settings are saved under:

```text
Documents\EmacRtcSyncGUI\settings.json
```

UTC safety behavior:

```text
UTC mode may be saved in the settings file, but the program starts in LOCAL mode unless UTC is checked again.
```

This prevents accidentally syncing the EMAC RTC to UTC when local time was expected.

## Troubleshooting

### The log says `RX: OK`

The sync worked. The 8085 accepted the command and updated the RTC.

### The log says `RX: ERR`

Check these first:

```text
Baud = 9600
Ending = CR
DTR = ON
RTS = ON
UTC mode = OFF unless you really want UTC
Safe Timing = ON
8085 clock program is running
```

If errors continue, click **Save + Connect** again, then try **Send Once**.

### The log shows screen text mixed with `ERR`

That means the PC is receiving the 8085 live display output and the 8085 rejected a sync frame. Safe timing should reduce this by sending only after the screen update quiets down.

### The COM port will not open

Close any other terminal program that might be using the port, such as PuTTY, Tera Term, Arduino Serial Monitor, or another copy of this app.

### Time is one hour off

Check Windows time zone and daylight-saving settings. Also verify whether UTC mode is checked.

## Included 8085-side behavior

The matching 8085 program:

- Displays a live big ASCII clock in the terminal.
- Shows date and time from the M48T35 RTC.
- Accepts `!UYYMMDDWHHMMSS<CR>` over serial.
- Validates the received date/time fields.
- Writes the values into the RTC.
- Returns `OK` or `ERR` to the PC.
- Uses a persistent saved-clock flag in battery-backed RAM.

## Project notes

This is intentionally a simple utility. The goal is not a complicated terminal emulator. The goal is to keep the serial connection ready, send the exact time frame the 8085 expects, and avoid collisions with the 8085 live screen output.

## License

Add your preferred license here.

For personal and hobby retrocomputing use, a permissive license such as MIT is usually a good fit.
