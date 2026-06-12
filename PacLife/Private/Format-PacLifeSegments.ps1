function Get-PacLifeVisibleWidth {
    <#
    .SYNOPSIS
        Approximate terminal cell width of a string: astral-plane chars (surrogate
        pairs, e.g. emoji) and CJK ranges count as 2 cells, everything else as 1.
    #>
    [CmdletBinding()]
    param([string]$Text)

    if (-not $Text) { return 0 }
    $width = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ([char]::IsHighSurrogate($c)) { $width += 2; $i++; continue }
        $code = [int]$c
        if (($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60)) { $width += 2 } else { $width += 1 }
    }
    return $width
}

function ConvertTo-PacLifeSgr {
    <#
    .SYNOPSIS
        '#rrggbb' → truecolor SGR parameter string ('38;2;r;g;b' or '48;2;r;g;b').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Hex,
        [switch]$Background
    )
    $rgb = ConvertFrom-PacLifeHex $Hex
    if (-not $rgb) { $rgb = @(255, 255, 255) }
    $plane = if ($Background) { 48 } else { 38 }
    return "$plane;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
}

function Format-PacLifeSegments {
    <#
    .SYNOPSIS
        Renders the statusline string for a PacLife context, styled by the active
        theme (builtin or derived from the user's oh-my-posh theme): truecolor,
        with powerline, diamond or plain segment joins. Segments are dropped by
        priority and the environment name trimmed when the terminal is narrow.
        Honors NO_COLOR.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Formats the set of segments as a whole')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Context,
        [int]$Width = 0
    )

    $theme = Get-PacLifeTheme
    $esc = [char]27

    # --- build segment list: @{ Text; AltText; Role; Priority } -------------------
    $segments = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($text, $role, $priority, $altText = $null)
        $segments.Add([pscustomobject]@{ Text = $text; AltText = $altText; Role = $role; Priority = $priority })
    }

    & $add '⚡ PacLife' 'Brand' 50

    switch ($Context.State) {
        'NotInstalled' { & $add 'pac CLI not found' 'Dim1' 100 }
        'NotLoggedIn'  { & $add 'not logged in — pac auth create' 'EnvUnknown' 100 }
        default {
            # identity
            if ($Context.IsServicePrincipal) {
                $shortId = if ($Context.Identity -and $Context.Identity.Length -gt 13) { $Context.Identity.Substring(0, 8) + '…' } else { $Context.Identity }
                & $add "SPN $shortId" 'Spn' 90 'SPN'
            } else {
                & $add $Context.Identity 'Identity' 90
            }

            if ($Context.State -eq 'NoEnvironment') {
                & $add 'no env — pac env select' 'EnvUnknown' 100
            } else {
                # environment, colored by classification; the warning states the
                # cause in plain words — no vocabulary to learn, no shouting
                $envName = [string]$Context.EnvironmentName
                switch ($Context.EnvironmentState) {
                    'Protected' {
                        $reason = switch ([string]$Context.EnvironmentType) {
                            'Production' { 'Production' }
                            'Default'    { 'Default Environment' }
                            default      { 'Protected' }
                        }
                        & $add "$envName ⚠ $reason" 'EnvProtected' 100 "$envName ⚠"
                    }
                    'Safe'      { & $add $envName 'EnvSafe' 100 }
                    default     { & $add $envName 'EnvUnknown' 100 }
                }

                if ($Context.Solution) { & $add "sln $($Context.Solution.Name)" 'Solution' 70 }

                if ($Context.CloudName -and $Context.CloudName -ne 'Public') {
                    & $add $Context.CloudName 'Sovereign' 95
                }
                if ($Context.AuthKind) { & $add $Context.AuthKind 'Dim1' 30 }

                $trail = @()
                if ($Context.EnvironmentGeo) { $trail += $Context.EnvironmentGeo }
                if ($Context.CloudName -eq 'Public') { $trail += 'Public' }
                if ($trail) { & $add ($trail -join ' · ') 'Dim2' 40 }
            }

            if ($Context.ProfileCount -gt 1) {
                $idx = if ($Context.ActiveProfileIndex) { "#$($Context.ActiveProfileIndex)/" } else { '' }
                & $add "$idx$($Context.ProfileCount)" 'Dim2' 35
            }
            if ($Context.PacVersion) { & $add "pac $($Context.PacVersion)" 'Dim3' 20 }
        }
    }

    # --- width fitting -------------------------------------------------------------
    $perSegmentOverhead = if ($theme.JoinStyle -eq 'diamond') { 5 } else { 3 }
    $measure = {
        param($segs)
        $total = 0
        foreach ($s in $segs) { $total += (Get-PacLifeVisibleWidth $s.Text) + $perSegmentOverhead }
        $total
    }
    if ($Width -gt 0) {
        if ((& $measure $segments) -gt $Width) {
            foreach ($s in $segments) { if ($s.AltText) { $s.Text = $s.AltText } }
        }
        while ((& $measure $segments) -gt $Width -and $segments.Count -gt 1) {
            $lowest = $segments | Sort-Object Priority | Select-Object -First 1
            if ($lowest.Priority -ge 100) { break }
            $null = $segments.Remove($lowest)
        }
        $excess = (& $measure $segments) - $Width
        if ($excess -gt 0) {
            $longest = $segments | Sort-Object { (Get-PacLifeVisibleWidth $_.Text) } -Descending | Select-Object -First 1
            $keep = [Math]::Max(3, $longest.Text.Length - $excess - 1)
            if ($keep -lt $longest.Text.Length) { $longest.Text = $longest.Text.Substring(0, $keep) + '…' }
        }
    }

    # --- render ---------------------------------------------------------------------
    if ($env:NO_COLOR) {
        return ' ' + (($segments | ForEach-Object { $_.Text }) -join ' | ')
    }

    $role = {
        param($name)
        $r = $theme.Roles[$name]
        if ($r) { $r } else { @{ Fg = '#ffffff'; Bg = '#444444' } }
    }
    # Memoized hex→SGR (per-prompt budget: avoid per-color function-call overhead)
    $sgr = {
        param($hex, $background)
        $key = "$hex|$background"
        $value = $script:SgrCache[$key]
        if (-not $value) {
            $rgb = ConvertFrom-PacLifeHex $hex
            if (-not $rgb) { $rgb = @(255, 255, 255) }
            $plane = if ($background) { 48 } else { 38 }
            $value = "$plane;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
            $script:SgrCache[$key] = $value
        }
        $value
    }
    $sb = [System.Text.StringBuilder]::new()

    switch ($theme.JoinStyle) {
        'diamond' {
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $s = $segments[$i]
                $c = & $role $s.Role
                $capFg = & $sgr $c.Bg $false                     # caps drawn in the segment's bg color
                $fg = & $sgr $c.Fg $false
                $bg = & $sgr $c.Bg $true
                [void]$sb.Append("$esc[0m$esc[${capFg}m$($theme.LeadCap)$esc[${bg}m$esc[${fg}m $($s.Text) $esc[0m$esc[${capFg}m$($theme.TrailCap)$esc[0m")
                if ($i -lt $segments.Count - 1) { [void]$sb.Append(' ') }
            }
        }
        'plain' {
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $s = $segments[$i]
                $c = & $role $s.Role
                [void]$sb.Append("$esc[$(& $sgr $c.Bg $true)m$esc[$(& $sgr $c.Fg $false)m $($s.Text) $esc[0m")
                if ($i -lt $segments.Count - 1) { [void]$sb.Append(' ') }
            }
        }
        default {   # powerline
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $s = $segments[$i]
                $c = & $role $s.Role
                [void]$sb.Append("$esc[$(& $sgr $c.Bg $true)m$esc[$(& $sgr $c.Fg $false)m $($s.Text) ")
                if ($i -lt $segments.Count - 1) {
                    $next = & $role $segments[$i + 1].Role
                    [void]$sb.Append("$esc[$(& $sgr $c.Bg $false)m$esc[$(& $sgr $next.Bg $true)m$($theme.Separator)")
                } else {
                    [void]$sb.Append("$esc[0m$esc[$(& $sgr $c.Bg $false)m$($theme.Separator)$esc[0m")
                }
            }
        }
    }
    return $sb.ToString()
}
