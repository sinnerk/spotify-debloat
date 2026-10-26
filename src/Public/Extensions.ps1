#Requires -Version 5.1

function Save-LeanRemoteFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Destination,
        [int] $Retries = 3
    )

    $temp = "$Destination.download"
    $lastError = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $temp -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
            $bytes = [IO.File]::ReadAllBytes($temp)
            if ($bytes.Length -lt 32) { throw "downloaded file is too small ($($bytes.Length) bytes)" }

            $probe = [Text.Encoding]::UTF8.GetString($bytes, 0, [Math]::Min(256, $bytes.Length)).TrimStart()
            if ($probe -match '^(?i)<!doctype|<html') { throw 'server returned an HTML error page' }

            Move-Item -LiteralPath $temp -Destination $Destination -Force
            return
        } catch {
            $lastError = $_
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
            if ($attempt -lt $Retries) { Start-Sleep -Milliseconds (350 * $attempt) }
        }
    }
    throw ("Could not download {0}: {1}" -f $Url, $lastError.Exception.Message)
}

function Get-LeanExtensionFileName {
    param([Parameter(Mandatory)] $Entry)
    # Entry.main is usually a bare file name but some manifests carry a full URL.
    # [IO.Path]::GetExtension rejects ':' on .NET Framework, so parse the leaf by hand.
    $leaf = (([string] $Entry.main) -split '[\\/]')[-1]
    $leaf = ($leaf -split '[?#]')[0]
    $dot = $leaf.LastIndexOf('.')
    $extension = if ($dot -gt 0) { $leaf.Substring($dot).ToLowerInvariant() } else { '' }
    if ($extension -notin @('.js', '.mjs', '.cjs')) { $extension = '.js' }
    return ('{0}{1}' -f $Entry.id, $extension)
}

