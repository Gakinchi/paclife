function Get-PacContext {
    <#
    .SYNOPSIS
        Returns the last known Power Platform CLI context as an object — who pac
        runs as, which tenant/environment/solution, and how the environment is
        classified. Read entirely from pac's local auth store; never a network call.
    .NOTES
        State:            NotInstalled | NotLoggedIn | NoEnvironment | Connected
        EnvironmentState: Protected | Safe | Unknown   (only meaningful when Connected)
    #>
    [CmdletBinding()]
    param()

    # Strict-mode-safe property reader for JSON-shaped objects
    $prop = {
        param($obj, $name)
        $p = $obj.PSObject.Properties[$name]
        if ($p) { $p.Value } else { $null }
    }

    $config = Get-PacLifeConfig
    $store = Get-PacAuthStore

    $context = [pscustomobject]@{
        State              = 'NotInstalled'
        Identity           = $null
        IsServicePrincipal = $false
        AuthKind           = $null
        TenantId           = $null
        TenantCountry      = $null
        CloudInstance      = $null
        CloudName          = $null
        EnvironmentName    = $null
        EnvironmentUrl     = $null
        EnvironmentType    = $null
        EnvironmentGeo     = $null
        EnvironmentState   = $null
        ProfileCount       = 0
        ActiveProfileIndex = $null
        Solution           = Get-PacSolutionContext
        PacVersion         = $null
        RefreshedAt        = $null
        Config             = $config
    }
    if (-not $store) { return $context }

    $context.PacVersion = Get-PacCliVersion -StoreDir $store.Dir
    $data = $store.Data

    $profiles = @()
    $rawProfiles = & $prop $data 'Profiles'
    if ($rawProfiles) { $profiles = @($rawProfiles) }
    $context.ProfileCount = $profiles.Count

    # Active profile: pac keeps a full copy per Kind under "Current" (UNIVERSAL preferred)
    $active = $null
    $current = & $prop $data 'Current'
    if ($current) {
        $universal = & $prop $current 'UNIVERSAL'
        if ($universal) {
            $active = $universal
        } else {
            $first = $current.PSObject.Properties | Select-Object -First 1
            if ($first) { $active = $first.Value }
        }
    }
    if (-not $active) {
        $context.State = 'NotLoggedIn'
        return $context
    }

    # Identity: user UPN or service principal AppId
    $user = & $prop $active 'User'
    $appId = & $prop $active 'ApplicationId'
    if (-not $appId) { $appId = & $prop $active 'ClientId' }
    $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    if ($appId) {
        $context.IsServicePrincipal = $true
        $context.Identity = $appId
    } elseif ($user -and $user -match $guidPattern) {
        $context.IsServicePrincipal = $true
        $context.Identity = $user
    } else {
        $context.Identity = $user
    }

    $context.AuthKind = & $prop $active 'Kind'
    $context.TenantId = & $prop $active 'TenantId'
    $context.TenantCountry = & $prop $active 'TenantCountry'

    $cloudNames = @{ 0 = 'Public'; 1 = 'GCC'; 2 = 'GCC High'; 3 = 'DoD'; 4 = 'China' }
    $cloud = & $prop $active 'CloudInstance'
    if ($null -ne $cloud) {
        $context.CloudInstance = [int]$cloud
        $context.CloudName = if ($cloudNames.ContainsKey([int]$cloud)) { $cloudNames[[int]$cloud] } else { "Cloud $cloud" }
    }

    # Freshness: ExpiresOn minus the typical access-token lifetime (~1h) approximates
    # the last time pac talked to the service. Informational only.
    $expiresOn = & $prop $active 'ExpiresOn'
    if ($expiresOn) {
        try { $context.RefreshedAt = ([datetimeoffset]$expiresOn).AddHours(-1) } catch { Write-Verbose "PacLife: unparsable ExpiresOn '$expiresOn'" }
    }

    # Environment: only when the profile points at an actual org (logged in ≠ connected)
    $orgId = & $prop $active 'OrganizationId'
    $friendly = & $prop $active 'FriendlyName'
    if (-not $orgId -and -not $friendly) {
        $context.State = 'NoEnvironment'
        return $context
    }

    $context.State = 'Connected'
    $context.EnvironmentName = $friendly
    $context.EnvironmentUrl = & $prop $active 'Resource'
    $context.EnvironmentType = & $prop $active 'EnvironmentType'
    $context.EnvironmentGeo = & $prop $active 'EnvironmentGeo'

    # Active index (1-based, matches pac auth list)
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        if ((& $prop $p 'Resource') -eq $context.EnvironmentUrl -and
            (& $prop $p 'User') -eq $user -and
            (& $prop $p 'ExpiresOn') -eq $expiresOn) {
            $context.ActiveProfileIndex = $i + 1
            break
        }
    }

    # Classification: protectedUrls > safeUrls > environment type
    $envState = switch -Regex ([string]$context.EnvironmentType) {
        '^(Production|Default)$'         { 'Protected'; break }
        '^(Sandbox|Developer|Trial)$'    { 'Safe'; break }
        default                          { 'Unknown' }
    }
    $url = [string]$context.EnvironmentUrl
    foreach ($pattern in @($config.safeUrls)) {
        if ($pattern -and $url -like $pattern) { $envState = 'Safe' }
    }
    foreach ($pattern in @($config.protectedUrls)) {
        if ($pattern -and $url -like $pattern) { $envState = 'Protected' }
    }
    $context.EnvironmentState = $envState

    return $context
}
