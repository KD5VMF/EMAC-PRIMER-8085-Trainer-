# Changelog

## 2026-01-02
- Added M48T35 RTC seconds tick runtime HHMMSS demo
  - leading-zero blanking
  - no-flicker (change-only digit updates)
  - correct wrap (59->00 minutes, 23->00 hours)
- Added RTC seconds sanity test (SS on rightmost digits)
- Added alternate 8155 timer based runtime demo
