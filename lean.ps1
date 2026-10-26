#Requires -Version 5.1
<#
.SYNOPSIS
    spicetify-lean command line.

.EXAMPLE
    .\lean.ps1 install

.EXAMPLE
    .\lean.ps1 install -DryRun

.EXAMPLE
    .\lean.ps1 catalog -Search lyrics -Top 15

.EXAMPLE
    .\lean.ps1 benchmark -Label before -Seconds 60

.EXAMPLE
    .\lean.ps1 restore
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Command = 'help',

    [string] $Profile = 'lean',
    [string[]] $Ids = @(),
    [string] $Kind = 'extensions',
    [string] $Search,
    [string] $Tag,
    [int] $Top = 0,
    [string] $Label = 'run',
    [int] $Seconds = 45,
    [int] $Warmup = 10,

    [switch] $Aggressive,
    [switch] $BlockSpotifyUpdates,
    [switch] $NoRestart,
    [switch] $DryRun,
    [switch] $Force,
    [switch] $KeepTheme,
    [switch] $Restart,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'src\Lean.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

function Show-LeanHelp {
    @'
spicetify-lean - a debloated Spicetify distribution

USAGE
  .\lean.ps1 <command> [options]

COMMANDS
  install       Backup, debloat, install the Lean theme and a plugin preset, then apply.
                -Profile lean|full|minimal   extension preset (default: lean)
                -Aggressive                  add Chromium memory limits
                -BlockSpotifyUpdates         stop Spotify auto-updates breaking the patch
                -NoRestart                   do not reopen Spotify
                -DryRun                      show every planned change, touch nothing
                -Force                       allow the 'full' preset

  debloat       Apply only the preprocessing/telemetry configuration, then apply.
  theme         Reinstall only the Lean theme and lean-ui.js, then apply.
  extensions    Install or switch an extension preset without touching the theme.
                -Profile lean|full|minimal, or -Ids id1,id2
  catalog       Search the committed Marketplace inventory.
                -Kind extensions|themes|apps|snippets|all
                -Search <regex>  -Tag <tag>  -Top <n>  -Json
  benchmark     Sample RAM/CPU and write reports/<timestamp>-<label>.json
                -Label before|after  -Seconds 60  -Restart
  status        Show the current Spotify/Spicetify/Lean state.
  doctor        Run preflight checks with fixes.
  restore       Undo everything and return to the original Spotify client.
                -KeepTheme  -NoRestart  -DryRun

EXAMPLES
  .\lean.ps1 doctor
  .\lean.ps1 install -DryRun
  .\lean.ps1 install
  .\lean.ps1 benchmark -Label before
  .\lean.ps1 install -Aggressive
  .\lean.ps1 benchmark -Label after
  .\lean.ps1 catalog -Search "lyrics" -Top 10
  .\lean.ps1 extensions -Ids spicetify-cli--shuffle,spicetify-cli--bookmark
  .\lean.ps1 restore

Docs: README.md and docs/README.md
'@ | Write-Host
}

