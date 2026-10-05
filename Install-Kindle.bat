@echo off
cd /d "%~dp0"

rem ---- check for administrator privileges ----
net session >nul 2>&1
if %errorlevel%==0 goto ELEVATED

echo.
echo  Requesting administrator privileges (click YES on the UAC prompt)...
echo.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:ELEVATED
echo.
echo  [OK] Running as administrator.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-kindle.ps1"
