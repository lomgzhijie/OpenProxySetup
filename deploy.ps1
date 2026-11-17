param([string]$ProjectName, [string]$Domain, [securestring]$AdminPassword, [securestring]$DnsheKey, [securestring]$DnsheSecret)
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

function Test-CloudflareAuth {
    if ($env:CLOUDFLARE_API_TOKEN) {
        $accountId = $env:CLOUDFLARE_ACCOUNT_ID
        if ($accountId -notmatch '^[a-fA-F0-9]{32}$') {
            throw 'API Token 模式需要设置 32 位的 CLOUDFLARE_ACCOUNT_ID。'
        }
        $headers = @{ Authorization = 'Bearer ' + $env:CLOUDFLARE_API_TOKEN }
        try {
            $accountsPage = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects?per_page=1" -Headers $headers -Method Get -TimeoutSec 8 -MaximumRedirection 0
            if (-not $accountsPage.success) { throw 'Cloudflare API 拒绝读取项目。' }
            return $true
        } catch {
            $responseProperty = $_.Exception.PSObject.Properties['Response']
            if ($responseProperty -and $responseProperty.Value -and [int]$responseProperty.Value.StatusCode -in @(401,403)) {
                throw 'Cloudflare 拒绝 API Token。请核对 Token、账号 ID 和 Pages 权限。'
            }
            throw 'Cloudflare API Token 验证失败。请核对账号 ID，并确认当前 VPN 环境可访问 Cloudflare API。'
        } finally { $headers.Clear() }
    }
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $tokenJson = & $nodeExe $wranglerJs auth token --json 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { return $false }
        $value = $tokenJson | ConvertFrom-Json
        return [bool]$value.token
    } catch { return $false }
    finally { $ErrorActionPreference = $prior; $tokenJson = $null; $value = $null }
}

function Attach-Domain([string]$Name, [string]$Project, [string]$DnsheKeyPlain, [string]$DnsheSecretPlain) {
    $oldPreference=$ErrorActionPreference
    try { $ErrorActionPreference='Continue'; $authJson = & $nodeExe $wranglerJs auth token --json 2>$null | Out-String; $authExit=$LASTEXITCODE }
    finally { $ErrorActionPreference=$oldPreference }
    if ($authExit -ne 0) { throw '无法取得 Cloudflare 授权，请重新登录。' }
    $auth = $authJson | ConvertFrom-Json
    if (-not $auth.token) { throw 'Cloudflare 授权方式不支持自动绑定域名。' }
    $headers = @{ Authorization = "Bearer $($auth.token)" }
    try {
        $accountId = $env:CLOUDFLARE_ACCOUNT_ID
        if (-not $accountId) {
            $accounts = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/accounts?per_page=50' -Headers $headers -Method Get
            if (-not $accounts.success) { throw '无法读取 Cloudflare 账号。' }
            $items = @($accounts.result)
            if ($items.Count -ne 1) { throw '当前登录关联多个 Cloudflare 账号，无法自动判断域名归属。请设置 CLOUDFLARE_ACCOUNT_ID 后重试。' }
            $accountId = $items[0].id
        }
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects/$Project/domains"
        $existing = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        if (-not @($existing.result | Where-Object { $_.name -eq $Name }).Count) {
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -ContentType 'application/json' -Body (@{name=$Name}|ConvertTo-Json -Compress)
            if (-not $response.success) { throw 'Cloudflare 拒绝绑定域名。' }
        }
        Write-Host "自定义域名 $Name 已提交 Pages 绑定。"
        & (Join-Path $root 'dnshe.ps1') -Domain $Name -Target "$Project.pages.dev" -ApiKey $DnsheKeyPlain -ApiSecret $DnsheSecretPlain
        if (-not $?) { throw 'DNSHE CNAME 创建失败。' }
        try { [void](Invoke-RestMethod -Uri "$uri/$Name" -Headers $headers -Method Patch) }
        catch { Write-Warning 'Cloudflare 域名验证重试请求未完成，稍后将继续检查状态。' }
        for ($i=0; $i -lt 6; $i++) {
            $check = Invoke-RestMethod -Uri "$uri/$Name" -Headers $headers -Method Get
            if ($check.result.status -eq 'active') { Write-Host "DNS 与证书验证完成：https://$Name/admin"; return }
            Start-Sleep -Seconds 5
        }
        Write-Host 'Cloudflare 正在签发证书或传播 DNS；稍后可直接访问自定义域名。生效前使用 pages.dev 地址。'
    } finally { $auth = $null; $authJson = $null; $headers = $null }
}

