# Plugins

Everything about extensions: what is catalogued, what the presets mean, how to install
something that is not in a preset, and which plugins are known to misbehave on the
current client.

## The catalog

`catalog/catalog.json` is a snapshot of what the Spicetify Marketplace would show. The
Marketplace has no static index - it queries GitHub for repositories tagged
`spicetify-extensions`, `spicetify-themes` and `spicetify-apps`, then reads each
repository's `manifest.json`. `tools/Sync-Catalog.ps1` does the same thing once and
commits the result:

| File | Contents |
| --- | --- |
| `catalog/catalog.json` | 489 extensions, 176 themes, 8 apps, plus `schemaVersion`, `generatedAt`, `counts` |
| `catalog/snippets.json` | 93 CSS snippets from the Marketplace snippet collection |
| `catalog/blacklist.json` | the Marketplace blacklist snapshot used during the sync |
| `catalog/errors.json` | 68 repositories that were found but had no readable `manifest.json` |

An extension entry looks like this:

```jsonc
{
  "id": "spicetify-cli--shuffle",          // "<vendor>-<repo>--<manifest name>", filesystem-safe
  "name": "Shuffle+",
  "description": "Shuffles using Fisher-Yates algorithm with zero bias...",
  "repo": "spicetify/cli",
  "repoUrl": "https://github.com/spicetify/cli",
  "branch": "main",
  "main": "Extensions/shuffle+.js",
  "rawUrl": "https://raw.githubusercontent.com/spicetify/cli/main/Extensions/shuffle+.js",
  "previewUrl": null,
  "authors": [{ "name": "spicetify", "url": "https://github.com/spicetify/cli" }],
  "tags": [],
  "stars": 25248,
  "pushedAt": "2026-10-26T06:00:12Z",
  "archived": false
}
```

Simple repositories contribute a single entry; monorepos contribute one entry per
manifest and share the repository's star count. Archived repositories are excluded by
default (`-IncludeArchived` keeps them).

## Searching

```powershell
.\lean.ps1 catalog -Search lyrics                  # regex over name, description, repo, tags
.\lean.ps1 catalog -Search "progress bar" -Top 10
.\lean.ps1 catalog -Kind themes -Search dark -Top 15
.\lean.ps1 catalog -Kind snippets -Search volume
.\lean.ps1 catalog -Kind all -Json | Out-File plugins.json
```

`-Kind` accepts `extensions` (default), `themes`, `apps`, `snippets`, `all`. Extension
results carry an extra `installed` flag computed from the extension folder, so you can
see what is already on disk.

Themes carry no tags in the Marketplace manifest, so `-Tag` only filters extensions and
apps; use `-Search` for themes. Snippet search covers `title` and `description`.

`-Json` returns raw objects instead of the console table, which is what you want when
scripting:

```powershell
(.\lean.ps1 catalog -Kind extensions -Json | ConvertFrom-Json |
  Where-Object { $_.stars -gt 500 -and $_.tags -contains 'lyrics' }).name
```

## Presets

A preset is a small JSON file in `presets/`:

```jsonc
{
  "schemaVersion": 1,
  "name": "lean",                 // must match the file name
  "title": "Lean",
  "description": "Small, maintained extensions that add real value without covering the UI.",
  "all": false,                    // true = start from the entire catalog
  "extensions": ["spicetify-cli--shuffle", "..."],
  "exclude": []                    // ids to drop after `all` and `extensions` are applied
}
```

| Preset | Behaviour |
| --- | --- |
| `lean` | 10 curated extensions. Installed by default. |
| `minimal` | Zero third-party extensions. Theme, toggle and debloat only. |
| `full` | `all: true`; every catalog extension after policy filtering. Refuses to run without `-Force`. |

An unknown id in a preset is a **hard error**, not a warning. Silently installing nine
of ten plugins is worse than failing loudly.

### The lean preset

