#Requires -Version 5.1
<#
================================================================================
  7th Heaven -> Steam Big Picture installer
--------------------------------------------------------------------------------
  Adds "7th Heaven" to Steam as a Non-Steam Game that launches straight into
  modded FF7, and installs matching Big Picture artwork (poster + hero banner).

  It does this the SAFE way:
    1. Writes a small launch .bat that clears the Steam env vars Steam injects
       (otherwise the modded FF7 process makes Steam re-pop the vanilla launcher).
    2. Gracefully shuts Steam down and WAITS for it to fully exit
       (Steam rewrites shortcuts.vdf on exit, so we must be gone before writing).
    3. Backs up shortcuts.vdf, then adds our entry (idempotent - safe to re-run).
    4. Drops the artwork into Steam's grid folder, keyed to our shortcut's appid.
    5. Relaunches Steam. The shortcut + art appear on next boot.

  Just run it. If you hit an execution-policy error, run instead:
     powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-BigPicture7H.ps1
  (or double-click the included Install.bat, which does that for you.)
================================================================================
#>

param(
    [switch]$Force,     # skip the "close Steam?" confirmation
    [switch]$AllUsers   # install for every Steam account on this PC (default: current/most-recent)
)

$ErrorActionPreference = 'Stop'

# ---- Things you can tweak ------------------------------------------------------
$AppName    = '7th Heaven - Final Fantasy VII Modded'
$PosterFile = Join-Path $PSScriptRoot 'steam images\Bigpicture poster.png'  # 600x900 portrait
$BannerFile = Join-Path $PSScriptRoot 'steam images\banner.png'             # wide hero
# 7th Heaven exe path baked into the launch .bat. %LOCALAPPDATA% expands per-user
# at runtime, so a standard install needs no editing.
$SeventhHeavenExe = '%LOCALAPPDATA%\Programs\7th Heaven\7th Heaven.exe'
# --------------------------------------------------------------------------------

function Write-Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Fail($msg)        { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------------------
# CRC32 + shortcut appid (the id Steam uses for both the vdf entry and the art)
# ------------------------------------------------------------------------------
function Get-Crc32([byte[]]$data) {
    [uint32]$poly = 0xEDB88320L
    $table = New-Object 'System.UInt32[]' 256
    for ($n = 0; $n -lt 256; $n++) {
        [uint32]$c = [uint32]$n
        for ($k = 0; $k -lt 8; $k++) {
            if (($c -band 1) -ne 0) { $c = [uint32](($poly) -bxor [uint32]($c -shr 1)) }
            else                    { $c = [uint32]($c -shr 1) }
        }
        $table[$n] = $c
    }
    [uint32]$crc = [uint32]0xFFFFFFFFL
    foreach ($b in $data) {
        $idx = [int](($crc -bxor [uint32]$b) -band 0xFF)
        $crc = [uint32]($table[$idx] -bxor [uint32]($crc -shr 8))
    }
    return [uint32]($crc -bxor [uint32]0xFFFFFFFFL)
}

function Get-ShortcutAppId([string]$exe, [string]$name) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($exe + $name)
    return [uint32]((Get-Crc32 $bytes) -bor 0x80000000L)
}

# ------------------------------------------------------------------------------
# Binary VDF (shortcuts.vdf) parser + writer.
# Model: each map is an [ArrayList] of field objects {Kind, Key, Value}.
#   Kind = 'str' (string) | 'int' (int32) | 'map' (nested ArrayList of fields)
# ------------------------------------------------------------------------------
function New-Field($kind, $key, $value) {
    [pscustomobject]@{ Kind = $kind; Key = $key; Value = $value }
}

function Read-CString([byte[]]$b, [ref]$pos) {
    $start = $pos.Value
    while ($b[$pos.Value] -ne 0) { $pos.Value++ }
    $s = [System.Text.Encoding]::UTF8.GetString($b, $start, $pos.Value - $start)
    $pos.Value++  # skip null terminator
    return $s
}

