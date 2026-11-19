#Requires -Version 5.1

function Invoke-LeanApply {
    [CmdletBinding()]
    param(
        [switch] $NoRestart,
        [switch] $Force
    )

    $wasRunning = Test-SpotifyRunning
    if ($wasRunning) {
        Write-LeanLog 'Stopping Spotify so Spicetify can patch its files...' -Level Step
        Stop-SpotifyClient -Force:$Force
    }

    Write-LeanLog 'Applying Spicetify patches...' -Level Step
    $result = Invoke-Spicetify -Arguments @('apply')
    if ($result.Text) { Write-LeanLog $result.Text -Level Debug }

    $context = Get-LeanContext
    $theme = Get-LeanIniValue -Path $context.ConfigPath -Section 'Setting' -Key 'current_theme'
    if ($theme -eq 'Lean') {
        # A blank copy of the stylesheet patches cleanly but renders unthemed,
        # so confirm the bundle actually carries it before starting the client.
        if (-not (Repair-LeanDeployedTheme -Context $context)) {
            Write-LeanLog 'Theme is installed but not present in the patched bundle; run lean.ps1 doctor.' -Level Error
        }
    }

    if ($wasRunning -and -not $NoRestart) {
        Write-LeanLog 'Starting Spotify...' -Level Step
        if (Start-SpotifyClient) {
            Write-LeanLog 'Spotify is running.' -Level Ok
        } else {
            Write-LeanLog 'Spotify did not open a window within 45 seconds. Start it manually and check docs/TROUBLESHOOTING.md.' -Level Warn
        }
    }
}

function Backup-LeanSpicetify {
    [CmdletBinding()]
    param([switch] $Force)

    $backup = Test-SpicetifyBackup
    if ($backup.Present) {
        if ($backup.MatchesCurrent) {
            Write-LeanLog ("Existing Spicetify backup matches Spotify {0}." -f $backup.BackupVersion) -Level Ok
            return
        }

        # Spotify's updater leaves a fresh xpui.spa next to the folder Spicetify
        # patched last time. When that file is present the update replaced the
        # client cleanly, so 'spicetify backup apply' is both safe and the only
        # supported way forward: current Spicetify releases (2.46.7 included)
        # make 'restore' refuse when the backup and client versions disagree.
        $context = Get-LeanContext
        $freshClient = Test-Path -LiteralPath (Join-Path $context.SpotifyPath 'Apps\xpui.spa')
        Write-LeanLog ("Spotify updated to {0}; the backup is still {1}." -f $backup.SpotifyVersion, $backup.BackupVersion) -Level Warn
        if (-not $freshClient) {
            Write-LeanLog "No clean xpui.spa from the updater; run 'spicetify backup apply' by hand and read its output." -Level Warn
            return
        }

        if (Test-SpotifyRunning) { Stop-SpotifyClient -Force:$Force }
        Write-LeanLog 'Refreshing the backup from the updated client (about 400 MB, one time per update)...' -Level Step
        $null = Invoke-Spicetify -Arguments @('-n', 'backup', 'apply')
        Write-LeanLog 'Backup refreshed and the client re-patched for this version.' -Level Ok
        return
    }

    if (Test-SpotifyRunning) { Stop-SpotifyClient -Force:$Force }
    Write-LeanLog 'Creating a clean Spicetify backup (one-time, about 400 MB)...' -Level Step
    $null = Invoke-Spicetify -Arguments @('backup')
    Write-LeanLog 'Backup created.' -Level Ok
}
