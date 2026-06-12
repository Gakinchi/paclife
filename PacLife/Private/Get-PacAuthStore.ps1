function Get-PacAuthStore {
    <#
    .SYNOPSIS
        Locates and parses pac CLI's local auth store (authprofiles_v2.json).
        Cached by file LastWriteTime so per-prompt calls cost ~nothing.
        Returns $null when pac has no local store (not installed / never logged in).
    #>
    [CmdletBinding()]
    param()

    # PACLIFE_STORE is an exclusive override (used by tests) — no fall-through
    if ($env:PACLIFE_STORE) {
        $candidates = @($env:PACLIFE_STORE)
    } else {
        $candidates = @()
        if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCLI') }
        if ($HOME) { $candidates += (Join-Path $HOME '.local/share/Microsoft/PowerAppsCli') }
    }

    $file = $null
    $dir = $null
    foreach ($candidate in $candidates) {
        $probe = Join-Path $candidate 'authprofiles_v2.json'
        if (Test-Path -LiteralPath $probe -PathType Leaf) {
            $file = $probe
            $dir = $candidate
            break
        }
    }
    if (-not $file) {
        $script:AuthStoreCache = $null
        return $null
    }

    $mtime = (Get-Item -LiteralPath $file).LastWriteTimeUtc
    $cache = $script:AuthStoreCache
    if ($cache -and $cache.File -eq $file -and $cache.MTime -eq $mtime) {
        return $cache
    }

    try {
        $data = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Verbose "PacLife: failed to parse '$file': $_"
        return $null
    }

    $script:AuthStoreCache = [pscustomobject]@{
        File  = $file
        Dir   = $dir
        MTime = $mtime
        Data  = $data
    }
    return $script:AuthStoreCache
}
