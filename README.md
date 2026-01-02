# EMAC PRIMER + M48T35 Timekeeper Toolkit

This repo is a “works-on-real-hardware” collection of notes and 8085 assembly projects for the **EMAC PRIMER Trainer**, upgraded with an **M48T35 Timekeeper RAM/RTC** mapped into **8000–FFFF**.

It includes:
- A proven **A000h runtime HHMMSS** demo that **ticks off RTC seconds** (no timer chips required),
  with **leading-zero blanking** and **no flicker** (updates only changed digits).
- A simple **RTC seconds sanity test** (SS on the rightmost digits).
- An **8155-timer** runtime HHMMSS demo (alternate ticker method).
- Clear documentation for the **ROM upgrade** and the **M48T35 RAM/RTC mapping**.

> **ROM image name (your build):** `EMOS_200_M48T35_SAFE_v2025.hex`  
> Place your ROM hex in `firmware/rom/` and follow the flashing notes in `docs/rom_upgrade.md`.

---

## Quick start

### 1) Flash the ROM
See: `docs/rom_upgrade.md`

### 2) Run a demo
All demo programs are intended to be loaded at **A000h** and started with:

```
G A000
```

Recommended order:
1) `projects/A000_RTC_Seconds_Test/PRIMER_A000_M48T35_RTC_SECONDS_TEST.asm`
2) `projects/A000_Runtime_HHMMSS_M48T35/PRIMER_A000_M48T35_RUNTIME_HHMMSS_NOLEAD_NOFLICKER.asm`
3) `projects/A000_Runtime_HHMMSS_8155/PRIMER_A000_8155_RUNTIME_HHMMSS.asm`

---

## Memory map assumptions

- **ROM:** `0000–7FFF`
- **RAM (M48T35):** `8000–FFFF`
- **M48T35 RTC registers:** `FFF8–FFFF`
  - `FFF8` control
  - `FFF9` seconds (BCD, **bit7 = STOP**)

More: `docs/memory_map.md` and `docs/m48t35_notes.md`

---

## License

MIT (see `LICENSE`).
