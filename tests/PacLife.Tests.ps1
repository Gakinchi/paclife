#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../PacLife/PacLife.psd1'
    $script:FixtureDir = Join-Path $PSScriptRoot 'fixtures'
    Import-Module $script:ModulePath -Force

    # Keep the developer's real store/config/oh-my-posh theme out of the tests
    $script:SavedStore = $env:PACLIFE_STORE
    $script:SavedConfig = $env:PACLIFE_CONFIG
    $script:SavedPoshTheme = $env:POSH_THEME
    $env:PACLIFE_CONFIG = Join-Path ([IO.Path]::GetTempPath()) 'paclife-test-config-does-not-exist.json'
    $env:POSH_THEME = $null

    function New-ThemeConfig {
        param([string]$ThemePath, [string]$Name = [guid]::NewGuid().ToString('N'))
        $path = Join-Path $TestDrive "config-$Name.json"
        @{ theme = $ThemePath } | ConvertTo-Json | Set-Content $path
        return $path
    }

    function New-StoreDir {
        param([string]$Fixture, [string]$Name = [guid]::NewGuid().ToString('N'))
        $dir = Join-Path $TestDrive "store-$Name"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ($Fixture) {
            Copy-Item (Join-Path $script:FixtureDir $Fixture) (Join-Path $dir 'authprofiles_v2.json')
        }
        return $dir
    }
}

AfterAll {
    $env:PACLIFE_STORE = $script:SavedStore
    $env:PACLIFE_CONFIG = $script:SavedConfig
    $env:POSH_THEME = $script:SavedPoshTheme
    Remove-Module PacLife -Force -ErrorAction SilentlyContinue
}

Describe 'Get-PacContext' {

    It 'classifies a Production environment as Protected (Connected)' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'connected.json'
        $ctx = Get-PacContext
        $ctx.State | Should -Be 'Connected'
        $ctx.Identity | Should -Be 'maker@contoso.com'
        $ctx.IsServicePrincipal | Should -BeFalse
        $ctx.EnvironmentName | Should -Be 'Contoso Prod'
        $ctx.EnvironmentState | Should -Be 'Protected'
        $ctx.ProfileCount | Should -Be 2
        $ctx.ActiveProfileIndex | Should -Be 2
        $ctx.CloudName | Should -Be 'Public'
        $ctx.AuthKind | Should -Be 'UNIVERSAL'
    }

    It 'classifies a Sandbox environment as Safe' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'sandbox.json'
        (Get-PacContext).EnvironmentState | Should -Be 'Safe'
    }

    It 'lets protectedUrls patterns override the environment type' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'sandbox.json'
        $config = Join-Path $TestDrive 'protected-config.json'
        '{ "protectedUrls": ["*contoso-dev*"] }' | Set-Content $config
        $env:PACLIFE_CONFIG = $config
        try {
            (Get-PacContext).EnvironmentState | Should -Be 'Protected'
        } finally {
            $env:PACLIFE_CONFIG = Join-Path ([IO.Path]::GetTempPath()) 'paclife-test-config-does-not-exist.json'
        }
    }

    It 'lets safeUrls patterns mute a type-based Protected' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'connected.json'
        $config = Join-Path $TestDrive 'safe-config.json'
        '{ "safeUrls": ["*contoso-prod*"] }' | Set-Content $config
        $env:PACLIFE_CONFIG = $config
        try {
            (Get-PacContext).EnvironmentState | Should -Be 'Safe'
        } finally {
            $env:PACLIFE_CONFIG = Join-Path ([IO.Path]::GetTempPath()) 'paclife-test-config-does-not-exist.json'
        }
    }

    It 'reports NoEnvironment when authenticated without an org (logged in ≠ connected)' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'noenv.json'
        $ctx = Get-PacContext
        $ctx.State | Should -Be 'NoEnvironment'
        $ctx.Identity | Should -Be 'maker@contoso.com'
    }

    It 'reports NotLoggedIn when the store has no current profile' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'notloggedin.json'
        (Get-PacContext).State | Should -Be 'NotLoggedIn'
    }

    It 'reports NotInstalled when there is no auth store at all' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture $null
        (Get-PacContext).State | Should -Be 'NotInstalled'
    }

    It 'detects a service principal and maps sovereign clouds' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'spn-gcchigh.json'
        $ctx = Get-PacContext
        $ctx.IsServicePrincipal | Should -BeTrue
        $ctx.Identity | Should -Be '4f2a8c11-7b3d-4e6f-9a20-5c8e1b34d91c'
        $ctx.CloudName | Should -Be 'GCC High'
        $ctx.AuthKind | Should -Be 'ADMIN'
    }

    It 'derives context freshness as ExpiresOn minus ~1h' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'connected.json'
        $ctx = Get-PacContext
        $ctx.RefreshedAt | Should -Be ([datetimeoffset]'2026-06-10T12:00:00+00:00').AddHours(-1)
    }

    It 'invalidates the cache when the store file changes (mtime)' {
        $dir = New-StoreDir -Fixture 'connected.json'
        $env:PACLIFE_STORE = $dir
        (Get-PacContext).EnvironmentState | Should -Be 'Protected'

        $file = Join-Path $dir 'authprofiles_v2.json'
        Copy-Item (Join-Path $script:FixtureDir 'sandbox.json') $file -Force
        (Get-Item $file).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
        (Get-PacContext).EnvironmentState | Should -Be 'Safe'
    }

    It 'reads the pac CLI version from the newest version folder' {
        $dir = New-StoreDir -Fixture 'connected.json'
        New-Item -ItemType Directory -Path (Join-Path $dir 'Microsoft.PowerApps.CLI.1.2.3') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'Microsoft.PowerApps.CLI.1.10.0') | Out-Null
        $env:PACLIFE_STORE = $dir
        (Get-PacContext).PacVersion | Should -Be ([version]'1.10.0')
    }
}

