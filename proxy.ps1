$settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
    $server = [string]$settings.ProxyServer
    if ($server -match '(?:^|;)https=([^;]+)') { $server = $Matches[1] }
    elseif ($server -match '(?:^|;)http=([^;]+)') { $server = $Matches[1] }
    elseif ($server -match '=') { $server = '' }
    if ($server -and $server -notmatch '^https?://') { $server = 'http://' + $server }
    if ($server -match '^https?://[a-zA-Z0-9.\-\[\]:]+$') {
        $env:HTTP_PROXY = $server
        $env:HTTPS_PROXY = $server
        $env:NO_PROXY = 'localhost,127.0.0.1,::1'
    }
}
