#Requires -Version 5.1

$script:AnsiPattern = [Regex]'\x1B\[[0-9;]*[A-Za-z]'

function Remove-LeanAnsi {
    param([AllowNull()] [string] $Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace $script:AnsiPattern, '')
}

function Invoke-Spicetify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $AllowFailure
    )

    $context = Get-LeanContext
    if (-not $context.SpicetifyExe) { throw 'Spicetify is not installed or not on PATH.' }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $context.SpicetifyExe @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    $text = Remove-LeanAnsi (($output | ForEach-Object { "$_" }) -join "`n")
    if ($code -ne 0 -and -not $AllowFailure) {
        throw ("spicetify {0} exited with code {1}`n{2}" -f ($Arguments -join ' '), $code, $text.Trim())
    }
    return [pscustomobject]@{ ExitCode = $code; Text = $text.Trim() }
}

function Get-SpicetifyConfigValue {
    param([Parameter(Mandatory)] [string] $Key)
    $result = Invoke-Spicetify -Arguments @('config', $Key) -AllowFailure
    $line = $result.Text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1
    if ($null -eq $line) { return '' }
    return ([string] $line).Trim()
}

function Get-SpicetifyConfigList {
    <#
    .SYNOPSIS
        Reads a list-valued setting, one entry per line.
    .DESCRIPTION
        `spicetify config extensions` prints one extension per line, unlike
        scalar settings (and spotify_launch_flags) which print a single line.
        Reading it with Get-SpicetifyConfigValue would return only the first
        extension, which silently breaks every "is this enabled?" check.
    #>
    param([Parameter(Mandatory)] [string] $Key)
    $result = Invoke-Spicetify -Arguments @('config', $Key) -AllowFailure
    return @(
        $result.Text -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Get-SpicetifyConfigMap {
    $result = Invoke-Spicetify -Arguments @('config')
    $map = [ordered]@{}
    foreach ($line in ($result.Text -split "`r?`n")) {
        if ($line -match '^\s*\[.+\]\s*$') { continue }
        if ($line -match '^(\S+)\s{2,}(.*)$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $map
}

function Set-SpicetifyConfigValues {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Values)

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('config')
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $arguments.Add($key)
        if ($key -eq 'spotify_launch_flags') { $arguments.Add('--') }
        $arguments.Add([string] $Values[$key])
    }
    if ($arguments.Count -le 1) { return }
    $null = Invoke-Spicetify -Arguments $arguments.ToArray()
}

function Set-SpicetifyExtensionList {
    [CmdletBinding()]
    param(
        [string[]] $Enable = @(),
        [string[]] $Disable = @()
    )

    $current = Get-SpicetifyConfigList -Key 'extensions'

    $target = New-Object System.Collections.Generic.List[string]
    foreach ($file in $current) { if ($file -notin $Disable) { $target.Add($file) } }
    foreach ($file in $Enable) { if ($file -notin $target) { $target.Add($file) } }

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('config')
    foreach ($file in $Disable) {
        if ($file -in $current) { $arguments.Add('extensions'); $arguments.Add("$file-") }
    }
    foreach ($file in $Enable) {
        if ($file -notin $current) { $arguments.Add('extensions'); $arguments.Add($file) }
    }
    if ($arguments.Count -gt 1) { $null = Invoke-Spicetify -Arguments $arguments.ToArray() }
}

function Get-SpotifyProcesses {
    return @(Get-Process -Name Spotify -ErrorAction SilentlyContinue)
}

function Test-SpotifyRunning {
    return ((Get-SpotifyProcesses).Count -gt 0)
}

function Wait-SpotifyStopped {
    param([int] $TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-SpotifyRunning)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return -not (Test-SpotifyRunning)
}

function Stop-SpotifyClient {
    [CmdletBinding()]
    param([switch] $Force)

    $processes = Get-SpotifyProcesses
    if ($processes.Count -eq 0) { return }

    if (-not $Force) {
        $main = $processes | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($main) { $null = $main.CloseMainWindow() }
        if (Wait-SpotifyStopped -TimeoutSeconds 15) { return }
    }

    Get-SpotifyProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    $null = Wait-SpotifyStopped -TimeoutSeconds 10
}

function Get-SpotifyLaunchFlags {
    <#
    .SYNOPSIS
        Reads spotify_launch_flags from the Spicetify config as a string array.
    .DESCRIPTION
        Spicetify stores the flags pipe-separated. It only applies them when it
        launches Spotify itself, and the CLI has no "start" command in v2.46, so
        lean.ps1 has to pass them on the command line to honour them.
    #>
    $raw = Get-SpicetifyConfigValue -Key 'spotify_launch_flags'
    if (-not $raw) { return @() }
    return @(
        $raw -split '\|' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Start-SpotifyClient {
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 45)

    $context = Get-LeanContext
    if (-not (Test-Path -LiteralPath $context.SpotifyExe)) { throw "Spotify.exe not found at $($context.SpotifyExe)" }

    $flags = @(Get-SpotifyLaunchFlags)
    if ($flags.Count -gt 0) {
        Write-LeanLog ("Launching Spotify with {0} flag(s)." -f $flags.Count) -Level Debug
        Start-Process -FilePath $context.SpotifyExe -ArgumentList $flags | Out-Null
    } else {
        Start-Process -FilePath $context.SpotifyExe | Out-Null
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $processes = Get-SpotifyProcesses
        $window = $processes | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($window) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-SpicetifyExtensionCachePath {
    <#
    .SYNOPSIS
        Directory where Spicetify drops copies of extensions inside the patched app.
    .DESCRIPTION
        `spicetify apply` copies each enabled extension into
        <Spotify>\Apps\xpui\extensions\. That copy is what actually loads at
        runtime, so removing an extension means removing it there too.
        Returns $null when the directory does not exist (other app layouts).
    #>
    $context = Get-LeanContext
    $candidate = Join-Path $context.SpotifyPath 'Apps\xpui\extensions'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

function Get-RunningSpotifyCommandLine {
    <#
    .SYNOPSIS
        Command line of the running Spotify process, or $null when it is closed.
    #>
    $processes = Get-SpotifyProcesses
    if ($processes.Count -eq 0) { return $null }
    try {
        $query = Get-CimInstance -ClassName Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop |
            Select-Object -First 1
        if ($query) { return [string] $query.CommandLine }
    } catch {
        # CIM is unavailable on some locked-down machines; not fatal.
    }
    return $null
}

function Restore-SpotifyWindow {
    <#
    .SYNOPSIS
        Brings the Spotify window back from the tray so benchmarks measure real work.
    .DESCRIPTION
        Chromium suspends renderers for an iconified or fully occluded window. A
        benchmark taken in that state can report exactly 0% CPU, which looks like a
        great result and is really a broken sample. Callers restore the window first
        and record the outcome in the report.
        Returns $true when a visible main window exists afterwards, $false when Spotify
        has no window at all (headless start, tray-only).
    #>
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 5)

    $main = Get-SpotifyProcesses | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $main) { return $false }

    if (-not ('SpicetifyLean.Window' -as [type])) {
        try {
            Add-Type -Namespace SpicetifyLean -Name Window -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindowAsync(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsIconic(System.IntPtr hWnd);
'@
        } catch {
            Write-LeanLog ("Could not load the window helper: {0}" -f $_.Exception.Message) -Level Debug
            return $false
        }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $main = Get-SpotifyProcesses | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if (-not $main) { return $false }
        if (-not [SpicetifyLean.Window]::IsIconic($main.MainWindowHandle)) { break }
        # SW_RESTORE = 9
        $null = [SpicetifyLean.Window]::ShowWindowAsync($main.MainWindowHandle, 9)
        Start-Sleep -Milliseconds 400
    }

    $main = Get-SpotifyProcesses | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $main) { return $false }
    $null = [SpicetifyLean.Window]::SetForegroundWindow($main.MainWindowHandle)
    Start-Sleep -Milliseconds 300
    return (-not [SpicetifyLean.Window]::IsIconic($main.MainWindowHandle))
}

function Get-SpotifyProcessSummary {
    $processes = Get-SpotifyProcesses
    $workingSet = 0L
    $private = 0L
    $cpu = 0.0
    foreach ($process in $processes) {
        $workingSet += $process.WorkingSet64
        $private += $process.PrivateMemorySize64
        $cpu += $process.CPU
    }
    return [pscustomobject]@{
        Count          = $processes.Count
        WorkingSet     = $workingSet
        PrivateBytes   = $private
        CpuSeconds     = $cpu
        MainWindowTitle = (($processes | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowTitle)
    }
}

function Assert-SpicetifyReady {
    $context = Get-LeanContext -Refresh
    if (-not $context.SpicetifyExe) { throw 'Spicetify is not installed. See docs/TROUBLESHOOTING.md.' }
    if (-not (Test-Path -LiteralPath $context.SpotifyExe)) { throw "Spotify was not found at $($context.SpotifyExe)." }
    if (-not (Test-Path -LiteralPath $context.ConfigPath)) {
        Write-LeanLog 'No Spicetify config yet; generating one by running spicetify once.' -Level Step
        $null = Invoke-Spicetify -Arguments @() -AllowFailure
        $context = Get-LeanContext -Refresh
    }
    return $context
}

function Test-SpicetifyBackup {
    $version = Get-LeanIniValue -Path (Get-LeanContext).ConfigPath -Section 'Backup' -Key 'version'
    return [pscustomobject]@{
        Present         = [bool] $version
        BackupVersion   = $version
        SpotifyVersion  = (Get-LeanContext).SpotifyVersion
        MatchesCurrent  = ($version -and (Get-LeanContext).SpotifyVersion -and $version.StartsWith((Get-LeanContext).SpotifyVersion))
    }
}
