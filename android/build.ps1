param(
    [Parameter(Mandatory = $true)][string]$Jdk,
    [Parameter(Mandatory = $true)][string]$BuildTools,
    [Parameter(Mandatory = $true)][string]$AndroidJar,
    [string]$SigningKey,
    [Parameter(Mandatory = $true)][string]$OutputApk,
    [string]$OAuthClientId = '9dace92fec31d3b3664761b971adfd53',
    [switch]$TestBuild
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ($OAuthClientId -and $OAuthClientId -notmatch '^[a-zA-Z0-9_-]{8,128}$') { throw 'Invalid Cloudflare OAuth client ID.' }
$releaseFingerprint = '0fc2bbaa2821d7b606dd90cf1319d55f508bca2ab3977ea87d0f70990f7b9585'
if (!$TestBuild) {
    if (!$SigningKey -or !(Test-Path -LiteralPath $SigningKey -PathType Leaf)) {
        throw 'Release build requires an existing signing keystore. Use -TestBuild for local diagnostics.'
    }
    if ([string]::IsNullOrEmpty($env:OPS_ANDROID_SIGNING_PASSWORD)) {
        throw 'Set OPS_ANDROID_SIGNING_PASSWORD before running a release build.'
    }
}
$vendor = Join-Path (Split-Path -Parent $root) 'vendor\edgetunnel'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ops-android-' + [Guid]::NewGuid().ToString('N'))
$classes = Join-Path $temp 'classes'
$assets = Join-Path $temp 'assets'
$dex = Join-Path $temp 'dex'
$onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'
$exe = if ($onWindows) { '.exe' } else { '' }
$batch = if ($onWindows) { '.bat' } else { '' }
$signer = Join-Path $BuildTools "apksigner$batch"
if ($TestBuild -and !$SigningKey) { $SigningKey = Join-Path $temp 'test-signing.p12' }
$SigningKey = [IO.Path]::GetFullPath($SigningKey)

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
    $keyAlias = 'ops-preview'
    $passwordSource = 'env:OPS_ANDROID_SIGNING_PASSWORD'
    if ($TestBuild) {
        $keyAlias = 'ops-test'
        $passwordSource = 'pass:android'
        if (!(Test-Path -LiteralPath $SigningKey -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $SigningKey) -Force | Out-Null
            Invoke-BuildTool (Join-Path $Jdk "bin/keytool$exe") @('-genkeypair','-keystore',$SigningKey,
                '-storetype','PKCS12','-storepass','android','-alias',$keyAlias,
                '-keyalg','RSA','-keysize','2048','-validity','365','-dname','CN=Open Proxy Setup Android Test')
        }
    }
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
    $oauthResource = Join-Path $temp 'res\values\oauth.xml'
    $oauthXml = '<resources><string name="cloudflare_oauth_client_id" translatable="false">' + $OAuthClientId + '</string></resources>'
    [IO.File]::WriteAllText($oauthResource, $oauthXml)

    $compiledRes = Join-Path $temp 'res.zip'
    $generated = Join-Path $temp 'generated'
    $unsigned = Join-Path $temp 'unsigned.apk'
    $aligned = Join-Path $temp 'aligned.apk'
    $aapt2 = Join-Path $BuildTools "aapt2$exe"
    Invoke-BuildTool $aapt2 @('compile','--dir',(Join-Path $temp 'res'),'-o',$compiledRes)
    Invoke-BuildTool $aapt2 @('link','-I',$AndroidJar,'--manifest',(Join-Path $temp 'AndroidManifest.xml'),
        '--java',$generated,'-A',$assets,'-o',$unsigned,$compiledRes)
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $temp 'src'),$generated -Recurse -Filter '*.java' -File |
        ForEach-Object FullName)
    Invoke-BuildTool (Join-Path $Jdk "bin/javac$exe") (@('--release','8','-encoding','UTF-8',
        '-classpath',$AndroidJar,'-d',$classes) + $sources)
    $classJar = Join-Path $temp 'classes.jar'
    Invoke-BuildTool (Join-Path $Jdk "bin/jar$exe") @('cf',$classJar,'-C',$classes,'.')
    Invoke-BuildTool (Join-Path $BuildTools "d8$batch") @('--lib',$AndroidJar,'--min-api','26','--output',$dex,$classJar)
    Invoke-BuildTool (Join-Path $Jdk "bin/jar$exe") @('uf',$unsigned,'-C',$dex,'classes.dex')
    Invoke-BuildTool (Join-Path $BuildTools "zipalign$exe") @('-f','4',$unsigned,$aligned)

    $output = [IO.Path]::GetFullPath($OutputApk)
    New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
    $signed = Join-Path $temp 'signed.apk'
    Invoke-BuildTool $signer @('sign','--ks',$SigningKey,'--ks-pass',$passwordSource,
        '--ks-key-alias',$keyAlias,'--v4-signing-enabled','false','--out',$signed,$aligned)
    $verification = Invoke-BuildTool $signer @('verify','--verbose','--print-certs',$signed)
    $fingerprints = @($verification | Select-String '^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value })
    if ($fingerprints.Count -ne 1 -or (!$TestBuild -and $fingerprints[0] -ne $releaseFingerprint) -or
            ($TestBuild -and $fingerprints[0] -eq $releaseFingerprint)) {
        throw 'APK signing certificate does not match the requested build mode.'
    }
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
