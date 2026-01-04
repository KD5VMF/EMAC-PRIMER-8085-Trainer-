\
@echo off
REM Example launcher for Anaconda Prompt on Windows.
REM 1) Activate your environment (or base) then run this:
REM    run_windows_anaconda.cmd COM9
REM
REM NOTE: Close Tera Term / PuTTY / Arduino Serial Monitor first!
REM       The Python sync needs exclusive access to the COM port.

if "%~1"=="" (
  echo Usage: %~nx0 COM9
  exit /b 1
)

python pc_rtc_sync.py --port %1 --baud 38400 --align --interval 5
