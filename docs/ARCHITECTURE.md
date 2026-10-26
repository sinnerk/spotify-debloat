# Architecture

How `spotify-debloat` is put together, why the moving parts are where they are, and which
behaviours of Spicetify 2.46 it works around.

## Layers

```
lean.ps1                     argument parsing + command dispatch + console formatting
  |
  +-- src/Lean.psd1          module manifest (version, exported functions, metadata)
  +-- src/Lean.psm1          dot-sources Private/*.ps1 then Public/*.ps1
        |
        +-- src/Private/     context, config IO, state, logging, policy, apply, backup
        +-- src/Public/      one function per user-facing verb
  |
  +-- theme/                 copied into %APPDATA%\spicetify\Themes\Lean
  +-- presets/               JSON presets resolved against catalog/catalog.json
  +-- data/policy.json       filtering rules for the `full` preset
  +-- catalog/               committed Marketplace inventory
  +-- tools/                 catalog sync and CDP diagnostics (not used at install time)
```

`lean.ps1` holds no logic that other callers might need. Every action is a module
function, so the same operations are available from a console:

```powershell
Import-Module .\src\Lean.psd1
Get-LeanStatus
Measure-LeanPerformance -Seconds 30 -Label adhoc
```

Private helpers are deliberately not exported. The ten exported names are the public
contract and are asserted by `tests/Run-Tests.ps1`.

## Context resolution

Every path and version is resolved once per session by `Get-LeanContext` and cached in
`$script:LeanContext`. Pass `-Refresh` after anything that could change it (a Spotify
update, a Spicetify reinstall).

| Property | Source |
| --- | --- |
| `Root` | Parent of `src/` |
| `ConfigPath` | `%APPDATA%\spicetify\config-xpui.ini` |
| `StatePath` | `%APPDATA%\spicetify\lean-state.json` |
| `BackupRoot` | `%APPDATA%\spicetify\Backup` |
| `ThemeRoot` | `%APPDATA%\spicetify\Themes` |
| `ExtensionRoot` | `%LOCALAPPDATA%\spicetify\Extensions` |
| `SpotifyPath` | `spotify_path` from the config, else `%APPDATA%\Spotify` |
| `SpotifyVersion` | `ProductVersion` of `Spotify.exe` |
| `SpicetifyExe` | `spicetify` on `PATH`, else `%LOCALAPPDATA%\spicetify\spicetify.exe` |
| `SpicetifyVersion` | Parsed from `spicetify -v` |

Note the split: Spicetify 2.x keeps **extensions** under `%LOCALAPPDATA%` and **themes**
under `%APPDATA%`. Getting that backwards is the most common way a hand-written
installer silently does nothing.

## Install pipeline

`Invoke-LeanInstall` runs steps in this order, and the order matters:

```
1. Test-LeanEnvironment        preflight; any FAIL throws before a single file changes
2. -DryRun short circuit       prints the plan, calls the same functions with -DryRun
3. Stop-SpotifyClient          Spicetify cannot patch files a running client has open
4. Set-LeanDebloat             backup (once), then write preprocessing + launch flags
5. Install-LeanExtensionSet    download preset, prune stale files, update the list
6. Install-LeanTheme           copy user.css/color.ini, install lean-ui.js
7. Invoke-LeanApply            spicetify apply, then restart if Spotify was running
```

Install deliberately stops there. It does not sample RAM/CPU: the first run after a
patch is dominated by indexing and renderer recompiles, and an earlier version that
measured it reported ~95 % CPU on a healthy install. Use
`lean.ps1 benchmark -Label lean -Seconds 45 -Warmup 20 -Restart` for numbers that are
comparable to the committed reports.

**Why extensions come before the theme.** `Install-LeanExtensionSet` recomputes
`managedExtensions` from the preset and overwrites that array in the state file.
`Install-LeanTheme` appends `lean-ui.js` to the same array. Theme-first would have the
companion extension erased from state, and a later `restore` would leave the file behind.

**Why a preset install prunes aggressively.** Files this project installed follow the
`vendor-repo--name.js` convention. During install, four sources are unioned into the
"previously ours" set: the state file, the files on disk matching that pattern, the
names enabled in the Spicetify config matching that pattern, and the previous run's list.
That union is what makes the installer idempotent even after a state file is lost.

