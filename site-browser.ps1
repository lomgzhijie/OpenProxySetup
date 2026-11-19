function New-SiteBrowser {
    if (-not ('OpenProxySetupBrowser' -as [type])) {
        $sdk = Join-Path $PSScriptRoot 'runtime\webview2'
        [void][Reflection.Assembly]::LoadFrom((Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'))
        [void][Reflection.Assembly]::LoadFrom((Join-Path $sdk 'Microsoft.Web.WebView2.WinForms.dll'))
        Add-Type -Path @((Join-Path $PSScriptRoot 'launcher\SiteAuth.cs'),(Join-Path $PSScriptRoot 'launcher\SiteBrowser.cs')) -ReferencedAssemblies @(
            'System.Windows.Forms','System.Drawing','System.Web.Extensions','System.Net.Http',
            (Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'),
            (Join-Path $sdk 'Microsoft.Web.WebView2.WinForms.dll'))
    }
    return (New-Object OpenProxySetupBrowser -ArgumentList $PSScriptRoot)
}
