param(
    [string]$Package = (Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenProxySetup-windows-x64-portable.zip'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenProxySetup-windows-x64-setup.exe')
)
$ErrorActionPreference = 'Stop'
$Package = (Resolve-Path -LiteralPath $Package).Path
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$icon = Join-Path $PSScriptRoot 'OpenProxySetup.ico'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$OutputPath" "/win32icon:$icon" "/resource:$Package,AppPayload" /reference:System.Windows.Forms.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'launcher\Setup.cs')
if ($LASTEXITCODE -ne 0) { throw "安装程序编译失败：$LASTEXITCODE" }
Write-Host $OutputPath
