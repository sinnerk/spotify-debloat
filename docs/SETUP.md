# Setup

Step-by-step install for a clean Windows machine. Ten minutes if Spotify and Spicetify
are already installed; about fifteen if they are not.

You do **not** need administrator rights, a Spotify Premium account, or a GitHub token.

## What you need

| Requirement | Notes |
| --- | --- |
| Windows 10 or 11 | Windows PowerShell 5.1 is built in. PowerShell 7 also works. |
| Spotify for Windows | Install from [spotify.com/download](https://www.spotify.com/download/windows/), **not** the Microsoft Store build. Sign in once so the client creates its profile. |
| Spicetify CLI | Version 2.46 or newer. Install command below. |
| Internet | First install downloads the preset's ten extensions. Browsing the committed catalog is offline. |
| Free disk space | About 500 MB for the one-time Spicetify backup. |

Close Spotify before you start. The installer will close it anyway if it is running.

## 1. Install Spotify and open it once

Install Spotify with the normal Windows installer. Launch it, sign in, let it finish its
first-run setup, then close it. Spicetify patches files inside the installed client, so a
Store/MSIX install will not work.

## 2. Install the Spicetify CLI

In PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/spicetify/cli/main/install.ps1 | iex
```

Close and reopen PowerShell, then verify:

```powershell
spicetify --version
```

Expected: `2.46.x` or newer. If the command is not found, the installer added
`%LOCALAPPDATA%\spicetify` to `PATH` but this shell started before that; open a new one.

If Spicetify is already installed, check it is current:

```powershell
spicetify update
```

## 3. Get this repository

With Git:

```powershell
git clone https://github.com/sinnerk/spotify-debloat.git
cd spotify-debloat
```

Without Git: open the repository page, choose **Code → Download ZIP**, extract it, and
open PowerShell in the extracted folder.

All commands below are run **from the repository root** (the folder containing
`lean.ps1`).

## 4. Allow the script to run

Windows blocks downloaded `.ps1` files by default. For the current PowerShell window only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

That setting disappears when the window closes; it does not change the machine policy.
Alternatively, call the script through a bypassing host:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\lean.ps1 install
```

## 5. Check the machine, then rehearse

Both commands change nothing:

```powershell
.\lean.ps1 doctor
.\lean.ps1 install -DryRun
```

`doctor` prints one line per check. You want every line to be `PASS` or `INFO`; a `FAIL`
line includes the fix. `-DryRun` lists the exact settings, files and extensions that the
real install would touch.

## 6. Install

```powershell
.\lean.ps1 install
```

What happens, in order:

1. Spicetify creates a one-time backup of the Spotify client (about 400 MB).
2. Debloat settings are written: Sentry and UI logging off, four analytics hosts mapped
   to `127.0.0.1` at launch.
3. The Lean theme is copied to `%APPDATA%\spicetify\Themes\Lean`.
4. Ten extensions from the `lean` preset are downloaded to
   `%LOCALAPPDATA%\spicetify\Extensions` and enabled.
5. Spicetify applies the patch and reopens Spotify.

Expect one to three minutes, mostly download and the backup.

## 7. Check the result

With Spotify open:

```powershell
.\lean.ps1 status
```

You should see `Theme Lean`, `Profile lean`, `Extensions 11 enabled` (ten preset
extensions plus the theme's `lean-ui.js`) and `Telemetry map active`.

In the client, a small **Lean** pill appears in the top bar. Click it to toggle the
debloat CSS on and off without restarting; the choice is stored in `localStorage`. From
the DevTools console the same switch is `Lean.toggle()` and the state is `Lean.enabled`.

## 8. Optional: measure it

The installer deliberately does not benchmark: its post-patch first run is dominated by
indexing and is not comparable to anything. Take a steady-state sample instead:

```powershell
.\lean.ps1 benchmark -Label lean -Seconds 45 -Warmup 20 -Restart
```

The report lands in `reports/<timestamp>-lean.json`. See
[BENCHMARKS.md](BENCHMARKS.md) for what the numbers mean and their limits.

## Choose a different preset

```powershell
.\lean.ps1 extensions -Profile minimal   # theme and debloat only
.\lean.ps1 extensions -Profile lean      # back to the curated ten
.\lean.ps1 extensions -Profile full -Force
```

`full` enables every compatible extension in the catalog (currently 399 after policy
filters). It is a stress test, not a daily driver.

Pick individual extensions by catalog id:

```powershell
.\lean.ps1 catalog -Search lyrics -Top 10
.\lean.ps1 extensions -Ids spicetify-cli--shuffle,rxri-spicetify-extensions--songstats
```

## Update

```powershell
git pull
.\lean.ps1 install
```

Re-running install is idempotent: it prunes extensions that left the preset, refreshes
the theme, and keeps one Spicetify backup. If Spotify itself updated and the patch
broke, read [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first; a `spicetify backup apply`
may be all that is needed.

## Uninstall

```powershell
.\lean.ps1 restore
```

This removes the managed extensions and theme, restores the Spicetify settings saved at
install time, unblocks auto-updates if they were blocked, and runs
`spicetify restore backup apply`. To remove Spicetify too, run `spicetify restore` and
delete `%APPDATA%\spicetify`.

## Common first-run problems

| Symptom | Fix |
| --- | --- |
| `lean.ps1 cannot be loaded because running scripts is disabled` | Step 4. Use `-ExecutionPolicy Bypass` for the process. |
| `spicetify` is not recognized | Open a new PowerShell window, or run `%LOCALAPPDATA%\spicetify\spicetify.exe` directly. |
| `doctor` says the Spotify version is unsupported | Update Spotify, then run `spicetify backup apply`; read [MAINTAINING.md](MAINTAINING.md). |
| Install stops at "Applying Spicetify patches" | Spotify is still running. Close it from the tray, then retry. |
| Nothing looks different | Run `.\lean.ps1 status`; if theme is Lean but the UI is stock, check for `[spotify-debloat] lean-ui` in the DevTools console. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md). |
| Antivirus quarantines `spicetify.exe` | Add `%LOCALAPPDATA%\spicetify` to exclusions. The CLI is unsigned, like most patching tools. |

## What gets written where

| Path | Contents |
| --- | --- |
| `%APPDATA%\spicetify\config-xpui.ini` | Spicetify settings, including the Lean debloat keys |
| `%APPDATA%\spicetify\Themes\Lean` | `user.css`, `color.ini`, `lean-ui.js` |
| `%LOCALAPPDATA%\spicetify\Extensions` | Downloaded preset extensions |
| `%APPDATA%\Spotify\Apps\xpui` | The copy Spicetify actually loads; regenerated by `spicetify apply` |
| `%APPDATA%\spicetify\lean-state.json` | What this project changed, so `restore` can undo it |

Nothing is written to `Program Files`, and no service or scheduled task is created.

## Safety

This project does not block ads, bypass DRM, or download tracks. It uses the official
client and the official Spicetify patch, and everything it changes is reversible with
`restore`. Read [SAFETY.md](SAFETY.md) before installing on a machine you do not own.
