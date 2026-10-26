#Requires -Version 5.1

function Get-LeanIniValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Section,
        [Parameter(Mandatory)] [string] $Key
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $current = ''
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*\[(.+?)\]\s*$') { $current = $Matches[1]; continue }
        if ($current -ne $Section) { continue }
        if ($line -match ('^\s*' + [Regex]::Escape($Key) + '\s*=\s*(.*)$')) { return $Matches[1].Trim() }
    }
    return $null
}

function Get-LeanContext {
    [CmdletBinding()]
    param([switch] $Refresh)

    if ($script:LeanContext -and -not $Refresh) { return $script:LeanContext }

    $root = $script:LeanRoot
    $configPath = Join-Path $env:APPDATA 'spicetify\config-xpui.ini'

    $spicetifyExe = $null
    $command = Get-Command spicetify -ErrorAction SilentlyContinue
    if ($command) { $spicetifyExe = $command.Source }
    if (-not $spicetifyExe) {
        $fallback = Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
        if (Test-Path -LiteralPath $fallback) { $spicetifyExe = $fallback }
    }

    $spotifyPath = Get-LeanIniValue -Path $configPath -Section 'Setting' -Key 'spotify_path'
    if (-not $spotifyPath) { $spotifyPath = Join-Path $env:APPDATA 'Spotify' }
    $spotifyExe = Join-Path $spotifyPath 'Spotify.exe'

    # Spicetify 2.x keeps extensions under LOCALAPPDATA and themes under APPDATA.
    $extensionRoot = Join-Path $env:LOCALAPPDATA 'spicetify\Extensions'
    $themeRoot = Join-Path $env:APPDATA 'spicetify\Themes'

    $spotifyVersion = $null
    if (Test-Path -LiteralPath $spotifyExe) {
        $spotifyVersion = (Get-Item -LiteralPath $spotifyExe).VersionInfo.ProductVersion
    }

    $spicetifyVersion = $null
    if ($spicetifyExe) {
        try {
            $raw = & $spicetifyExe -v 2>$null | Select-Object -First 1
            if ($raw -match 'v?([\d]+\.[\d]+\.[\d]+)') { $spicetifyVersion = $Matches[1] }
        } catch { }
    }

    $script:LeanContext = [pscustomobject]@{
        Root             = $root
        CatalogPath      = Join-Path $root 'catalog\catalog.json'
        SnippetsPath     = Join-Path $root 'catalog\snippets.json'
        PresetsPath      = Join-Path $root 'presets'
        ThemeSource      = Join-Path $root 'theme'
        ReportsPath      = Join-Path $root 'reports'
        ConfigPath       = $configPath
        ConfigDir        = (Join-Path $env:APPDATA 'spicetify')
        BackupRoot       = (Join-Path $env:APPDATA 'spicetify\Backup')
        ThemeRoot        = $themeRoot
        ExtensionRoot    = $extensionRoot
        StatePath        = (Join-Path $env:APPDATA 'spicetify\lean-state.json')
        SpotifyPath      = $spotifyPath
        SpotifyExe       = $spotifyExe
        SpotifyVersion   = $spotifyVersion
        SpicetifyExe     = $spicetifyExe
        SpicetifyVersion = $spicetifyVersion
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        IsWindows        = ($env:OS -eq 'Windows_NT')
    }
    return $script:LeanContext
}

function Test-LeanAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
