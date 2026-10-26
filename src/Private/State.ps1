#Requires -Version 5.1

function Read-LeanJson {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $Optional
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Optional) { return $null }
        throw "JSON file not found: $Path"
    }

    # Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI with Get-Content.
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    try {
        return $text | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in $Path`: $($_.Exception.Message)"
    }
}

function Write-LeanJson {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Object,
        [int] $Depth = 10
    )

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $json = $Object | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-LeanState {
    $context = Get-LeanContext
    return Read-LeanJson -Path $context.StatePath -Optional
}

function Save-LeanState {
    param([Parameter(Mandatory)] $State)
    $context = Get-LeanContext
    $State | Add-Member -NotePropertyName updatedAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) -Force
    Write-LeanJson -Path $context.StatePath -Object $State
}

function Get-LeanCatalogData {
    if ($script:LeanCatalog) { return $script:LeanCatalog }
    $context = Get-LeanContext
    $catalog = Read-LeanJson -Path $context.CatalogPath
    if (-not $catalog.schemaVersion -or $catalog.schemaVersion -lt 1) {
        throw 'catalog/catalog.json is missing or has an unsupported schemaVersion.'
    }
    $script:LeanCatalog = $catalog
    return $catalog
}

function Get-LeanPreset {
    param([Parameter(Mandatory)] [string] $Name)

    $context = Get-LeanContext
    $safe = $Name -replace '[^a-zA-Z0-9_-]', ''
    $path = Join-Path $context.PresetsPath "$safe.json"
    $preset = Read-LeanJson -Path $path
    if (-not $preset.extensions) { $preset | Add-Member -NotePropertyName extensions -NotePropertyValue @() -Force }
    return $preset
}
