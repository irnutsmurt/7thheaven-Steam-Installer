@echo off
REM ============================================================
REM  7th Heaven - Steam / Big Picture launch wrapper
REM ------------------------------------------------------------
REM  WHAT THIS DOES
REM  When you add 7th Heaven to Steam as a Non-Steam Game, Steam
REM  injects its own SteamAppId / SteamGameId environment variables
REM  into the shortcut. The modded FF7 process that 7th Heaven
REM  spawns inherits those variables, which makes Steamworks think
REM  it was launched wrong and ask Steam to relaunch FF7 -- popping
REM  the vanilla Square Enix launcher and killing the modded game.
REM
REM  This wrapper clears those inherited variables first, so the
REM  modded FF7 boots cleanly. Add THIS .bat to Steam instead of
REM  7th Heaven.exe directly.
REM
REM  Because 7th Heaven.exe is called directly (no START), this
REM  window stays alive for the whole session, so Steam keeps
REM  showing "Playing" until FF7 closes.
REM ============================================================

REM --- Strip the Steam launch variables Steam injects ---
set "SteamAppId="
set "SteamGameId="
set "SteamOverlayGameId="
set "SteamClientLaunch="
set "SteamClientLaunchID="
set "SteamTenfoot="

REM --- Path to 7th Heaven. The default below works for a standard
REM     install. If you installed 7th Heaven somewhere custom, edit
REM     this one line to point at your 7th Heaven.exe. ---
set "SEVENTH_HEAVEN_EXE=%LOCALAPPDATA%\Programs\7th Heaven\7th Heaven.exe"

if not exist "%SEVENTH_HEAVEN_EXE%" (
    echo Could not find 7th Heaven.exe at:
    echo   %SEVENTH_HEAVEN_EXE%
    echo.
    echo Edit this .bat and set SEVENTH_HEAVEN_EXE to the correct path.
    pause
    exit /b 1
)

REM --- Launch: apply active profile's mods, boot FF7, quit 7H when FF7 closes ---
"%SEVENTH_HEAVEN_EXE%" /LAUNCH /QUIT
