function Get-PacSolutionContext {
    <#
    .SYNOPSIS
        Detects the Power Platform solution being worked on by searching the
        current directory and up to 4 parent levels (the same mental model as
        git finding .git): *.cdsproj, src/Other/Solution.xml, *.pcfproj.
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
            $result = [pscustomobject]@{ Name = $cdsproj.BaseName; Source = $cdsproj.FullName; Kind = 'Solution' }
            break
        }

        $solutionXml = Join-Path $dir 'src/Other/Solution.xml'
        if (Test-Path -LiteralPath $solutionXml -PathType Leaf) {
            $name = $null
            try {
                $xml = [xml](Get-Content -LiteralPath $solutionXml -Raw -ErrorAction Stop)
                $name = $xml.ImportExportXml.SolutionManifest.UniqueName
            } catch {
                Write-Verbose "PacLife: failed to parse '$solutionXml': $_"
            }
            if ($name) {
                $result = [pscustomobject]@{ Name = $name; Source = $solutionXml; Kind = 'Solution' }
                break
            }
        }

        $pcfproj = Get-ChildItem -LiteralPath $dir -Filter '*.pcfproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pcfproj) {
            $result = [pscustomobject]@{ Name = $pcfproj.BaseName; Source = $pcfproj.FullName; Kind = 'PCF' }
            break
        }

        $parent = Split-Path -Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }

    $script:SolutionCache[$Path] = [pscustomobject]@{ At = Get-Date; Result = $result }
    return $result
}
