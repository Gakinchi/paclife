# PacLife statusline launcher for AI coding agents (GitHub Copilot CLI, Cursor CLI).
#
# These agents invoke a command after each turn, pipe session JSON to its stdin,
# and render its stdout as the statusline. PacLife reads pac's own auth store, so
# the piped JSON is discarded — we just need one colored line on stdout.
#
# Point the agent's statusLine command at:
#   powershell -NoProfile -File <path>\paclife-statusline.ps1
#
# (Claude Code users compose PacLife into their existing statusline script instead;
#  see the README.)

$null = $Input    # drain the piped session JSON so the parent never blocks on the pipe
Import-Module PacLife -ErrorAction SilentlyContinue
if (Get-Command Get-PacLifeStatusLine -ErrorAction SilentlyContinue) {
    Get-PacLifeStatusLine
}
