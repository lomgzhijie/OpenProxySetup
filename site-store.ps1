# Credentials are protected for the current Windows user, outside the install folder.
Add-Type -AssemblyName System.Security
function Get-SiteStorePath {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenProxySetup\site.dat'
}
function Write-SavedSites([object[]]$Sites, [string]$Path = (Get-SiteStorePath)) {
    $json = @{ version=2; sites=@($Sites) } | ConvertTo-Json -Compress -Depth 4
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
function Get-SavedSites([string]$Path = (Get-SiteStorePath)) {
    if (-not [IO.File]::Exists($Path)) { return }
    $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($Path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        $data = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
        if ($data.version -eq 2) { return ($data.sites | Where-Object { $_ -and $_.url }) }
        if ($data.url) { return ([pscustomobject]@{url=$data.url; password=$data.password}) }
    }
    finally { [Array]::Clear($plain,0,$plain.Length) }
}
function Save-SavedSite([string]$Url, [string]$Password, [string]$Path = (Get-SiteStorePath), [string]$PreviousUrl = '') {
    $sites = @([pscustomobject]@{ url=$Url; password=$Password }) + @(Get-SavedSites $Path | Where-Object { $_ -and $_.url -ne $Url -and $_.url -ne $PreviousUrl })
    Write-SavedSites $sites $Path
}
function Read-SavedSite([string]$Path = (Get-SiteStorePath)) {
    $sites = @(Get-SavedSites $Path)
    if ($sites.Count) { return $sites[0] }
}
function Remove-SiteEntry([string]$Url, [string]$Path = (Get-SiteStorePath)) {
    Write-SavedSites @(Get-SavedSites $Path | Where-Object { $_.url -ne $Url }) $Path
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
