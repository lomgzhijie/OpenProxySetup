param(
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$ApiKey,
    [Parameter(Mandatory)][string]$ApiSecret
)
$ErrorActionPreference = 'Stop'

function Invoke-Dnshe([string]$Endpoint, [string]$Action, [string]$Method = 'Get', [object]$Body = $null, [string]$Query = '') {
    $uri = "https://api005.dnshe.com/index.php?m=domain_hub&endpoint=$Endpoint&action=$Action$Query"
    $headers = @{'X-API-Key'=$ApiKey; 'X-API-Secret'=$ApiSecret}
    $request = @{Uri=$uri; Headers=$headers; Method=$Method; TimeoutSec=30}
    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = $Body | ConvertTo-Json -Compress
    }
    try { $response = Invoke-RestMethod @request }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { '网络错误' }
        throw "DNSHE $Endpoint/$Action 请求失败（$status）。请检查授权和网络。"
    }
    if (-not $response.success) { throw "DNSHE $Endpoint/$Action 失败：$($response.message)" }
    return $response
}

$owned = @()
$page = 1
do {
    $list = Invoke-Dnshe 'subdomains' 'list' 'Get' $null "&page=$page&per_page=200"
    $owned += @($list.subdomains | Where-Object { $_.full_domain -ieq $Domain })
    if ($owned.Count -gt 0) { break }
    $count = @($list.subdomains).Count
    $page++
} while ($count -eq 200 -and $page -le 20)
if ($owned.Count -ne 1) { throw 'DNSHE API 中找不到该域名；请确认完整域名和授权账号。' }

$id = $owned[0].id
$records = Invoke-Dnshe 'dns_records' 'list' 'Get' $null "&subdomain_id=$id"
$atApex = @($records.records | Where-Object { $_.name.TrimEnd('.') -ieq $Domain.TrimEnd('.') })
$same = @($atApex | Where-Object { $_.type -eq 'CNAME' -and $_.content.TrimEnd('.') -ieq $Target.TrimEnd('.') })
if ($same.Count -eq 1 -and $atApex.Count -eq 1) {
    Write-Host "DNSHE CNAME 已存在：$Domain -> $Target"
    return
}
if ($atApex.Count -gt 0) {
    throw "DNSHE 域名 $Domain 已有记录，脚本不会覆盖。请在 DNSHE 检查该域名的 DNS 记录。"
}

$created = Invoke-Dnshe 'dns_records' 'create' 'Post' @{subdomain_id=$id; type='CNAME'; name='@'; content=$Target; ttl=600}
Write-Host "DNSHE CNAME 已创建：$Domain -> $Target；记录 ID：$($created.id)"
