Set-StrictMode -Version Latest

# Session state for the statusline engine
$script:StatusLineActive = $false
$script:OriginalPrompt = $null
$script:OriginalTitle = $null
$script:AuthStoreCache = $null
$script:ConfigCache = $null
$script:CliVersionCache = $null
$script:ThemeCache = $null
$script:SgrCache = @{}
$script:SolutionCache = @{}
$script:RepoSlug = 'Gakinchi/paclife'

foreach ($scope in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $scope) -Filter '*.ps1' -ErrorAction SilentlyContinue) {
        . $file.FullName
    }
}

# Playful aliases — the marketed interface (see README)
Set-Alias -Name paclife      -Value Show-PacLife
Set-Alias -Name alleyez      -Value Show-PacLifeFull   # "All Eyez on Me"
Set-Alias -Name keepyaheadup -Value Enable-PacLife     # "Keep Ya Head Up"
Set-Alias -Name lifegoeson   -Value Disable-PacLife    # "Life Goes On"
Set-Alias -Name changes      -Value Update-PacLife     # "Changes"

# Show-PacLifeFull must be exported for the 'alleyez' alias to resolve from the caller's scope
Export-ModuleMember -Function Show-PacLife, Show-PacLifeFull, Get-PacContext, Enable-PacLife, Disable-PacLife, Update-PacLife `
    -Alias paclife, alleyez, keepyaheadup, lifegoeson, changes

# Restore the terminal if the module is removed while the statusline is active
$ExecutionContext.SessionState.Module.OnRemove = {
    try { Disable-PacLife -Session } catch { Write-Verbose "PacLife cleanup failed: $_" }
}
