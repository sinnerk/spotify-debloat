# Troubleshooting

Start here:

```powershell
.\lean.ps1 doctor     # PASS / WARN / FAIL with a fix hint per line
.\lean.ps1 status     # what is currently applied
```

`doctor` exits `1` if anything is `FAIL`, so it is safe to use as a gate in a script.

## Install and prerequisites

| Symptom | Cause | Fix |
| --- | --- | --- |
| `.\lean.ps1 : File ... cannot be loaded because running scripts is disabled` | Execution policy. | `powershell -NoProfile -ExecutionPolicy Bypass -File .\lean.ps1 install` |
| `Spicetify is not installed or not on PATH` | CLI missing, or installed after the shell started. | Reinstall: `iwr -useb https://raw.githubusercontent.com/spicetify/cli/main/install.ps1 | iex`, then open a **new** shell. `doctor` also checks `%LOCALAPPDATA%\spicetify\spicetify.exe`. |
| `Spotify.exe not found` | Spotify is not installed, or `spotify_path` in the Spicetify config points somewhere stale. | Install Spotify (Microsoft Store version is not supported by Spicetify - use the installer from spotify.com) and launch it once. |
| `Preflight checks failed. Nothing was changed.` | At least one `FAIL` above it. | Read the `Fix:` lines printed after the table; nothing was modified, so it is safe to retry. |
| Install hangs at "Creating a clean Spicetify backup" | 400 MB copy on a slow disk, or antivirus scanning the copy. | Wait it out. Do not interrupt: a partial backup is worse than none. |
| `Could not download <url>: ...` | Network, proxy, GitHub rate limit, or the plugin moved. | Re-run `.\lean.ps1 extensions -Profile lean`; only the failed files are retried. If one id keeps failing, that repository changed - check `catalog/catalog.json`, then `tools/Sync-Catalog.ps1`. |

## Spotify does not start or looks broken

| Symptom | Cause | Fix |
| --- | --- | --- |
| Spotify opens and immediately closes after `apply` | The patch does not match this client build (usually right after a Spotify update). | `spicetify restore backup apply`, then re-run `.\lean.ps1 install`. |
| Black or blank window, no UI | A broken extension threw during startup, or the bundle patch failed. | `.\lean.ps1 extensions -Profile minimal`, then `spicetify apply`. If that fixes it, add extensions back one at a time. |
| "Something went wrong" error page inside the client | Same as above. The console tells you which extension threw: `spicetify enable-devtools`, then Ctrl+Shift+I, then Console. | Disable the extension named in the stack trace. |
| Spotify starts but no window appears | A second instance is holding the lock. | `Get-Process Spotify | Stop-Process -Force`, then start again. |
| Windows Defender / SmartScreen warns about Spotify after install | Spicetify rewrites `xpui.spa` inside the Spotify folder; unsigned modified binaries trip heuristics. | Expected. If you do not accept it, `spicetify restore backup apply` and uninstall. |
| Everything is stuttering after `-Aggressive` | `--renderer-process-limit=3` is reusing renderers under load. | Re-run `.\lean.ps1 debloat` (without `-Aggressive`), then apply. |

## Theme

| Symptom | Cause | Fix |
| --- | --- | --- |
| Colours and fonts are stock | `inject_css` / `replace_colors` off, or the theme is not selected. | `spicetify config current_theme Lean`, `spicetify config inject_css 1`, `spicetify config replace_colors 1`, `spicetify apply`. |
| Theme applied but some panels still use Spotify colours | Encore components that read variables the theme does not set. Normal for a new build. | Report it with the element's computed style; the fix belongs in `theme/user.css` tokens. |
| Font is wrong | The theme asks for "Segoe UI Variable Display", which ships with Windows 11. On Windows 10 it falls back to "Segoe UI". | Nothing to do - or set `--font-family` in `user.css`. |
| Cards are square again after a Spotify update | Encore renamed its radius tokens. | Inspect the new token names, update the `--encore-corner-radius-*` block, re-run `spicetify refresh`. |
| Colours look right but spacing is cramped or broken | A rule is matching too much, usually a `[class*="..."]` substring. | Click the Lean pill to toggle debloat off and see whether the debloat rules are responsible; if not, bisect the stylesheet with `tools/cdp-inject.mjs`. |

## The UI toggle

