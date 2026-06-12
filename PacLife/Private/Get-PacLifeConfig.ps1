function Get-PacLifeConfig {
    <#
    .SYNOPSIS
        Reads optional ~/.paclife.json and merges it over defaults.
        Cached by file LastWriteTime.
    #>
    [CmdletBinding()]
    param()

    $defaults = [pscustomobject]@{
        protectedUrls = @()      # wildcard patterns that force the red treatment
        safeUrls      = @()      # wildcard patterns that mute it
        windowTitle   = $true    # also set the terminal tab title
        theme         = 'auto'   # 'auto' (match oh-my-posh via POSH_THEME) | 'builtin' | path to .omp.json
        style         = 'auto'   # 'auto' (follow theme) | 'powerline' | 'diamond' | 'plain'
        icons         = 'powerline'  # legacy: 'ascii' behaves like style = 'plain'
    }

    $path = if ($env:PACLIFE_CONFIG) { $env:PACLIFE_CONFIG } else { Join-Path $HOME '.paclife.json' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        # Return a stable object so downstream caches can key on reference equality
        $cache = $script:ConfigCache
        if ($cache -and $cache.Path -eq $path -and $cache.Missing) { return $cache.Config }
        $script:ConfigCache = [pscustomobject]@{ Path = $path; MTime = $null; Missing = $true; Config = $defaults }
        return $defaults
    }

    $mtime = (Get-Item -LiteralPath $path).LastWriteTimeUtc
    $cache = $script:ConfigCache
    if ($cache -and $cache.Path -eq $path -and -not $cache.Missing -and $cache.MTime -eq $mtime) {
        return $cache.Config
    }

    $config = $defaults
    try {
        $user = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($prop in $user.PSObject.Properties) {
            if ($defaults.PSObject.Properties[$prop.Name]) {
                $defaults.PSObject.Properties[$prop.Name].Value = $prop.Value
            }
        }
    } catch {
        Write-Verbose "PacLife: failed to parse config '$path': $_"
    }

    $script:ConfigCache = [pscustomobject]@{ Path = $path; MTime = $mtime; Missing = $false; Config = $config }
    return $config
}
