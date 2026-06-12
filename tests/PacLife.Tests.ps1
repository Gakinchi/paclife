#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../PacLife/PacLife.psd1'
    $script:FixtureDir = Join-Path $PSScriptRoot 'fixtures'
    Import-Module $script:ModulePath -Force

    # Keep the developer's real store/config out of the tests
    $script:SavedStore = $env:PACLIFE_STORE
    $script:SavedConfig = $env:PACLIFE_CONFIG
    $env:PACLIFE_CONFIG = Join-Path ([IO.Path]::GetTempPath()) 'paclife-test-config-does-not-exist.json'

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

    It 'shouts ALL EYEZ ON YOU for protected environments at full width' {
        $ctx = Get-PacContext
        InModuleScope PacLife -Parameters @{ Ctx = $ctx } {
            Format-PacLifeSegments -Context $Ctx -Width 200 | Should -Match 'ALL EYEZ ON YOU'
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
            $line | Should -Not -Match 'ALL EYEZ ON YOU'   # swapped to the short ⚠ form
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
