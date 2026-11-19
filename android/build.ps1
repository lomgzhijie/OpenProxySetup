param(
    [Parameter(Mandatory = $true)][string]$Jdk,
    [Parameter(Mandatory = $true)][string]$BuildTools,
    [Parameter(Mandatory = $true)][string]$AndroidJar,
    [Parameter(Mandatory = $true)][string]$PreviewKey,
    [Parameter(Mandatory = $true)][string]$OutputApk
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$vendor = Join-Path (Split-Path -Parent $root) 'vendor\edgetunnel'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ops-android-' + [Guid]::NewGuid().ToString('N'))
$classes = Join-Path $temp 'classes'
$assets = Join-Path $temp 'assets'
$dex = Join-Path $temp 'dex'

function Invoke-BuildTool([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable exited with code $LASTEXITCODE."
    }
}

$previousJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $Jdk
    New-Item -ItemType Directory -Path $classes,$assets,$dex -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $root) 'assets\admin-theme.js') -Destination $assets
    foreach ($file in '_worker.js','LICENSE','UPSTREAM_COMMIT') {
        Copy-Item -LiteralPath (Join-Path $vendor $file) -Destination $assets
    }
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $root) 'LICENSE') -Destination (Join-Path $assets 'LICENSE-MIT')
    foreach ($file in 'README.md','README.en.md','README.ja.md','README.ko.md') {
        Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $root) $file) -Destination $assets
    }
    # Some Windows SDK binaries cannot open input paths with non-ASCII characters.
    foreach ($entry in 'src','res','AndroidManifest.xml') {
        Copy-Item -LiteralPath (Join-Path $root $entry) -Destination $temp -Recurse
    }

    $compiledRes = Join-Path $temp 'res.zip'
    $generated = Join-Path $temp 'generated'
    $unsigned = Join-Path $temp 'unsigned.apk'
    $aligned = Join-Path $temp 'aligned.apk'
    $aapt2 = Join-Path $BuildTools 'aapt2.exe'
    Invoke-BuildTool $aapt2 @('compile','--dir',(Join-Path $temp 'res'),'-o',$compiledRes)
    Invoke-BuildTool $aapt2 @('link','-I',$AndroidJar,'--manifest',(Join-Path $temp 'AndroidManifest.xml'),
        '--java',$generated,'-A',$assets,'-o',$unsigned,$compiledRes)
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $temp 'src'),$generated -Recurse -Filter '*.java' -File |
        ForEach-Object FullName)
    Invoke-BuildTool (Join-Path $Jdk 'bin\javac.exe') (@('--release','8','-encoding','UTF-8',
        '-classpath',$AndroidJar,'-d',$classes) + $sources)
    $classJar = Join-Path $temp 'classes.jar'
    Invoke-BuildTool (Join-Path $Jdk 'bin\jar.exe') @('cf',$classJar,'-C',$classes,'.')
    Invoke-BuildTool (Join-Path $BuildTools 'd8.bat') @('--lib',$AndroidJar,'--min-api','26','--output',$dex,$classJar)
    Invoke-BuildTool (Join-Path $Jdk 'bin\jar.exe') @('uf',$unsigned,'-C',$dex,'classes.dex')
    Invoke-BuildTool (Join-Path $BuildTools 'zipalign.exe') @('-f','4',$unsigned,$aligned)

    if (!(Test-Path -LiteralPath $PreviewKey)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $PreviewKey) -Force | Out-Null
        Invoke-BuildTool (Join-Path $Jdk 'bin\keytool.exe') @('-genkeypair','-keystore',$PreviewKey,
            '-storetype','PKCS12','-storepass','android','-alias','ops-preview','-keypass','android',
            '-keyalg','RSA','-keysize','2048','-validity','10000','-dname','CN=Open Proxy Setup Android Preview')
    }
    $output = [IO.Path]::GetFullPath($OutputApk)
    New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
    $signed = Join-Path $temp 'signed.apk'
    $signer = Join-Path $BuildTools 'apksigner.bat'
    Invoke-BuildTool $signer @('sign','--ks',$PreviewKey,'--ks-pass','pass:android',
        '--ks-key-alias','ops-preview','--v4-signing-enabled','false','--out',$signed,$aligned)
    Invoke-BuildTool $signer @('verify','--verbose',$signed)
    Copy-Item -LiteralPath $signed -Destination $output -Force
    Get-FileHash -LiteralPath $output -Algorithm SHA256
} finally {
    $env:JAVA_HOME = $previousJavaHome
    if (Test-Path -LiteralPath $temp -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $temp).Path
        if ([string]::Equals($resolved, $temp, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
