<#
.SYNOPSIS
    PacLife uninstaller: disables the statusline, removes the profile block,
    and deletes the module from the user module path(s).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive uninstaller')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Disable in this session and clean the profile, if the module is loadable
try {
    Import-Module PacLife -ErrorAction Stop
    Disable-PacLife
} catch {
    # Module not importable — scrub the profile block manually
    if ($PROFILE -and (Test-Path -LiteralPath $PROFILE)) {
        $content = Get-Content -LiteralPath $PROFILE -Raw
        if ($content -match '# >>> PacLife >>>') {
            # keep this pattern in sync with PacLife\Private\ProfileBlock.ps1
            # (leading newline must NOT be consumed — would join surrounding lines)
            $content = ($content -replace '(?s)# >>> PacLife >>>.*?# <<< PacLife <<<[ \t]*(\r?\n)?', '').TrimEnd()
            Set-Content -LiteralPath $PROFILE -Value $content -Encoding UTF8
            Write-Host "Removed PacLife block from $PROFILE"
        }
    }
}
Remove-Module PacLife -Force -ErrorAction SilentlyContinue

# Remove the module folder from all known user module locations
$docs = [Environment]::GetFolderPath('MyDocuments')
$locations = @(
    (Join-Path $docs 'PowerShell\Modules\PacLife')
    (Join-Path $docs 'WindowsPowerShell\Modules\PacLife')
    (Join-Path $HOME '.local/share/powershell/Modules/PacLife')
)
foreach ($location in $locations) {
    if (Test-Path -LiteralPath $location) {
        Remove-Item -LiteralPath $location -Recurse -Force
        Write-Host "Removed $location"
    }
}

Write-Host 'PacLife uninstalled. Life goes on.'
