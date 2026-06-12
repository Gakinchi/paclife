function Test-PacLifeVtSupport {
    <#
    .SYNOPSIS
        Capability check, not version check: any VT-capable terminal qualifies
        (Windows Terminal, VS Code terminal, ConEmu, iTerm2, ...) on both
        powershell.exe 5.1 and pwsh 7+. Legacy conhost without VT → $false.
    #>
    [CmdletBinding()]
    param()

    if ($env:PACLIFE_FORCE_VT -eq '1') { return $true }
    try {
        if ([Console]::IsOutputRedirected) { return $false }
    } catch { return $false }

    if ($env:WT_SESSION) { return $true }
    if ($env:TERM_PROGRAM) { return $true }
    if ($env:ConEmuANSI -eq 'ON') { return $true }
    if ($env:TERM -and $env:TERM -ne 'dumb') { return $true }

    $supportsVt = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    if ($supportsVt -and $supportsVt.Value) { return $true }
    return $false
}

function Initialize-PacLifeStatusLine {
    <#
    .SYNOPSIS
        Activates the pinned statusline: wraps the existing prompt function
        (composing with oh-my-posh/starship — the original prompt still runs)
        and lets Update-PacLifeStatusLine re-assert the scroll region and redraw
        the top row on every prompt. Returns $true when active.
    #>
    [CmdletBinding()]
    param()

    if ($script:StatusLineActive) { return $true }
    if (-not (Test-PacLifeVtSupport)) {
        Write-Verbose 'PacLife: terminal has no VT support — statusline skipped.'
        return $false
    }

    $script:OriginalPrompt = $function:global:prompt
    try { $script:OriginalTitle = $Host.UI.RawUI.WindowTitle } catch { $script:OriginalTitle = $null }
    $script:StatusLineActive = $true

    # The wrapper is created in module scope, so it can call private functions.
    $function:global:prompt = {
        try { Update-PacLifeStatusLine } catch { Write-Verbose "PacLife: statusline update failed: $_" }
        if ($script:OriginalPrompt) {
            & $script:OriginalPrompt
        } else {
            "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
        }
    }

    try { Update-PacLifeStatusLine } catch { Write-Verbose "PacLife: initial draw failed: $_" }
    return $true
}
