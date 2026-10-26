#Requires -Version 5.1

function Test-LeanEnvironment {
    <#
    .SYNOPSIS
        Checks the local Spotify/Spicetify installation before changing anything.
    #>
    [CmdletBinding()]
    param()

    $context = Get-LeanContext -Refresh
    $checks = New-Object System.Collections.ArrayList

    function Add-Check {
        param([string] $Name, [string] $Status, [string] $Detail, [string] $Fix = '')
        [void] $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Fix = $Fix })
    }

    Add-Check 'Platform' 'PASS' ("{0} / PowerShell {1}" -f $env:OS, $context.PowerShellVersion)

    if ($context.SpotifyVersion) {
        Add-Check 'Spotify' 'PASS' ("{0} ({1})" -f $context.SpotifyVersion, $context.SpotifyPath)
    } else {
        Add-Check 'Spotify' 'FAIL' 'Spotify.exe not found.' 'Install the Spotify desktop client, then run this again.'
    }

    if ($context.SpicetifyVersion) {
        Add-Check 'Spicetify' 'PASS' ("v{0} ({1})" -f $context.SpicetifyVersion, $context.SpicetifyExe)
    } else {
        Add-Check 'Spicetify' 'FAIL' 'spicetify is not installed or not on PATH.' 'Run: iwr -useb https://raw.githubusercontent.com/spicetify/cli/main/install.ps1 | iex'
    }

    if (Test-Path -LiteralPath $context.ConfigPath) {
        Add-Check 'Config' 'PASS' $context.ConfigPath
    } elseif ($context.SpicetifyExe) {
        Add-Check 'Config' 'WARN' 'Spicetify has not generated its config yet.' "Run 'spicetify' once, then 'spicetify backup apply'."
    } else {
        Add-Check 'Config' 'FAIL' 'No config and no Spicetify binary.' 'Install Spicetify first.'
    }

    $backup = Test-SpicetifyBackup
    if ($backup.Present -and $backup.MatchesCurrent) {
        Add-Check 'Backup' 'PASS' ("matches Spotify {0}" -f $backup.BackupVersion)
    } elseif ($backup.Present) {
        Add-Check 'Backup' 'WARN' ("backup {0} does not match Spotify {1}" -f $backup.BackupVersion, $backup.SpotifyVersion) "Run 'spicetify restore backup apply' after a Spotify update."
    } else {
        Add-Check 'Backup' 'WARN' 'No Spicetify backup yet.' "The installer creates one automatically (about 400 MB)."
    }

    try {
        $catalog = Get-LeanCatalogData
        Add-Check 'Catalog' 'PASS' ("{0} extensions, {1} themes, {2} apps, {3} snippets" -f $catalog.counts.extensions, $catalog.counts.themes, $catalog.counts.apps, $catalog.counts.snippets)
    } catch {
        Add-Check 'Catalog' 'FAIL' $_.Exception.Message 'Run tools/Sync-Catalog.ps1.'
    }

    $themeFiles = @('color.ini', 'user.css', 'lean-ui.js')
    $missing = @($themeFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $context.ThemeSource $_)) })
    if ($missing.Count -eq 0) {
        Add-Check 'Theme files' 'PASS' $context.ThemeSource
    } else {
        Add-Check 'Theme files' 'FAIL' ("missing: {0}" -f ($missing -join ', ')) 'Re-clone the repository.'
    }

    if (Test-Path -LiteralPath $context.ExtensionRoot) {
        $probe = Join-Path $context.ExtensionRoot '.lean-write-test'
        try {
            [IO.File]::WriteAllText($probe, 'ok')
            Remove-Item -LiteralPath $probe -Force
            Add-Check 'Extensions folder' 'PASS' $context.ExtensionRoot
        } catch {
            Add-Check 'Extensions folder' 'FAIL' $context.ExtensionRoot 'Check folder permissions.'
        }
    } else {
        Add-Check 'Extensions folder' 'WARN' 'Folder does not exist yet.' 'It will be created on install.'
    }

    $running = Get-SpotifyProcessSummary
    if ($running.Count -gt 0) {
        Add-Check 'Spotify process' 'INFO' ("running, {0} process(es), {1}" -f $running.Count, (Format-LeanBytes $running.WorkingSet))
    } else {
        Add-Check 'Spotify process' 'INFO' 'not running'
    }

    Add-Check 'Node.js' $(if (Get-Command node -ErrorAction SilentlyContinue) { 'INFO' } else { 'INFO' }) $(if (Get-Command node -ErrorAction SilentlyContinue) { (node --version) } else { 'not installed (only needed for tests)' })
    Add-Check 'Administrator' 'INFO' $(if (Test-LeanAdmin) { 'yes (not required)' } else { 'no (not required)' })

    return @($checks)
}

function Get-LeanStatus {
    <#
    .SYNOPSIS
        Shows the current Lean/Spicetify state.
    #>
    [CmdletBinding()]
    param()

    $context = Get-LeanContext -Refresh
    $state = Get-LeanState
    $config = Get-SpicetifyConfigMap
    $processes = Get-SpotifyProcessSummary

    $extensions = @()
    if ($config['extensions']) { $extensions = @($config['extensions'] -split '\|' | Where-Object { $_ }) }
    $managed = @()
    if ($state) { $managed = @($state.managedExtensions) }

    $catalog = $null
    try { $catalog = Get-LeanCatalogData } catch { }

    return [pscustomobject]@{
        SpotifyVersion   = $context.SpotifyVersion
        SpicetifyVersion = $context.SpicetifyVersion
        Theme            = $config['current_theme']
        ColorScheme      = $config['color_scheme']
        ExtensionsEnabled = $extensions.Count
        ExtensionsManaged = $managed.Count
        Extensions        = $extensions
        LaunchFlags       = $config['spotify_launch_flags']
        DebloatActive     = ($config['disable_sentry'] -eq '1' -and $config['disable_ui_logging'] -eq '1')
        Profile           = $(if ($state) { $state.profile } else { $null })
        Aggressive        = $(if ($state) { $state.aggressive } else { $false })
        UpdatesBlocked    = $(if ($state) { $state.blockedUpdates } else { $false })
        InstalledAt       = $(if ($state) { $state.createdAt } else { $null })
        Catalog           = $(if ($catalog) { $catalog.counts } else { $null })
        Running           = ($processes.Count -gt 0)
        ProcessCount      = $processes.Count
        WorkingSet        = $processes.WorkingSet
        PrivateBytes      = $processes.PrivateBytes
    }
}