function Install-LeanExtensionSet {
    <#
    .SYNOPSIS
        Installs a preset of Marketplace extensions and enables them.
    .DESCRIPTION
        Files land in Spicetify's Extensions folder. Every extension is fetched
        from its own repository at the pinned commit-less raw URL in the catalog.
        Existing extensions that this project does not manage are left alone.
    #>
    [CmdletBinding()]
    param(
        [string] $Profile = 'lean',
        [string[]] $Ids = @(),
        [switch] $DryRun,
        [switch] $Force
    )

    $context = Assert-SpicetifyReady
    $catalog = Get-LeanCatalogData
    $policy = Get-LeanPolicy

    if ($Ids.Count -gt 0) {
        $preset = [pscustomobject]@{ name = 'custom'; extensions = $Ids; exclude = @(); all = $false }
    } else {
        $preset = Get-LeanPreset -Name $Profile
        if ($preset.all -and -not $Force -and -not $DryRun) {
            throw ("The '{0}' profile enables every compatible Marketplace extension and will likely break some UI. Re-run with -Force if you want that, or use -Profile lean." -f $Profile)
        }
    }

    $targets = Resolve-LeanPresetTargets -Preset $preset -Catalog $catalog -Policy $policy
    if ($targets.Count -eq 0) {
        Write-LeanLog "Preset '$($preset.name)' resolved to zero extensions." -Level Warn
    }

    Write-LeanLog ("Installing {0} extension(s) from preset '{1}'..." -f $targets.Count, $preset.name) -Level Step

    $state = Get-LeanState
    if (-not $state) { $state = New-LeanState -ConfigMap (Get-SpicetifyConfigMap) }
    $previous = @($state.managedExtensions)

    # Files this project installed follow the "vendor-repo--name.ext" convention.
    # Anything matching it is ours to reconcile, even if the state file lost track
    # of it or the file itself is already gone but still enabled in the config.
    # lean-ui.js is the theme's companion extension: never stale, never pruned.
    $managedPattern = '^[a-z0-9][a-z0-9-]*-[a-z0-9][a-z0-9-]*--[a-z0-9][a-z0-9-]*\.(js|mjs)$'
    $ours = @()
    if (Test-Path -LiteralPath $context.ExtensionRoot) {
        $ours = @(Get-ChildItem -LiteralPath $context.ExtensionRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $managedPattern } |
            ForEach-Object { $_.Name })
    }
    $configured = @(Get-SpicetifyConfigList -Key 'extensions' | Where-Object { $_ -match $managedPattern })
    $previous = @(@($previous) + $ours + $configured | Sort-Object -Unique | Where-Object { $_ -ne 'lean-ui.js' })

    $installed = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.Generic.List[string]
    $index = 0

    foreach ($entry in $targets) {
        $index++
        $fileName = Get-LeanExtensionFileName -Entry $entry
        $destination = Join-Path $context.ExtensionRoot $fileName
        if ($DryRun) {
            Write-LeanLog ("  would install {0} ({1})" -f $entry.name, $fileName)
            $files.Add($fileName)
            continue
        }

        try {
            Write-Progress -Activity 'Installing extensions' -Status ("{0}/{1} {2}" -f $index, $targets.Count, $entry.name) -PercentComplete (($index / [Math]::Max(1, $targets.Count)) * 100)
            Save-LeanRemoteFile -Url $entry.rawUrl -Destination $destination

            [void] $installed.Add([pscustomobject]@{
                id     = $entry.id
                name   = $entry.name
                file   = $fileName
                repo   = $entry.repo
                source = $entry.rawUrl
            })
            $files.Add($fileName)
        } catch {
            [void] $failed.Add([pscustomobject]@{ id = $entry.id; name = $entry.name; error = $_.Exception.Message })
        }
    }
    if (-not $DryRun) { Write-Progress -Activity 'Installing extensions' -Completed }

    if ($DryRun) {
        Write-LeanLog 'Dry run: no files downloaded and config unchanged.' -Level Warn
        return [pscustomobject]@{ Installed = 0; Failed = 0; Files = $files; DryRun = $true }
    }

    # Remove files that we installed before but are no longer in the target set.
    # Spicetify keeps its own copy of every extension inside the patched app
    # directory, and `spicetify apply` does not prune files it no longer sees, so
    # a removed extension would otherwise keep loading from that cache.
    $stale = @($previous | Where-Object { $_ -notin $files })
    $cacheRoot = Get-SpicetifyExtensionCachePath
    foreach ($file in $stale) {
        if ([IO.Path]::GetFileName($file) -ne $file) { continue }
        $path = Join-Path $context.ExtensionRoot $file
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        if ($cacheRoot) {
            $cached = Join-Path $cacheRoot $file
            if (Test-Path -LiteralPath $cached) { Remove-Item -LiteralPath $cached -Force -ErrorAction SilentlyContinue }
        }
    }

    Set-SpicetifyExtensionList -Enable @($files) -Disable $stale

    # lean-ui.js belongs to the theme, not to a preset. It is never pruned, so it has to
    # stay in the managed list: `restore` removes exactly the files this list names.
    $managed = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) { $managed.Add($file) }
    if ((Test-Path -LiteralPath (Join-Path $context.ExtensionRoot 'lean-ui.js')) -and
        ($managed -notcontains 'lean-ui.js')) {
        $managed.Add('lean-ui.js')
    }
    $state.managedExtensions = @($managed)
    $state | Add-Member -NotePropertyName installedExtensions -NotePropertyValue @($installed) -Force
    $state | Add-Member -NotePropertyName profile -NotePropertyValue $preset.name -Force
    Save-LeanState -State $state

    if ($failed.Count -gt 0) {
        Write-LeanLog ("{0} extension(s) could not be downloaded:" -f $failed.Count) -Level Warn
        foreach ($failure in $failed) { Write-LeanLog ("  {0}: {1}" -f $failure.name, $failure.error) -Level Warn }
    }
    Write-LeanLog ("Enabled {0} extension(s); {1} failed." -f $files.Count, $failed.Count) -Level Ok

    return [pscustomobject]@{
        Installed = $installed.Count
        Failed    = $failed.Count
        Files     = $files
        Errors    = $failed
        DryRun    = $false
    }
}
