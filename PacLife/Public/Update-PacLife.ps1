function Update-PacLife {
    <#
    .SYNOPSIS
        Updates PacLife to the latest GitHub release (alias: changes).
        This is the only PacLife command that touches the network, and only
        because you explicitly asked for it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup command')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Explicit user-invoked update; the installer prints every action')]
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072  # TLS 1.2
    }
    $installerUrl = "https://raw.githubusercontent.com/$($script:RepoSlug)/main/install.ps1"
    Write-Host "Fetching installer from $installerUrl ..."
    $installer = Invoke-RestMethod -Uri $installerUrl -Headers @{ 'User-Agent' = 'PacLife' }
    & ([scriptblock]::Create($installer))
}
