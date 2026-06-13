function Get-PacCliVersion {
    <#
    .SYNOPSIS
        Reads the installed pac CLI version from the version folders next to the
        auth store (Microsoft.PowerApps.CLI.x.y.z). Local only — never a network
        "update available" check. Cached for the session.
    #>
    [CmdletBinding()]
    param(
        [string]$StoreDir
    )

    if (-not $StoreDir -or -not (Test-Path -LiteralPath $StoreDir)) { return $null }
    # key on the directory's mtime too: 'pac install latest' creates a new version
    # folder, which bumps it — the statusline then shows the new version immediately
    $mtime = (Get-Item -LiteralPath $StoreDir).LastWriteTimeUtc
    if ($script:CliVersionCache -and $script:CliVersionCache.Dir -eq $StoreDir -and $script:CliVersionCache.MTime -eq $mtime) {
        return $script:CliVersionCache.Version
    }

    $version = $null
    try {
        $version = Get-ChildItem -LiteralPath $StoreDir -Directory -Filter 'Microsoft.PowerApps.CLI.*' -ErrorAction Stop |
            ForEach-Object {
                $suffix = $_.Name.Substring('Microsoft.PowerApps.CLI.'.Length)
                try { [version]$suffix } catch { $null }
            } |
            Where-Object { $_ } |
            Sort-Object -Descending |
            Select-Object -First 1
    } catch {
        Write-Verbose "PacLife: version probe failed: $_"
    }

    $script:CliVersionCache = [pscustomobject]@{ Dir = $StoreDir; MTime = $mtime; Version = $version }
    return $version
}
