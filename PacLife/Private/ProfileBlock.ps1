$script:ProfileBlockPattern = '(?s)\r?\n?# >>> PacLife >>>.*?# <<< PacLife <<<[ \t]*\r?\n?'

function Add-PacLifeProfileBlock {
    <#
    .SYNOPSIS
        Appends (idempotently) the PacLife activation block to a PowerShell profile.
        The block is placed last so PacLife's prompt wrapper composes on top of
        oh-my-posh/starship initialized earlier in the profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$ModuleBase
    )

    $manifest = Join-Path $ModuleBase 'PacLife.psd1'
    $block = @"
# >>> PacLife >>>
if (`$Host.Name -eq 'ConsoleHost') {
    Import-Module '$manifest' -ErrorAction SilentlyContinue
    if (Get-Command Enable-PacLife -ErrorAction SilentlyContinue) { Enable-PacLife -Session }
}
# <<< PacLife <<<
"@

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $content = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { '' }
    if ($null -eq $content) { $content = '' }
    $content = $content -replace $script:ProfileBlockPattern, ''
    $content = $content.TrimEnd()
    if ($content) { $content += [Environment]::NewLine + [Environment]::NewLine }
    $content += $block + [Environment]::NewLine
    Set-Content -LiteralPath $Path -Value $content -NoNewline -Encoding UTF8
}

function Remove-PacLifeProfileBlock {
    <#
    .SYNOPSIS
        Removes the PacLife activation block from a PowerShell profile, if present.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public Disable-PacLife is the user-facing entry point')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $content -or $content -notmatch '# >>> PacLife >>>') { return }
    $content = ($content -replace $script:ProfileBlockPattern, '').TrimEnd()
    if ($content) {
        Set-Content -LiteralPath $Path -Value ($content + [Environment]::NewLine) -NoNewline -Encoding UTF8
    } else {
        Set-Content -LiteralPath $Path -Value '' -NoNewline -Encoding UTF8
    }
}
