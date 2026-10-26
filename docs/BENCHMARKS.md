# Benchmarks

Three questions this answers:

1. Does the Lean theme itself cost anything?
2. What do the ten extensions in the `lean` preset cost?
3. Is `-Aggressive` worth it?

The answer to (3) is "not measured, and probably not" - see the end.

## What is measured

| Metric | Definition |
| --- | --- |
| Working set | `WorkingSet64` summed over every `Spotify.exe` process, sampled once per second |
| Private bytes | `PrivateMemorySize64`, same sum - closer to what the app actually reserves |
| CPU | delta of summed `TotalProcessorTime` divided by wall-clock elapsed, expressed as a percentage of **one** core |
| Processes | count of `Spotify.exe` processes |

Not measured: GPU time, disk I/O, network traffic, JavaScript heap, frame rate, battery
drain. Those need tooling that would itself perturb the client.

## Method

Both configurations were measured the same way, back to back, on the same machine:

```powershell
# 3 cold runs with the lean preset
1..3 | ForEach-Object { .\lean.ps1 benchmark -Label "lean-$_" -Seconds 45 -Warmup 20 -Restart }

# switch to the theme-only baseline (keeps the theme, removes the 10 preset
# extensions; the theme's own lean-ui.js stays in both configurations)
.\lean.ps1 extensions -Profile minimal

# 3 cold runs of the baseline
1..3 | ForEach-Object { .\lean.ps1 benchmark -Label "theme-only-$_" -Seconds 45 -Warmup 20 -Restart }
```

Each run:

* force-closes Spotify and starts it again (`-Restart`) - no warm caches, no leftover
  renderers;
* restores the client window before sampling, because Chromium freezes renderers for an
  iconified or fully occluded window. Without this step a run can report exactly
  `0.00 %`, which is a broken sample, not a good result;
* waits 20 s for startup work to settle;
* samples for 45 s at 1 Hz with playback **paused** and no interaction.

The two configurations differ in exactly one thing: the ten preset extensions. The theme,
the debloat settings, the window size and the telemetry mapping are identical.

## Environment

| | |
| --- | --- |
| Spotify | 1.3.6.1921 (`g7086c071a617`) |
| Spicetify | 2.46.2 |
| Theme | Lean (`color.ini` "Lean", debloat on) |
| OS | Windows 11 24H2 |
| CPU | 16 logical cores |
| Client window | 1296 x 768 CSS px, visible |
| Playback | paused, no UI interaction |
| `-Aggressive` | off in both |

## Results

Three cold runs per configuration, 45 s each, same session (2026-10-26):

| Config | Extensions | Working set avg | Peak | Private avg | CPU (% of one core) |
| --- | --- | --- | --- | --- | --- |
| Theme only (`minimal`) | 1 (`lean-ui.js`) | 1 209.9 MB | 1 342.8 MB | 928.8 MB | 4.47 % |
| Theme + `lean` preset | 11 (`lean-ui.js` + 10) | 1 226.9 MB | 1 359.4 MB | 950.8 MB | 4.47 % |
| Difference | +10 | **+17.0 MB (+1.4 %)** | +16.6 MB | +22.0 MB | **0.00 pp** |

Per run:

| Run | Working set avg | Peak | Private avg | CPU |
| --- | --- | --- | --- | --- |
| `lean-1` | 1 233.8 MB | 1 371.6 MB | 959.7 MB | 4.47 % |
| `lean-2` | 1 223.6 MB | 1 352.5 MB | 944.7 MB | 4.47 % |
| `lean-3` | 1 223.4 MB | 1 354.1 MB | 947.9 MB | 4.47 % |
| `theme-only-1` | 1 213.5 MB | 1 340.1 MB | 932.1 MB | 4.47 % |
| `theme-only-2` | 1 192.3 MB | 1 322.8 MB | 913.7 MB | 4.47 % |
| `theme-only-3` | 1 223.8 MB | 1 365.5 MB | 940.7 MB | 4.47 % |

Every run has `windowVisible: true`, an empty `warnings` array, 8 processes and 45
samples. The raw reports are in [`reports/`](../reports).

## Interpretation

**The theme is effectively free.** CSS does not run timers, and the stylesheet adds no
network requests, no images and no fonts. Its cost sits below the run-to-run noise of the
client itself, which is why there is no "bare Spotify" column: the honest comparison for
"what did the theme cost" is the theme-only column against itself, and the interesting
question is what the extensions cost.

**The ten extensions are light, and the measurement cannot resolve a CPU difference.**
They add about 17 MB of summed working set (1.4 %) and 22 MB of private bytes. That is
smaller than the 32 MB spread of the theme-only baseline itself, so the honest reading is
"no difference beyond noise", not "+17 MB". Idle CPU is identical at 4.47 % of one core in
all six runs - see the resolution caveat below; this is not evidence that extensions are
free while the UI is busy.

