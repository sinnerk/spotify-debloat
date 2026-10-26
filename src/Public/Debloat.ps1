#Requires -Version 5.1

$script:LeanTelemetryHosts = @(
    'log.spotify.com',
    'crashdump.spotify.com',
    'crashdump.spotify.net',
    'analytics.spotify.com'
)

function New-LeanState {
    param([Parameter(Mandatory)] $ConfigMap)

    $keys = @(
        'extensions', 'custom_apps', 'current_theme', 'color_scheme',
        'inject_theme_js', 'inject_css', 'replace_colors', 'overwrite_assets',
        'spotify_launch_flags', 'home_config', 'experimental_features', 'sidebar_config',
        'check_spicetify_update', 'always_enable_devtools',
        'disable_sentry', 'disable_ui_logging', 'remove_rtl_rule', 'expose_apis'
    )
    $original = [ordered]@{}
    foreach ($key in $keys) {
        $value = $null
        if ($ConfigMap.Contains($key)) { $value = $ConfigMap[$key] }
        $original[$key] = $value
    }

    # `spicetify config` prints the extension list pipe-separated, but a state
    # file written before any extension was enabled records nothing. Read it
    # straight from the list getter so `restore` has a real baseline.
    if (-not $original['extensions']) {
        $original['extensions'] = (@(Get-SpicetifyConfigList -Key 'extensions') -join '|')
    }

    return [pscustomobject]@{
        schemaVersion     = 1
        createdAt         = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        profile           = $null
        aggressive        = $false
        original          = $original
        managedExtensions = @()
        themeInstalled    = $false
        blockedUpdates    = $false
    }
}

function Set-LeanDebloat {
    <#
    .SYNOPSIS
        Configures Spicetify's preprocessing and launch flags for a lean client.
    .DESCRIPTION
        Changes only documented Spicetify settings plus Chromium launch flags.
        It does not patch Spotify's binary, block ads, or touch your account.
    #>
    [CmdletBinding()]
    param(
        [switch] $Aggressive,
        [switch] $BlockSpotifyUpdates,
        [switch] $SkipBackup,
        [switch] $DryRun,
        [switch] $Force
    )

    $context = Assert-SpicetifyReady
    $configMap = Get-SpicetifyConfigMap

    $state = Get-LeanState
    $isNewState = $false
    if (-not $state) {
        $state = New-LeanState -ConfigMap $configMap
        $isNewState = $true
    }

    if (-not $SkipBackup -and -not $DryRun) {
        Backup-LeanSpicetify -Force:$Force
    }

    $settings = [ordered]@{
        disable_sentry        = '1'
        disable_ui_logging    = '1'
        remove_rtl_rule       = '1'
        expose_apis           = '1'
        inject_css            = '1'
        # The Lean theme ships no theme.js; the top-bar toggle is an extension.
        inject_theme_js       = '0'
        replace_colors        = '1'
        home_config           = '0'
        experimental_features = '0'
        sidebar_config        = '0'
        always_enable_devtools = '0'
    }

    $flagSet = New-Object System.Collections.Generic.List[string]
    $currentFlags = @()
    $rawFlags = Get-SpicetifyConfigValue -Key 'spotify_launch_flags'
    if ($rawFlags) { $currentFlags = @($rawFlags -split '\|' | Where-Object { $_ }) }

    # Keep user flags, replace only the flags this project owns.
    $ownedNames = @('--host-resolver-rules', '--renderer-process-limit', '--js-flags')
    foreach ($flag in $currentFlags) {
        $name = ($flag -split '=', 2)[0]
        if ($name -notin $ownedNames) { $flagSet.Add($flag) }
    }

    # Spicetify quotes flags containing spaces when it launches Spotify.
    $rules = (@($script:LeanTelemetryHosts | ForEach-Object { "MAP $_ 127.0.0.1" }) -join ',')
    $flagSet.Add("--host-resolver-rules=$rules")

    if ($Aggressive) {
        $flagSet.Add('--renderer-process-limit=3')
        $flagSet.Add('--js-flags=--max-old-space-size=512')
    }

    $settings['spotify_launch_flags'] = ($flagSet -join '|')

    Write-LeanLog 'Debloat settings:' -Level Step
    foreach ($key in $settings.Keys) {
        $value = $settings[$key]
        if ($key -eq 'spotify_launch_flags') {
            Write-LeanLog ("  launch flags       {0}" -f $value)
        } else {
            Write-LeanLog ("  {0,-18} {1}" -f $key, $value)
        }
    }
    if ($Aggressive) { Write-LeanLog '  mode               aggressive (extra Chromium memory limits)' }

    if ($DryRun) {
        Write-LeanLog 'Dry run: configuration not written.' -Level Warn
        return [pscustomobject]@{ Applied = $false; Settings = $settings; State = $state }
    }

    Set-SpicetifyConfigValues -Values $settings

    if ($BlockSpotifyUpdates) {
        Write-LeanLog 'Blocking Spotify auto-updates (spicetify spotify-updates block)...' -Level Step
        $result = Invoke-Spicetify -Arguments @('spotify-updates', 'block') -AllowFailure
        if ($result.ExitCode -eq 0) {
            $state.blockedUpdates = $true
            Write-LeanLog 'Spotify auto-updates blocked. Undo with: spicetify spotify-updates unblock' -Level Ok
        } else {
            Write-LeanLog ("Could not block updates: {0}" -f $result.Text) -Level Warn
        }
    }

    $state.aggressive = [bool] $Aggressive
    Save-LeanState -State $state
    if ($isNewState) {
        Write-LeanLog 'Saved original Spicetify settings for a clean uninstall.' -Level Ok
    }
    return [pscustomobject]@{ Applied = $true; Settings = $settings; State = $state }
}
