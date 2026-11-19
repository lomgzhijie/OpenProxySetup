# Windows PowerShell 5.1 update lookup. Called from a background runspace.
function Get-OpenProxySetupUpdate {
    param(
        [Parameter(Mandatory = $true)][version]$CurrentVersion,
        [object[]]$Releases
    )
    $ErrorActionPreference = 'Stop'
    if (-not $PSBoundParameters.ContainsKey('Releases')) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $request = @{
            Uri='https://api.github.com/repos/lomgzhijie/OpenProxySetup/releases?per_page=100'
            Headers=@{'User-Agent'='OpenProxySetup-Windows'; Accept='application/vnd.github+json'}
            TimeoutSec=12
        }
        $Releases = Invoke-RestMethod @request
    }
    $newest = $null
    foreach ($release in $Releases) {
        if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') { continue }
        $releaseVersion = [version]$Matches[1]
        if ($releaseVersion -le $CurrentVersion -or ($newest -and $releaseVersion -le $newest.Version)) { continue }
        foreach ($asset in $release.assets) {
            if ($asset.name -ne 'OpenProxySetup-windows-x64-setup.exe' -or
                $asset.state -ne 'uploaded' -or $asset.size -le 0) { continue }
            $expected = 'https://github.com/lomgzhijie/OpenProxySetup/releases/download/' +
                $release.tag_name + '/OpenProxySetup-windows-x64-setup.exe'
            if ($asset.browser_download_url -cne $expected) { continue }
            $newest = [pscustomobject]@{Version=$releaseVersion; DownloadUrl=$expected}
        }
    }
    return $newest
}