Ten small extensions, all of which are additive (they add a menu entry, a keybind or a
hidden-by-default panel) rather than replacing a view:

| Extension | What it adds |
| --- | --- |
| **Shuffle+** (`spicetify-cli--shuffle`) | Unbiased Fisher-Yates shuffle via a "Play with Shuffle+" context item. |
| **Keyboard Shortcut** (`spicetify-cli--keyboardshortcut`) | Keybinds for navigation and playback. |
| **Bookmark** (`spicetify-cli--bookmark`) | Save pages, tracks and track positions for later. |
| **Trash Bin** (`spicetify-cli--trashbin`) | Auto-skip tracks and artists you never want to hear again. |
| **Loopy Loop** (`spicetify-cli--loopyloop`) | Mark A/B points on the progress bar and loop that section. |
| **Auto Skip Videos** (`spicetify-cli--autoskipvideo`) | Skips region-blocked video tracks instead of stopping playback. |
| **Hide Podcasts** (`therealpadster-...--hidepodcasts`) | Removes podcasts and shows from the UI. |
| **Song Stats** (`rxri-...--songstats`) | Audio-features panel for the current track. |
| **Clean Links** (`borfak-...--clean-links`) | Strips `si`, `pt`, `utm_*` tracking parameters from copied Spotify links. |
| **Hide Announcements** (`noahtberger-...--hide-announcements`) | Hides promo banners and logs what it caught. |

