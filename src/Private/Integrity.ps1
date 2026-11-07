#Requires -Version 5.1

<#
    File-integrity guards.

    Windows can report a successful Copy-Item while the destination ends up as a
    correctly sized, all-zero file. That was observed here after a Spotify update:
    Themes\Lean\user.css was 13844 bytes of NUL, so `spicetify apply` injected an
    empty stylesheet and the client rendered unthemed while every command printed
    success. Deployed files are therefore read back and compared, and the patched
    bundle is verified after `spicetify apply`.
#>

function Test-LeanFileMatches {
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination
    )
    if (-not (Test-Path -LiteralPath $Destination)) { return $false }
    $s = [System.IO.File]::ReadAllBytes($Source)
    $d = [System.IO.File]::ReadAllBytes($Destination)
    if ($s.Length -ne $d.Length) { return $false }
    for ($i = 0; $i -lt $s.Length; $i++) {
        if ($s[$i] -ne $d[$i]) { return $false }
    }
    return $true
}

function Test-LeanFileBlank {
    <#
        True when a file is missing, empty, or contains only NUL bytes - the
        signature of the failed copy described above.
    #>
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return $true }
    foreach ($byte in $bytes) {
        if ($byte -ne 0) { return $false }
    }
    return $true
}

function Copy-LeanFileVerified {
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [int] $Attempts = 3
    )
    $name = Split-Path -Leaf $Destination
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        if (Test-LeanFileMatches -Source $Source -Destination $Destination) { return $true }
        Write-LeanLog ("Copy of {0} did not land (attempt {1}/{2}); retrying." -f $name, $attempt, $Attempts) -Level Warn
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Get-LeanAppliedCssPath {
    param($Context)
    return (Join-Path $Context.SpotifyPath 'Apps\xpui\user.css')
}

function Test-LeanThemeDeployed {
    <#
        True when the stylesheet Spicetify patched into the client still matches
        the installed theme. A false result means the client is running unthemed
        even though every install step reported success.
    #>
    param($Context)
    $themeCss = Join-Path (Join-Path $Context.ThemeRoot 'Lean') 'user.css'
    $appliedCss = Get-LeanAppliedCssPath -Context $Context
    if (Test-LeanFileBlank -Path $themeCss) { return $false }
    return (Test-LeanFileMatches -Source $themeCss -Destination $appliedCss)
}

function Repair-LeanDeployedTheme {
    <#
        Re-deploys the theme stylesheet and re-applies once when the patched
        bundle came out blank. Returns $true when the client now carries the
        theme CSS.
    #>
    param($Context)

    if (Test-LeanThemeDeployed -Context $Context) { return $true }

    Write-LeanLog 'The patched bundle does not carry the theme stylesheet; repairing.' -Level Warn
    $source = Join-Path $Context.ThemeSource 'user.css'
    $themeDir = Join-Path $Context.ThemeRoot 'Lean'
    New-Item -ItemType Directory -Force -Path $themeDir | Out-Null
    if (-not (Copy-LeanFileVerified -Source $source -Destination (Join-Path $themeDir 'user.css'))) {
        throw 'Could not write the theme stylesheet; the destination keeps coming back blank. Check disk health and antivirus interference.'
    }
    if (-not (Copy-LeanFileVerified -Source (Join-Path $Context.ThemeSource 'color.ini') -Destination (Join-Path $themeDir 'color.ini'))) {
        throw 'Could not write the theme colour scheme; the destination keeps coming back blank.'
    }

    $result = Invoke-Spicetify -Arguments @('apply')
    if ($result.Text) { Write-LeanLog $result.Text -Level Debug }

    if (Test-LeanThemeDeployed -Context $Context) {
        Write-LeanLog 'Theme repaired and re-applied.' -Level Ok
        return $true
    }

    Write-LeanLog 'Theme stylesheet is still not in the patched bundle.' -Level Error
    Write-LeanLog ("Expected {0} to match {1}." -f (Get-LeanAppliedCssPath -Context $Context), (Join-Path $themeDir 'user.css')) -Level Error
    return $false
}