function Format-LeanStatus {
    param($Status)
    Write-Host ''
    Write-Host '  spicetify-lean status' -ForegroundColor DarkGray
    Write-Host ''
    $rows = @(
        @('Spotify', $Status.SpotifyVersion),
        @('Spicetify', $Status.SpicetifyVersion),
        @('Theme', $Status.Theme),
        @('Profile', $Status.Profile),
        @('Extensions', ("{0} enabled / {1} managed" -f $Status.ExtensionsEnabled, $Status.ExtensionsManaged)),
        @('Debloat', $(if ($Status.DebloatActive) { 'sentry + UI logging disabled' } else { 'not active' })),
        @('Telemetry map', $(if ($Status.LaunchFlags -match 'host-resolver-rules') { 'active' } else { 'not set' })),
        @('Aggressive flags', $(if ($Status.Aggressive) { 'on' } else { 'off' })),
        @('Updates blocked', $(if ($Status.UpdatesBlocked) { 'yes' } else { 'no' })),
        @('Installed', $Status.InstalledAt),
        @('Running', $(if ($Status.Running) { ("{0} processes, {1:N0} MB" -f $Status.ProcessCount, ($Status.WorkingSet / 1MB)) } else { 'no' }))
    )
    foreach ($row in $rows) {
        Write-Host ("  {0,-18}" -f $row[0]) -NoNewline -ForegroundColor DarkGray
        Write-Host $row[1]
    }
    if ($Status.Catalog) {
        Write-Host ''
        Write-Host ("  Catalog: {0} extensions, {1} themes, {2} apps, {3} snippets" -f `
            $Status.Catalog.extensions, $Status.Catalog.themes, $Status.Catalog.apps, $Status.Catalog.snippets) -ForegroundColor DarkGray
    }
    Write-Host ''
}

switch ($Command.ToLowerInvariant()) {
    'install' {
        $result = Invoke-LeanInstall -Profile $Profile -Aggressive:$Aggressive -BlockSpotifyUpdates:$BlockSpotifyUpdates `
            -NoRestart:$NoRestart -DryRun:$DryRun -Force:$Force
        if ($Json) { $result | ConvertTo-Json -Depth 6 }
    }

    'setup' {
        $result = Invoke-LeanInstall -Profile $Profile -Aggressive:$Aggressive -BlockSpotifyUpdates:$BlockSpotifyUpdates `
            -NoRestart:$NoRestart -DryRun:$DryRun -Force:$Force
        if ($Json) { $result | ConvertTo-Json -Depth 6 }
    }

    'debloat' {
        $null = Set-LeanDebloat -Aggressive:$Aggressive -BlockSpotifyUpdates:$BlockSpotifyUpdates -DryRun:$DryRun -Force:$Force
        if (-not $DryRun) { Invoke-LeanApply -NoRestart:$NoRestart -Force:$Force }
    }

    'theme' {
        $result = Install-LeanTheme -DryRun:$DryRun
        if (-not $DryRun) { Invoke-LeanApply -NoRestart:$NoRestart -Force:$Force }
        if ($Json) { $result | ConvertTo-Json -Depth 4 }
    }

    'extensions' {
        $result = Install-LeanExtensionSet -Profile $Profile -Ids $Ids -DryRun:$DryRun -Force:$Force
        if (-not $DryRun) { Invoke-LeanApply -NoRestart:$NoRestart -Force:$Force }
        if ($Json) { $result | ConvertTo-Json -Depth 4 }
    }

    'catalog' {
        $items = Get-LeanCatalog -Kind $Kind -Search $Search -Tag $Tag -Top $Top -Json:$Json
        if ($Json) {
            $items
        } elseif ($Kind -eq 'all') {
            foreach ($name in @('extensions', 'themes', 'apps', 'snippets')) {
                Write-Host ("  {0,-12} {1}" -f $name, @($items.$name).Count)
            }
        } elseif ($Kind -eq 'snippets') {
            $items | Select-Object title, id | Format-Table -AutoSize
        } else {
            $items | Select-Object name, stars, repo, id | Format-Table -AutoSize
        }
    }

    'search' {
        $items = Get-LeanCatalog -Kind 'extensions' -Search $Search -Top $(if ($Top -gt 0) { $Top } else { 25 })
        $items | Select-Object name, stars, repo, id | Format-Table -AutoSize
    }

    'benchmark' {
        $report = Measure-LeanPerformance -Seconds $Seconds -Warmup $Warmup -Label $Label -Restart:$Restart
        if ($Json) {
            $report | ConvertTo-Json -Depth 5
        } else {
            Write-Host ''
            Write-Host '  benchmark: ' -NoNewline -ForegroundColor DarkGray
            Write-Host $report.label
            Write-Host ("  memory    {0} MB avg, {1} MB peak, {2} MB private" -f $report.memory.workingSetAverageMB, $report.memory.workingSetPeakMB, $report.memory.privateAverageMB)
            Write-Host ("  cpu       {0}% of one core ({1}% of the system)" -f $report.cpu.percentOfOneCore, $report.cpu.percentOfSystem)
            Write-Host ("  processes {0}" -f $report.processes.average)
            if ($report.PSObject.Properties['warnings'] -and @($report.warnings).Count -gt 0) {
                foreach ($warning in @($report.warnings)) {
                    Write-Host ("  warning   {0}" -f $warning) -ForegroundColor Yellow
                }
            }
            if ($report.PSObject.Properties['reportPath']) { Write-Host ("  report    {0}" -f $report.reportPath) -ForegroundColor DarkGray }
            Write-Host ''
        }
    }

    'status' {
        Format-LeanStatus -Status (Get-LeanStatus)
    }

    'doctor' {
        $checks = Test-LeanEnvironment
        Write-Host ''
        foreach ($check in $checks) {
            $color = switch ($check.Status) {
                'FAIL' { 'Red' }
                'WARN' { 'Yellow' }
                'PASS' { 'Green' }
                default { 'DarkGray' }
            }
            Write-Host ("  {0,-18}" -f $check.Name) -NoNewline -ForegroundColor DarkGray
            Write-Host ("{0,-5}" -f $check.Status) -NoNewline -ForegroundColor $color
            Write-Host $check.Detail
            if ($check.Fix -and $check.Status -ne 'PASS' -and $check.Status -ne 'INFO') {
                Write-Host ("  {0,-18}      {1}" -f '', $check.Fix) -ForegroundColor DarkYellow
            }
        }
        Write-Host ''
        if (@($checks | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0) { exit 1 }
    }

    'restore' {
        $null = Restore-Lean -DryRun:$DryRun -Force:$Force -KeepTheme:$KeepTheme -NoRestart:$NoRestart
    }

    'uninstall' {
        $null = Restore-Lean -DryRun:$DryRun -Force:$Force -KeepTheme:$KeepTheme -NoRestart:$NoRestart
    }

    'version' {
        $module = Get-Module Lean
        Write-Host ("spicetify-lean {0}" -f $module.Version)
    }

    'help' { Show-LeanHelp }
    default {
        Write-Host ("Unknown command: {0}" -f $Command) -ForegroundColor Red
        Write-Host ''
        Show-LeanHelp
        exit 1
    }
}
