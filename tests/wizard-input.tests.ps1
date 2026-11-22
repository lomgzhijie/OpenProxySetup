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
$source = $source.Replace("`nSet-TaskbarIdentity", "`n# No shell COM integration in hosted tests")
$source = $source.Replace('[Windows.Forms.Clipboard]::SetText(', '(Set-TestClipboardText ')
$source = $source.Replace('[Windows.Forms.Clipboard]::GetText()', '[string]$global:opsWizardTestClipboard')
$source = $source.Replace('[Windows.Forms.Clipboard]::ContainsText()', '(![string]::IsNullOrEmpty($global:opsWizardTestClipboard))')
# Exercise the account selection controls without a modal desktop on hosted runners.
$source = $source.Replace('$picker.ShowDialog($form)',
    '$( $options.SelectedIndex = 1; [Windows.Forms.DialogResult]::OK )')
$source = $source.Replace("'OpenProxySetup\theme.txt'", ("'" + [guid]::NewGuid().ToString('N') + "\theme.txt'"))

try {
    $script:clipboardLocked = $false
    function Invoke-TestClick([Windows.Forms.Button]$Button) {
        if (!$Button) { throw 'Missing test button' }
        $onClick = [Windows.Forms.Button].GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
        [void]$onClick.Invoke($Button, @([EventArgs]::Empty))
    }
    function Set-TestClipboardText([string]$Text) {
        if ($script:clipboardLocked) { throw 'Test clipboard is locked' }
        $global:opsWizardTestClipboard = $Text
    }
    foreach ($checkpoint in @('Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing', '$form = New-Object OpenProxySetupWindow', '$form.ClientSize =', '$header =', '$script:cloudflareVerified = $false', '$managePage =', '$readmePage =', '$initialSection =')) {
        $source = $source.Replace($checkpoint, ("Write-Host 'Wizard initialization: " + $checkpoint.Replace("'", "''") + "'`n" + $checkpoint))
    }
    Write-Host 'Loading wizard source for handler regression'
    . ([scriptblock]::Create($source))
    if (-not ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12)) {
        throw 'TLS 1.2 is not enabled'
    }
    function Start-AppUpdateCheck { }
    Write-Host 'Wizard controls initialized without a desktop window'
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
    Write-Host 'Account selection regression passed'
    foreach ($value in @(' example.com ', 'https://EXAMPLE.com/admin/', 'http://example.com/')) {
        if ((Normalize-DeploymentDomain $value) -ne 'example.com') { throw 'Domain cleanup failed' }
    }
    $generate = $deployCard.Controls | Where-Object Text -eq '生成强密码'
    Invoke-TestClick $generate
    if ($password.Text.Length -ne 20 -or $password.Text -cnotmatch '[A-Z]' -or
            $password.Text -cnotmatch '[a-z]' -or $password.Text -notmatch '[0-9]') { throw 'Password generator failed' }
    $domain.Text = 'old.example'
    Set-TestClipboardText " https://example.com/admin/`r`n"
    $paste = $deployCard.Controls | Where-Object { $_.Text -eq '粘贴' -and $_.Top -eq $domain.Top }
    Invoke-TestClick $paste
    if ($domain.Text -ne 'example.com') { throw 'Paste failed to replace and normalize the entire domain field' }
    Set-TestClipboardText ' password-with-spaces '
    $paste = $deployCard.Controls | Where-Object { $_.Text -eq '粘贴' -and $_.Top -eq $password.Top }
    Invoke-TestClick $paste
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
    Invoke-TestClick ($progressCard.Controls | Where-Object Text -eq '复制诊断信息')
    $report = $global:opsWizardTestClipboard
    if ($report -notlike '*HTTP 503*' -or $report -like '*private-fixture*' -or $report -like '*private-password*') {
        throw 'Diagnostic copy included raw credentials or omitted the error category'
    }
    if ($progress.Text -ne '诊断信息已复制。') { throw 'Diagnostic copy success feedback missing' }
    $script:deployment.FailedStep = 0
    Invoke-TestClick ($progressCard.Controls | Where-Object Text -eq '复制诊断信息')
    $report = $global:opsWizardTestClipboard
    if ($report -notlike '*未记录失败*' -or $report -like '*服务请求失败*') { throw 'No-failure diagnostic was misleading' }
    $script:clipboardLocked = $true
    Invoke-TestClick ($progressCard.Controls | Where-Object Text -eq '复制诊断信息')
    if ($progress.Text -ne '暂时无法访问剪贴板，请重试。') { throw 'Diagnostic clipboard error feedback missing' }
    Show-WizardPage $managePage
    [void]$siteList.Items.Add([pscustomobject]@{url='https://example.test/admin';Domain='example.test';Display='example.test'})
    $siteList.SelectedIndex = 0
    Invoke-TestClick ($manageCard.Controls | Where-Object Text -eq '复制网址')
    if ($manageStatus.Text -ne '暂时无法访问剪贴板，请重试。') { throw 'URL clipboard error feedback missing' }
    Show-WizardPage $deployPage
    Invoke-TestClick ($deployCard.Controls | Where-Object Text -eq '复制密码')
    if ($deployHint.Text -ne '暂时无法访问剪贴板，请重试。') { throw 'Password clipboard error feedback missing' }
    $script:clipboardLocked = $false
    $script:pagesOnlyInvoked = $false
    function Start-Deployment([switch]$PagesOnly) { $script:pagesOnlyInvoked = [bool]$PagesOnly }
    Invoke-TestClick ($deployCard.Controls | Where-Object Text -eq '暂时只发布 Pages')
    if (-not $script:pagesOnlyInvoked) { throw 'Pages-only entry point failed' }
    'PASS Windows generator, domain normalization, clipboard replacement, account chooser, safe diagnostics and Pages-only entry point'
} finally {
    if ($form) { $form.Close(); $form.Dispose() }
    Remove-Variable opsWizardTestClipboard -Scope Global -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($temporary)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP) + '\',[StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
