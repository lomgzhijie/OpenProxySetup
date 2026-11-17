# Build with Windows PowerShell 5.1 and the Windows .NET Framework compiler.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$output = Join-Path $root 'OpenProxySetup.exe'
$temporary = Join-Path ([IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString('N')) + '.exe')
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$source = Join-Path $root 'launcher\Launcher.cs'
$icon = Join-Path $root 'OpenProxySetup.ico'
try {
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$temporary" "/win32icon:$icon" /reference:System.Windows.Forms.dll $source
    if ($LASTEXITCODE -ne 0) { throw "应用编译失败：$LASTEXITCODE" }
    Move-Item -LiteralPath $temporary -Destination $output -Force
    Write-Host "已生成：$output"
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
