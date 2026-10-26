# Safety

What this project changes, what it cannot undo, and where the real risks are.

## What is written, and where

| Path | Change | Undone by |
| --- | --- | --- |
| `%APPDATA%\spicetify\config-xpui.ini` | 11 settings, `current_theme`, `color_scheme`, the extension list, `spotify_launch_flags` | `restore` writes back the values saved at install |
| `%APPDATA%\spicetify\Themes\Lean\` | `color.ini`, `user.css` copied in | `restore` deletes the folder |
| `%LOCALAPPDATA%\spicetify\Extensions\` | one `.js` per preset extension, plus `lean-ui.js` | `restore` deletes the files it recorded |
| `%APPDATA%\Spotify\Apps\xpui\` | patched client bundle (Spicetify) | `spicetify restore backup apply` |
| `%APPDATA%\Spotify\Apps\xpui\extensions\` | Spicetify's copy of each enabled extension | pruned on install, deleted on restore |
| `%APPDATA%\spicetify\Backup\` | one-time ~400 MB snapshot | `spicetify clear` |
| `%APPDATA%\spicetify\lean-state.json` | this project's record | `restore` deletes it |

Nothing else. No registry keys, no services, no scheduled tasks, no hosts file, no
firewall rules, no environment variables, no PATH changes.

The one exception is opt-in: `-BlockSpotifyUpdates` calls
`spicetify spotify-updates block`, which **patches `Spotify.exe`** so it cannot
self-update. It is off by default, it is recorded in the state file, and `restore`
calls `spotify-updates unblock`. Do not use it if you are not prepared to reinstall
Spotify to clear a bad patch.

## What is never touched

* Your Spotify account, library, playlists, downloads or login session. The tool never
  authenticates and never sees a token.
* Your listening data on Spotify's servers.
* Other applications' files.
* Any file outside the paths in the table above.

## The backup

`spicetify backup` copies the unpatched client to `%APPDATA%\spicetify\Backup\<version>`.
It is created once, on the first install, and it is the only way back to a clean client:

```powershell
spicetify restore backup apply
```

Two things to know:

1. **The backup is version-locked.** If Spotify updates to 1.3.7 while the backup is
   1.3.6, restoring gives you 1.3.6 back, and Spotify will try to update again. That is
   usually what you want after a broken patch, but it means "restore" is not a
   time machine for your library - nothing here touches your library.
2. **A fresh backup costs about 400 MB** each time `spicetify clear` is run. `lean.ps1`
   never clears an existing backup; it only creates one when none exists. If the backup
   version no longer matches the installed client, `doctor` reports `WARN` and tells you
   to run `spicetify restore backup apply` first.

## Revocability, honestly

`restore` reverts everything in the table above. It cannot revert:

* a Spotify auto-update that happened while the patch was applied (the patch is expected
  to break; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md));
* extensions you installed yourself outside this tool, including anything from the
  Marketplace GUI;
* files you edited by hand inside `%APPDATA%\spicetify\`.

If `lean-state.json` is lost, `restore` falls back to clearing the theme and launch
flags and running `spicetify restore backup apply`. Extension files following the
`vendor-repo--name.js` pattern are still found and removed on the next `extensions` run.

## Supply chain

This is the largest real risk and it deserves a straight answer.

At install time the tool downloads JavaScript from
`https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>` and Spicetify loads it
inside the Spotify client with full access to the page, `localStorage` and Spotify's
internal APIs.

* **The URLs are not pinned to a commit.** A catalog entry records the branch head path,
  not a SHA. If a maintainer rewrites their extension tomorrow, the next install gets the
  new code.
* **There is no checksum or signature check.** Raw GitHub has no way to sign a file.
* **The files are plain, readable JavaScript.** A quick `Get-Content` on the installed
  file is a real audit, not a formality - extensions are usually a few hundred lines.
* **`catalog/catalog.json` is committed and diffable.** A repository that changes owner,
  branch or entry point shows up in a `git diff` after a sync. That is the strongest
  signal this project can give you.

Mitigations available to you:

```powershell
.\lean.ps1 install -Profile minimal        # no third-party code at all
.\lean.ps1 extensions -Ids <id>            # only the ids you have read
```

and pin a version by editing the entry's `rawUrl` to a commit SHA before installing:

```
https://raw.githubusercontent.com/owner/repo/<40-char-sha>/path/to/extension.js
```

## Terms of Service

Spicetify is a client mod: it patches the official Spotify desktop client. Spotify does
not support modified clients, and a strict reading of their terms does not permit
modification. In practice client mods of this kind have been used widely for years
without mass enforcement, but **this is not sanctioned and the risk is yours**. That risk
is one reason the project contains no ad blocking or DRM circumvention, and why
`data/policy.json` refuses to enable those categories even in the `full` preset.

If your Spotify account matters to you and you are not comfortable with that, do not
install this.

## Privacy

* `lean.ps1` contains no telemetry, no analytics and no update check.
* It makes network requests for exactly two things: downloading the extensions you asked
  for, and `tools/Sync-Catalog.ps1` (only when you run it manually).
* The state file records settings and file names. It does **not** record your Spotify
  path, your Windows user name or any token - `spotify_path` is deliberately excluded
  from the saved key list.
* Benchmarks read process memory and CPU counters locally and write them to
  `reports/`. Reports contain versions, counts and timings, no paths.
* This repository contains no personal paths, tokens or machine names. `tests/Run-Tests.ps1`
  scans every text file for absolute user-profile paths, token prefixes and credential
  patterns, and CI runs the same scan on every push.

## Reporting a problem

Open an issue with `.\lean.ps1 doctor` output and `.\lean.ps1 status` output. Both are
free of personal data. If you believe you found a security issue in the installer
itself (path handling, command injection through a catalog field, state-file tampering),
please report it privately rather than in a public issue.
