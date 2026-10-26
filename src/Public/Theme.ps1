#Requires -Version 5.1

function Install-LeanTheme {
    <#
    .SYNOPSIS
        Installs the Lean theme and the small companion extension.
    #>
    [CmdletBinding()]
    param(
        [switch] $SkipExtension,
        [switch] $DryRun
    )

    $context = Assert-SpicetifyReady
    $source = $context.ThemeSource
    $destination = Join-Path $context.ThemeRoot 'Lean'

    foreach ($file in @('color.ini', 'user.css')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $file))) {
            throw "Theme source is incomplete: missing $file in $source"
        }
    }

    Write-LeanLog ("Installing theme to {0}" -f $destination) -Level Step
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Copy-Item -LiteralPath (Join-Path $source 'color.ini') -Destination $destination -Force
        Copy-Item -LiteralPath (Join-Path $source 'user.css') -Destination $destination -Force
    }

    $enabled = @()
    if (-not $SkipExtension) {
        $extensionSource = Join-Path $source 'lean-ui.js'
        if (-not (Test-Path -LiteralPath $extensionSource)) { throw "Missing companion extension: $extensionSource" }
        New-Item -ItemType Directory -Force -Path $context.ExtensionRoot | Out-Null
        if (-not $DryRun) {
            Copy-Item -LiteralPath $extensionSource -Destination (Join-Path $context.ExtensionRoot 'lean-ui.js') -Force
        }
        $enabled = @('lean-ui.js')
    }

    $values = @{
        current_theme    = 'Lean'
        color_scheme     = 'Lean'
        inject_theme_js  = '0'
        inject_css       = '1'
        replace_colors   = '1'
    }

    if ($DryRun) {
        Write-LeanLog 'Dry run: theme files and config not written.' -Level Warn
        return [pscustomobject]@{ Installed = $false; ThemePath = $destination; Extensions = $enabled }
    }

    Set-SpicetifyConfigValues -Values $values
    if ($enabled.Count -gt 0) { Set-SpicetifyExtensionList -Enable $enabled }

    $state = Get-LeanState
    if (-not $state) {
        $state = New-LeanState -ConfigMap (Get-SpicetifyConfigMap)
    }
    $state.themeInstalled = $true
    $managed = @($state.managedExtensions)
    foreach ($file in $enabled) { if ($file -notin $managed) { $managed += $file } }
    $state.managedExtensions = $managed
    Save-LeanState -State $state

    Write-LeanLog 'Theme installed and selected.' -Level Ok
    return [pscustomobject]@{ Installed = $true; ThemePath = $destination; Extensions = $enabled }}