**What the debloat actually buys is a smaller surface, not a smaller process.** The
extension preset removes UI chrome and adds a few keybinds; it does not shrink Chromium's
baseline footprint. Telemetry hosts are mapped to `127.0.0.1` at launch, Sentry/UI logging
is patched off, and the upsell/"What's New" surfaces are hidden. If you want lower RAM on
an 8 GB machine, the useful levers are `-Aggressive` (fewer renderers) and keeping fewer
views open, not deleting two more extensions.

**Earlier exploratory numbers are superseded.** An earlier draft quoted 1 190 MB vs
1 253 MB and 3.4 % vs 10.2 % CPU. Those samples were taken with the CDP debug port open,
without a cold restart in every case, and with the window state uncontrolled. They are
not comparable to this protocol and have been removed.

**Do not enable the `full` preset and call it a benchmark.** It is a stress test for the
patch, not a usable client.

### Per-extension attribution

Not done here, deliberately: measuring ten extensions one at a time means ten reinstalls
and ten restarts on this machine. If you need it, the workflow is:

```powershell
.\lean.ps1 extensions -Ids spicetify-cli--shuffle
.\lean.ps1 benchmark -Label shuffle-only -Seconds 45 -Warmup 20 -Restart
```

Compare against the same-session `theme-only` run, not against the numbers above: client
version, background sync and machine state all drift between sessions.

## Caveats

Read these before quoting a number:

* **Single machine, single session.** Three runs per configuration reduce noise; they do
  not make the result general.
* **RSS is shared.** Chromium processes share pages, so the sum of working sets
  over-counts the physical memory actually used. It is a consistent metric across
  configurations, not an "app uses N MB" claim.
* **CPU at idle is timer-dominated and quantized.** `Get-Process` reports CPU time in
  1/32 s ticks per process, so a 45 s sample can only resolve about 0.07 percentage
  points of one core. All six runs landed on the same tick count (2.0 s of CPU), which is
  why the CPU column is identical. A busy-UI benchmark would need a different method.
* **Background work is not controlled.** Spotify syncs, checks for updates and refreshes
  caches on its own schedule. That is most of the run-to-run spread.
* **The sample rate is 1 Hz.** Short spikes between samples are invisible. Peak memory
  is the max of the samples, not a true peak.
* **The debug port was not open** during these runs. Earlier exploratory numbers were
  taken with `--remote-debugging-port=9222` active and are not comparable to these.

## Reproducing

Any two labels are comparable as long as they come from the same session:

```powershell
.\lean.ps1 benchmark -Label before -Seconds 60 -Warmup 20 -Restart
# change one thing
.\lean.ps1 benchmark -Label after  -Seconds 60 -Warmup 20 -Restart
```

Reports are written to `reports/<timestamp>-<label>.json` and are committed when they
describe a shipped configuration. Delete exploratory ones; a directory of fifteen
half-context numbers is worse than none.

## Reading a report

```jsonc
{
  "schemaVersion": 1,
  "label": "lean-1",
  "capturedAt": "2026-10-26T20:12:44Z",
  "durationSeconds": 44.5,          // actual elapsed sampling window
  "sampleCount": 45,
  "spotifyVersion": "1.3.6.1921",
  "spicetifyVersion": "2.46.2",
  "theme": "Lean",
  "aggressive": false,
  "launchFlags": "--host-resolver-rules=...",
  "extensionCount": 11,             // includes lean-ui.js
  "processorCount": 16,
  "windowVisible": true,
  "warnings": [],                   // non-empty means do not trust the sample
  "memory": { "workingSetAverageMB": 0, "workingSetPeakMB": 0, "privateAverageMB": 0, "privatePeakMB": 0 },
  "cpu": { "percentOfOneCore": 0, "percentOfSystem": 0 },
  "processes": { "average": 0, "peak": 0 }
}
```

A non-empty `warnings` array is the first thing to check: a zero CPU delta means the
client was frozen, and the run should be repeated with the window visible.

## Why `-Aggressive` is not benchmarked

`--renderer-process-limit=3` and `--max-old-space-size=512` trade stability for a smaller
footprint. Whether that trade is good depends on how many views you keep open and how
large your playlists are, so a single idle measurement would be misleading in the
direction that matters (it would look free). If you use it, measure the scenarios you
actually care about, and expect reloads rather than savings on a machine with headroom.

## Adding a column

If you want the stock-client baseline, the honest way is a separate machine or a full
`spicetify restore backup apply` round trip, which is a ~400 MB operation and lands the
client on the backup's version - not the version under test. That is why it is not in
this table.
