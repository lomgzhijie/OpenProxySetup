$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'site-store.ps1')
$path = Join-Path ([IO.Path]::GetTempPath()) ('ops-site-' + [Guid]::NewGuid().ToString('N') + '.dat')
$testPassword = 'test-only-' + [Guid]::NewGuid().ToString('N') + '"中文'
try {
    $legacy = [Text.Encoding]::UTF8.GetBytes('{"version":1,"url":"https://legacy.test/admin","password":"legacy-password"}')
    [IO.File]::WriteAllBytes($path,[Security.Cryptography.ProtectedData]::Protect($legacy,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
    if (@(Get-SavedSites $path).Count -ne 1) { throw 'Legacy site not restored' }
    Save-SavedSite 'https://new.test/admin' 'new-password' $path
    if (@(Get-SavedSites $path).Count -ne 2 -or -not (Get-SavedSites $path | Where-Object password -eq 'legacy-password')) { throw 'Legacy migration lost credentials' }
    Remove-SavedSite $path
    Save-SavedSite 'https://example.test/admin' $testPassword $path
    $saved = Read-SavedSite $path
    if ($saved.url -ne 'https://example.test/admin' -or $saved.password -cne $testPassword) { throw 'Round-trip failed' }
    if ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).Contains($testPassword)) { throw 'Plaintext on disk' }
    Save-SavedSite 'https://updated.test/admin' 'second-test-password' $path
    if ((Read-SavedSite $path).url -ne 'https://updated.test/admin') { throw 'Atomic overwrite failed' }
    if (@(Get-SavedSites $path).Count -ne 2) { throw 'Multiple sites not preserved' }
    Save-SavedSite 'https://example.test/admin' 'edited-password' $path
    if (@(Get-SavedSites $path).Count -ne 2) { throw 'Duplicate site created' }
    Remove-SiteEntry 'https://updated.test/admin' $path
    if (@(Get-SavedSites $path).Count -ne 1 -or (Read-SavedSite $path).password -ne 'edited-password') { throw 'Removing a site affected another entry' }
    Save-SavedSite 'https://renamed.test/admin' 'edited-password' $path 'https://example.test/admin'
    if (@(Get-SavedSites $path).Count -ne 1 -or (Read-SavedSite $path).url -ne 'https://renamed.test/admin') { throw 'Renaming a site failed' }
    $bytes = [IO.File]::ReadAllBytes($path); $bytes[$bytes.Length-1] = $bytes[$bytes.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($path,$bytes)
    $rejected = $false
    try { [void](Read-SavedSite $path) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Tampered credentials accepted' }
    Remove-SavedSite $path
    if ((Read-SavedSite $path) -ne $null) { throw 'Deleted entry still available' }
    'PASS DPAPI round-trip, encrypted storage, overwrite, tamper rejection, deletion'
} finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
