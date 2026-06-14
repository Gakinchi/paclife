function Get-PacLifeStatusLine {
    <#
    .SYNOPSIS
        Emits the PacLife context as a single line for an AI coding agent's own
        statusline (Claude Code, GitHub Copilot CLI, Cursor CLI).
    .DESCRIPTION
        Inside a full-screen TUI agent the pinned top-row banner can't survive —
        the agent owns the screen and the PowerShell prompt loop that re-asserts it
        no longer runs. Those agents instead invoke a command and render its stdout
        as their statusline. This is that command's payload: the same compact,
        theme-aware segment line the pinned statusline draws, as one string on
        stdout — no scroll-region writes, safe inside a piped child process.

        Reads pac's local auth store directly (offline, instant), so it needs
        nothing from the JSON the agent pipes to the command on stdin.
    .PARAMETER Width
        Target cell width for segment fitting. When omitted (0), it is taken from
        $env:COLUMNS (Claude Code sets it), then [Console]::WindowWidth, else 0
        (render full and let the agent truncate).
    .EXAMPLE
        Get-PacLifeStatusLine
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Returns a string; the agent renders stdout')]
    [CmdletBinding()]
    param(
        [int]$Width = 0
    )

    if ($Width -le 0) {
        $cols = 0
        if ($env:COLUMNS -and [int]::TryParse($env:COLUMNS, [ref]$cols) -and $cols -gt 0) {
            $Width = $cols
        } else {
            try { $Width = [Console]::WindowWidth } catch { $Width = 0 }
        }
    }

    Format-PacLifeSegments -Context (Get-PacContext) -Width $Width
}
