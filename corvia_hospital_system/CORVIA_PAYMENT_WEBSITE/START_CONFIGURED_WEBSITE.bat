@echo off
setlocal
cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
  echo Node.js 22.13 or newer is required.
  pause
  exit /b 1
)

if not exist ".env" (
  echo The configured website cannot start because .env is missing.
  echo Copy .env.example to .env and add the Supabase and PayFast details first.
  echo Never commit or send the completed .env file.
  pause
  exit /b 1
)

echo Starting the configured Corvia payment website...
echo The server will refuse unsafe or incomplete live configuration.
echo.
npm start

echo.
echo The configured website stopped.
pause
