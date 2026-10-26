#Requires -Version 5.1

function Get-LeanPolicy {
    $context = Get-LeanContext
    $path = Join-Path $context.Root 'data\policy.json'
    return Read-LeanJson -Path $path
}

function Resolve-LeanPresetTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Preset,
        [Parameter(Mandatory)] $Catalog,
        [Parameter(Mandatory)] $Policy,
        [switch] $SkipPolicy
    )

    $byId = @{}
    foreach ($entry in $Catalog.extensions) { $byId[$entry.id] = $entry }

    $selected = New-Object System.Collections.Generic.List[object]
    if ($Preset.all) {
        foreach ($entry in $Catalog.extensions) { $selected.Add($entry) }
    }

    foreach ($id in @($Preset.extensions)) {
        if (-not $id) { continue }
        if (-not $byId.ContainsKey($id)) {
            throw "Preset '$($Preset.name)' references an unknown extension id: $id. Run tools/Sync-Catalog.ps1 and rebuild the preset."
        }
        if (-not ($selected | Where-Object { $_.id -eq $id })) { $selected.Add($byId[$id]) }
    }

    foreach ($id in @($Preset.exclude)) {
        if (-not $id) { continue }
        $selected = @($selected | Where-Object { $_.id -ne $id })
    }

    if (-not $SkipPolicy) {
        foreach ($rule in @($Policy.blockedPatterns)) {
            if (-not $rule.pattern) { continue }
            $selected = @($selected | Where-Object {
                $_.id -notmatch $rule.pattern -and $_.name -notmatch $rule.pattern -and $_.repo -notmatch $rule.pattern
            })
        }

        foreach ($group in @($Policy.conflictGroups)) {
            if (-not $group.pattern) { continue }
            $groupMembers = @($selected | Where-Object {
                $_.name -match $group.pattern -or $_.repo -match $group.pattern -or (($_.tags -join ' ') -match $group.pattern)
            })
            if ($groupMembers.Count -le 1) { continue }

            $keep = $null
            if ($group.preferred) {
                $keep = $groupMembers | Where-Object { $_.id -in @($group.preferred) } | Select-Object -First 1
            }
            if (-not $keep) {
                $keep = $groupMembers | Sort-Object -Property @{ Expression = 'stars'; Descending = $true } | Select-Object -First 1
            }
            $selected = @($selected | Where-Object { $_.id -eq $keep.id -or $_.id -notin @($groupMembers.id) })
        }
    }

    # Stable, readable order: curated order first, then stars.
    return @($selected)
}
