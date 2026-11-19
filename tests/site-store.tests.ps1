$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'site-store.ps1')
$path = Join-Path ([IO.Path]::GetTempPath()) ('ops-site-' + [Guid]::NewGuid().ToString('N') + '.dat')
$testPassword = 'test-only-' + [Guid]::NewGuid().ToString('N') + '"中文'
try {
    Save-SavedSite 'https://example.test/admin' $testPassword $path
    $saved = Read-SavedSite $path
    if ($saved.url -ne 'https://example.test/admin' -or $saved.password -cne $testPassword) { throw 'Round-trip failed' }
    if ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).Contains($testPassword)) { throw 'Plaintext on disk' }
    Save-SavedSite 'https://updated.test/admin' 'second-test-password' $path
    if ((Read-SavedSite $path).url -ne 'https://updated.test/admin') { throw 'Atomic overwrite failed' }
    $bytes = [IO.File]::ReadAllBytes($path); $bytes[$bytes.Length-1] = $bytes[$bytes.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($path,$bytes)
    $rejected = $false
    try { [void](Read-SavedSite $path) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Tampered credentials accepted' }
    Remove-SavedSite $path
    if ((Read-SavedSite $path) -ne $null) { throw 'Deleted entry still available' }
    'PASS DPAPI round-trip, encrypted storage, overwrite, tamper rejection, deletion'
} finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
