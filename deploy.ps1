param([string]$ProjectName, [string]$Domain, [securestring]$AdminPassword, [securestring]$DnsheKey, [securestring]$DnsheSecret,
      [hashtable]$Deployment)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'proxy.ps1')
$nodeExe = Join-Path $root 'runtime\node.exe'
$wranglerJs = Join-Path $root 'runtime\node_modules\wrangler\bin\wrangler.js'

function Run([string]$Exe, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Exe @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "命令执行失败（退出码 $exitCode）：$output" }
    Write-Host $output
    return $output
}

function Set-AdminSecret([string]$Value) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $secretOutput = $Value | & $nodeExe $wranglerJs pages secret put ADMIN --project-name $ProjectName 2>&1 | Out-String
        $secretExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference; $Value = $null }
    if ($secretExit -ne 0) {
        $clean = [regex]::Replace($secretOutput, '\x1B\[[0-?]*[ -/]*[@-~]', '')
        throw "ADMIN 密钥设置失败（退出码 $secretExit）：$clean"
    }
    Write-Host 'ADMIN 密钥已设置。'
}

function Set-DeploymentStep([int]$Step) {
    $now = [DateTime]::UtcNow
    if ($Deployment.Step -gt 0) {
        $Deployment.Times[$Deployment.Step] += ($now - $Deployment.StepStarted).TotalSeconds
    }
    if ($Step -gt 0) { $Deployment.LastStep = $Step }
    $Deployment.StepStarted = $now
    $Deployment.Step = $Step
}

function Read-WranglerJson([string[]]$Arguments) {
    $prior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $json = & $nodeExe $wranglerJs @Arguments 2>$null | Out-String
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prior }
    if ($exitCode -ne 0) { throw 'Cloudflare 命令失败。请检查授权、账号权限和网络后重试。' }
    return ($json | ConvertFrom-Json)
}

function Resolve-CloudflareAccount {
    $accountId = $env:CLOUDFLARE_ACCOUNT_ID
    $token = $env:CLOUDFLARE_API_TOKEN
    if ($token) {
        if ($accountId -notmatch '^[a-fA-F0-9]{32}$') {
            throw 'API Token 模式需要设置 32 位的 CLOUDFLARE_ACCOUNT_ID。'
        }
    } else {
        try { $token = (Read-WranglerJson @('auth','token','--json')).token }
        catch { $token = $null }
        if (-not $token) { throw 'Cloudflare 尚未授权。请回到第 3 步完成浏览器授权，再继续部署。' }
    }

    $headers = @{Authorization = "Bearer $token"}
    if (-not $accountId) {
        $accounts = Invoke-CloudflareRequest 'https://api.cloudflare.com/client/v4/accounts?per_page=50' $headers
        $items = @($accounts.result)
        if ($items.Count -ne 1) {
            throw '无法确定唯一的 Cloudflare 账号。请通过 CLOUDFLARE_ACCOUNT_ID 指定目标账号。'
        }
        $accountId = $items[0].id
    }
    if ($Deployment.AccountId -and $Deployment.AccountId -ne $accountId) {
        throw 'Cloudflare 账号已更换。请使用本次部署原来的账号重新授权后继续。'
    }
    [void](Invoke-CloudflareRequest "https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects?per_page=1" $headers)
    $Deployment.AccountId = $accountId
    return $headers
}

function Get-KvId {
    $name = "$ProjectName-KV"
    if ($Deployment.KvAttempted) {
        $existing = @(Read-WranglerJson @('kv','namespace','list') | Where-Object title -eq $name)
        if ($existing.Count -eq 1) { return $existing[0].id }
        if ($existing.Count -gt 1) { throw "Cloudflare 中有多个同名 KV（$name）。请在控制台核对后重试。" }
    }
    $Deployment.KvAttempted = $true
    $output = Run $nodeExe @($wranglerJs,'kv','namespace','create',$name)
    $match = [regex]::Match($output, '(?m)["'']?id["'']?\s*[:=]\s*["'']([a-f0-9]{32})["'']')
    if (-not $match.Success) { throw 'KV 已提交创建，但未取得 ID。继续部署时会重新查询同名 KV。' }
    return $match.Groups[1].Value
}

function Invoke-CloudflareRequest([string]$Uri, [hashtable]$Headers, [string]$Method = 'Get', [string]$Body = '') {
    $request = @{Uri=$Uri; Headers=$Headers; Method=$Method; TimeoutSec=15}
    if ($Body) {
        $request.Body = $Body
        $request.ContentType = 'application/json'
    }
    try {
        $response = Invoke-RestMethod @request
    } catch {
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        $status = if ($responseProperty -and $responseProperty.Value) {
            'HTTP ' + [int]$responseProperty.Value.StatusCode
        } else { $_.Exception.Message }
        throw "Cloudflare 请求失败（$status）。"
    }
    if (-not $response.success) { throw 'Cloudflare API 拒绝请求。请核对账号和权限。' }
    return $response
}

function Attach-Domain([string]$Name, [string]$Project, [hashtable]$Headers, [string]$DnsheKeyPlain, [string]$DnsheSecretPlain) {
    $accountId = $Deployment.AccountId
    $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects/$Project/domains"
    $existing = Invoke-CloudflareRequest $uri $Headers
    if (-not @($existing.result | Where-Object { $_.name -eq $Name }).Count) {
        [void](Invoke-CloudflareRequest $uri $Headers 'Post' (@{name=$Name}|ConvertTo-Json -Compress))
    }
    Write-Host "自定义域名 $Name 已提交 Pages 绑定。"
    & (Join-Path $root 'dnshe.ps1') -Domain $Name -Target "$Project.pages.dev" -ApiKey $DnsheKeyPlain -ApiSecret $DnsheSecretPlain
    if (-not $?) { throw 'DNSHE CNAME 创建失败。' }
    try { [void](Invoke-CloudflareRequest "$uri/$Name" $Headers 'Patch') }
    catch { Write-Warning 'Cloudflare 域名验证重试请求未完成，稍后将继续检查状态。' }
    for ($i=0; $i -lt 6; $i++) {
        $check = Invoke-CloudflareRequest "$uri/$Name" $Headers
        if ($check.result.status -eq 'active') { Write-Host "DNS 与证书验证完成：https://$Name/admin"; return $true }
        if ($i -lt 5) { Start-Sleep -Seconds 5 }
    }
    Write-Host 'Cloudflare 正在签发证书或传播 DNS；稍后可直接访问自定义域名。生效前使用 pages.dev 地址。'
    return $false
}

