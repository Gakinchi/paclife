@{
    RootModule        = 'PacLife.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '7b1f2c63-9a4e-4c8d-b5a1-2f0e6d9c3a18'
    Author            = 'Gakinchi'
    Copyright         = '(c) 2026 Gakinchi. MIT License.'
    Description       = 'All Eyez on your environment. A persistent Power Platform CLI (pac) statusline pinned to the top of your terminal: identity, tenant, environment, solution and more - offline, instant, always visible.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Show-PacLife'
        'Get-PacContext'
        'Enable-PacLife'
        'Disable-PacLife'
        'Update-PacLife'
    )
    AliasesToExport   = @(
        'paclife'
        'alleyez'
        'keepyaheadup'
        'lifegoeson'
        'changes'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('PowerPlatform', 'pac', 'Dataverse', 'statusline', 'terminal', 'prompt')
            LicenseUri   = 'https://github.com/Gakinchi/power-platform-cli-environment-banner/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/Gakinchi/power-platform-cli-environment-banner'
            ReleaseNotes = 'Initial release.'
        }
    }
}
