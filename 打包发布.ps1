$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$out=Join-Path (Split-Path -Parent $root) 'OpenProxySetup-windows-x64-portable.zip'
& (Join-Path $root '构建应用.ps1')
$files=@('OpenProxySetup.exe','启动应用.cmd','Cloudflare授权.cmd','app.ps1','deploy.ps1','dnshe.ps1','proxy.ps1','links.ps1','README.md','README.en.md','README.ja.md','README.ko.md','LICENSE')
foreach($file in $files){ if(-not(Test-Path (Join-Path $root $file))){throw "缺少文件：$file"} }
foreach($file in @('_worker.js','LICENSE','UPSTREAM_COMMIT')){if(-not(Test-Path (Join-Path $root "vendor\edgetunnel\$file"))){throw "缺少上游文件：$file"}}
foreach($file in @('node.exe','NODE-LICENSE','node_modules\wrangler\bin\wrangler.js')){if(-not(Test-Path (Join-Path $root "runtime\$file"))){throw "缺少运行组件：$file"}}
$paths=@($files | ForEach-Object {Join-Path $root $_}) + @((Join-Path $root 'vendor'),(Join-Path $root 'runtime'))
Compress-Archive -LiteralPath $paths -DestinationPath $out -Force
Write-Host "下载包已生成：$out"