if (-not (Test-Path $nodeExe) -or -not (Test-Path $wranglerJs)) { throw '下载包缺少内置运行组件，请重新下载完整 ZIP。' }
if (-not $ProjectName) { $ProjectName = 'zijianjichang-' + ([guid]::NewGuid().ToString('N')).Substring(0,8) }
if ($ProjectName -notmatch '^[a-z0-9][a-z0-9-]{1,60}[a-z0-9]$') { throw '项目名格式无效。' }
if (-not $Domain) { $Domain = Read-Host 'DNSHE 完整域名' }
if ($Domain -and $Domain -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') { throw '域名格式无效。' }

if (-not $AdminPassword) { $AdminPassword = Read-Host '管理员密码（仅传给 Cloudflare，不保存）' -AsSecureString }
$admin = $AdminPassword
if ($admin.Length -lt 12) { throw '管理员密码至少 12 个字符。' }
$vendor = Join-Path $root 'vendor\edgetunnel'
if (-not (Test-Path (Join-Path $vendor '_worker.js'))) { throw '上游源码缺少 _worker.js。' }
if (-not (Test-Path (Join-Path $vendor 'LICENSE'))) { throw '上游源码缺少 LICENSE。' }
if ((Get-Item (Join-Path $vendor '_worker.js')).Length -lt 100000) { throw '包内 _worker.js 不完整，请重新下载应用包。' }
Write-Host "使用内置 edgetunnel 版本：$(Get-Content (Join-Path $vendor 'UPSTREAM_COMMIT') -Raw)"

$dir = Join-Path $env:TEMP ("zijianjichang-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    Copy-Item (Join-Path $vendor '_worker.js') (Join-Path $dir '_worker.js')
    Copy-Item (Join-Path $vendor 'LICENSE') (Join-Path $dir 'UPSTREAM-LICENSE')
    if (-not (Test-CloudflareAuth)) {
        throw 'Cloudflare 尚未授权。请回到应用第 3 步，点击“开始 Cloudflare 授权”，完成浏览器登录后再部署。'
    }
    if (-not $DnsheKey -or -not $DnsheSecret) { throw '缺少 DNSHE API Key 或 Secret。' }
    $oldPreference=$ErrorActionPreference
    try { $ErrorActionPreference='Continue'; $kvOut = & $nodeExe $wranglerJs kv namespace create "$ProjectName-KV" 2>&1 | Out-String; $kvExit=$LASTEXITCODE }
    finally { $ErrorActionPreference=$oldPreference }
    if ($kvExit -ne 0) { throw "KV 创建失败：$kvOut" }
    $match = [regex]::Match($kvOut, '(?m)["'']?id["'']?\s*[:=]\s*["'']([a-f0-9]{32})["'']')
    if (-not $match.Success) { throw "无法读取 KV ID，请在 Cloudflare 控制台核对：$kvOut" }
    $cfg = @{ name=$ProjectName; pages_build_output_dir='.'; compatibility_date=(Get-Date -Format 'yyyy-MM-dd'); kv_namespaces=@(@{binding='KV';id=$match.Groups[1].Value}) }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'wrangler.json') -Encoding utf8
    Push-Location $dir
    try {
        Run $nodeExe @($wranglerJs,'pages','project','create',$ProjectName,'--production-branch','main')
        $plain = [System.Net.NetworkCredential]::new('', $admin).Password
        try {
            Set-AdminSecret -Value $plain
        } finally { $plain = $null }
        Run $nodeExe @($wranglerJs,'pages','deploy','.','--project-name',$ProjectName,'--branch','main')
    } finally { Pop-Location }
    Write-Host "Pages 地址：https://$ProjectName.pages.dev/admin"
    if ($Domain) {
        $keyPlain=[System.Net.NetworkCredential]::new('',$DnsheKey).Password
        $secretPlain=[System.Net.NetworkCredential]::new('',$DnsheSecret).Password
        try { Attach-Domain -Name $Domain -Project $ProjectName -DnsheKeyPlain $keyPlain -DnsheSecretPlain $secretPlain }
        catch { Write-Output "__DOMAIN_WARNING__:$($_.Exception.Message)" }
        finally { $keyPlain=$null; $secretPlain=$null }
        Write-Host "自定义域名预期后台：https://$Domain/admin"
    }
    Write-Host '进入后台获取实际订阅路径，再运行 .\links.ps1 拼接完整订阅链接。'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
