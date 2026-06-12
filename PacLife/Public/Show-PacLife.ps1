function Show-PacLife {
    <#
    .SYNOPSIS
        Prints the PacLife context once. Default: the compact statusline-style
        segment line. -Full: the detailed banner box (alias: alleyez).
    .EXAMPLE
        paclife          # compact line
    .EXAMPLE
        alleyez          # Show-PacLife -Full — All Eyez on Me
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive display command')]
    [CmdletBinding()]
    param(
        [switch]$Full
    )

    $context = Get-PacContext
    $width = try { [Console]::WindowWidth } catch { 100 }

    if (-not $Full) {
        Write-Host (Format-PacLifeSegments -Context $context -Width $width)
        return
    }

    $esc = [char]27
    $reset = "$esc[0m"
    $dim = "$esc[38;5;245m"
    $theme = Get-PacLifeTheme
    $accentHex = switch ($context.EnvironmentState) {
        'Protected' { $theme.Roles.EnvProtected.Bg }
        'Safe'      { $theme.Roles.EnvSafe.Bg }
        default     { $theme.Roles.EnvUnknown.Bg }
    }
    $accent = "$esc[$(ConvertTo-PacLifeSgr $accentHex)m"
    if ($env:NO_COLOR) { $reset = ''; $dim = ''; $accent = '' }

    $rows = [System.Collections.Generic.List[string]]::new()
    $pad = {
        param($label, $value)
        '{0,-10} {1}' -f $label, $value
    }

    switch ($context.State) {
        'NotInstalled' {
            $rows.Add('pac CLI not found on this machine.')
            $rows.Add('Install: https://aka.ms/PowerAppsCLI')
        }
        'NotLoggedIn' {
            $rows.Add('Not logged in.')
            $rows.Add('Run: pac auth create')
        }
        default {
            $identity = if ($context.IsServicePrincipal) { "$($context.Identity)  (service principal)" } else { $context.Identity }
            $rows.Add((& $pad 'Identity' $identity))
            $tenant = $context.TenantId
            if ($context.TenantCountry) { $tenant += "  ($($context.TenantCountry))" }
            $rows.Add((& $pad 'Tenant' $tenant))
            $rows.Add((& $pad 'Auth' "$($context.AuthKind)  ·  cloud: $($context.CloudName)"))

            if ($context.State -eq 'NoEnvironment') {
                $rows.Add((& $pad 'Env' 'no environment selected — run: pac env select'))
            } else {
                $envLine = $context.EnvironmentName
                $tags = @($context.EnvironmentType, $context.EnvironmentGeo) | Where-Object { $_ }
                if ($tags) { $envLine += "  [$($tags -join ' · ')]" }
                if ($context.EnvironmentState -eq 'Protected') {
                    $reason = switch ([string]$context.EnvironmentType) {
                        'Production' { 'Production' }
                        'Default'    { 'Default Environment' }
                        default      { 'Protected' }
                    }
                    $envLine += "  ⚠ $reason — all eyez on you"
                }
                $rows.Add((& $pad 'Env' $envLine))
                $rows.Add((& $pad 'URL' $context.EnvironmentUrl))
            }
            if ($context.Solution) {
                $solutionLine = $context.Solution.Name
                if ($context.Solution.Version) { $solutionLine += "  v$($context.Solution.Version)" }
                $solutionLine += "  ($($context.Solution.Kind))"
                $rows.Add((& $pad 'Solution' $solutionLine))
            }
            if ($context.ProfileCount -gt 0) {
                $profileLine = "$($context.ProfileCount)"
                if ($context.ActiveProfileIndex) { $profileLine += "  (active #$($context.ActiveProfileIndex))" }
                $profileLine += '  ·  pac auth list'
                $rows.Add((& $pad 'Profiles' $profileLine))
            }
            $footer = @()
            if ($context.PacVersion) { $footer += "pac $($context.PacVersion)" }
            if ($context.RefreshedAt) { $footer += "context last refreshed by pac ≈ $($context.RefreshedAt.ToString('MMM d HH:mm'))" }
            if ($footer) { $rows.Add($footer -join '  ·  ') }
        }
    }

    $inner = [Math]::Min([Math]::Max(40, $width - 4), 78)
    foreach ($row in $rows) {
        $w = Get-PacLifeVisibleWidth $row
        if ($w + 2 -gt $inner) { $inner = [Math]::Min($w + 2, $width - 4) }
    }

    $title = ' Pac''s Life — Power Platform CLI '
    $titleWidth = Get-PacLifeVisibleWidth $title
    $top = "$accent╭─$title" + ('─' * [Math]::Max(0, $inner - $titleWidth - 1)) + "╮$reset"
    Write-Host $top
    foreach ($row in $rows) {
        $w = Get-PacLifeVisibleWidth $row
        $clip = $row
        while ($w -gt $inner - 2 -and $clip.Length -gt 1) {
            $clip = $clip.Substring(0, $clip.Length - 2) + '…'
            $w = Get-PacLifeVisibleWidth $clip
        }
        Write-Host "$accent│$reset $clip$(' ' * [Math]::Max(0, $inner - 2 - $w)) $accent│$reset"
    }
    Write-Host "$accent╰$('─' * $inner)╯$reset"
    Write-Host "$dim  All Eyez on your environment.$reset"
}

function Show-PacLifeFull {
    # Target of the exported 'alleyez' alias (aliases cannot bind parameters)
    [CmdletBinding()]
    param()
    Show-PacLife -Full
}
