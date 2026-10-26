# Maintaining

The project breaks for exactly one reason: Spotify changes its client. This document is
the checklist for when that happens, plus how to keep the catalog and the numbers honest.

## Fragile points, in order of likelihood

| What | Where | Breaks when |
| --- | --- | --- |
| Encore design tokens | `theme/user.css` `:root` blocks | Spotify renames a `--encore-*` or `--background-*` variable |
| Build-stamped class substrings | `[class*="card__main"]`, `[class*="legacy-list-row"]` | A component is renamed wholesale |
| Top-bar mount point | `theme/lean-ui.js` `mount()` | The global nav is restructured |
| Debloat selectors | `[data-testid="component-shelf"]`, upsell test ids | A test id is renamed or the surface is removed |
| Config output shape | `Get-SpicetifyConfigValue` / `Get-SpicetifyConfigList` | Spicetify changes `spicetify config` formatting |
| Extension entry points | `catalog/catalog.json` `rawUrl` | A plugin moves or renames its `main` file |

## After a Spotify update

Spotify auto-updates silently. The patch is expected to break: Spicetify patches files
whose hash it knows.

```powershell
# 1. Confirm what happened
.\lean.ps1 doctor

# 2. Roll the client back to the version the backup was made from
spicetify restore backup apply

# 3. If step 2 failed because the backup is gone, reinstall Spotify, run it once,
#    then create a new backup:
spicetify backup

# 4. Reapply everything
.\lean.ps1 install

# 5. Verify the UI, then re-audit selectors (below)
```

`doctor` reports `Backup WARN backup <old> does not match Spotify <new>` for exactly this
case, and `lean.ps1 install` refuses to proceed when the preflight fails.

Do not run `spicetify clear` to "fix" a version mismatch unless you are prepared to
reinstall Spotify. It deletes the only clean copy of the client.

## Selector audits

The audit tool tells you which selectors in `theme/user.css` no longer match anything in
the live client. Run it after every Spotify update, and ideally after every Spicetify
update too.

```powershell
# one session with the debug port, see TROUBLESHOOTING.md
Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force
& "$env:APPDATA\Spotify\Spotify.exe" --remote-debugging-port=9222

node tools/cdp-audit.mjs
```

The output splits selectors into four buckets:

| Bucket | Meaning | Action |
| --- | --- | --- |
| **live** | Matches at least one element now | Keep |
| **state-only** | Only matches on hover/focus or via a pseudo-element | Keep; the target exists |
| **dead** | Matches nothing on this page | Fix, or confirm it is page- or account-scoped |
| **invalid** | The browser rejected the selector | Always a bug in the stylesheet |

**Audit per page type.** Selectors are scoped to what is on screen, so a single run is
misleading. Navigate to each of these and re-run:

1. Home (with the debloat rules on)
2. A playlist page
3. An album or artist page
4. Now Playing / full-screen view
5. Your library in the sidebar
6. Search results

**Expect false "dead" entries** in two categories:

* *Page-scoped*: `.main-entityHeader-*` will not match on Home; `.view-homeShortcutsGrid-*`
  will not match on a playlist. Only worry about a selector that is dead on the page it
  styles.
* *Account-scoped*: `[data-testid="upgrade-button"]`, `[data-testid="download-button"]`
  and the "What's New" button never render on a Premium account.

**Fix order matters.** Tokens first, then structural selectors, then test ids:

1. If a *token* is gone (radii, background colours), fix the `:root` block. That single
   change usually repairs a dozen visual regressions at once.
2. If a *component* moved, prefer a `[class*="..."]` substring over a build-stamped
   full class name.
3. Only reach for `data-testid` when the component has one; Spotify keeps those stable
   for its own tests.
4. Never re-add 2022-era names (`Root__nav-bar`, `.main-trackList-row`, `.main-card-card`).
   They are dead and they make the audit noisy.

To iterate without restarting, hot-load the stylesheet:

```powershell
node tools/cdp-inject.mjs theme/user.css
node tools/cdp-shot.mjs home.png
```

When it looks right, commit and run `.\lean.ps1 theme` to install it for real.

## Refreshing the catalog

Monthly, or when a plugin you use disappears:

```powershell
.\tools\Sync-Catalog.ps1 -Verbose
git diff --stat catalog/
```

Then read the diff, not just the counts:

* `errors.json` growing by a few entries is normal churn. A single repository that used
  to parse and now does not is a real problem - usually a moved `manifest.json`.
* `catalog.json` entries whose `rawUrl` changed need a second look: the plugin may have
  been rewritten, not just reorganised.
