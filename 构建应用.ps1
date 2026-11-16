# Build with Windows PowerShell 5.1 and the Windows .NET Framework compiler.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$output = Join-Path $root '自建机场.exe'
$temporary = Join-Path ([IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString('N')) + '.exe')
try {
    $source = [IO.File]::ReadAllText((Join-Path $root 'launcher\Launcher.cs'))
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies System.Windows.Forms -OutputAssembly $temporary -OutputType WindowsApplication
    Move-Item -LiteralPath $temporary -Destination $output -Force
    Write-Host "已生成：$output"
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
