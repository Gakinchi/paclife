function ConvertFrom-PacLifeHex {
    <#
    .SYNOPSIS
        '#rrggbb' or '#rgb' → @(r, g, b), or $null for anything else
        (oh-my-posh template/dynamic color strings are intentionally ignored).
    #>
    [CmdletBinding()]
    param([string]$Hex)

    if (-not $Hex) { return $null }
    if ($Hex -match '^#([0-9a-fA-F]{6})$') {
        $v = $Matches[1]
        return @(
            [Convert]::ToInt32($v.Substring(0, 2), 16)
            [Convert]::ToInt32($v.Substring(2, 2), 16)
            [Convert]::ToInt32($v.Substring(4, 2), 16)
        )
    }
    if ($Hex -match '^#([0-9a-fA-F]{3})$') {
        $v = $Matches[1]
        return @(
            [Convert]::ToInt32("$($v[0])$($v[0])", 16)
            [Convert]::ToInt32("$($v[1])$($v[1])", 16)
            [Convert]::ToInt32("$($v[2])$($v[2])", 16)
        )
    }
    return $null
}

function ConvertTo-PacLifeHsl {
    <#
    .SYNOPSIS
        RGB (0-255) → @{ H = 0..360; S = 0..1; L = 0..1 } for hue harvesting.
    #>
    [CmdletBinding()]
    param([int]$R, [int]$G, [int]$B)

    # NB: locals must not be named $r/$g/$b — PowerShell variables are
    # case-insensitive, so they'd alias the [int] parameters and round to 0/1.
    $rf = $R / 255.0; $gf = $G / 255.0; $bf = $B / 255.0
    $max = [Math]::Max($rf, [Math]::Max($gf, $bf))
    $min = [Math]::Min($rf, [Math]::Min($gf, $bf))
    $l = ($max + $min) / 2
    if ($max -eq $min) { return @{ H = 0.0; S = 0.0; L = $l } }

    $d = $max - $min
    $s = if ($l -gt 0.5) { $d / (2 - $max - $min) } else { $d / ($max + $min) }
    $h = switch ($max) {
        $rf { (($gf - $bf) / $d) % 6; break }
        $gf { (($bf - $rf) / $d) + 2; break }
        default { (($rf - $gf) / $d) + 4 }
    }
    $h *= 60
    if ($h -lt 0) { $h += 360 }
    return @{ H = $h; S = $s; L = $l }
}

function Get-PacLifeBuiltinTheme {
    [CmdletBinding()]
    param()
    @{
        Source    = 'builtin'
        JoinStyle = 'powerline'
        Separator = [string][char]0xE0B0
        LeadCap   = [string][char]0xE0B6
        TrailCap  = [string][char]0xE0B4
        Roles     = @{
            Brand        = @{ Fg = '#ffffff'; Bg = '#0087af' }
            Identity     = @{ Fg = '#ffffff'; Bg = '#005f87' }
            Spn          = @{ Fg = '#ffffff'; Bg = '#8700af' }
            Solution     = @{ Fg = '#87d7ff'; Bg = '#444444' }
            Sovereign    = @{ Fg = '#ffffff'; Bg = '#af00af' }
            Dim1         = @{ Fg = '#a8a8a8'; Bg = '#3a3a3a' }
            Dim2         = @{ Fg = '#8a8a8a'; Bg = '#303030' }
            Dim3         = @{ Fg = '#6c6c6c'; Bg = '#262626' }
            EnvProtected = @{ Fg = '#ffffff'; Bg = '#af0000' }
            EnvSafe      = @{ Fg = '#ffffff'; Bg = '#008700' }
            EnvUnknown   = @{ Fg = '#121212'; Bg = '#d78700' }
        }
    }
}

