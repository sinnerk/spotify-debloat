#Requires -Version 5.1
<#
    spicetify-lean - module loader.
    Public functions live in src/Public, internal helpers in src/Private.
#>

$script:LeanRoot = Split-Path -Parent $PSScriptRoot
$script:LeanQuiet = $false

foreach ($folder in @('Private', 'Public')) {
    $path = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path -LiteralPath $path)) { continue }
    Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
        . $_.FullName
    }
}

Export-ModuleMember -Function @(
    'Invoke-LeanInstall',
    'Invoke-LeanApply',
    'Set-LeanDebloat',
    'Install-LeanExtensionSet',
    'Install-LeanTheme',
    'Get-LeanCatalog',
    'Get-LeanStatus',
    'Test-LeanEnvironment',
    'Measure-LeanPerformance',
    'Restore-Lean'
)
