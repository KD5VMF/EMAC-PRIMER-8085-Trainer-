# EMAC PRIMER 8085 + M48T35 Timekeeper Clock (Serial + PC Sync)

This repo contains **two matching pieces**:

1. **8085 assembly program** (loads at **9000h**) that displays the Date/Time from your upgraded **battery‑backed Timekeeper RAM/RTC** module (M48T35‑style) and accepts time updates over the serial port.
2. **Python serial utility** that reads your PC time and sends updates to the PRIMER over the same serial connection.

> Important: **Only one program can own the serial COM port at a time.**  
> When you run the Python sync tool, you must **close Tera Term (or any other terminal program)** first.

---

## Files in this ZIP

- `pc_rtc_sync.ASM` – 8085 source (loads/runs at 9000h)
- `pc_rtc_sync_9000.hex` – Intel HEX you send to the PRIMER at 9000h
- `pc_rtc_sync.py` – Python time sync tool (pyserial)
- `requirements.txt` – Python dependency list
- `screenshot_terminal.png` – example of what you’ll see on the terminal
- `run_windows_anaconda.cmd` – helper launcher (Windows)
- `run_linux.sh` – helper launcher (Linux)

---

## Hardware / memory map assumptions

This build targets an **EMAC PRIMER 8085** that has been upgraded to a **Timekeeper RAM+RTC module** (M48T35‑style).  
Instead of the original “separate RTC chip” approach, the RTC registers live in the **top bytes of the RAM address space**, and the RAM is battery‑backed.

The assembly uses this **memory mapped RTC register block**:

- `FFF8` – seconds (BCD)
- `FFF9` – minutes (BCD)
- `FFFA` – hours (BCD)
- `FFFB` – day of week (BCD/flags depending on module)
- `FFFC` – date/day of month (BCD)
- `FFFD` – month (BCD)
- `FFFE` – year (BCD, 00–99)
- `FFFF` – control/flags (read/clear flags depending on module)

The program also assumes the PRIMER serial port is working at **38400 8N1**.

---

## What you’ll see when it runs

When you `G 9000` you’ll get a screen like the screenshot:

- A title line showing the project name.
- The current **DATE** and **TIME** in decimal, and a live updating display.
- A line like `MODE: DEC  22:12:18 HEX>` showing both decimal/hex style hints.
- Key help at the bottom, including:
  - `S` = set clock (manual set from keyboard)
  - `C` = clear RTC flag
  - `Q` = redraw
  - `E` = exit
  - `SW0` toggles DEC/HEX on the 7‑segment (if you have that wired/enabled)

---

## Load & run on the EMAC PRIMER (Tera Term + EMOS)

### 1) Open Tera Term
- Connect to the PRIMER serial port (example: **COM9**) at **38400**, 8N1.
- You should be at the EMOS prompt.

### 2) Tell EMOS where to load the HEX (9000h)
At the prompt, type:

```
>9000
```

### 3) Send the HEX file
In Tera Term:
- **File → Send file…**
- Select: `pc_rtc_sync_9000.hex`
- Send as **text** (normal “Send file”)

You should see Intel HEX lines scroll by and then return to the prompt.

### 4) Run it
At the prompt:

```
G 9000
```

That’s it — the clock UI starts.

---

## PC time sync utility (Python)

The Python tool opens the **same serial port** and periodically sends a “set time” packet to the PRIMER program.

### IMPORTANT: close your terminal program first
- Close Tera Term / PuTTY / Arduino Serial Monitor
- Then run the Python sync tool (so it can open the COM port)

### Windows 11 (Anaconda)
From **Anaconda Prompt**:

```bat
conda create -n envTimeSync python=3.11 -y
conda activate envTimeSync
pip install -r requirements.txt

python pc_rtc_sync.py --port COM9 --baud 38400 --align --interval 5
```

Or use the helper:

```bat
run_windows_anaconda.cmd COM9
```

### Linux
```bash
python3 -m venv envTimeSync
source envTimeSync/bin/activate
pip install -r requirements.txt

python3 pc_rtc_sync.py --port /dev/ttyUSB0 --baud 38400 --align --interval 5
```

Or:

```bash
chmod +x run_linux.sh
./run_linux.sh /dev/ttyUSB0
```

### Options
- `--once` : send one update and exit
- `--interval N` : keep updating every N seconds
- `--utc` : use UTC instead of local time
- `--align` : align the send to just after a second tick (best accuracy)

Run `python pc_rtc_sync.py -h` for the full list.

---

## Common problems

### “Access denied / COM port busy”
Another program still has the serial port open.  
Close Tera Term (or whatever is connected) and try again.

### “Nothing changes on the PRIMER”
Make sure:
- You loaded and ran the 8085 program (`G 9000`)
- You closed Tera Term before starting Python
- You used the correct COM port and baud

---

## License
Use whatever license you prefer for your GitHub repo (MIT is common).  
If you want, tell me “MIT” (or another), and I’ll add the license file.
