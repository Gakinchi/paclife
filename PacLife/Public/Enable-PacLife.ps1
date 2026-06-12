function Enable-PacLife {
    <#
    .SYNOPSIS
        Turns on the pinned statusline (alias: keepyaheadup). By default also adds
        an activation block to your PowerShell profile so it survives new sessions.
    .PARAMETER Session
        Activate for the current session only — do not touch the profile.
        (This is what the profile block itself uses.)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup command')]
    [CmdletBinding()]
    param(
        [switch]$Session
    )

    $active = Initialize-PacLifeStatusLine

    if (-not $Session) {
        $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
        Add-PacLifeProfileBlock -Path $PROFILE -ModuleBase $moduleBase
        Write-Host "PacLife enabled — activation block added to your profile ($PROFILE)."
        if ($active) {
            Write-Host 'Keep ya head up: the statusline now lives at the top of your terminal.'
        } else {
            Write-Host 'This terminal has no VT support, so the statusline stays off here.'
            Write-Host 'It will light up automatically in Windows Terminal / VS Code.'
        }
        Write-Host "Turn it off anytime with: lifegoeson  (Disable-PacLife)"
    } elseif (-not $active) {
        Write-Verbose 'PacLife: statusline not activated (no VT support in this host).'
    }
}
