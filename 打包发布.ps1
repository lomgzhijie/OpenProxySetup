param([string]$OutputDirectory = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$portableZip = Join-Path $outputDirectory 'OpenProxySetup-windows-x64-portable.zip'
$cmdZip = Join-Path $outputDirectory 'OpenProxySetup-windows-x64-cmd-v1.4.2.zip'
& (Join-Path $root '构建应用.ps1')
$files=@('OpenProxySetup.ico','Cloudflare授权.cmd','app.ps1','site-store.ps1','site-browser.ps1','update.ps1','readme-view.ps1','deploy.ps1','dnshe.ps1','proxy.ps1','links.ps1','README.md','README.en.md','README.ja.md','README.ko.md','LICENSE')
foreach($file in $files){ if(-not(Test-Path (Join-Path $root $file))){throw "缺少文件：$file"} }
foreach($file in @('_worker.js','LICENSE','UPSTREAM_COMMIT')){if(-not(Test-Path (Join-Path $root "vendor\edgetunnel\$file"))){throw "缺少上游文件：$file"}}
foreach($file in @('node.exe','NODE-LICENSE','node_modules\wrangler\bin\wrangler.js')){if(-not(Test-Path (Join-Path $root "runtime\$file"))){throw "缺少运行组件：$file"}}
$sharedPaths=@($files | ForEach-Object {Join-Path $root $_}) + @((Join-Path $root 'vendor'),(Join-Path $root 'runtime'),(Join-Path $root 'assets'),(Join-Path $root 'launcher'))
$launcher = Join-Path $root 'OpenProxySetup.exe'
$launchScript = Join-Path $root '启动应用.cmd'
Compress-Archive -LiteralPath ($sharedPaths + @($launcher, $launchScript)) -DestinationPath $portableZip -Force
Write-Host "下载包已生成：$portableZip"

$stage = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$cmdEntry = Join-Path $stage 'OpenProxySetup.cmd'
try {
    Copy-Item -LiteralPath $launchScript -Destination $cmdEntry
    Compress-Archive -LiteralPath ($sharedPaths + @($cmdEntry)) -DestinationPath $cmdZip -Force
    Write-Host "下载包已生成：$cmdZip"
} finally {
    Remove-Item -LiteralPath $cmdEntry -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stage
}