function Parse-Fields([byte[]]$b, [ref]$pos) {
    $fields = New-Object System.Collections.ArrayList
    while ($pos.Value -lt $b.Length) {
        $type = $b[$pos.Value]; $pos.Value++
        if ($type -eq 0x08) { break }   # end of this map
        $key = Read-CString $b $pos
        switch ($type) {
            0x00 { $val = Parse-Fields $b $pos;                       $kind = 'map' }
            0x01 { $val = Read-CString $b $pos;                       $kind = 'str' }
            0x02 { $val = [BitConverter]::ToInt32($b, $pos.Value); $pos.Value += 4; $kind = 'int' }
            default { throw "Unknown VDF field type 0x$('{0:X2}' -f $type) at offset $($pos.Value - 1)" }
        }
        [void]$fields.Add((New-Field $kind $key $val))
    }
    return ,$fields
}

function Add-CString([System.Collections.Generic.List[byte]]$list, [string]$s) {
    $list.AddRange([System.Text.Encoding]::UTF8.GetBytes($s))
    $list.Add([byte]0)
}

function Write-Fields([System.Collections.Generic.List[byte]]$list, $fields) {
    foreach ($f in $fields) {
        switch ($f.Kind) {
            'map' { $list.Add([byte]0x00); Add-CString $list $f.Key; Write-Fields $list $f.Value; $list.Add([byte]0x08) }
            'str' { $list.Add([byte]0x01); Add-CString $list $f.Key; Add-CString $list ([string]$f.Value) }
            'int' {
                $list.Add([byte]0x02); Add-CString $list $f.Key
                if ($f.Value -is [uint32]) { $list.AddRange([BitConverter]::GetBytes([uint32]$f.Value)) }
                else                       { $list.AddRange([BitConverter]::GetBytes([int32]$f.Value)) }
            }
        }
    }
}

function Build-ShortcutEntry([string]$index, [uint32]$appid, [string]$name, [string]$exe, [string]$startDir) {
    $f = New-Object System.Collections.ArrayList
    [void]$f.Add((New-Field 'int' 'appid'               $appid))
    [void]$f.Add((New-Field 'str' 'AppName'             $name))
    [void]$f.Add((New-Field 'str' 'Exe'                 $exe))
    [void]$f.Add((New-Field 'str' 'StartDir'            $startDir))
    [void]$f.Add((New-Field 'str' 'icon'                ''))
    [void]$f.Add((New-Field 'str' 'ShortcutPath'        ''))
    [void]$f.Add((New-Field 'str' 'LaunchOptions'       ''))
    [void]$f.Add((New-Field 'int' 'IsHidden'            ([int32]0)))
    [void]$f.Add((New-Field 'int' 'AllowDesktopConfig'  ([int32]1)))
    [void]$f.Add((New-Field 'int' 'AllowOverlay'        ([int32]1)))
    [void]$f.Add((New-Field 'int' 'OpenVR'              ([int32]0)))
    [void]$f.Add((New-Field 'int' 'Devkit'              ([int32]0)))
    [void]$f.Add((New-Field 'str' 'DevkitGameID'        ''))
    [void]$f.Add((New-Field 'int' 'DevkitOverrideAppID' ([int32]0)))
    [void]$f.Add((New-Field 'int' 'LastPlayTime'        ([int32]0)))
    [void]$f.Add((New-Field 'str' 'FlatpakAppID'        ''))
    [void]$f.Add((New-Field 'map' 'tags'                (New-Object System.Collections.ArrayList)))
    return (New-Field 'map' $index $f)
}

