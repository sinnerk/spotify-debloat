#Requires -Version 5.1

function Measure-LeanPerformance {
    <#
    .SYNOPSIS
        Samples Spotify's memory and CPU over a window and writes a JSON report.
    .DESCRIPTION
        CPU is measured as a delta of Get-Process CPU seconds divided by elapsed
        wall time. Run the same command before and after a change with different
        -Label values to compare like with like.
    #>
    [CmdletBinding()]
    param(
        [int] $Seconds = 45,
        [int] $Warmup = 10,
        [string] $Label = 'run',
        [switch] $Restart,
        [switch] $NoWrite
    )

    if ($Seconds -lt 5) { throw 'Seconds must be at least 5.' }
    $context = Get-LeanContext -Refresh

    if ($Restart) {
        Write-LeanLog 'Restarting Spotify for a cold measurement...' -Level Step
        if (Test-SpotifyRunning) { Stop-SpotifyClient -Force }
        if (-not (Start-SpotifyClient)) { throw 'Spotify did not start.' }
    }

    if (-not (Test-SpotifyRunning)) { throw 'Spotify is not running. Start it first, or pass -Restart.' }

    # An iconified or occluded Chromium window has its renderers frozen, so a sample
    # taken in that state can read exactly 0% CPU. Restore it first, always.
    $windowVisible = Restore-SpotifyWindow
    if (-not $windowVisible) {
        Write-LeanLog 'Spotify has no visible window; the sample may understate CPU.' -Level Warn
    }

    if ($Warmup -gt 0) {
        Write-LeanLog ("Warming up for {0}s..." -f $Warmup) -Level Step
        Start-Sleep -Seconds $Warmup
    }

    Write-LeanLog ("Sampling Spotify for {0}s..." -f $Seconds) -Level Step
    $samples = New-Object System.Collections.ArrayList
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $Seconds; $i++) {
        $processes = Get-SpotifyProcesses
        if ($processes.Count -eq 0) { throw 'Spotify exited during the measurement.' }

        $workingSet = 0L
        $private = 0L
        $cpu = 0.0
        foreach ($process in $processes) {
            $workingSet += $process.WorkingSet64
            $private += $process.PrivateMemorySize64
            $cpu += $process.CPU
        }
        [void] $samples.Add([pscustomobject]@{
            Elapsed      = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
            WorkingSet   = $workingSet
            PrivateBytes = $private
            CpuSeconds   = $cpu
            Processes    = $processes.Count
        })
        Start-Sleep -Milliseconds 1000
    }
    $stopwatch.Stop()

    $first = $samples[0]
    $last = $samples[$samples.Count - 1]
    $elapsed = [Math]::Max(0.001, ($last.Elapsed - $first.Elapsed))
    $cpuDelta = [Math]::Max(0, ($last.CpuSeconds - $first.CpuSeconds))
    $workingSets = @($samples | ForEach-Object { $_.WorkingSet })
    $privates = @($samples | ForEach-Object { $_.PrivateBytes })

    $average = { param($values) ($values | Measure-Object -Average).Average }
    $peak = { param($values) ($values | Measure-Object -Maximum).Maximum }
    $state = Get-LeanState

    $warnings = New-Object System.Collections.ArrayList
    if ($cpuDelta -le 0) {
        [void] $warnings.Add('CPU delta was zero: the client was idle or frozen (iconified/occluded). Bring the window to the foreground and re-run before trusting this sample.')
    }
    if (-not $windowVisible) {
        [void] $warnings.Add('Spotify had no visible window during the sample.')
    }
    if (Test-SpotifyRunning) {
        $current = Get-SpotifyProcessSummary
        if ($current.MainWindowTitle -match '^-?\s*$') {
            [void] $warnings.Add('The Spotify window title is empty; playback state is unknown.')
        }
    }

    $report = [pscustomobject]@{
        schemaVersion   = 1
        label           = $Label
        capturedAt      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        durationSeconds = [Math]::Round($elapsed, 1)
        sampleCount     = $samples.Count
        spotifyVersion  = $context.SpotifyVersion
        spicetifyVersion = $context.SpicetifyVersion
        theme           = (Get-SpicetifyConfigValue -Key 'current_theme')
        aggressive      = $(if ($state) { $state.aggressive } else { $false })
        launchFlags     = (Get-SpicetifyConfigValue -Key 'spotify_launch_flags')
        extensionCount  = (Get-SpicetifyConfigList -Key 'extensions').Count
        processorCount  = [Environment]::ProcessorCount
        windowVisible   = $windowVisible
        warnings        = @($warnings)
        memory          = [pscustomobject]@{
            workingSetAverageMB = [Math]::Round((& $average $workingSets) / 1MB, 1)
            workingSetPeakMB    = [Math]::Round((& $peak $workingSets) / 1MB, 1)
            privateAverageMB    = [Math]::Round((& $average $privates) / 1MB, 1)
            privatePeakMB       = [Math]::Round((& $peak $privates) / 1MB, 1)
        }
        cpu             = [pscustomobject]@{
            percentOfOneCore = [Math]::Round(($cpuDelta / $elapsed) * 100, 2)
            percentOfSystem  = [Math]::Round((($cpuDelta / $elapsed) * 100) / [Environment]::ProcessorCount, 2)
        }
        processes       = [pscustomobject]@{
            average = [Math]::Round((& $average @($samples | ForEach-Object { $_.Processes })), 1)
            peak    = (& $peak @($samples | ForEach-Object { $_.Processes }))
        }
    }

    if (-not $NoWrite) {
        $reports = $context.ReportsPath
        New-Item -ItemType Directory -Force -Path $reports | Out-Null
        $safeLabel = ($Label -replace '[^a-zA-Z0-9_-]', '-')
        $file = Join-Path $reports ("{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $safeLabel)
        Write-LeanJson -Path $file -Object $report
        $report | Add-Member -NotePropertyName reportPath -NotePropertyValue $file -Force
    }

    return $report
}