Describe 'Get-PacSolutionContext' {

    It 'finds a cdsproj by searching upward from a subdirectory' {
        $root = Join-Path $TestDrive "sln-$([guid]::NewGuid().ToString('N'))"
        $child = Join-Path $root 'src/components'
        New-Item -ItemType Directory -Path $child -Force | Out-Null
        Set-Content (Join-Path $root 'ContosoCore.cdsproj') '<Project />'

        InModuleScope PacLife -Parameters @{ Path = $child } {
            $result = Get-PacSolutionContext -Path $Path
            $result.Name | Should -Be 'ContosoCore'
            $result.Kind | Should -Be 'Solution'
        }
    }

    It 'reads the UniqueName from src/Other/Solution.xml' {
        $root = Join-Path $TestDrive "xml-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $root 'src/Other') -Force | Out-Null
        Set-Content (Join-Path $root 'src/Other/Solution.xml') @'
<ImportExportXml><SolutionManifest><UniqueName>FancySolution</UniqueName></SolutionManifest></ImportExportXml>
'@

        InModuleScope PacLife -Parameters @{ Path = $root } {
            (Get-PacSolutionContext -Path $Path).Name | Should -Be 'FancySolution'
        }
    }

    It 'returns $null when nothing solution-like is found' {
        $root = Join-Path $TestDrive "empty-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        InModuleScope PacLife -Parameters @{ Path = $root } {
            Get-PacSolutionContext -Path $Path | Should -BeNullOrEmpty
        }
    }
}

Describe 'Format-PacLifeSegments' {

    BeforeEach {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'connected.json'
    }

    It 'states the cause in plain words for a Production environment' {
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Match '⚠ Production'
        }
    }

    It 'hides the auth kind segment for modern UNIVERSAL profiles' {
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Not -Match 'UNIVERSAL'
        }
    }

    It 'shows the auth kind segment for legacy non-UNIVERSAL profiles' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'spn-gcchigh.json'
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Match 'ADMIN'
        }
    }

    It 'says Default Environment for a protected default-type environment' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'default-env.json'
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Match '⚠ Default Environment'
        }
    }

    It 'says Protected when a protectedUrls rule (not the type) triggered the warning' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'sandbox.json'
        $config = Join-Path $TestDrive 'reason-config.json'
        '{ "protectedUrls": ["*contoso-dev*"] }' | Set-Content $config
        $env:PACLIFE_CONFIG = $config
        try {
            $ctx = Get-PacContext
            InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
                Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Match '⚠ Protected'
            }
        } finally {
            $env:PACLIFE_CONFIG = Join-Path ([IO.Path]::GetTempPath()) 'paclife-test-config-does-not-exist.json'
        }
    }

    It 'emits no escape sequences when NO_COLOR is set' {
        $ctx = Get-PacContext
        $env:NO_COLOR = '1'
        try {
            InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
                Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Not -Match "`e"
            }
        } finally {
            Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
        }
    }

    It 'fits within a narrow terminal by dropping low-priority segments' {
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            $line = Format-PacLifeSegments -Context $Ctx -Width 60
            $visible = $line -replace "`e\[[0-9;]*m", ''
            (Get-PacLifeVisibleWidth $visible) | Should -BeLessOrEqual 60
            $line | Should -Not -Match '⚠ Production'   # swapped to the short ⚠ form
        }
    }

    It 'renders the SPN identity distinctly' {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'spn-gcchigh.json'
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            $line = Format-PacLifeSegments -Context $Ctx -Width 200
            $line | Should -Match 'SPN'
            $line | Should -Match 'GCC HIGH'
        }
    }
}

