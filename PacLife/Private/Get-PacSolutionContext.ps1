function Read-PacLifeSolutionXml {
    <#
    .SYNOPSIS
        Parses a Solution.xml manifest → @{ Name; Version } (either may be $null).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    try {
        $xml = [xml](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
        $manifest = $xml.ImportExportXml.SolutionManifest
        return @{
            Name    = [string]$manifest.UniqueName
            Version = [string]$manifest.Version
        }
    } catch {
        Write-Verbose "PacLife: failed to parse '$Path': $_"
        return $null
    }
}

function Get-PacSolutionContext {
    <#
    .SYNOPSIS
        Detects the Power Platform solution being worked on by searching the
        current directory and up to 4 parent levels (the same mental model as
        git finding .git): *.cdsproj, src/Other/Solution.xml, *.pcfproj.
        Includes the solution version from Solution.xml when available.
        Cached per path with a 30s TTL so `pac solution init` shows up quickly.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $PWD.Path
    )

    $cached = $script:SolutionCache[$Path]
    if ($cached -and ((Get-Date) - $cached.At).TotalSeconds -lt 30) {
        return $cached.Result
    }

    $result = $null
    $dir = $Path
    for ($level = 0; $level -le 4 -and $dir; $level++) {
        if (-not (Test-Path -LiteralPath $dir)) { break }

        $cdsproj = Get-ChildItem -LiteralPath $dir -Filter '*.cdsproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cdsproj) {
            # standard `pac solution init` layout keeps the manifest next to the project
            $version = $null
            $manifestPath = Join-Path $dir 'src/Other/Solution.xml'
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                $manifest = Read-PacLifeSolutionXml -Path $manifestPath
                if ($manifest) { $version = $manifest.Version }
            }
            $result = [pscustomobject]@{ Name = $cdsproj.BaseName; Version = $version; Source = $cdsproj.FullName; Kind = 'Solution' }
            break
        }

        $solutionXml = Join-Path $dir 'src/Other/Solution.xml'
        if (Test-Path -LiteralPath $solutionXml -PathType Leaf) {
            $manifest = Read-PacLifeSolutionXml -Path $solutionXml
            if ($manifest -and $manifest.Name) {
                $result = [pscustomobject]@{ Name = $manifest.Name; Version = $manifest.Version; Source = $solutionXml; Kind = 'Solution' }
                break
            }
        }

        $pcfproj = Get-ChildItem -LiteralPath $dir -Filter '*.pcfproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pcfproj) {
            $result = [pscustomobject]@{ Name = $pcfproj.BaseName; Version = $null; Source = $pcfproj.FullName; Kind = 'PCF' }
            break
        }

        $parent = Split-Path -Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }

    $script:SolutionCache[$Path] = [pscustomobject]@{ At = Get-Date; Result = $result }
    return $result
}