* Archived repositories are dropped by default. If a `lean` preset id disappears, the
  preset install will throw a hard error naming the id - that is intentional.

Finally:

```powershell
.\lean.ps1 extensions -Profile lean -DryRun
.\tests\Run-Tests.ps1
```

## Changing the lean preset

The bar for inclusion is deliberately narrow. An extension belongs in `lean` if it is:

* **additive** - adds a menu entry, keybind or hidden panel, rather than replacing a view
  the theme styles;
* **maintained** - a commit in roughly the last year, and it works on the current client;
* **small** - no vendored framework, no network calls at import time, readable in a few
  minutes;
* **non-overlapping** - it does not fight another preset member for the same DOM.

Procedure:

1. `.\lean.ps1 catalog -Search <name>` and read the entry.
2. Read the extension source before enabling it (see
   [SAFETY.md](SAFETY.md#supply-chain)).
3. Test it in isolation: `.\lean.ps1 extensions -Ids <id>`, restart, exercise it.
4. Add the id to `presets/lean.json` **and** a row to the table in
   [PLUGINS.md](PLUGINS.md#the-lean-preset).
5. Benchmark before/after if it is a large plugin - see [BENCHMARKS.md](BENCHMARKS.md).
6. Update the count in the README (`Theme + lean (N extensions)` and the preset table).

Removing one is the same in reverse, plus a note in `PLUGINS.md` under
*Compatibility notes* explaining why it was dropped. `spicy-lyrics` is the worked example.

## Benchmarks

Re-run the pair whenever you touch the theme or the preset, so the committed numbers
always describe the shipped configuration:

```powershell
.\lean.ps1 install -Profile lean
.\lean.ps1 benchmark -Label lean -Seconds 45 -Warmup 20 -Restart

.\lean.ps1 extensions -Profile minimal
.\lean.ps1 benchmark -Label theme-only -Seconds 45 -Warmup 20 -Restart

.\lean.ps1 extensions -Profile lean      # put it back
```

Commit the reports (three runs per configuration) and update the table in
[BENCHMARKS.md](BENCHMARKS.md) and the summary in the README.

## Versioning

| Place | What to bump | When |
| --- | --- | --- |
| `src/Lean.psd1` `ModuleVersion` | minor | Any behaviour change |
| `theme/lean-ui.js` `VERSION` | minor | Any change to the pill or `window.Lean` |
| `README.md` *Verified against* | versions | New Spotify/Spicetify target |
| `lean-state.json` `schemaVersion` | major | Incompatible state layout |

The state schema has no migrator on purpose. `schemaVersion` 1 is the only supported
value; a future incompatible change bumps it and `restore` will say so instead of
guessing at a half-understood file.

## Tests and CI

```powershell
.\tests\Run-Tests.ps1            # everything, exit 1 on failure
.\tests\Run-Tests.ps1 -Section theme
```

The suite is dependency-free (no Pester), so it runs on a stock Windows PowerShell 5.1:

| Section | Checks |
| --- | --- |
| `json` | Every committed JSON file parses, catalog counts match array lengths |
| `catalog` | Unique ids, required fields, https raw URLs, no duplicate raw URLs |
| `presets` | Names match file names, every id exists, `full` uses `all` |
| `policy` | Blocked patterns match no `lean` extension; conflict groups resolve to one each |
| `module` | Import succeeds, exactly the ten public functions are exported, context resolves |
| `theme` | Braces balanced, no remote `url()`, no `@import`, `color.ini` sections present, `node --check` on `lean-ui.js` |
| `style` | Every `.ps1` parses, no `??`/ternary, no tabs, files under 2 MB |
| `privacy` | No user-profile paths, token prefixes or credential patterns in any text file |

`.github/workflows/ci.yml` runs the same suite on `windows-latest` with PowerShell 5.1
and 7, validates JSON with `ConvertFrom-Json`, syntax-checks the `.mjs` tools with
`node --check`, and runs PSScriptAnalyzer with `-Severity Error`.

## Release checklist

1. `.\lean.ps1 install` on a clean machine or a fresh Spotify install.
2. `.\lean.ps1 doctor` - no `FAIL`.
3. `.\lean.ps1 status` - profile, theme and extension count as expected.
4. `.\tests\Run-Tests.ps1` - green.
5. Benchmarks re-run and committed, README table updated.
6. `theme/user.css` audited on Home, playlist, album, now playing.
7. Docs updated: `PLUGINS.md` table, `BENCHMARKS.md` numbers, `README.md` versions.
8. Tag: `git tag v0.<minor>.0 && git push --tags`.