Six come from the official `spicetify/cli` repository. The other four are small,
single-author projects - two with fewer than ten stars. They are in the preset because
they work on the current client, not because they are audited. If that matters to you,
switch to `-Profile minimal` and add back only what you read. See
[SAFETY.md](SAFETY.md#supply-chain).

## Installing something else

Any catalog id can be installed directly, with no preset involved:

```powershell
.\lean.ps1 extensions -Ids spicetify-cli--shuffle,rxri-spicetify-extensions--songstats
```

The list replaces the preset: extensions this project installed earlier and that are not
in the new list are removed, files and config entries both. Extensions you installed
yourself (files that do not follow the `vendor-repo--name.js` pattern) are never touched.

`-Profile` and `-Ids` together: `-Ids` wins. Add `-DryRun` to see the file names first.

## Policy

`data/policy.json` only affects the `full` preset. It never hides anything from
`catalog`, because browsing and enabling are different decisions.

**Blocked patterns** - `full` silently drops anything whose id, name or repo matches:

| Pattern | Reason |
| --- | --- |
| `adblock`, `ad-block`, `adblocker`, `ads-?block` | Ad blocking circumvents Spotify's monetisation and is out of scope. |
| `spicedl`, `spotiflac`, `speedify`, `spotify-?downloader`, `song-?downloader` | Download and DRM-circumvention tools are not bundled or enabled. |

**Conflict groups** - several extensions legitimately cannot coexist, usually because
they claim the same DOM node. Each group keeps exactly one entry, preferring the listed
id and otherwise the most-starred candidate:

| Group | Matches | Kept |
| --- | --- | --- |
| `lyrics` | `lyric` | most stars (currently Beautiful Lyrics) |
| `fullscreen` | `full app`, `fullscreen`, `full-screen` | most stars |
| `progress` | `progress bar`, `progressbar`, `seek bar` | most stars |
| `miniplayer` | `mini player`, `now playing view` | most stars |
| `shuffle` | `shuffle` | `spicetify-cli--shuffle` |
| `podcasts` | `podcast` | `therealpadster-...--hidepodcasts` |
| `stats` | `song stats`, `listening stats` | `rxri-...--songstats` |

Adding a rule is a one-line JSON edit; nothing else needs to change.

## Compatibility notes

Recorded from testing on Spotify 1.3.6.1921 / Spicetify 2.46.2:

| Plugin | Status |
| --- | --- |
| `spikerko-spicy-lyrics--spicy-lyrics` | **Removed from `lean`.** Its jsDelivr entry point is a 108-byte loader for a multi-megabyte bundle; it broke the now-playing card on 1.3.6. Still installable by id if you want to retest it. |
| Theme-replacing extensions (fullscreen, progress bar, mini player) | Not in `lean` by design - they own parts of the layout the theme styles, and the result is unpredictable. |
| Extensions that predate Encore | Many still work because they hook Spicetify APIs rather than DOM classes, but any that query `.main-trackList-row` or `.Root__nav-bar` will do nothing on 1.3.x. |
| Ad blockers / downloaders | Out of scope. |

## Roll your own preset

1. Create `presets/mine.json`:

   ```json
   {
     "schemaVersion": 1,
     "name": "mine",
     "title": "Mine",
     "description": "What I actually use.",
     "all": false,
     "extensions": ["spicetify-cli--shuffle", "spicetify-cli--bookmark"],
     "exclude": []
   }
   ```

2. `.\lean.ps1 extensions -Profile mine -DryRun`
3. `.\lean.ps1 extensions -Profile mine`

Commit it if you want it to survive: presets are data, not code, and the tests verify
that every referenced id exists in the catalog.

## Catalog refresh

```powershell
.\tools\Sync-Catalog.ps1 -Verbose
```

The script uses `GITHUB_TOKEN`, then `gh auth token`. Unauthenticated use is rate
limited to the point of being useless (one search page per topic, ~60 manifest reads).
It writes all four files in `catalog/` and prints counts plus the number of unreadable
manifests. Diff `errors.json` afterwards: a plugin that used to parse and now does not
is usually a broken repository, not a transient failure.

## Themes and apps

`lean.ps1` installs extensions only. The catalog also lists 176 themes and 8 apps:
browsable, and installable, but not by this tool, because the Marketplace entry does not
carry everything an install needs.

* A **theme** is a folder: `color.ini`, `user.css`, optionally `theme.js` and `assets/`.
  The catalog records the repository, not which subfolder of it is a theme.
* A **custom app** needs `%APPDATA%\spicetify\CustomApps\<name>\manifest.json` plus every
  file that manifest references. The catalog has the entry point but not the rest.

Manual install, theme first:

```powershell
# browse, then clone the repository the entry points at
.\lean.ps1 catalog -Kind themes -Search <name>

git clone --depth 1 https://github.com/<owner>/<repo> "$env:TEMP\spotify-theme"
Copy-Item "$env:TEMP\spotify-theme\<ThemeName>" "$env:APPDATA\spicetify\Themes\<ThemeName>" -Recurse

# the scheme name is the bracketed section in that theme's color.ini
spicetify config current_theme <ThemeName>
spicetify config color_scheme <SchemeName>
spicetify apply
```

```powershell
# custom app
git clone --depth 1 https://github.com/<owner>/<repo> "$env:TEMP\spotify-app"
Copy-Item "$env:TEMP\spotify-app" "$env:APPDATA\spicetify\CustomApps\<name>" -Recurse
spicetify config custom_apps <name>
spicetify apply
```

Things to know:

* `lean.ps1 restore` removes only the Lean theme and the extensions it managed. Themes and
  apps you install by hand stay.
* Switching themes replaces the visual layer entirely - the Lean debloat rules live in
  `theme/user.css`, so `data-lean` will have no effect under another theme.
* Custom apps show up in the sidebar next to Marketplace. They are ordinary JavaScript in
  your client, with the same trust considerations as an extension.

## The Marketplace app instead

If you would rather click than clone, the Marketplace GUI is itself a custom app:

```powershell
spicetify config custom_apps marketplace
spicetify apply
```

`lean.ps1` does not install it, and `restore` does not remove it. Anything installed
through the GUI lands in the same extension folder and will coexist with the preset -
but the next `lean.ps1 extensions` run will not know about it and will leave it enabled,
so keep track of what you added.
