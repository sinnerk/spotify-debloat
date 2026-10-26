@{
    RootModule        = 'Lean.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b6f2a1d4-7c3e-4a58-9f61-2e0d8c4b7a10'
    Author            = 'sinnerk'
    CompanyName       = 'spicetify-lean'
    Copyright         = '(c) 2026 spicetify-lean contributors. MIT licensed.'
    Description       = 'A documented, debloated Spicetify distribution with the full Marketplace catalog.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('spotify', 'spicetify', 'debloat', 'windows', 'powershell')
            ProjectUri = 'https://github.com/sinnerk/spicetify-lean'
            LicenseUri = 'https://github.com/sinnerk/spicetify-lean/blob/main/LICENSE'
        }
    }
}
