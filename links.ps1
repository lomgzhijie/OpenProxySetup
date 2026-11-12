param([string]$Domain, [string]$Path)
$ErrorActionPreference = 'Stop'
if (-not $Domain) { $Domain = Read-Host '已生效的自定义域名' }
if ($Domain -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') { throw '域名格式无效。' }
if (-not $Path) { $Path = Read-Host '从上游后台复制的订阅路径（含查询参数）' }
if (-not $Path.StartsWith('/')) { $Path = '/' + $Path }
if ($Path -match '[\s#]') { throw '订阅路径包含无效字符。' }
Write-Output "https://$Domain$Path"
