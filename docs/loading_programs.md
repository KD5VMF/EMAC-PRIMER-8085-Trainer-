# Loading and running programs (A000h)

These projects are written as **8085 assembly** and are intended to be loaded into **RAM at A000h** and executed with:

```
G A000
```

Because the EMAC PRIMER has been shipped with multiple monitor/EMOS variants, the exact keystrokes can differ slightly — but the common pattern is:

1) Enter **Intel HEX download mode** in the monitor  
2) **Send the `.hex` file** from your PC over the serial port  
3) (Optional) **Verify** the bytes landed in RAM  
4) Run: `G A000`

This doc gives a clean, step‑by‑step “do this, then this” workflow.

---

## What you need

- EMAC PRIMER connected to your PC via serial (USB‑serial adapter is fine).
- A terminal program that can **send an ASCII file** (Intel HEX) with optional pacing.
  - **Windows:** Tera Term (recommended), RealTerm, ExtraPuTTY plugins, etc.
  - **Linux:** `minicom`, `screen`, `picocom` (file send varies).
- Your assembled **Intel HEX** file:
  - Lines start with `:`
  - End with an EOF record like: `:00000001FF`
  - Contains addresses starting at **A000** (because these projects use `ORG 0A000H`).

---

## Serial settings (typical)

Most PRIMER setups people use with EMOS/monitor are:

- **Baud:** 38400 (yours is often locked here)
- **Data bits:** 8
- **Parity:** None
- **Stop bits:** 1
- **Flow control:** None (no RTS/CTS, no XON/XOFF)

If your screen is gibberish, your baud rate or framing is wrong.

---

## Step-by-step: load an Intel HEX file (Windows + Tera Term)

### 1) Connect and open the monitor
1. Plug in the serial cable / USB‑serial adapter.
2. Open **Tera Term** → choose the COM port.
3. Configure: **Setup → Serial port…**
   - Speed: **38400**
   - Data: **8 bit**
   - Parity: **none**
   - Stop: **1**
   - Flow control: **none**
4. Press **Reset** on the PRIMER (or power cycle).
5. Confirm you see the monitor/EMOS prompt/menu and typing works.

### 2) Put the PRIMER into Intel HEX receive mode
On many EMOS 2.00 style menus, the command is:

- `<`  (hex download)

So you typically type:
```
<
```

Some monitors will print a short message like “DOWNLOAD” or “SEND HEX”, others just wait silently.

> If your monitor uses a different command, use its help menu to find the “Intel HEX load / download” feature.

### 3) Send the `.hex` file from Tera Term
1. **File → Send file…**
2. Choose your `.hex` file.
3. **Check** “Send as text” / “ASCII” (wording depends on Tera Term version).
4. If available, set **Transmit delay** (this matters!):
   - Start with **Line delay: 5–15 ms**
   - Char delay: **0–1 ms**
5. Click **Open/Send**.

You should see hex records scroll by.

### 4) Confirm the download completed
A successful load usually ends when the PRIMER receives the EOF record (`:00000001FF`) and returns to a prompt.

If it immediately prints **CHECKSUM ERROR** or stops partway:
- Increase line delay (e.g., 20–50 ms).
- Ensure flow control is **NONE**.
- Make sure “CR/LF translation” is OFF (don’t add extra CRs).
- Try again.

### 5) Optional: verify memory
If your monitor supports memory dump, dump a small range to confirm the bytes landed:

Example (monitor-dependent):
```
D A000 A040
```

### 6) Run the program
Start execution at A000:

```
G A000
```

---

## Troubleshooting (most common)

### “CHECKSUM ERROR !”
Almost always caused by the PC sending too fast or the terminal altering the file.

Fixes:
- Increase **line delay** (try 20 ms, then 50 ms).
- Ensure sending as **ASCII/text** (not binary).
- Disable any options that add extra characters (CR/LF conversions).
- Confirm the HEX file is “clean” (every line starts with `:` and has the right checksum).

### It loads but crashes / reboots
- Make sure your program is built for **A000h** and doesn’t overwrite the monitor workspace/stack.
- Keep your stack away from A000 (these projects set SP to a safe high RAM value).
- Verify your RAM map is correct (ROM 0000–7FFF, RAM 8000–FFFF).

### Nothing happens when you type the load command
- Verify you are at the correct monitor prompt (some menus show but don’t accept input if UART init isn’t right).
- Confirm flow control is OFF.
- Confirm local echo settings don’t confuse you (echo is usually handled by the PRIMER, not the terminal).

---

## Recommended order (for this repo)

1) **RTC test**: confirms your M48T35 seconds tick  
   `projects/A000_RTC_Seconds_Test/PRIMER_A000_M48T35_RTC_SECONDS_TEST.asm`

2) **Runtime HHMMSS (M48T35 tick)**: uses RTC seconds as the 1‑second ticker  
   `projects/A000_Runtime_HHMMSS_M48T35/PRIMER_A000_M48T35_RUNTIME_HHMMSS_NOLEAD_NOFLICKER.asm`

3) **8155 runtime**: alternate ticker method  
   `projects/A000_Runtime_HHMMSS_8155/PRIMER_A000_8155_RUNTIME_HHMMSS.asm`
