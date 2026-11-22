$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path $env:TEMP ('ops-wizard-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$source = [IO.File]::ReadAllText((Join-Path $root 'app.ps1'))
$source = $source.Replace('$PSScriptRoot', ("'" + $root.Replace("'","''") + "'"))
$storeLine = ". (Join-Path '" + $root.Replace("'","''") + "' 'site-store.ps1')"
$isolatedPath = Join-Path $temporary 'site.dat'
$source = $source.Replace($storeLine, $storeLine + [Environment]::NewLine +
    "function Get-SiteStorePath { '" + $isolatedPath.Replace("'","''") + "' }")
$source = $source.Replace('[void]$form.ShowDialog()', '')
$source = $source.Replace('[Windows.Forms.Clipboard]::SetText(', '(Set-TestClipboardText ')
$source = $source.Replace('$picker.AcceptButton = $confirm',
    '$picker.AcceptButton = $confirm; $picker.add_Shown({ $options.SelectedIndex = 1; $confirm.PerformClick() })')
$source = $source.Replace("'OpenProxySetup\theme.txt'", ("'" + [guid]::NewGuid().ToString('N') + "\theme.txt'"))

try {
    $script:clipboardLocked = $false
    function Set-TestClipboardText([string]$Text) {
        if ($script:clipboardLocked) { throw 'Test clipboard is locked' }
        [Windows.Forms.Clipboard]::SetText($Text)
    }
    . ([scriptblock]::Create($source))
    if (-not ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12)) {
        throw 'TLS 1.2 is not enabled'
    }
    function Start-AppUpdateCheck { }
    $form.Show()
    Show-WizardPage $deployPage
    $script:deployment = $null
    $env:CLOUDFLARE_ACCOUNT_ID = $null
    function Invoke-RestMethod($Uri,$Headers,$TimeoutSec) {
        if ($Headers.Authorization -ne 'Bearer fixture-token') { throw 'Account credentials not forwarded' }
        return [pscustomobject]@{success=$true;result=@(
            [pscustomobject]@{name='first';id=('0'*31+'1')},
            [pscustomobject]@{name='second';id=('0'*31+'2')}
        )}
    }
    $selected = Select-CloudflareAccount 'fixture-token'
    if ($selected.name -ne 'second') { throw 'Account chooser did not use the selected account' }
    [Windows.Forms.Application]::DoEvents()
    foreach ($value in @(' example.com ', 'https://EXAMPLE.com/admin/', 'http://example.com/')) {
        if ((Normalize-DeploymentDomain $value) -ne 'example.com') { throw 'Domain cleanup failed' }
    }
    $generate = $deployCard.Controls | Where-Object Text -eq '生成强密码'
    $generate.PerformClick()
    if ($password.Text.Length -ne 20 -or $password.Text -cnotmatch '[A-Z]' -or
            $password.Text -cnotmatch '[a-z]' -or $password.Text -notmatch '[0-9]') { throw 'Password generator failed' }
    $domain.Text = 'old.example'
    [Windows.Forms.Clipboard]::SetText(" https://example.com/admin/`r`n")
    $paste = $deployCard.Controls | Where-Object { $_.Text -eq '粘贴' -and $_.Top -eq $domain.Top }
    $paste.PerformClick()
    if ($domain.Text -ne 'example.com') { throw 'Paste failed to replace and normalize the entire domain field' }
    [Windows.Forms.Clipboard]::SetText(' password-with-spaces ')
    $paste = $deployCard.Controls | Where-Object { $_.Text -eq '粘贴' -and $_.Top -eq $password.Top }
    $paste.PerformClick()
    if ($password.Text -cne ' password-with-spaces ') { throw 'Paste changed the password' }
    if ($env:OPS_WIZARD_SCREENSHOT) {
        $image = New-Object Drawing.Bitmap($form.Width,$form.Height)
        try {
            $form.DrawToBitmap($image,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
            $image.Save($env:OPS_WIZARD_SCREENSHOT,[Drawing.Imaging.ImageFormat]::Png)
        } finally { $image.Dispose() }
    }
    Show-WizardPage $progressPage
    $script:deployment = @{FailedStep=3;PagesReady=$false;DomainActive=$false}
    $progressDetail.Text = 'HTTP 503 token=private-fixture password=private-password'
    ($progressCard.Controls | Where-Object Text -eq '复制诊断信息').PerformClick()
    $report = [Windows.Forms.Clipboard]::GetText()
    if ($report -notlike '*HTTP 503*' -or $report -like '*private-fixture*' -or $report -like '*private-password*') {
        throw 'Diagnostic copy included raw credentials or omitted the error category'
    }
    if ($progress.Text -ne '诊断信息已复制。') { throw 'Diagnostic copy success feedback missing' }
    $script:deployment.FailedStep = 0
    ($progressCard.Controls | Where-Object Text -eq '复制诊断信息').PerformClick()
    $report = [Windows.Forms.Clipboard]::GetText()
    if ($report -notlike '*未记录失败*' -or $report -like '*服务请求失败*') { throw 'No-failure diagnostic was misleading' }
    $script:clipboardLocked = $true
    ($progressCard.Controls | Where-Object Text -eq '复制诊断信息').PerformClick()
    if ($progress.Text -ne '暂时无法访问剪贴板，请重试。') { throw 'Diagnostic clipboard error feedback missing' }
    Show-WizardPage $managePage
    [void]$siteList.Items.Add([pscustomobject]@{url='https://example.test/admin';Domain='example.test';Display='example.test'})
    $siteList.SelectedIndex = 0
    ($manageCard.Controls | Where-Object Text -eq '复制网址').PerformClick()
    if ($manageStatus.Text -ne '暂时无法访问剪贴板，请重试。') { throw 'URL clipboard error feedback missing' }
    Show-WizardPage $deployPage
    ($deployCard.Controls | Where-Object Text -eq '复制密码').PerformClick()
    if ($deployHint.Text -ne '暂时无法访问剪贴板，请重试。') { throw 'Password clipboard error feedback missing' }
    $script:clipboardLocked = $false
    $script:pagesOnlyInvoked = $false
    function Start-Deployment([switch]$PagesOnly) { $script:pagesOnlyInvoked = [bool]$PagesOnly }
    ($deployCard.Controls | Where-Object Text -eq '暂时只发布 Pages').PerformClick()
    if (-not $script:pagesOnlyInvoked) { throw 'Pages-only entry point failed' }
    'PASS Windows generator, domain normalization, clipboard replacement, account chooser, safe diagnostics and Pages-only entry point'
} finally {
    if ($form) { $form.Close(); $form.Dispose() }
    [Windows.Forms.Clipboard]::Clear()
    $resolved = [IO.Path]::GetFullPath($temporary)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP) + '\',[StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
