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
        } else {
            Write-LeanLog ("Backup version {0} does not match installed Spotify {1}; Spotify probably updated." -f $backup.BackupVersion, $backup.SpotifyVersion) -Level Warn
            Write-LeanLog "Run 'spicetify restore backup apply' once, then re-run the installer." -Level Warn
        }
        return
    }

    if (Test-SpotifyRunning) { Stop-SpotifyClient -Force:$Force }
    Write-LeanLog 'Creating a clean Spicetify backup (one-time, about 400 MB)...' -Level Step
    $null = Invoke-Spicetify -Arguments @('backup')
    Write-LeanLog 'Backup created.' -Level Ok
}
