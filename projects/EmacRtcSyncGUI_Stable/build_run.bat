@echo off
cd /d "%~dp0"
echo Building EMAC RTC Sync...
dotnet build EmacRtcSyncGUI.sln -c Release
if errorlevel 1 (
  echo.
  echo Build failed.
  pause
  exit /b 1
)
echo.
echo Starting...
dotnet run --project EmacRtcSyncGUI\EmacRtcSyncGUI.csproj -c Release
pause