function Get-PacLifeTheme {
    <#
    .SYNOPSIS
        Returns the active PacLife theme: the builtin palette, or one derived from
        the user's oh-my-posh theme (POSH_THEME / explicit path in ~/.paclife.json).
        The OMP JSON is parsed offline — never a process spawn, never network.
        Glossary principle: theme changes shades, never meaning — semantic env
        colors are hue-harvested (the theme's own red/green/yellow) with builtin
        fallback per color.
    #>
    [CmdletBinding()]
    param()

    $config = Get-PacLifeConfig

    # Resolve the theme source
    $setting = [string]$config.theme
    $file = $null
    if ($setting -and $setting -notin 'auto', 'builtin') {
        $file = $setting
    } elseif ($setting -ne 'builtin' -and $env:POSH_THEME) {
        $file = $env:POSH_THEME
    }
    if ($file -and ($file -notmatch '\.json$' -or -not (Test-Path -LiteralPath $file -PathType Leaf))) {
        $file = $null
    }
    $mtime = if ($file) { (Get-Item -LiteralPath $file).LastWriteTimeUtc } else { $null }

    # Per-prompt budget: return the fully-applied theme while the file, its mtime
    # and the config object (reference equality — configs are cached too) hold
    $cache = $script:ThemeCache
    if ($cache -and $cache.File -eq $file -and $cache.MTime -eq $mtime -and [object]::ReferenceEquals($cache.Config, $config)) {
        return $cache.Applied
    }

    $builtin = Get-PacLifeBuiltinTheme
    $finish = {
        param($theme)
        $style = $config.style
        if ((-not $style -or $style -eq 'auto') -and $config.icons -eq 'ascii') { $style = 'plain' }  # legacy key
        if ($style -and $style -ne 'auto') { $theme.JoinStyle = $style }
        # Precompute SGR codes once per theme build — the render loop runs every
        # prompt and must not pay per-color conversion calls
        foreach ($roleName in @($theme.Roles.Keys)) {
            $role = $theme.Roles[$roleName]
            $theme.Roles[$roleName] = @{
                Fg        = $role.Fg
                Bg        = $role.Bg
                FgSgr     = ConvertTo-PacLifeSgr $role.Fg $false
                BgSgr     = ConvertTo-PacLifeSgr $role.Bg $true
                BgAsFgSgr = ConvertTo-PacLifeSgr $role.Bg $false   # powerline separators / diamond caps
            }
        }
        $script:ThemeCache = @{ File = $file; MTime = $mtime; Config = $config; Applied = $theme }
        $theme
    }

    if (-not $file) {
        return & $finish $builtin
    }

    try {
        $omp = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Verbose "PacLife: failed to parse theme '$file': $_"
        return & $finish $builtin
    }

    $prop = {
        param($obj, $name)
        $p = $obj.PSObject.Properties[$name]
        if ($p) { $p.Value } else { $null }
    }

    # Optional palette: resolve 'p:name' color references
    $palette = & $prop $omp 'palette'
    $resolve = {
        param($color)
        if ($color -is [string] -and $color -like 'p:*' -and $palette) {
            $color = & $prop $palette ($color.Substring(2))
        }
        ConvertFrom-PacLifeHex $color
    }

    # Walk every segment: collect styles, join glyphs, and (bg, fg) color pairs
    $styleCounts = @{}
    $separators = @{}
    $leadCaps = @{}
    $trailCaps = @{}
    $pairs = [System.Collections.Generic.List[object]]::new()
    $blocks = & $prop $omp 'blocks'
    foreach ($block in @($blocks)) {
        foreach ($segment in @((& $prop $block 'segments'))) {
            if (-not $segment) { continue }
            $style = [string](& $prop $segment 'style')
            if ($style) { $styleCounts[$style] = 1 + [int]$styleCounts[$style] }

            foreach ($glyphKey in @{ powerline_symbol = $separators; leading_diamond = $leadCaps; trailing_diamond = $trailCaps }.GetEnumerator()) {
                $value = [string](& $prop $segment $glyphKey.Key)
                # harvest single private-use-area glyphs only (skip decorations like '╭─')
                foreach ($c in $value.ToCharArray()) {
                    if ([int]$c -ge 0xE000 -and [int]$c -le 0xF8FF) {
                        $glyphKey.Value[[string]$c] = 1 + [int]$glyphKey.Value[[string]$c]
                        break
                    }
                }
            }

            $bg = & $resolve (& $prop $segment 'background')
            if (-not $bg) { continue }
            $fg = & $resolve (& $prop $segment 'foreground')
            $hsl = ConvertTo-PacLifeHsl $bg[0] $bg[1] $bg[2]
            $bgHex = '#{0:x2}{1:x2}{2:x2}' -f $bg[0], $bg[1], $bg[2]
            $fgHex = if ($fg) { '#{0:x2}{1:x2}{2:x2}' -f $fg[0], $fg[1], $fg[2] }
                     elseif ($hsl.L -gt 0.6) { '#1a1a1a' } else { '#ffffff' }
            $pairs.Add(@{ Bg = $bgHex; Fg = $fgHex; H = $hsl.H; S = $hsl.S; L = $hsl.L })
        }
    }

    $top = {
        param($counts, $default)
        $best = $counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        if ($best) { $best.Key } else { $default }
    }

    $theme = @{
        Source    = $file
        JoinStyle = & $top $styleCounts 'powerline'
        Separator = & $top $separators ([string][char]0xE0B0)
        LeadCap   = & $top $leadCaps ([string][char]0xE0B6)
        TrailCap  = & $top $trailCaps ([string][char]0xE0B4)
        Roles     = @{}
    }
    if ($theme.JoinStyle -notin 'powerline', 'diamond', 'plain') { $theme.JoinStyle = 'powerline' }

    # --- semantic hue harvest: the theme's own red / green / yellow --------------
    $claimed = @{}
    $harvest = {
        param($targetHue, $tolerance, $minS, $minL, $maxL)
        $best = $null
        $bestDistance = [double]::MaxValue
        foreach ($pair in $pairs) {
            if ($claimed[$pair.Bg]) { continue }
            if ($pair.S -lt $minS -or $pair.L -lt $minL -or $pair.L -gt $maxL) { continue }
            $distance = [Math]::Abs($pair.H - $targetHue)
            if ($distance -gt 180) { $distance = 360 - $distance }
            if ($distance -le $tolerance -and $distance -lt $bestDistance) { $best = $pair; $bestDistance = $distance }
        }
        if ($best) { $claimed[$best.Bg] = $true }
        $best
    }
    $red = & $harvest 0 30 0.4 0.2 0.7
    $green = & $harvest 120 40 0.3 0.2 0.65
    $yellow = & $harvest 45 25 0.5 0.3 0.8
    $theme.Roles.EnvProtected = if ($red) { @{ Fg = $red.Fg; Bg = $red.Bg } } else { $builtin.Roles.EnvProtected }
    $theme.Roles.EnvSafe = if ($green) { @{ Fg = $green.Fg; Bg = $green.Bg } } else { $builtin.Roles.EnvSafe }
    $theme.Roles.EnvUnknown = if ($yellow) { @{ Fg = $yellow.Fg; Bg = $yellow.Bg } } else { $builtin.Roles.EnvUnknown }

    # --- non-semantic roles: saturated pairs in theme order, dark pairs for dims --
    $saturated = @($pairs | Where-Object { -not $claimed[$_.Bg] -and $_.S -ge 0.25 -and $_.L -ge 0.15 -and $_.L -le 0.85 })
    $darks = @($pairs | Where-Object { -not $claimed[$_.Bg] -and $_.S -lt 0.25 -and $_.L -lt 0.4 })

    $colorRoles = 'Brand', 'Identity', 'Spn', 'Solution', 'Sovereign'
    for ($i = 0; $i -lt $colorRoles.Count; $i++) {
        $theme.Roles[$colorRoles[$i]] = if ($saturated.Count) {
            $pair = $saturated[$i % $saturated.Count]
            @{ Fg = $pair.Fg; Bg = $pair.Bg }
        } else {
            $builtin.Roles[$colorRoles[$i]]
        }
    }
    $dimRoles = 'Dim1', 'Dim2', 'Dim3'
    for ($i = 0; $i -lt $dimRoles.Count; $i++) {
        $theme.Roles[$dimRoles[$i]] = if ($darks.Count) {
            $pair = $darks[$i % $darks.Count]
            @{ Fg = $pair.Fg; Bg = $pair.Bg }
        } else {
            $builtin.Roles[$dimRoles[$i]]
        }
    }

    return & $finish $theme
}
