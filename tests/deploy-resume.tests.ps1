$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'deploy.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors) { throw 'Unable to parse deployment script' }
foreach ($fn in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}

$ProjectName = 'ops-resume-test'
$accountUrl = 'https://api.cloudflare.com/client/v4/accounts/00000000000000000000000000000001'
$headers = @{Authorization='Bearer test-token'}
$kvId = '00000000000000000000000000000002'
$kvUrl = "$accountUrl/storage/kv/namespaces"
$pagesUrl = "$accountUrl/pages/projects"
$calls = New-Object 'Collections.Generic.List[string]'
$Deployment = @{KvAttempted=$false; ProjectAttempted=$false; ProjectCreated=$false}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -cne $Actual) { throw $Message }
}

function Invoke-RestMethod($Uri, $Headers, $Method, $TimeoutSec, $Body, $ContentType) {
    $calls.Add("$Method $Uri")
    Assert-Equal 'Bearer test-token' $Headers.Authorization 'Account credentials not forwarded'
    switch -Wildcard ("$Method $Uri") {
        "Post $kvUrl" {
            Assert-Equal "$ProjectName-KV" (ConvertFrom-Json $Body).title 'Wrong KV title'
            if ($kvTimeout) { throw [TimeoutException]::new('Simulated lost KV creation response') }
            return [pscustomobject]@{success=$true; result=[pscustomobject]@{id=$kvId}}
        }
        "Get ${kvUrl}?search=*" {
            $query = [Uri]$Uri
            if ($query.Query -match 'page=1$') {
                return [pscustomobject]@{success=$true; result=@(1..100 | ForEach-Object { [pscustomobject]@{title="$ProjectName-KV-$_"; id=$kvId} })}
            }
            $found = [pscustomobject]@{title="$ProjectName-KV"; id=$kvId}
            return [pscustomobject]@{success=$true; result=@($found)}
        }
        "Post $pagesUrl" {
            $project = ConvertFrom-Json $Body
            Assert-Equal $ProjectName $project.name 'Wrong Pages project name'
            Assert-Equal 'main' $project.production_branch 'Wrong Pages production branch'
            if ($pagesTimeout) { throw [TimeoutException]::new('Simulated lost Pages creation response') }
            return [pscustomobject]@{success=$true; result=[pscustomobject]@{name=$ProjectName}}
        }
        "Get $pagesUrl/$ProjectName" {
            if ($lookupStatus -ne 200) {
                $httpError = [Exception]::new('Simulated HTTP failure')
                $httpError | Add-Member -NotePropertyName Response -NotePropertyValue @{StatusCode=$lookupStatus}
                throw $httpError
            }
            return [pscustomobject]@{success=$true; result=[pscustomobject]@{name=$ProjectName}}
        }
        default { throw "Unexpected request $Method $Uri" }
    }
}

$kvTimeout = $true
try { Get-KvId $accountUrl $headers; throw 'Expected KV creation timeout' }
catch { if ($_.Exception.Message -notmatch 'Simulated lost KV creation response') { throw } }
Assert-Equal $true $Deployment.KvAttempted 'KV attempt flag was lost'
$kvTimeout = $false
Assert-Equal $kvId (Get-KvId $accountUrl $headers) 'Retry failed to recover the exact KV title on page 2'
Assert-Equal 1 (@($calls | Where-Object { $_ -eq "Post $kvUrl" }).Count) 'Retry created another KV namespace'

$pagesTimeout = $true
try { Initialize-PagesProject $accountUrl $headers; throw 'Expected Pages creation timeout' }
catch { if ($_.Exception.Message -notmatch 'Simulated lost Pages creation response') { throw } }
Assert-Equal $true $Deployment.ProjectAttempted 'Pages attempt flag was lost'
$pagesTimeout = $false
$lookupStatus = 200
Initialize-PagesProject $accountUrl $headers
Assert-Equal $true $Deployment.ProjectCreated 'Retry failed to recover existing Pages project'
Assert-Equal 1 (@($calls | Where-Object { $_ -eq "Post $pagesUrl" }).Count) 'Retry created another Pages project'

$Deployment.ProjectCreated = $false
$lookupStatus = 403
try { Initialize-PagesProject $accountUrl $headers; throw 'Expected authorization failure' }
catch { if ($_.Exception.Message -notmatch 'HTTP 403') { throw } }
Assert-Equal 1 (@($calls | Where-Object { $_ -eq "Post $pagesUrl" }).Count) 'Permission failure triggered a create request'

$lookupStatus = 404
Initialize-PagesProject $accountUrl $headers
Assert-Equal $true $Deployment.ProjectCreated 'Missing project was not recreated'
Assert-Equal 2 (@($calls | Where-Object { $_ -eq "Post $pagesUrl" }).Count) 'Missing project did not trigger exactly one create'
'PASS deployment recovery, paginated KV lookup, Pages 403 and 404 handling'
