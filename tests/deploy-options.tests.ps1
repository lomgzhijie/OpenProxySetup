$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $testRoot 'deploy.ps1'))
$source = $source.Replace('$root = Split-Path -Parent $MyInvocation.MyCommand.Path',
    ("`$root = '" + $testRoot.Replace("'","''") + "'"))
$source = $source.Replace(". (Join-Path `$root 'proxy.ps1')", '# Proxy setup is unnecessary for mocked service requests.')
$mock = @'
# Runtime commands below are mocked; use existing files as presence-check fixtures.
# CI checks out source without the distributable Node/Wrangler binaries.
$nodeExe = Join-Path $PSHOME 'powershell.exe'
$wranglerJs = Join-Path $root 'tests\deploy-options.tests.ps1'
function Resolve-CloudflareAccount {
    $Deployment.AccountId = '00000000000000000000000000000001'
    return @{Authorization='Bearer fixture-token'}
}
function Get-KvId { return '00000000000000000000000000000002' }
function Initialize-PagesProject { $Deployment.ProjectCreated = $true }
function Set-AdminSecret { }
function Run { return 'Mock Pages deployment uploaded' }
function Attach-Domain { throw 'Status checks must not submit a binding request' }
function Invoke-CloudflareRequest($Uri,$Headers) {
    if ($Uri -notlike '*/domains/example.test') { throw 'Unexpected status request' }
    return [pscustomobject]@{result=[pscustomobject]@{status='active'}}
}
'@
$source = $source.Replace('if (-not (Test-Path $nodeExe)', $mock + "`nif (-not (Test-Path `$nodeExe)")
$entry = [scriptblock]::Create($source)
$state = @{
    Step=0; LastStep=0; StepStarted=[DateTime]::UtcNow; Times=@(0.0,0.0,0.0,0.0,0.0)
    AccountId=''; KvId=''; KvAttempted=$false; ProjectAttempted=$false
    ProjectCreated=$false; PagesReady=$false; DomainStarted=$false; DomainActive=$false
}
& $entry -ProjectName 'ops-options-test' -PagesOnly -Deployment $state `
    -AdminPassword (ConvertTo-SecureString 'fixture-password' -AsPlainText -Force) | Out-Null
if (-not $state.PagesReady -or $state.DomainStarted) { throw 'Pages-only deployment required domain credentials' }
$state.DomainStarted = $true
& $entry -ProjectName 'ops-options-test' -Domain 'example.test' -CheckDomainOnly -Deployment $state | Out-Null
if (-not $state.DomainActive) { throw 'Domain query failed to update deployment state' }
'PASS Pages-only deployment and query-only domain validation without DNSHE credentials'
