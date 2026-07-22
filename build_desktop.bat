@echo off
setlocal
cd /d "%~dp0"

REM Forward args to PowerShell. Default: flutter build --release only.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_desktop.ps1" %*
set ERR=%ERRORLEVEL%

if %ERR% neq 0 (
  echo.
  echo Build failed with code %ERR%
  echo.
  pause
  exit /b %ERR%
)

exit /b 0
