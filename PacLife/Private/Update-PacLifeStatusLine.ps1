function Update-PacLifeStatusLine {
    <#
    .SYNOPSIS
        Redraws the pinned top row. Called by the prompt wrapper on every prompt:
        re-asserts the scroll region (heals after vim/less/Clear-Host/resize),
        repaints the segments, and keeps the window title in sync. Budget < 10 ms —
        all context reads are mtime-cached, no network ever.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Redraws the screen; changes no persistent state')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Raw VT output must bypass the pipeline')]
    [CmdletBinding()]
    param()

    if (-not $script:StatusLineActive) { return }

    $esc = [char]27
    try {
        $height = [Console]::WindowHeight
        $width = [Console]::WindowWidth
        $cursorTop = [Console]::CursorTop
    } catch {
        # Redirected/odd console handle — fall back to the host, or skip the redraw
        try {
            $size = $Host.UI.RawUI.WindowSize
            $height = $size.Height
            $width = $size.Width
            $cursorTop = $Host.UI.RawUI.CursorPosition.Y
        } catch {
            Write-Verbose 'PacLife: console dimensions unavailable — redraw skipped.'
            return
        }
    }
    if ($height -lt 3 -or $width -lt 10) { return }

    $context = Get-PacContext
    $line = Format-PacLifeSegments -Context $context -Width $width

    $out = "${esc}7"                                  # save cursor (DECSC)
    $out += "${esc}[2;${height}r"                     # scroll region: rows 2..bottom (row 1 pinned)
    $out += "${esc}[1;1H${line}${esc}[0m${esc}[K"     # repaint row 1, clear remainder
    $out += "${esc}8"                                 # restore cursor (DECRC)
    # After Clear-Host the cursor sits on row 1 — nudge it below the statusline
    # so the prompt doesn't render on top of it.
    if ($cursorTop -le 0) { $out += "${esc}[2;1H" }
    # $Host.UI.Write goes through WriteConsoleW (full Unicode). [Console]::Write
    # would re-encode via the console codepage and turn ⚡/⚠/powerline glyphs
    # into '?' on Windows PowerShell 5.1.
    try { $Host.UI.Write($out) } catch { [Console]::Write($out) }

    if ($context.Config.windowTitle) {
        try {
            $title = switch ($context.State) {
                'Connected'     { "⚡ $($context.EnvironmentName)" }
                'NoEnvironment' { '⚡ pac: no environment' }
                default         { $null }
            }
            if ($title) { $Host.UI.RawUI.WindowTitle = $title }
        } catch { Write-Verbose "PacLife: window title update failed: $_" }
    }
}
