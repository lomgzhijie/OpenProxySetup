# Credentials are protected for the current Windows user, outside the install folder.
Add-Type -AssemblyName System.Security
function Get-SiteStorePath {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenProxySetup\site.dat'
}
function Save-SavedSite([string]$Url, [string]$Password, [string]$Path = (Get-SiteStorePath)) {
    $json = @{ version=1; url=$Url; password=$Password } | ConvertTo-Json -Compress
    $plain = [Text.Encoding]::UTF8.GetBytes($json)
    try {
        $cipher = [Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        $temporary = $Path + '.tmp'
        [IO.File]::WriteAllBytes($temporary,$cipher)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { [Array]::Clear($plain,0,$plain.Length) }
}
function Read-SavedSite([string]$Path = (Get-SiteStorePath)) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($Path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { return ([Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json) }
    finally { [Array]::Clear($plain,0,$plain.Length) }
}
function Remove-SavedSite([string]$Path = (Get-SiteStorePath)) {
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
}
function Get-RememberSite {
    $path = Join-Path (Split-Path -Parent (Get-SiteStorePath)) 'remember-site.txt'
    return (-not ([IO.File]::Exists($path) -and [IO.File]::ReadAllText($path).Trim() -eq 'no'))
}
function Set-RememberSite([bool]$Enabled) {
    $path = Join-Path (Split-Path -Parent (Get-SiteStorePath)) 'remember-site.txt'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $(if ($Enabled) { 'yes' } else { 'no' }))
    if (-not $Enabled) { Remove-SavedSite }
}
