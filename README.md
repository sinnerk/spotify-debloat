# Spotify Debloat

A debloated, documented [Spicetify](https://spicetify.app) setup for the **official**
Spotify desktop client on Windows, plus a committed inventory of every extension in the
Spicetify Marketplace so you can pick the ones you actually want.

It is not a Spotify clone and it ships no modified Spotify binaries. It configures
Spicetify, installs one small stylesheet, and enables a curated extension preset.

**First time?** [docs/SETUP.md](docs/SETUP.md) walks through it from a clean machine,
including the Spicetify prerequisite and execution-policy errors.

```
  spotify-debloat  install
  ------------------------------------------------
  theme       %APPDATA%\spicetify\Themes\Lean
  extensions  10 enabled via preset 'lean'
  debloat     sentry/logging off, telemetry hosts mapped to 127.0.0.1
  next        lean.ps1 benchmark -Label lean -Seconds 45 -Warmup 20 -Restart
```

## What it does

| Area | Effect |
| --- | --- |
| **Look** | One accent colour, flat surfaces, no gradients or glows, smaller radii, capped entity titles, quiet scrollbars. Light and dark schemes included. |
| **Debloat** | Sentry/UI logging off in the client patch, four analytics hosts resolved to `127.0.0.1` at launch, upsell and "What's New" chrome hidden, Home cut down to your pinned shortcuts and your recent listening. |
| **Plugins** | 489 extensions, 176 themes, 8 apps and 93 CSS snippets catalogued offline. Three presets (`lean`, `minimal`, `full`) plus `-Ids` for any extension in the catalog. |
| **Reversible** | Every change is recorded in `%APPDATA%\spicetify\lean-state.json`; `lean.ps1 restore` puts the original client back. |

Deliberately **not** included: ad blocking and download/DRM circumvention. See
[docs/DEBLOAT.md](docs/DEBLOAT.md#what-is-out-of-scope) and the policy rules in
[docs/SAFETY.md](docs/SAFETY.md#terms-of-service).

## Verified against

| Component | Version |
| --- | --- |
| Spotify for Windows | 1.3.6.1921 (`g7086c071a617`) |
| Spicetify CLI | 2.46.2 |
| Windows | 11 24H2, Windows PowerShell 5.1 |
| Node.js (tests only) | 24.x |

Spotify changes its DOM every release, so versions matter. If Spotify has moved on,
read [docs/MAINTAINING.md](docs/MAINTAINING.md) before installing.

## Quick start

Prerequisites:

* Spotify for Windows installed and **run at least once** (so it creates its profile).
* [Spicetify CLI](https://spicetify.app/docs/getting-started/installation) on `PATH`:

  ```powershell
  iwr -useb https://raw.githubusercontent.com/spicetify/cli/main/install.ps1 | iex
  ```

* Windows PowerShell 5.1 (built in). PowerShell 7 works too.

Clone it, then work from the repository root:

```powershell
git clone https://github.com/sinnerk/spotify-debloat.git
cd spotify-debloat

# 1. Check the machine first - changes nothing
.\lean.ps1 doctor

# 2. See exactly what would happen - changes nothing
.\lean.ps1 install -DryRun

# 3. Do it
.\lean.ps1 install
```

If PowerShell blocks the script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\lean.ps1 install
```

The first install creates a Spicetify backup (about 400 MB, one time only), patches the
client, copies the theme, downloads the preset's extensions, enables them and restarts
Spotify. Expect 1-3 minutes including the download.

## Commands

```
.\lean.ps1 <command> [options]
```

| Command | What it does |
| --- | --- |
| `install` | Backup, debloat, theme, preset, apply, restart. Measurement is separate. |
| `debloat` | Only the preprocessing/telemetry configuration, then apply. |
| `theme` | Only the Lean theme and its companion extension, then apply. |
| `extensions` | Install or switch an extension preset; leaves the theme alone. |
| `catalog` | Search the committed Marketplace inventory. |
| `benchmark` | Sample RAM/CPU and write `reports/<timestamp>-<label>.json`. |
| `status` | Show Spotify/Spicetify/Lean state, including live process memory. |
| `doctor` | Preflight checks with a fix hint per failure. Exits 1 on `FAIL`. |
| `restore` | Undo everything and return to the original client. |
| `version`, `help` | Housekeeping. |

Frequently used options:

```
-Profile lean|minimal|full   preset to install          (default: lean)
-Aggressive                  add Chromium memory caps   (see docs/DEBLOAT.md)
-BlockSpotifyUpdates         stop auto-updates breaking the patch
-Ids id1,id2                 explicit extension list, overrides -Profile
-DryRun                      print every planned change, touch nothing
-Force                       required for -Profile full, forces Spotify closed
```

Examples:

```powershell
.\lean.ps1 catalog -Search lyrics -Top 10
.\lean.ps1 catalog -Kind themes -Search dark -Top 15
.\lean.ps1 extensions -Ids spicetify-cli--shuffle,rxri-spicetify-extensions--songstats
.\lean.ps1 benchmark -Label before -Seconds 60 -Restart
.\lean.ps1 restore
```

## Presets

| Preset | Extensions | Intent |
| --- | --- | --- |
| `lean` (default) | 10 | Small, maintained extensions that add real value without covering the UI. |
| `minimal` | 0 | Theme and debloat only. The honest baseline for benchmarks. |
| `full` | up to 489 | Everything compatible, minus blocked categories and all but one extension per conflict group. Requires `-Force`, expects breakage. |

The ten extensions in `lean` are listed with one-line notes in
[docs/PLUGINS.md](docs/PLUGINS.md#the-lean-preset).

## The catalog

`catalog/catalog.json` is a reproducible snapshot of what the Marketplace would show:
GitHub repositories tagged `spicetify-extensions`, `spicetify-themes` and
`spicetify-apps`, each one read from its own `manifest.json`. `catalog/snippets.json`
holds the Marketplace CSS snippet collection. Both are committed, so using this repo
never requires a GitHub token or a network round-trip to browse plugins.

```powershell
.\lean.ps1 catalog -Search "progress bar"
.\lean.ps1 catalog -Kind all -Json | Out-File plugins.json
```

Extensions can be installed by id (`lean.ps1 extensions -Ids ...`). Themes and apps are
listed for discovery; they need a folder copy rather than a single file, so they have a
documented manual install in [docs/PLUGINS.md](docs/PLUGINS.md#themes-and-apps).

Refresh them with `tools/Sync-Catalog.ps1` (needs a GitHub token; `gh auth token` is
used automatically). Details in [docs/PLUGINS.md](docs/PLUGINS.md).

## Measured effect

Six cold runs, 45-second samples, playback paused, window visible, 16 logical cores
(2026-10-26). The only difference between the two configurations is the ten preset
extensions; both keep the Lean theme and the theme's `lean-ui.js`.

| Configuration | Working set (avg) | CPU (% of one core) | Processes |
| --- | --- | --- | --- |
| Theme only (`-Profile minimal`, 1 extension) | 1 210 MB | 4.47 % | 8 |
| Theme + `lean` (10 extensions) | 1 227 MB | 4.47 % | 8 |

The ten extensions add about 17 MB (1.4 %) of summed working set, which is inside the
baseline's own 32 MB run-to-run spread; idle CPU does not move at the resolution of the
measurement. The theme itself costs nothing measurable. The debloat's real effect is a
smaller UI surface and blocked telemetry, not a smaller process. Full method, caveats and
reproduction steps: [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Repository layout

```
lean.ps1                 command line entry point
src/Lean.psd1|psm1       module manifest and loader
src/Private/             context, config, state, logging, policy, apply
src/Public/              install, debloat, theme, extensions, catalog, benchmark, doctor, restore
theme/                   user.css, color.ini, lean-ui.js
presets/                 lean.json, minimal.json, full.json
data/policy.json         blocked categories and conflict groups for the full preset
catalog/                 catalog.json, snippets.json, blacklist.json, errors.json
tools/                   Sync-Catalog.ps1 and CDP diagnostics (Node.js)
tests/                   Run-Tests.ps1
reports/                 committed benchmark results
docs/                    the documents listed below
```

## Documentation

| Document | Contents |
| --- | --- |
| [SETUP.md](docs/SETUP.md) | Step-by-step install from a clean Windows machine, presets, update and uninstall. |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the module, state file and install pipeline fit together. |
| [DEBLOAT.md](docs/DEBLOAT.md) | Every setting and flag that is changed, and what it actually does. |
| [PLUGINS.md](docs/PLUGINS.md) | Catalog format, presets, policy, installing your own picks. |
| [BENCHMARKS.md](docs/BENCHMARKS.md) | Measurement method, results, caveats. |
| [SAFETY.md](docs/SAFETY.md) | What is touched on disk, supply chain, Terms of Service, privacy. |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom-to-fix table for the failures that actually happen. |
| [MAINTAINING.md](docs/MAINTAINING.md) | Spotify/Spicetify updates, catalog refresh, selector audits, CI. |

## Uninstall

```powershell
.\lean.ps1 restore
```

Removes the managed extensions, the theme folder, restores the Spicetify settings saved
at install time, unblocks auto-updates if they were blocked, and runs
`spicetify restore backup apply`. To remove Spicetify as well, run
`spicetify restore` and then delete `%APPDATA%\spicetify`.

## License

MIT for the code in this repository. Spotify, Spicetify and the catalogued extensions
belong to their respective owners; nothing here is affiliated with Spotify AB.
