#Requires -Version 5.1

function Restore-Lean {
    <#
    .SYNOPSIS
        Reverts configuration, theme, extensions and Spotify files to their pre-Lean state.
    #>
    [CmdletBinding()]
    param(
        [switch] $DryRun,
        [switch] $Force,
        [switch] $KeepTheme,
        [switch] $NoRestart
    )

    $context = Assert-SpicetifyReady
    $state = Get-LeanState
    $wasRunning = Test-SpotifyRunning

    Write-LeanBanner 'restore' 'reverting to the original Spotify client'

    if (-not $state) {
        Write-LeanLog 'No lean-state.json found. Falling back to Spicetify restore.' -Level Warn
    }

    if ($DryRun) {
        Write-LeanLog ("Would remove {0} managed extension(s)." -f @($state.managedExtensions).Count)
        if ($state -and $state.themeInstalled -and -not $KeepTheme) {
            Write-LeanLog ("Would remove theme folder {0}" -f (Join-Path $context.ThemeRoot 'Lean'))
        }
        Write-LeanLog "Would restore original Spicetify config values and run 'spicetify restore backup apply'."
        Write-LeanLog 'Dry run complete. Nothing was changed.' -Level Warn
        return [pscustomobject]@{ DryRun = $true; Restored = $false }
    }

    if ($wasRunning) { Stop-SpotifyClient -Force:$Force }

    $removedFiles = 0
    if ($state) {
        $removeFiles = @($state.managedExtensions)
        # The companion extension belongs to the theme, not to a preset. If the theme
        # is being removed, its file goes too - even when an older state file lost
        # track of it.
        if ($state.themeInstalled -and -not $KeepTheme -and 'lean-ui.js' -notin $removeFiles) {
            $removeFiles += 'lean-ui.js'
        }
        foreach ($file in $removeFiles) {
            if (-not $file -or [IO.Path]::GetFileName($file) -ne $file) { continue }
            $path = Join-Path $context.ExtensionRoot $file
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                $removedFiles++
            }
        }
        Write-LeanLog ("Removed {0} managed extension file(s)." -f $removedFiles) -Level Ok

        $restoreValues = @{}
        foreach ($key in $state.original.PSObject.Properties.Name) {
            # The extension list is pipe-joined in the state file and is restored as a
            # list below; writing it back as one scalar would create a single bogus
            # entry ("a.js|b.js").
            if ($key -eq 'extensions') { continue }
            $value = $state.original.$key
            if ($null -eq $value) { $value = '' }
            $restoreValues[$key] = [string] $value
        }
        Set-SpicetifyConfigValues -Values $restoreValues

        $current = Get-SpicetifyConfigList -Key 'extensions'
        $original = @(([string] $state.original.extensions) -split '\s*\|\s*' | Where-Object { $_ })
        if ($original.Count -gt 0) {
            $disable = @($current | Where-Object { $_ -notin $original })
        } else {
            # No usable baseline (state written before any extension was enabled, or by
            # an older version). Undo only what this project installed and leave
            # extensions the user enabled themselves alone.
            Write-LeanLog 'No extension baseline recorded; disabling only managed extensions.' -Level Warn
            $managedFiles = @($state.managedExtensions)
            $disable = @($current | Where-Object { $_ -in $managedFiles })
        }
        $enable = @($original | Where-Object { $_ -notin $current })
        if ($state.themeInstalled -and -not $KeepTheme) {
            $disable = @(@($disable) + 'lean-ui.js' | Sort-Object -Unique)
        }
        Set-SpicetifyExtensionList -Enable $enable -Disable $disable

        if ($state.themeInstalled -and -not $KeepTheme) {
            $themePath = Join-Path $context.ThemeRoot 'Lean'
            if (Test-Path -LiteralPath $themePath) {
                Remove-Item -LiteralPath $themePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-LeanLog 'Removed theme folder Lean.' -Level Ok
            }
        }
    } else {
        Set-SpicetifyConfigValues -Values @{ current_theme = ''; color_scheme = ''; spotify_launch_flags = '' }
    }

    Write-LeanLog 'Restoring original Spotify files...' -Level Step
    $restore = Invoke-Spicetify -Arguments @('restore', 'backup', 'apply') -AllowFailure
    if ($restore.ExitCode -ne 0) {
        Write-LeanLog ("spicetify restore failed: {0}" -f $restore.Text) -Level Warn
        Write-LeanLog 'You can reset manually with: spicetify restore backup apply' -Level Warn
    }

    if ($state -and $state.blockedUpdates) {
        $null = Invoke-Spicetify -Arguments @('spotify-updates', 'unblock') -AllowFailure
        Write-LeanLog 'Spotify auto-updates unblocked.' -Level Ok
    }

    if (Test-Path -LiteralPath $context.StatePath) { Remove-Item -LiteralPath $context.StatePath -Force }

    if ($wasRunning -and -not $NoRestart) {
        if (Start-SpotifyClient) { Write-LeanLog 'Spotify restarted with the original client.' -Level Ok }
    }

    Write-LeanLog 'Restore complete.' -Level Ok
    return [pscustomobject]@{ DryRun = $false; Restored = $true; RemovedFiles = $removedFiles }
}