Describe 'Theme matching (oh-my-posh)' {

    BeforeEach {
        $env:PACLIFE_STORE = New-StoreDir -Fixture 'connected.json'
    }

    AfterEach {
        $env:PACLIFE_CONFIG = Join-Path ([IO.Path]::GetTempPath()) 'paclife-test-config-does-not-exist.json'
        $env:POSH_THEME = $null
    }

    It 'adopts colors, diamond shape and hue-harvested semantics from a diamond theme' {
        $env:PACLIFE_CONFIG = New-ThemeConfig -ThemePath (Join-Path $script:FixtureDir 'atomic-like.omp.json')
        InModuleScope PacLife {
            $theme = Get-PacLifeTheme
            $theme.JoinStyle | Should -Be 'diamond'
            $theme.Roles.EnvProtected.Bg | Should -Be '#ef5350'   # the theme's own red
            $theme.Roles.EnvUnknown.Bg | Should -Be '#fffb38'     # the theme's own yellow
            $theme.Roles.EnvSafe.Bg | Should -Be '#008700'        # no green in theme → builtin fallback
            $theme.Roles.Brand.Bg | Should -Be '#0077c2'          # first saturated pair
        }
    }

    It 'renders truecolor SGR with the theme red on a protected environment' {
        $env:PACLIFE_CONFIG = New-ThemeConfig -ThemePath (Join-Path $script:FixtureDir 'atomic-like.omp.json')
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            $line = Format-PacLifeSegments -Context $Ctx -Width 200
            $line | Should -Match '48;2;239;83;80'   # #ef5350 as 24-bit background
        }
    }

    It 'adopts the powerline symbol and resolves p: palette references' {
        $env:PACLIFE_CONFIG = New-ThemeConfig -ThemePath (Join-Path $script:FixtureDir 'powerline-like.omp.json')
        InModuleScope PacLife {
            $theme = Get-PacLifeTheme
            $theme.JoinStyle | Should -Be 'powerline'
            $theme.Separator | Should -Be ([string][char]0xE0B4)
            $theme.Roles.EnvSafe.Bg | Should -Be '#15803d'        # p:green resolved + hue-harvested
            $theme.Roles.Brand.Bg | Should -Be '#1e3a8a'          # p:blue resolved
        }
    }

    It 'ignores POSH_THEME when theme is builtin' {
        $env:POSH_THEME = Join-Path $script:FixtureDir 'atomic-like.omp.json'
        $config = Join-Path $TestDrive 'builtin-config.json'
        '{ "theme": "builtin" }' | Set-Content $config
        $env:PACLIFE_CONFIG = $config
        InModuleScope PacLife {
            (Get-PacLifeTheme).Source | Should -Be 'builtin'
        }
    }

    It 'falls back to builtin for a broken or non-JSON theme file' {
        $broken = Join-Path $TestDrive 'broken.omp.json'
        'this is not json {{{' | Set-Content $broken
        $env:PACLIFE_CONFIG = New-ThemeConfig -ThemePath $broken
        InModuleScope PacLife {
            (Get-PacLifeTheme).Source | Should -Be 'builtin'
        }
    }

    It 'honors the legacy icons=ascii setting as plain style' {
        $config = Join-Path $TestDrive 'legacy-config.json'
        '{ "theme": "builtin", "icons": "ascii" }' | Set-Content $config
        $env:PACLIFE_CONFIG = $config
        InModuleScope PacLife {
            (Get-PacLifeTheme).JoinStyle | Should -Be 'plain'
        }
    }
}

Describe 'Profile block' {

    It 'is idempotent: enabling twice leaves a single block' {
        $profilePath = Join-Path $TestDrive 'profile.ps1'
        Set-Content $profilePath '# my existing profile'

        InModuleScope PacLife -Parameters @{ Path = $profilePath } {
            Add-PacLifeProfileBlock -Path $Path -ModuleBase 'C:\fake\PacLife'
            Add-PacLifeProfileBlock -Path $Path -ModuleBase 'C:\fake\PacLife'
        }
        $content = Get-Content $profilePath -Raw
        ([regex]::Matches($content, '# >>> PacLife >>>')).Count | Should -Be 1
        $content | Should -Match '# my existing profile'
    }

    It 'removes the block and preserves the rest of the profile' {
        $profilePath = Join-Path $TestDrive 'profile2.ps1'
        Set-Content $profilePath '# keep me'

        InModuleScope PacLife -Parameters @{ Path = $profilePath } {
            Add-PacLifeProfileBlock -Path $Path -ModuleBase 'C:\fake\PacLife'
            Remove-PacLifeProfileBlock -Path $Path
        }
        $content = Get-Content $profilePath -Raw
        $content | Should -Not -Match 'PacLife'
        $content | Should -Match '# keep me'
    }
}
