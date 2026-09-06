# 7th Heaven - Steam Big Picture Launcher

Adds [7th Heaven](https://github.com/tsunamods-codes/7th-Heaven) (the Final Fantasy VII
mod manager) to Steam as a Non-Steam Game so you can launch straight into modded FF7
from Steam or Big Picture mode, with matching library artwork. When you quit the game,
7th Heaven closes itself automatically.

The installer does the whole thing for you: it finds Steam, adds the shortcut, installs
the poster and banner art, and restarts Steam.

---

## Screenshots

![7th Heaven for FFVII in Steam Big Picture mode](https://i.imgur.com/wgl7OkC.png)

![7th Heaven for FFVII in Steam Big Picture mode](https://i.imgur.com/53YB0Qo.png)

---

## Read this first

**You must fully set up 7th Heaven before using this.** This package only adds a Steam
shortcut that launches whatever 7th Heaven is already configured to run. It does not
install, configure, or activate any mods for you.

If you run 7th Heaven for the first time through this shortcut without configuring it,
the game will launch with **zero mods active**. So before you install this, open 7th
Heaven normally and:

- Point it at your Final Fantasy VII installation and let it finish the game conversion.
- Download and activate the mods you want.
- Set up and select the profile you want to play with.
- Confirm it all works by launching the game once from 7th Heaven itself.

Once modded FF7 launches correctly from 7th Heaven, come back and install this.

---

## Quick start

1. Install [7th Heaven](https://github.com/tsunamods-codes/7th-Heaven) and **fully
   configure it first** - see "Read this first" above. This is required, or you will have
   no mods active.
2. Download this folder (Code -> Download ZIP, then extract it) and keep all the files
   together.
3. Double-click **Install.bat**.
4. When prompted, let it close Steam. It will add the shortcut and reopen Steam.
5. Find **7th Heaven - Final Fantasy VII Modded** in your Steam library and launch it.

That is it. Modded FF7 boots straight up, and 7th Heaven closes when you exit the game.

---

## Requirements

- Windows
- Steam (any install location - it is found automatically)
- 7th Heaven, already installed and configured with the mods you want active
- Administrator rights are **not** required in normal cases

---

## What it does and why it is needed

When you add 7th Heaven to Steam as a Non-Steam Game, Steam injects its own launch
environment variables into the shortcut. The modded FF7 process that 7th Heaven starts
inherits those variables, which makes Steam think the game was launched incorrectly and
relaunch the vanilla Square Enix launcher on top of it, killing the modded game.

This package works around that by launching 7th Heaven through a small wrapper batch file
that clears those inherited variables first, so the modded game boots cleanly.

The installer:

1. Writes the launch wrapper to `%LOCALAPPDATA%\7thHeaven-BigPicture\`.
2. Locates Steam from the registry and picks your current Steam account.
3. Gracefully shuts Steam down and waits for it to fully exit (Steam rewrites its
   shortcuts file on exit, so it must be closed before writing).
4. Backs up `shortcuts.vdf` (timestamped) and adds the shortcut. Safe to re-run - it
   updates the existing entry instead of creating duplicates.
5. Copies the poster and banner into Steam's artwork folder, keyed to the shortcut so the
   art appears automatically.
6. Relaunches Steam.

---

## Launch options explained

The shortcut runs 7th Heaven with `/LAUNCH /QUIT`:

- `/LAUNCH` starts the game using your currently active 7th Heaven profile and mods.
- `/QUIT` waits for FF7 to close, then shuts 7th Heaven down automatically.

---

## Making it show up nicely in Big Picture

Non-Steam games always appear under the **Non-Steam** shelf in Big Picture. That grouping
is set by Steam and cannot be changed. To keep the game up front instead of buried in that
shelf:

- **Favorite it:** right-click the game in your library -> Add to -> Favorites.
- **Add it to a Collection:** Collections appear as their own rows in Big Picture.
- It will also show under **Recent** automatically after you play it once.

---

## Manual method (no installer)

If you would rather not run the installer, you can set it up by hand:

1. Edit **Launch7thHeaven-BigPicture.bat** if your 7th Heaven is installed somewhere other
   than the default location, then save it somewhere permanent.
2. In Steam: Games -> Add a Non-Steam Game -> Browse -> set the file filter to All Files ->
   select the `.bat`.
3. Leave the launch options empty (the `/LAUNCH /QUIT` is already inside the `.bat`).
4. Optionally set the artwork by right-clicking the game in your library and using
   Set Custom Artwork with the images in the `steam images` folder.

---

## Renaming the shortcut

The shortcut is named `7th Heaven - Final Fantasy VII Modded`. To change it, edit the
`$AppName` line near the top of **Install-BigPicture7H.ps1** before running. If you rename
it after already installing, remove the old shortcut from Steam first so you do not end up
with two entries.

---

## Troubleshooting

**"Running scripts is disabled on this system" / execution policy error**
Use **Install.bat** rather than running the `.ps1` directly. It runs PowerShell with an
execution-policy bypass for that one session only and changes no system settings.

**The game launches but no mods are active**
7th Heaven was not configured before you used the shortcut. This tool does not set up
mods. Open 7th Heaven directly, configure your game path, activate your mods, and select
a profile, then confirm the game launches modded from 7th Heaven itself. See
"Read this first" at the top.

**The game launches but the vanilla FF7 launcher appears**
This is the exact problem the wrapper prevents. Make sure Steam is launching the `.bat`
(via the installer) and not `7th Heaven.exe` directly.

**"Could not find 7th Heaven.exe at ..."**
Your 7th Heaven is installed somewhere other than the default location. Open the launch
wrapper at `%LOCALAPPDATA%\7thHeaven-BigPicture\Launch7thHeaven-BigPicture.bat` and set the
`SEVENTH_HEAVEN_EXE` line to the correct path.

**Access denied writing shortcuts.vdf**
Rare, and only if your Steam folder permissions are locked down. Right-click **Install.bat**
and choose Run as administrator.

**The shortcut did not appear**
Give Steam a few seconds to finish restarting. If it still does not show, check that the
Big Picture library filter is not hiding non-Steam games, and restart Steam fully.

---

## Uninstall

1. In Steam, right-click the shortcut -> Manage -> Remove non-Steam game from your library.
2. Delete the folder `%LOCALAPPDATA%\7thHeaven-BigPicture\`.
3. Optionally delete the copied artwork from
   `<Steam>\userdata\<your-id>\config\grid\` (the files whose names are the shortcut's
   numeric id).

The installer keeps timestamped backups of `shortcuts.vdf` next to the original
(`shortcuts.vdf.bak-...`) if you ever need to restore it.

---

## Files in this folder

| File | Purpose |
| --- | --- |
| `Install.bat` | Double-click entry point. Runs the installer with an execution-policy bypass. |
| `Install-BigPicture7H.ps1` | The installer. Adds the Steam shortcut and artwork. |
| `Launch7thHeaven-BigPicture.bat` | Standalone launch wrapper for the manual method. |
| `steam images/` | The poster (600x900) and banner artwork installed by the script. |

---

## Notes and credits

- 7th Heaven is developed by the [Tsunamods team](https://github.com/tsunamods-codes/7th-Heaven).
  This project is an unofficial helper for launching it through Steam and is not affiliated
  with them.
- The installer edits Steam's `shortcuts.vdf`. It backs the file up first, but as with any
  tool that touches Steam config, use it at your own discretion.
