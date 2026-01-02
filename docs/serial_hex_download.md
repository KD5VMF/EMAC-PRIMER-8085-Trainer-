# Sending Intel HEX to the EMAC PRIMER (practical “works every time”)

This is the condensed “do this exactly” version aimed at avoiding checksum errors.

## Windows + Tera Term (recommended)
1) Open Tera Term → select your COM port  
2) Setup → Serial port…
   - 38400, 8N1
   - Flow control: NONE
3) Reset PRIMER, confirm prompt/menu
4) Enter Intel HEX receive mode (commonly `<`)
5) File → Send file…
   - choose `.hex`
   - **Send as text / ASCII**
   - **Line delay: 20 ms** (start here; lower later if it’s stable)
   - Char delay: 0
6) Wait for EOF record and prompt to return
7) Run: `G A000`

## If you still get CHECKSUM ERROR
- Increase line delay to **50 ms**
- Make sure:
  - No “append CR/LF” options are enabled
  - No XON/XOFF or RTS/CTS flow control
- Re-export your HEX from your assembler (corrupted copy/paste can break checksums)

## Good HEX file checklist
- Every line starts with `:`
- Final line is `:00000001FF`
- Addresses match your `ORG` (A000h for these projects)

## Tip: verify by dumping memory
If your monitor supports a dump command, dump a short range after loading and compare
against your HEX file’s first few data records.
