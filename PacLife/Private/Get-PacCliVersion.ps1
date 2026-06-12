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

    if ($script:CliVersionCache -and $script:CliVersionCache.Dir -eq $StoreDir) {
        return $script:CliVersionCache.Version
    }
    if (-not $StoreDir -or -not (Test-Path -LiteralPath $StoreDir)) { return $null }

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

    $script:CliVersionCache = [pscustomobject]@{ Dir = $StoreDir; Version = $version }
    return $version
}
