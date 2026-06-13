<#
.SYNOPSIS
    PacLife installer — All Eyez on your environment.
    Installs the latest GitHub Release of the PacLife PowerShell module into
    your user module path and enables the statusline.
.EXAMPLE
    irm https://raw.githubusercontent.com/Gakinchi/paclife/main/install.ps1 | iex
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer')]
[CmdletBinding()]
param(
    [string]$Repo = 'Gakinchi/paclife',
    [switch]$NoProfile   # install only; do not enable / touch the profile
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072  # TLS 1.2
}
$headers = @{ 'User-Agent' = 'PacLife-installer' }

# --- resolve download: latest tagged release, falling back to main ---------------
$zipUrl = $null
$version = $null
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    $version = $release.tag_name
    $asset = @($release.assets) | Where-Object { $_.name -eq 'PacLife.zip' } | Select-Object -First 1
    $zipUrl = if ($asset) { $asset.browser_download_url } else { $release.zipball_url }
} catch {
    Write-Host 'No published release found — installing from the main branch instead.'
    $zipUrl = "https://codeload.github.com/$Repo/zip/refs/heads/main"
    $version = 'main'
}

# --- download + extract ------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "PacLife-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'paclife.zip'
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -Headers $headers
    Expand-Archive -Path $zip -DestinationPath $tmp

    $psd1 = Get-ChildItem -Path $tmp -Recurse -Filter 'PacLife.psd1' | Select-Object -First 1
    if (-not $psd1) { throw "PacLife.psd1 not found in the download from $zipUrl" }
    $source = $psd1.DirectoryName

    # --- destination: user module path for the running PowerShell edition ----------
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsWindows) {
            $dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules\PacLife'
        } else {
            $dest = Join-Path $HOME '.local/share/powershell/Modules/PacLife'
        }
    } else {
        $dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\PacLife'
    }

    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $source '*') -Destination $dest -Recurse

    Write-Host ''
    Write-Host "PacLife $version installed to $dest"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Import-Module (Join-Path $dest 'PacLife.psd1') -Force
if ($NoProfile) {
    Write-Host 'Run keepyaheadup (Enable-PacLife) when you are ready to turn it on.'
} else {
    Enable-PacLife
}

Write-Host ''
Write-Host 'Commands (All Eyez on your environment):'
Write-Host '  paclife        Show-PacLife          compact context line'
Write-Host '  alleyez        Show-PacLife -Full    the full picture'
Write-Host '  keepyaheadup   Enable-PacLife        pin the statusline to the top'
Write-Host '  lifegoeson     Disable-PacLife       turn it off'
Write-Host '  changes        Update-PacLife        update to the latest release'