**Why two copies are deleted.** `spicetify apply` copies every enabled extension into
`%APPDATA%\Spotify\Apps\xpui\extensions\`. That copy is what actually loads, and
`spicetify apply` never deletes files it no longer sees. Removing only the source in
`%LOCALAPPDATA%` leaves a working extension running with no way to disable it from the
config. `Get-SpicetifyExtensionCachePath` locates the cache and both copies are removed.

## Reading Spicetify configuration

`spicetify config` has three output shapes, and using the wrong reader produces silent
wrong answers:

| Setting | Output |
| --- | --- |
| `extensions` | one file name per line |
| `spotify_launch_flags` | one line, entries separated by `\|` |
| everything else | one line |

* `Get-SpicetifyConfigValue` returns the first non-empty line. Correct for scalars.
* `Get-SpicetifyConfigList` returns every non-empty line. Required for `extensions` -
  the value form returned only the first extension, which made every "is it enabled?"
  check answer "no".
* `Get-SpicetifyConfigMap` parses the full `spicetify config` dump into a hashtable.
* `Set-SpicetifyConfigValues` writes many keys in one invocation and inserts `--` before
  the `spotify_launch_flags` value so values starting with `--` are not parsed as flags.

## Launch flags

Spicetify stores `spotify_launch_flags` but only applies them when *Spicetify* starts
Spotify. At the time of writing the CLI has **no `start` command** (`spicetify start`
does not exist in 2.46), so a wrapper that writes the setting and then launches
`Spotify.exe` itself gets no flags at all.

`Start-SpotifyClient` therefore reads the setting with `Get-SpotifyLaunchFlags`, splits
it on `|` and passes the array to `Start-Process -ArgumentList`. `lean.ps1 status` shows
whether the telemetry mapping is present, and `Get-RunningSpotifyCommandLine` exposes the
live command line for verification.

## State file

`%APPDATA%\spicetify\lean-state.json` is the only record of what was changed. It is
written with `[IO.File]::WriteAllText` and a BOM-less UTF-8 encoder, because Windows
PowerShell 5.1 reads BOM-less UTF-8 as ANSI and would corrupt non-ASCII repository names.

```jsonc
{
  "schemaVersion": 1,
  "createdAt": "2026-10-26T19:14:33Z",
  "updatedAt": "2026-10-26T20:05:10Z",
  "profile": "lean",
  "aggressive": false,
  "original": {                      // pre-install values, restored by `restore`
    "extensions": "a.js|b.js",
    "current_theme": "marketplace",
    "spotify_launch_flags": "",
    "disable_sentry": "0",
    "...": "18 keys total"
  },
  "managedExtensions": ["x.js"],     // files this project owns
  "installedExtensions": [{ "id": "...", "repo": "...", "source": "https://..." }],
  "themeInstalled": true,
  "blockedUpdates": false
}
```

`original.extensions` is stored pipe-joined rather than as an array so that
`ConvertTo-Json` in PowerShell 5.1 does not unroll single-element arrays into a string.
`restore` splits it again.

## Catalog and preset resolution

```
tools/Sync-Catalog.ps1
  GitHub search API  ── topic:spicetify-extensions|themes|apps
        │
        ├─ per repository: raw manifest.json  ── name, description, main, authors, tags
        │
        └─ catalog/catalog.json   { schemaVersion, generatedAt, counts, extensions[], themes[], apps[] }
           catalog/snippets.json  Marketplace CSS snippets
           catalog/errors.json    repositories whose manifest could not be read
           catalog/blacklist.json blacklist snapshot used during the sync

Get-LeanCatalogData ── validates schemaVersion, caches in memory
        │
Get-LeanPreset ─────── presets/<name>.json  { all, extensions[], exclude[] }
        │
Resolve-LeanPresetTargets
        ├─ unknown id  -> hard error (a preset must never silently install nothing)
        ├─ policy blockedPatterns  -> drop
        ├─ policy conflictGroups   -> keep one per group (preferred id, else most stars)
        └─ ordered list of catalog entries
```

The catalog is committed because the Marketplace has no static endpoint: it queries
GitHub at runtime. Committing a snapshot makes installs reproducible, keeps them working
without a token, and gives the repository something to diff when a plugin disappears or
changes its entry point.

`errors.json` is kept on purpose. 68 repositories were reachable but had no readable
`manifest.json`; recording them makes the next sync's diff meaningful instead of
"the count went down again, no idea why".

## Theme

`theme/user.css` styles Spotify 1.3.x in three layers, because Encore class names are
build-stamped (`e-10860-card__main`) and change every release:

1. **Design tokens** - `--encore-corner-radius-*`, `--background-*`, `--text-*`,
   `--essential-*`, `--shadow-*`, `--background-noise`. Version-proof: components read
   the variables, not class names.
2. **Substring matches** - `[class*="card__main"]`, `[class*="legacy-list-row"]`,
   `[class*="legacy-button-primary"]`. Survives the numeric build stamp.
3. **Semantic hooks** - `data-testid`, `aria-*`, `#main`, `#global-nav-bar`,
   `#Desktop_LeftSidebar_Id`, and the `main-*` / `x-*` prefixes Spotify keeps stable
   because its own tests use them.

Old `.main-card*`, `.main-trackList*`, `.main-shelf*`, `Root__nav-bar` and
`Root__now-playing-bar` selectors from 2022-era themes are dead on 1.3.x and were
deleted rather than left in as noise.

Debloat rules are scoped to `:root:not([data-lean="0"])`. `lean-ui.js` sets
`data-lean` on `<html>` from `localStorage`, so the same stylesheet can be switched
between debloated and stock layout at runtime without a restart.

`lean-ui.js` builds its top-bar control with plain DOM instead of
`Spicetify.Topbar.Button`, which renders the icon *name* as text on 1.3.x (the icon font
no longer resolves the ligature). It mounts into `.main-globalNav-contentRight` with a
bounded 20-second retry loop and stops. No polling, no DOM rewriting, no network calls.

## Diagnostics tooling

`tools/` is developer tooling, not part of install:

| Script | Purpose | Needs |
| --- | --- | --- |
| `Sync-Catalog.ps1` | Rebuild `catalog/` from GitHub. | GitHub token (`gh auth token` is used automatically) |
| `cdp-audit.mjs` | Count live elements per selector in `user.css`. | Spotify started with `--remote-debugging-port=9222` |
| `cdp-eval.mjs` | Evaluate JS in the live client (`--file` for anything multi-line). | same |
| `cdp-inject.mjs` | Hot-load a stylesheet without restarting. | same |
| `cdp-shot.mjs` | Screenshot the client window. | same |

The debug port is **not** part of the shipped configuration. Enable it temporarily by
appending to `spotify_launch_flags`, then remove it again - see
[docs/MAINTAINING.md](MAINTAINING.md#selector-audits).
