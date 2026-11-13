@echo off
setlocal
cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
  echo Node.js 22.13 or newer is required.
  echo Install Node.js, then run this file again.
  pause
  exit /b 1
)

echo Starting the Corvia payment website preview...
echo Open http://127.0.0.1:8080 in your browser.
echo This local preview has checkout disabled.
echo.
npm run preview

echo.
echo The local website stopped.
pause
