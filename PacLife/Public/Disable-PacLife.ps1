function Disable-PacLife {
    <#
    .SYNOPSIS
        Turns off the statusline and restores the terminal (alias: lifegoeson).
        By default also removes the activation block from your PowerShell profile.
    .PARAMETER Session
        Deactivate for the current session only — leave the profile untouched.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup command')]
    [CmdletBinding()]
    param(
        [switch]$Session
    )

    if ($script:StatusLineActive) {
        $script:StatusLineActive = $false
        # Only restore the saved prompt if the current one is still OUR wrapper —
        # another tool (oh-my-posh re-init, starship) may have replaced it after
        # Enable, and clobbering that with a stale snapshot would break their setup.
        $currentPrompt = $function:global:prompt
        $isOurWrapper = $currentPrompt -and $currentPrompt.ToString().Contains('Update-PacLifeStatusLine')
        if ($isOurWrapper) {
            if ($script:OriginalPrompt) {
                $function:global:prompt = $script:OriginalPrompt
            } else {
                $function:global:prompt = {
                    "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
                }
            }
        }
        $script:OriginalPrompt = $null

        # Reset the scroll region and wipe the pinned row
        $esc = [char]27
        try { $Host.UI.Write("${esc}7${esc}[r${esc}[1;1H${esc}[0m${esc}[K${esc}8") } catch { Write-Verbose "PacLife: terminal reset failed: $_" }

        if ($null -ne $script:OriginalTitle) {
            try { $Host.UI.RawUI.WindowTitle = $script:OriginalTitle } catch { Write-Verbose "PacLife: title restore failed: $_" }
            $script:OriginalTitle = $null
        }
    }

    if (-not $Session) {
        Remove-PacLifeProfileBlock -Path $PROFILE
        Write-Host 'PacLife disabled and removed from your profile. Life goes on.'
    }
}
