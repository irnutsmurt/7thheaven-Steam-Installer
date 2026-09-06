@echo off
REM Double-click me. Runs the PowerShell installer with execution-policy bypass
REM so you don't have to change any system settings.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-BigPicture7H.ps1" %*
echo.
pause