if (-not (Test-Path $nodeExe) -or -not (Test-Path $wranglerJs)) { throw '下载包缺少内置运行组件，请重新下载完整 ZIP。' }
if (-not $ProjectName) { $ProjectName = 'zijianjichang-' + ([guid]::NewGuid().ToString('N')).Substring(0,8) }
if ($ProjectName -notmatch '^[a-z0-9][a-z0-9-]{1,60}[a-z0-9]$') { throw '项目名格式无效。' }
if (-not $Domain) { $Domain = Read-Host 'DNSHE 完整域名' }
if ($Domain -and $Domain -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') { throw '域名格式无效。' }

$headers = $null
$previousAccount = $env:CLOUDFLARE_ACCOUNT_ID
if (-not $Deployment) {
    $Deployment = @{
        Step = 0; StepStarted = [DateTime]::UtcNow; Times = @(0.0,0.0,0.0,0.0,0.0)
        AccountId = ''; KvId = ''; KvAttempted = $false
        ProjectAttempted = $false; ProjectCreated = $false; PagesReady = $false
        DomainStarted = $false; DomainActive = $false
    }
}
try {
    Set-DeploymentStep 1
    $headers = Resolve-CloudflareAccount
    $env:CLOUDFLARE_ACCOUNT_ID = $Deployment.AccountId
    if (-not $DnsheKey -or -not $DnsheSecret) { throw '缺少 DNSHE API Key 或 Secret。' }

    if (-not $Deployment.PagesReady) {
        if (-not $AdminPassword) { $AdminPassword = Read-Host '管理员密码（仅传给 Cloudflare，不保存）' -AsSecureString }
        if ($AdminPassword.Length -lt 12) { throw '管理员密码至少 12 个字符。' }
        $vendor = Join-Path $root 'vendor\edgetunnel'
        $worker = Join-Path $vendor '_worker.js'
        if (-not (Test-Path $worker) -or -not (Test-Path (Join-Path $vendor 'LICENSE')) -or
            (Get-Item $worker).Length -lt 100000) { throw '包内上游源码或许可证不完整，请重新下载应用包。' }
        Write-Host "使用内置 edgetunnel 版本：$(Get-Content (Join-Path $vendor 'UPSTREAM_COMMIT') -Raw)"

        if (-not $Deployment.KvId) {
            Set-DeploymentStep 2
            $Deployment.KvId = Get-KvId
        }
        Set-DeploymentStep 3
        $dir = Join-Path $env:TEMP ("zijianjichang-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        try {
            Copy-Item $worker (Join-Path $dir '_worker.js')
            Copy-Item (Join-Path $vendor 'LICENSE') (Join-Path $dir 'UPSTREAM-LICENSE')
            $cfg = @{ name=$ProjectName; pages_build_output_dir='.'; compatibility_date=(Get-Date -Format 'yyyy-MM-dd'); kv_namespaces=@(@{binding='KV';id=$Deployment.KvId}) }
            $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'wrangler.json') -Encoding utf8
            Push-Location $dir
            try {
                if (-not $Deployment.ProjectCreated) {
                    if ($Deployment.ProjectAttempted) {
                        $existing = @(Read-WranglerJson @('pages','project','list','--json') | Where-Object { $_.'Project Name' -eq $ProjectName })
                        $Deployment.ProjectCreated = $existing.Count -eq 1
                    }
                    if (-not $Deployment.ProjectCreated) {
                        $Deployment.ProjectAttempted = $true
                        [void](Run $nodeExe @($wranglerJs,'pages','project','create',$ProjectName,'--production-branch','main'))
                        $Deployment.ProjectCreated = $true
                    }
                }
                $plain = [System.Net.NetworkCredential]::new('', $AdminPassword).Password
                try { Set-AdminSecret -Value $plain }
                finally { $plain = $null }
                [void](Run $nodeExe @($wranglerJs,'pages','deploy','.','--project-name',$ProjectName,'--branch','main'))
                $Deployment.PagesReady = $true
            } finally { Pop-Location }
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Pages 地址：https://$ProjectName.pages.dev/admin"
    if ($Domain) {
        $Deployment.DomainStarted = $true
        Set-DeploymentStep 4
        $keyPlain = [System.Net.NetworkCredential]::new('', $DnsheKey).Password
        $secretPlain = [System.Net.NetworkCredential]::new('', $DnsheSecret).Password
        try { $Deployment.DomainActive = Attach-Domain $Domain $ProjectName $headers $keyPlain $secretPlain }
        catch { Write-Output "__DOMAIN_WARNING__:$($_.Exception.Message)" }
        finally { $keyPlain = $null; $secretPlain = $null }
        if ($Deployment.DomainActive) { Write-Host "自定义域名后台：https://$Domain/admin" }
    }
    Write-Host '进入后台获取实际订阅链接。'
} finally {
    Set-DeploymentStep 0
    $env:CLOUDFLARE_ACCOUNT_ID = $previousAccount
    if ($headers) { $headers.Clear() }
}