# ------------------------------------------------------------------------------
# Locate Steam
# ------------------------------------------------------------------------------
Write-Step "Locating Steam..."
$steamPath = $null
try   { $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch {}
if (-not $steamPath) {
    try { $steamPath = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch {}
}
if (-not $steamPath) { Fail "Could not find Steam in the registry. Is Steam installed?" }
$steamPath = $steamPath -replace '/', '\'
$steamExe  = Join-Path $steamPath 'steam.exe'
if (-not (Test-Path $steamExe)) { Fail "Found Steam path '$steamPath' but no steam.exe there." }
Write-Ok "Steam: $steamPath"

# ------------------------------------------------------------------------------
# Pick which Steam user(s) to install for
# ------------------------------------------------------------------------------
$userdataRoot = Join-Path $steamPath 'userdata'
if (-not (Test-Path $userdataRoot)) { Fail "No userdata folder at $userdataRoot - has anyone logged into Steam on this PC?" }

$userDirs = Get-ChildItem $userdataRoot -Directory | Where-Object { $_.Name -match '^\d+$' -and $_.Name -ne '0' }
if (-not $userDirs) { Fail "No Steam user folders found under $userdataRoot." }

$targetUsers = @()
if ($AllUsers) {
    $targetUsers = $userDirs
} elseif ($userDirs.Count -eq 1) {
    $targetUsers = @($userDirs[0])
} else {
    # Prefer the most-recent account from loginusers.vdf; fall back to newest folder.
    $chosen = $null
    $loginVdf = Join-Path $steamPath 'config\loginusers.vdf'
    if (Test-Path $loginVdf) {
        $raw = Get-Content $loginVdf -Raw
        $m = [regex]::Match($raw, '"(7656\d+)"\s*\{[^}]*?"MostRecent"\s*"1"', 'IgnoreCase, Singleline')
        if ($m.Success) {
            $accountId = [uint64]$m.Groups[1].Value - 76561197960265728
            $chosen = $userDirs | Where-Object { $_.Name -eq "$accountId" } | Select-Object -First 1
        }
    }
    if (-not $chosen) { $chosen = $userDirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
    $targetUsers = @($chosen)
}
Write-Ok ("User(s): " + (($targetUsers | ForEach-Object { $_.Name }) -join ', '))

# ------------------------------------------------------------------------------
# Write the launch .bat to a stable per-user location
# ------------------------------------------------------------------------------
Write-Step "Writing launch wrapper..."
$batDir  = Join-Path $env:LOCALAPPDATA '7thHeaven-BigPicture'
$batPath = Join-Path $batDir 'Launch7thHeaven-BigPicture.bat'
New-Item -ItemType Directory -Force -Path $batDir | Out-Null
$batContent = @"
@echo off
REM Auto-generated by Install-BigPicture7H.ps1 - launches modded FF7 for Steam/Big Picture.
REM Clears the Steam env vars Steam injects so the modded FF7 process does not
REM trigger Steam to relaunch the vanilla FF7 launcher.
set "SteamAppId="
set "SteamGameId="
set "SteamOverlayGameId="
set "SteamClientLaunch="
set "SteamClientLaunchID="
set "SteamTenfoot="

set "SEVENTH_HEAVEN_EXE=$SeventhHeavenExe"

if not exist "%SEVENTH_HEAVEN_EXE%" (
    echo Could not find 7th Heaven.exe at:
    echo   %SEVENTH_HEAVEN_EXE%
    echo Edit this .bat and set SEVENTH_HEAVEN_EXE to the correct path.
    pause
    exit /b 1
)

"%SEVENTH_HEAVEN_EXE%" /LAUNCH /QUIT
"@
Set-Content -Path $batPath -Value $batContent -Encoding ASCII
Write-Ok "Launcher: $batPath"

# The Exe field must match between the appid calc and the vdf entry (Steam quotes it).
$exeField  = '"' + $batPath + '"'
$startDir  = '"' + $batDir + '\"'
$appId     = Get-ShortcutAppId $exeField $AppName
Write-Ok ("Shortcut appid: {0}" -f $appId)

# ------------------------------------------------------------------------------
# Shut Steam down (and remember to relaunch)
# ------------------------------------------------------------------------------
$steamWasRunning = [bool](Get-Process -Name steam -ErrorAction SilentlyContinue)
if ($steamWasRunning) {
    if (-not $Force) {
        Write-Warn2 "Steam needs to close to safely add the shortcut (this will also close any running Steam games)."
        $ans = Read-Host "    Close Steam now and continue? [Y/N]"
        if ($ans -notmatch '^(y|yes)$') { Fail "Cancelled by user." }
    }
    Write-Step "Shutting Steam down..."
    & $steamExe -shutdown | Out-Null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Process -Name steam -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
        Write-Warn2 "Steam did not exit gracefully in time; forcing it closed."
        Get-Process -Name steam -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    Write-Ok "Steam closed."
}

# ------------------------------------------------------------------------------
# For each target user: back up + update shortcuts.vdf, install artwork
# ------------------------------------------------------------------------------
foreach ($user in $targetUsers) {
    Write-Step ("Configuring Steam user {0}..." -f $user.Name)
    $configDir    = Join-Path $user.FullName 'config'
    $shortcutsVdf = Join-Path $configDir 'shortcuts.vdf'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    # ---- Load or create the shortcuts structure ----
    if (Test-Path $shortcutsVdf) {
        $backup = "$shortcutsVdf.bak-" + (Get-Date -Format 'yyyyMMddHHmmss')
        Copy-Item $shortcutsVdf $backup -Force
        Write-Ok "Backup: $backup"
        $bytes = [System.IO.File]::ReadAllBytes($shortcutsVdf)
        $pos = 0
        $root = Parse-Fields $bytes ([ref]$pos)
    } else {
        $root = New-Object System.Collections.ArrayList
        [void]$root.Add((New-Field 'map' 'shortcuts' (New-Object System.Collections.ArrayList)))
    }

    $sc = $root | Where-Object { $_.Kind -eq 'map' -and $_.Key -ieq 'shortcuts' } | Select-Object -First 1
    if (-not $sc) {
        $sc = New-Field 'map' 'shortcuts' (New-Object System.Collections.ArrayList)
        [void]$root.Add($sc)
    }
    # Ensure the entries container is a mutable ArrayList
    if ($sc.Value -isnot [System.Collections.ArrayList]) {
        $tmp = New-Object System.Collections.ArrayList
        foreach ($e in $sc.Value) { [void]$tmp.Add($e) }
        $sc.Value = $tmp
    }

    # ---- Is our shortcut already there? (match on AppName) ----
    $existing = $null
    foreach ($e in $sc.Value) {
        $an = $e.Value | Where-Object { $_.Kind -eq 'str' -and $_.Key -ieq 'AppName' } | Select-Object -First 1
        if ($an -and $an.Value -eq $AppName) { $existing = $e; break }
    }

    if ($existing) {
        # Update the fields we care about, keep everything else.
        function Set-EntryField($entry, $kind, $key, $value) {
            $fld = $entry.Value | Where-Object { $_.Key -ieq $key } | Select-Object -First 1
            if ($fld) { $fld.Kind = $kind; $fld.Value = $value }
            else      { [void]$entry.Value.Add((New-Field $kind $key $value)) }
        }
        Set-EntryField $existing 'int' 'appid'    $appId
        Set-EntryField $existing 'str' 'Exe'      $exeField
        Set-EntryField $existing 'str' 'StartDir' $startDir
        Write-Ok "Updated existing '$AppName' shortcut."
    } else {
        $index = "$($sc.Value.Count)"
        [void]$sc.Value.Add((Build-ShortcutEntry $index $appId $AppName $exeField $startDir))
        Write-Ok "Added '$AppName' shortcut."
    }

    # ---- Re-index entries 0..n-1 (Steam expects sequential keys) ----
    for ($i = 0; $i -lt $sc.Value.Count; $i++) { $sc.Value[$i].Key = "$i" }

    # ---- Serialize + write ----
    $out = New-Object 'System.Collections.Generic.List[byte]'
    Write-Fields $out $root
    $out.Add([byte]0x08)   # close the implicit root object
    [System.IO.File]::WriteAllBytes($shortcutsVdf, $out.ToArray())
    Write-Ok "Wrote $shortcutsVdf"

    # ---- Install artwork into the grid folder, keyed to our appid ----
    $gridDir = Join-Path $configDir 'grid'
    New-Item -ItemType Directory -Force -Path $gridDir | Out-Null
    if (Test-Path $PosterFile) {
        Copy-Item $PosterFile (Join-Path $gridDir "$($appId)p.png") -Force   # portrait library capsule
        Write-Ok "Poster -> $($appId)p.png"
    } else { Write-Warn2 "Poster not found at '$PosterFile' - skipped." }
    if (Test-Path $BannerFile) {
        Copy-Item $BannerFile (Join-Path $gridDir "$($appId)_hero.png") -Force # library hero
        Copy-Item $BannerFile (Join-Path $gridDir "$($appId).png")      -Force # landscape/grid tile
        Write-Ok "Banner -> $($appId)_hero.png, $($appId).png"
    } else { Write-Warn2 "Banner not found at '$BannerFile' - skipped." }
}

# ------------------------------------------------------------------------------
# Relaunch Steam
# ------------------------------------------------------------------------------
if ($steamWasRunning) {
    Write-Step "Relaunching Steam..."
    Start-Process $steamExe
    Write-Ok "Steam is starting back up."
}

Write-Host ""
Write-Host "Done! '$AppName' is now in your Steam library with Big Picture artwork." -ForegroundColor Green
Write-Host "If Steam was already open, give it a few seconds to reappear." -ForegroundColor Green