| Symptom | Cause | Fix |
| --- | --- | --- |
| No "Lean" pill in the top bar | `lean-ui.js` is not enabled, or it loaded before the top bar existed. | `.\lean.ps1 theme` then `spicetify apply`. Check the console for `[spotify-debloat] lean-ui 0.2.0 loaded`. |
| Pill shows, clicking does nothing | `localStorage` is full or blocked. | Console: `Lean.toggle()` directly; then `localStorage.removeItem("spotify-debloat:ui")`. |
| Pill disappeared after an update | The mount point `.main-globalNav-contentRight` changed. | `lean-ui.js` warns in the console when it cannot mount; update the selector list in `mount()`. |
| Debloat rules come back after restart | `localStorage` is cleared on exit (rare, corporate profiles). | Set `data-lean` from a userscript, or make the rules unconditional in `user.css`. |

## Extensions

| Symptom | Cause | Fix |
| --- | --- | --- |
| An extension I removed still runs | Spicetify's copy in `%APPDATA%\Spotify\Apps\xpui\extensions\` was not pruned (older versions of this tool did not prune it). | Re-run `.\lean.ps1 extensions -Profile lean` - it removes both copies - then `spicetify apply`. |
| An extension is enabled in config but not loaded | The file is missing from `%LOCALAPPDATA%\spicetify\Extensions\`. | Re-run the install for that profile. |
| Extension loads but has no effect | It targets pre-Encore DOM classes (`.main-trackList-row`, `.Root__nav-bar`). | Nothing to fix on your side; the extension is stale for 1.3.x. |
| Extensions multiply every time I install | You are mixing preset installs with Marketplace GUI installs. The GUI's files do not match the managed naming pattern, so they are left alone. | Pick one method, or clean up by hand in the Marketplace GUI. |
| `Unknown extension id` thrown by a preset | The catalog is older than the preset, or the plugin left the Marketplace. | `tools/Sync-Catalog.ps1`, then remove or replace the id in `presets/*.json`. |

## Benchmarking and diagnostics

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Spotify is not running. Start it first, or pass -Restart.` | Nothing to sample. | `.\lean.ps1 benchmark -Label x -Restart` |
| Two benchmarks differ by hundreds of MB | Something else was running, or a track was playing. | Pause playback, close other heavy apps, use `-Restart -Warmup 25`, compare medians of three runs. |
| `tools/cdp-audit.mjs` cannot connect | The debug port is off. It is off by default on purpose. | See below. |
| `cdp-eval.mjs` fails with a syntax error | Multi-line JS mangled by shell quoting. | Write the JS to a file and pass `--file script.js`. |

### Enabling the debug port temporarily

The port is not part of the shipped configuration, and it should not be. The flag is
passed on the command line for one session only, so nothing persists:

```powershell
Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force
& "$env:APPDATA\Spotify\Spotify.exe" --remote-debugging-port=9222

node tools/cdp-audit.mjs
```

`lean.ps1` will start Spotify without the flag next time, so closing the client is
enough to remove the port. If the WebSocket handshake is rejected, add
`--remote-allow-origins=http://localhost:9222` to the same command line.

Do not leave a debugging port open: any local process can drive the client through it.

## Restore

| Symptom | Cause | Fix |
| --- | --- | --- |
| `restore` says "Spicetify restore failed" | No backup, or the backup does not match the client. | `spicetify restore backup apply` by hand and read its output; if there is no backup at all, reinstall Spotify. |
| Theme is gone but the client still looks modified | The patch is still applied. | `spicetify restore backup apply`, or `spicetify restore` followed by `spicetify apply` for a clean re-patch. |
| Extensions still listed after restore | Restore disabled them but the files remain (older state file). | Delete `%LOCALAPPDATA%\spicetify\Extensions\*.js` files that follow `vendor-repo--name.js`. |
| I want Spicetify gone entirely | - | `.\lean.ps1 restore`, then `spicetify restore`, then delete `%APPDATA%\spicetify` and `%LOCALAPPDATA%\spicetify`. |

## Collecting diagnostics for an issue

```powershell
.\lean.ps1 doctor        > diag-doctor.txt
.\lean.ps1 status        > diag-status.txt
spicetify -v             > diag-spicetify.txt
Get-Content "$env:APPDATA\spicetify\config-xpui.ini" > diag-config.txt
```

Review the config file before attaching it: it is plain text and contains your Spotify
install path. Everything else in that list is free of personal data.
