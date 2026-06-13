# NB: must not consume the LEADING newline — otherwise removing a block that sits
# between other content joins the surrounding lines into one (profile corruption).
# Keep in sync with the literal copy in uninstall.ps1 (which must run standalone).
$script:ProfileBlockPattern = '(?s)# >>> PacLife >>>.*?# <<< PacLife <<<[ \t]*(\r?\n)?'

function Set-PacLifeProfileContent {
    <#
    .SYNOPSIS
        Writes profile content via a temp file + Move-Item so a failed write
        (disk full, AV interference) can never truncate the user's $PROFILE.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; public Enable/Disable are the entry points')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Content
    )

    $temp = "$Path.paclife-tmp"
    Set-Content -LiteralPath $temp -Value $Content -NoNewline -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

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
    Set-PacLifeProfileContent -Path $Path -Content $content
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
    if ($content) { $content += [Environment]::NewLine }
    Set-PacLifeProfileContent -Path $Path -Content $content
}
