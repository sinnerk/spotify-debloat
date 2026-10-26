#Requires -Version 5.1

function Invoke-LeanInstall {
    <#
    .SYNOPSIS
        One-command install: backup, debloat, theme, extension preset, apply.
    #>
    [CmdletBinding()]
    param(
        [string] $Profile = 'lean',
        [switch] $Aggressive,
        [switch] $BlockSpotifyUpdates,
        [switch] $NoRestart,
        [switch] $DryRun,
        [switch] $Force
    )

    Write-LeanBanner 'install' ("profile: {0}{1}" -f $Profile, $(if ($DryRun) { ' (dry run)' } else { '' }))

    $checks = Test-LeanEnvironment
    foreach ($check in $checks) {
        $level = switch ($check.Status) {
            'FAIL' { 'Error' }
            'WARN' { 'Warn' }
            default { 'Debug' }
        }
        Write-LeanLog ("{0,-18} {1,-5} {2}" -f $check.Name, $check.Status, $check.Detail) -Level $level
    }
    $failures = @($checks | Where-Object { $_.Status -eq 'FAIL' })
    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-LeanLog ("Fix: {0}" -f $failure.Fix) -Level Error }
        throw 'Preflight checks failed. Nothing was changed.'
    }

    if ($DryRun) {
        Write-LeanLog 'Planned changes:' -Level Step
        Write-LeanLog ("  1. Back up Spotify files (if no backup exists)")
        Write-LeanLog ("  2. Apply debloat config (aggressive={0}, block updates={1})" -f [bool]$Aggressive, [bool]$BlockSpotifyUpdates)
        Write-LeanLog ("  3. Install theme 'Lean' and lean-ui.js")
        Write-LeanLog ("  4. Download and enable preset '{0}'" -f $Profile)
        Write-LeanLog ("  5. spicetify apply")
        $null = Set-LeanDebloat -Aggressive:$Aggressive -BlockSpotifyUpdates:$BlockSpotifyUpdates -DryRun
        $null = Install-LeanTheme -DryRun
        $null = Install-LeanExtensionSet -Profile $Profile -DryRun -Force:$Force
        Write-LeanLog 'Dry run complete. Nothing was changed.' -Level Warn
        return [pscustomobject]@{ DryRun = $true; Profile = $Profile }
    }

    $wasRunning = Test-SpotifyRunning
    if ($wasRunning) {
        Write-LeanLog 'Closing Spotify for the patch step...' -Level Step
        Stop-SpotifyClient -Force:$Force
    }

    $debloat = Set-LeanDebloat -Aggressive:$Aggressive -BlockSpotifyUpdates:$BlockSpotifyUpdates -Force:$Force
    # Extensions first: installing a preset prunes files that are no longer in it,
    # and the theme's companion extension must land after that prune.
    $extensions = Install-LeanExtensionSet -Profile $Profile -Force:$Force
    $theme = Install-LeanTheme

    Invoke-LeanApply -NoRestart

    if ($wasRunning -and -not $NoRestart) {
        Write-LeanLog 'Starting Spotify...' -Level Step
        if (Start-SpotifyClient) { Write-LeanLog 'Spotify is running.' -Level Ok }
        else { Write-LeanLog 'Spotify did not open within 45 seconds; start it manually.' -Level Warn }
    }

    Write-LeanLog '' 
    Write-LeanLog 'Install complete.' -Level Ok
    Write-LeanLog ("  theme       {0}" -f $theme.ThemePath)
    Write-LeanLog ("  extensions  {0} enabled via preset '{1}'" -f $extensions.Installed, $Profile)
    Write-LeanLog ("  debloat     sentry/logging off, telemetry hosts mapped to 127.0.0.1")
    Write-LeanLog ''
    Write-LeanLog "Steady-state numbers: lean.ps1 benchmark -Label lean -Seconds 45 -Warmup 20 -Restart" -Level Info
    Write-LeanLog "Undo everything with: lean.ps1 restore" -Level Info

    return [pscustomobject]@{
        DryRun     = $false
        Profile    = $Profile
        Theme      = $theme
        Extensions = $extensions
        Debloat    = $debloat.Settings
    }
}
