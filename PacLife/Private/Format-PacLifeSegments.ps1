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

function Format-PacLifeSegments {
    <#
    .SYNOPSIS
        Renders the powerline statusline string for a PacLife context.
        Segments are dropped by priority (lowest first) and the environment name
        trimmed when the terminal is narrow. Honors NO_COLOR and icons=ascii.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Formats the set of segments as a whole')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Context,
        [int]$Width = 0
    )

    $config = $Context.Config
    $esc = [char]27

    # --- build segment list: @{ Text; AltText; Fg; Bg; Priority } -----------------
    $segments = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($text, $fg, $bg, $priority, $altText = $null)
        $segments.Add([pscustomobject]@{ Text = $text; AltText = $altText; Fg = $fg; Bg = $bg; Priority = $priority })
    }

    & $add '⚡ PacLife' 231 31 50

    switch ($Context.State) {
        'NotInstalled' { & $add 'pac CLI not found' 250 237 100 }
        'NotLoggedIn'  { & $add 'not logged in — pac auth create' 16 172 100 }
        default {
            # identity
            if ($Context.IsServicePrincipal) {
                $shortId = if ($Context.Identity -and $Context.Identity.Length -gt 13) { $Context.Identity.Substring(0, 8) + '…' } else { $Context.Identity }
                & $add "SPN $shortId" 231 91 90 'SPN'
            } else {
                & $add $Context.Identity 231 24 90
            }

            if ($Context.State -eq 'NoEnvironment') {
                & $add 'no env — pac env select' 16 172 100
            } else {
                # environment, colored by classification
                $envName = [string]$Context.EnvironmentName
                switch ($Context.EnvironmentState) {
                    'Protected' { & $add "$envName ⚠ ALL EYEZ ON YOU" 231 124 100 "$envName ⚠" }
                    'Safe'      { & $add $envName 231 28 100 }
                    default     { & $add $envName 16 172 100 }
                }

                if ($Context.Solution) { & $add "sln $($Context.Solution.Name)" 117 238 70 }

                if ($Context.CloudName -and $Context.CloudName -ne 'Public') {
                    & $add ($Context.CloudName.ToUpper()) 231 127 95
                }
                if ($Context.AuthKind) { & $add $Context.AuthKind 248 237 30 }

                $trail = @()
                if ($Context.EnvironmentGeo) { $trail += $Context.EnvironmentGeo }
                if ($Context.CloudName -eq 'Public') { $trail += 'Public' }
                if ($trail) { & $add ($trail -join ' · ') 245 236 40 }
            }

            if ($Context.ProfileCount -gt 1) {
                $idx = if ($Context.ActiveProfileIndex) { "#$($Context.ActiveProfileIndex)/" } else { '' }
                & $add "$idx$($Context.ProfileCount)" 245 236 35
            }
            if ($Context.PacVersion) { & $add "pac $($Context.PacVersion)" 242 235 20 }
        }
    }

    # --- width fitting -------------------------------------------------------------
    $measure = {
        param($segs)
        $total = 0
        foreach ($s in $segs) { $total += (Get-PacLifeVisibleWidth $s.Text) + 3 }  # ' text ' + separator
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

    $separator = if ($config.icons -eq 'ascii') { '' } else { [string][char]0xE0B0 }
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $s = $segments[$i]
        [void]$sb.Append("$esc[48;5;$($s.Bg)m$esc[38;5;$($s.Fg)m $($s.Text) ")
        if ($i -lt $segments.Count - 1) {
            $next = $segments[$i + 1]
            [void]$sb.Append("$esc[38;5;$($s.Bg)m$esc[48;5;$($next.Bg)m$separator")
        } else {
            [void]$sb.Append("$esc[0m$esc[38;5;$($s.Bg)m$separator$esc[0m")
        }
    }
    return $sb.ToString()
}
