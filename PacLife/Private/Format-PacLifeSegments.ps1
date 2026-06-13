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

function Get-PacLifeCellPrefix {
    <#
    .SYNOPSIS
        Returns the longest prefix of a string that fits within a cell budget —
        truncation must count cells, not chars, or wide (CJK/emoji) text is
        over- or under-trimmed.
    #>
    [CmdletBinding()]
    param(
        [string]$Text,
        [int]$Cells
    )

    if (-not $Text) { return '' }
    $used = 0
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        $isSurrogate = [char]::IsHighSurrogate($c)
        $code = [int]$c
        $w = if ($isSurrogate -or
            ($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60)) { 2 } else { 1 }
        if ($used + $w -gt $Cells) { break }
        $used += $w
        $i += if ($isSurrogate) { 2 } else { 1 }
    }
    return $Text.Substring(0, $i)
}

# Plain function on purpose (no CmdletBinding): called ~15-20x per prompt render.
# Memoized in $script:SgrCache — the single hex→SGR implementation.
function ConvertTo-PacLifeSgr {
    param(
        [string]$Hex,
        [bool]$Background = $false
    )
    $key = "$Hex|$Background"
    $value = $script:SgrCache[$key]
    if ($value) { return $value }
    $rgb = ConvertFrom-PacLifeHex $Hex
    if (-not $rgb) { $rgb = @(255, 255, 255) }
    $plane = if ($Background) { 48 } else { 38 }
    $value = "$plane;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
    $script:SgrCache[$key] = $value
    return $value
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

    # --- build segment list: @{ Text; AltText; Role; Priority; CellWidth } --------
    $segments = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($text, $role, $priority, $altText = $null)
        $segments.Add([pscustomobject]@{ Text = $text; AltText = $altText; Role = $role; Priority = $priority; CellWidth = $null })
    }

    # visual anchor only — the name lives in alleyez/README, not in prime screen estate
    & $add '⚡' 'Brand' 50

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
                # cause in plain words (ProtectedReason, derived in Get-PacContext)
                $envName = [string]$Context.EnvironmentName
                switch ($Context.EnvironmentState) {
                    'Protected' { & $add "$envName ⚠ $($Context.ProtectedReason)" 'EnvProtected' 100 "$envName ⚠" }
                    'Safe'      { & $add $envName 'EnvSafe' 100 }
                    default     { & $add $envName 'EnvUnknown' 100 }
                }

                if ($Context.Solution) {
                    $slnText = "sln $($Context.Solution.Name)"
                    if ($Context.Solution.Version) {
                        # version drops first on narrow terminals (AltText)
                        & $add "$slnText $($Context.Solution.Version)" 'Solution' 70 $slnText
                    } else {
                        & $add $slnText 'Solution' 70
                    }
                }

                if ($Context.CloudName -and $Context.CloudName -ne 'Public') {
                    & $add $Context.CloudName 'Sovereign' 95
                }
                # exception-based: UNIVERSAL is the modern default and carries no
                # information — only legacy DATAVERSE/ADMIN profiles are worth a segment
                if ($Context.AuthKind -and $Context.AuthKind -ne 'UNIVERSAL') { & $add $Context.AuthKind 'Dim1' 30 }

                # 'Public' cloud is the constant default — exception-based display:
                # only the sovereign segment above ever mentions the cloud
                if ($Context.EnvironmentGeo) { & $add $Context.EnvironmentGeo 'Dim2' 40 }
            }

            # plain words, and only when there is actually something to switch to;
            # the active index lives in the full banner (alleyez)
            if ($Context.ProfileCount -gt 1) {
                & $add "$($Context.ProfileCount) profiles" 'Dim2' 35
            }
            if ($Context.PacVersion) { & $add "pac $($Context.PacVersion)" 'Dim3' 20 }
        }
    }

    # --- width fitting -------------------------------------------------------------
    $perSegmentOverhead = if ($theme.JoinStyle -eq 'diamond') { 5 } else { 3 }
    $measure = {
        param($segs)
        $total = 0
        foreach ($s in $segs) {
            if ($null -eq $s.CellWidth) { $s.CellWidth = Get-PacLifeVisibleWidth $s.Text }
            $total += $s.CellWidth + $perSegmentOverhead
        }
        $total
    }
    if ($Width -gt 0) {
        if ((& $measure $segments) -gt $Width) {
            foreach ($s in $segments) {
                if ($s.AltText) { $s.Text = $s.AltText; $s.CellWidth = $null }
            }
        }
        # sort once, drop lowest-priority first until the line fits
        foreach ($candidate in @($segments | Sort-Object Priority)) {
            if ((& $measure $segments) -le $Width) { break }
            if ($candidate.Priority -ge 100 -or $segments.Count -le 1) { break }
            $null = $segments.Remove($candidate)
        }
        $excess = (& $measure $segments) - $Width
        if ($excess -gt 0) {
            $longest = $segments | Sort-Object CellWidth -Descending | Select-Object -First 1
            # trim by CELLS, not chars — wide (CJK/emoji) text is otherwise mis-trimmed
            $targetCells = [Math]::Max(3, $longest.CellWidth - $excess - 1)
            $prefix = Get-PacLifeCellPrefix -Text $longest.Text -Cells $targetCells
            if ($prefix.Length -lt $longest.Text.Length) {
                $longest.Text = $prefix + '…'
                $longest.CellWidth = $null
            }
        }
    }

    # --- render ---------------------------------------------------------------------
    if ($env:NO_COLOR) {
        return ' ' + (($segments | ForEach-Object { $_.Text }) -join ' | ')
    }

    # roles carry precomputed SGR codes (FgSgr/BgSgr/BgAsFgSgr) from Get-PacLifeTheme —
    # no per-color conversion calls in this per-prompt loop
    $role = {
        param($name)
        $r = $theme.Roles[$name]
        if ($r) { $r } else {
            @{ FgSgr = (ConvertTo-PacLifeSgr '#ffffff' $false); BgSgr = (ConvertTo-PacLifeSgr '#444444' $true); BgAsFgSgr = (ConvertTo-PacLifeSgr '#444444' $false) }
        }
    }
    $sb = [System.Text.StringBuilder]::new()

    switch ($theme.JoinStyle) {
        'diamond' {
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $s = $segments[$i]
                $c = & $role $s.Role
                [void]$sb.Append("$esc[0m$esc[$($c.BgAsFgSgr)m$($theme.LeadCap)$esc[$($c.BgSgr)m$esc[$($c.FgSgr)m $($s.Text) $esc[0m$esc[$($c.BgAsFgSgr)m$($theme.TrailCap)$esc[0m")
                if ($i -lt $segments.Count - 1) { [void]$sb.Append(' ') }
            }
        }
        'plain' {
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $s = $segments[$i]
                $c = & $role $s.Role
                [void]$sb.Append("$esc[$($c.BgSgr)m$esc[$($c.FgSgr)m $($s.Text) $esc[0m")
                if ($i -lt $segments.Count - 1) { [void]$sb.Append(' ') }
            }
        }
        default {   # powerline
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $s = $segments[$i]
                $c = & $role $s.Role
                [void]$sb.Append("$esc[$($c.BgSgr)m$esc[$($c.FgSgr)m $($s.Text) ")
                if ($i -lt $segments.Count - 1) {
                    $next = & $role $segments[$i + 1].Role
                    [void]$sb.Append("$esc[$($c.BgAsFgSgr)m$esc[$($next.BgSgr)m$($theme.Separator)")
                } else {
                    [void]$sb.Append("$esc[0m$esc[$($c.BgAsFgSgr)m$($theme.Separator)$esc[0m")
                }
            }
        }
    }
    return $sb.ToString()
}
