# Debloat

What "debloat" means in this project: stop the client doing work you never see, and stop
it rendering surfaces you never asked for. Nothing here patches Spotify's binary, blocks
ads, or touches your account.

Two switches exist:

* the default configuration written by `Set-LeanDebloat` (`lean.ps1 install` /
  `lean.ps1 debloat`);
* `-Aggressive`, which adds two Chromium limits and is **off by default**.

## 1. Client preprocessing

These are Spicetify's own documented `[Preprocesses]` switches. They edit the client's
JavaScript bundle while patching, so they survive as long as the patch does.

| Setting | Value | Effect |
| --- | --- | --- |
| `disable_sentry` | `1` | Removes the Sentry error-reporting SDK from the bundle. No crash reports leave the machine, and the SDK's own startup cost is gone. |
| `disable_ui_logging` | `1` | Drops the client's verbose UI logging calls. Less string building and console traffic per interaction. |
| `remove_rtl_rule` | `1` | Removes the right-to-left CSS rule injection. Slightly smaller stylesheet, no effect on LTR layouts. |
| `expose_apis` | `1` | Enables Spicetify's own API surface, which the bundled `lean-ui.js` and any extension needs. Not a privacy setting. |

## 2. Theme and layout settings

| Setting | Value | Why |
| --- | --- | --- |
| `inject_css` | `1` | Loads `user.css`. Without it nothing visual applies. |
| `inject_theme_js` | `0` | The Lean theme ships no `theme.js`, so there is nothing to inject. The top-bar toggle is an extension (`lean-ui.js`), which loads from the extension list regardless of this setting. |
| `replace_colors` | `1` | Lets `color.ini` set the palette instead of Spotify's default. |
| `home_config` | `0` | Keeps Spicetify's own Home layout editor disabled; the theme does the trimming. |
| `experimental_features` | `0` | No experimental Spicetify features. |
| `sidebar_config` | `0` | No Spicetify sidebar customisation. |
| `always_enable_devtools` | `0` | The DevTools shortcut stays off, so an accidental F12 cannot leave a debugger attached. |

## 3. Launch flags

`spotify_launch_flags` receives exactly one flag from this project unless `-Aggressive`
is used:

```
--host-resolver-rules=MAP log.spotify.com 127.0.0.1,
                        MAP crashdump.spotify.com 127.0.0.1,
                        MAP crashdump.spotify.net 127.0.0.1,
                        MAP analytics.spotify.com 127.0.0.1
```

This is a Chromium host-resolver override: those four names resolve to loopback, so any
request to them fails immediately instead of leaving the machine, waiting for a timeout,
and being retried.

What it does:

* removes the DNS lookup and the TLS handshake for the analytics and crash-report
  endpoints;
* makes crash uploads and event batches fail fast rather than retry in the background.

What it does **not** do:

* it is not an ad blocker - audio and banner ads are served from Spotify's normal
  content and CDN hosts, which are untouched;
* it does not stop every outbound connection - Spotify still talks to its API, its CDN
  and its licence server, or playback would not work;
* it changes nothing outside the Spotify process.

The flag is only applied when this project starts Spotify (`Start-SpotifyClient` passes
it explicitly). Spicetify 2.46 has no `start` command, so a launcher that merely writes
the setting never gets the flags - that bug is fixed in `Get-SpotifyLaunchFlags`.

## 4. UI surfaces hidden by the theme

These are CSS rules, not client changes, and they are all scoped to
`:root:not([data-lean="0"])`:

| Target | Selector | Why |
| --- | --- | --- |
| Upgrade / Premium buttons | `[data-testid="upgrade-button"]`, `[data-testid="download-button"]`, `[class*="topBar-upgradeButton"]` | Pure upsell chrome. |
| "What's New" | `[class*="topBar-whatsNewButton"]`, `button[aria-label="What's New"]` | A modal you did not ask for. |
| Home recommendation carousels | `[data-testid="home-page"] [data-testid="component-shelf"]:not(:has(a[href="/recents"]))` | Removes every shelf except the one that links to your own recent listening. |

The Home rule deliberately keeps the pinned shortcut grid and the `/recents` shelf.
`a[href="/recents"]` is a locale-independent hook, unlike the visible shelf title.

Upsell rules are account-dependent: a Premium account never renders an upgrade button,
so `tools/cdp-audit.mjs` will report those selectors as dead on such a login. That is
expected, not a bug.

## 5. Aggressive mode

`lean.ps1 install -Aggressive` (or `debloat -Aggressive`) adds:

| Flag | Effect | Risk |
| --- | --- | --- |
| `--renderer-process-limit=3` | Caps how many renderer processes Chromium may spawn. | With many open views Chromium starts reusing renderers; heavy pages can stutter. |
| `--js-flags=--max-old-space-size=512` | Caps V8's old-generation heap at 512 MB. | Large playlists, long queues or big library scrolls can hit the cap and force a reload. |

Both are legitimate levers on a memory-constrained machine and both can make a fast
machine feel worse. Measure before and after; do not enable them because the name sounds
good.

## The toggle

`window.Lean` is the runtime API provided by `theme/lean-ui.js`:

```js
Lean.enabled          // boolean, mirrored in localStorage
Lean.setEnabled(false) // debloat rules off, stock layout back
Lean.toggle()
```

The top-bar "Lean" pill does the same thing. State persists in
`localStorage["spotify-debloat:ui"]`; setting it to `0` keeps the theme's typography,
spacing and colours while restoring the hidden surfaces. That makes it a one-click
A/B test when you suspect a rule is hiding something you needed.

## What is out of scope

| Not done | Why |
| --- | --- |
| Ad blocking | Circumvents Spotify's monetisation. `data/policy.json` also refuses to enable ad-blocking extensions in the `full` preset. |
| Downloading / DRM circumvention | Same reason; explicitly blocked by policy. |
| Binary patching beyond Spicetify's documented preprocessing | Unmaintainable and impossible to revert cleanly. |
| Network proxying or a hosts-file edit | The launch flag is scoped to one process and dies with it. |
| Account, playlist or library changes | The tool never authenticates. |

## Measuring the result

```powershell
.\lean.ps1 benchmark -Label before -Seconds 60 -Restart
# make a change
.\lean.ps1 benchmark -Label after  -Seconds 60 -Restart
```

Reports land in `reports/`. Method and caveats: [BENCHMARKS.md](BENCHMARKS.md).
