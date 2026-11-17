# Windows PowerShell 5.1 desktop wizard. Keep this file UTF-8 with BOM.
$ErrorActionPreference = 'Stop'
$deployScript = Join-Path $PSScriptRoot 'deploy.ps1'
$bundledNode = Join-Path $PSScriptRoot 'runtime\node.exe'
$bundledWrangler = Join-Path $PSScriptRoot 'runtime\node_modules\wrangler\bin\wrangler.js'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class OpenProxySetupWindow : Form
{
    private Rectangle normalBounds;

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            const int resizeAndSystemMenu = 0x000F0000;
            parameters.Style |= resizeAndSystemMenu;
            return parameters;
        }
    }

    public void MoveFromHeader()
    {
        Point cursor = Cursor.Position;
        int position = (cursor.X & 0xffff) | ((cursor.Y & 0xffff) << 16);
        ReleaseCapture();
        SendMessage(Handle, 0xA1, new IntPtr(2), new IntPtr(position)); // WM_NCLBUTTONDOWN, HTCAPTION
    }

    public void ToggleMaximized()
    {
        if (WindowState == FormWindowState.Maximized)
        {
            WindowState = FormWindowState.Normal;
            if (!normalBounds.IsEmpty) Bounds = normalBounds;
        }
        else
        {
            normalBounds = Bounds;
            MaximizedBounds = Screen.FromControl(this).WorkingArea;
            WindowState = FormWindowState.Maximized;
        }
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x83) // WM_NCCALCSIZE
        {
            message.Result = IntPtr.Zero;
            return;
        }
        base.WndProc(ref message);
        if (message.Msg != 0x84) return; // WM_NCHITTEST

        long packed = message.LParam.ToInt64();
        Point point = PointToClient(new Point((short)packed, (short)(packed >> 16)));
        int hit = 1; // HTCLIENT
        if (WindowState == FormWindowState.Normal)
        {
            const int grip = 7;
            bool left = point.X < grip;
            bool right = point.X >= ClientSize.Width - grip;
            if (point.Y < grip) hit = left ? 13 : right ? 14 : 12;
            else if (point.Y >= ClientSize.Height - grip) hit = left ? 16 : right ? 17 : 15;
            else if (left) hit = 10;
            else if (right) hit = 11;
        }
        message.Result = new IntPtr(hit);
    }
}
'@

$form = New-Object OpenProxySetupWindow
$form.FormBorderStyle = 'None'
$form.Text = 'Open Proxy Setup'
$proxyScript = Join-Path $PSScriptRoot 'proxy.ps1'
. $proxyScript

$theme = @{
    Background = [Drawing.ColorTranslator]::FromHtml('#F6F8FC')
    Ink = [Drawing.ColorTranslator]::FromHtml('#14213B')
    Blue = [Drawing.ColorTranslator]::FromHtml('#244ED8')
    BlueHover = [Drawing.ColorTranslator]::FromHtml('#193CAE')
    PaleBlue = [Drawing.ColorTranslator]::FromHtml('#EDF2FF')
    Line = [Drawing.ColorTranslator]::FromHtml('#DCE5F2')
    Muted = [Drawing.ColorTranslator]::FromHtml('#485771')
    Green = [Drawing.ColorTranslator]::FromHtml('#216449')
    Red = [Drawing.ColorTranslator]::FromHtml('#9E2C32')
    White = [Drawing.Color]::White
}
$form.ClientSize = New-Object Drawing.Size(900,670)
$form.MinimumSize = New-Object Drawing.Size(863,630)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.BackColor = $theme.Background
$form.ForeColor = $theme.Ink
$iconPath = Join-Path $PSScriptRoot 'OpenProxySetup.ico'
if (Test-Path -LiteralPath $iconPath) {
    $form.Icon = [Drawing.Icon]::new($iconPath)
}

function New-RoundedPath([int]$width, [int]$height, [int]$radius) {
    $diameter = 2 * $radius
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0,0,$diameter,$diameter,180,90)
    $path.AddArc(($width-$diameter),0,$diameter,$diameter,270,90)
    $path.AddArc(($width-$diameter),($height-$diameter),$diameter,$diameter,0,90)
    $path.AddArc(0,($height-$diameter),$diameter,$diameter,90,90)
    $path.CloseFigure()
    return $path
}

function Add-Card($parent, [int]$x, [int]$y, [int]$w, [int]$h, [Drawing.Color]$fill, [int]$radius = 16) {
    $card = New-Object Windows.Forms.Panel
    $card.Bounds = New-Object Drawing.Rectangle($x,$y,$w,$h)
    $card.BackColor = [Drawing.Color]::Transparent
    $card.Tag = @{ Fill = $fill; Radius = $radius; Line = $theme.Line }
    $card.add_Paint({
        param($sender, $event)
        $path = New-RoundedPath ($sender.Width-1) ($sender.Height-1) $sender.Tag.Radius
        $brush = New-Object Drawing.SolidBrush($sender.Tag.Fill)
        $border = New-Object Drawing.Pen($sender.Tag.Line)
        try {
            $event.Graphics.SmoothingMode = 'AntiAlias'
            $event.Graphics.FillPath($brush,$path)
            $event.Graphics.DrawPath($border,$path)
        } finally { $border.Dispose(); $brush.Dispose(); $path.Dispose() }
    })
    $parent.Controls.Add($card)
    return $card
}

function Add-Text($parent,[string]$value,[int]$x,[int]$y,[int]$w,[int]$h) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $value
    $label.Bounds = New-Object Drawing.Rectangle($x,$y,$w,$h)
    $label.UseMnemonic = $false
    $parent.Controls.Add($label)
    return $label
}

function Add-Heading($parent,[string]$value,[int]$x,[int]$y,[int]$w,[int]$h,[int]$points = 20) {
    $label = Add-Text $parent $value $x $y $w $h
    $label.Font = New-Object Drawing.Font($form.Font.FontFamily,$points,[Drawing.FontStyle]::Bold)
    return $label
}

function Add-Link($parent,[string]$value,[string]$url,[int]$x,[int]$y,[int]$width = 760) {
    $link = New-Object Windows.Forms.LinkLabel
    $link.Text = $value
    $link.Bounds = New-Object Drawing.Rectangle($x,$y,$width,30)
    $link.LinkColor = $theme.Blue
    $link.ActiveLinkColor = $theme.BlueHover
    $link.LinkBehavior = 'HoverUnderline'
    $link.Tag = $url
    $link.add_LinkClicked({ if ($this.Tag) { Start-Process -FilePath $this.Tag } })
    $parent.Controls.Add($link)
    return $link
}

function Set-ButtonStyle($button, [bool]$primary = $false) {
    $button.FlatStyle = 'Flat'
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = if ($primary) { $theme.Blue } else { $theme.White }
    $button.ForeColor = if ($primary) { $theme.White } else { $theme.Blue }
    $button.FlatAppearance.BorderColor = if ($primary) { $theme.Blue } else { $theme.Line }
    $button.FlatAppearance.MouseOverBackColor = if ($primary) { $theme.BlueHover } else { $theme.PaleBlue }
    $button.FlatAppearance.MouseDownBackColor = $button.FlatAppearance.MouseOverBackColor
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    $path = New-RoundedPath $button.Width $button.Height 8
    try { $button.Region = New-Object Drawing.Region($path) }
    finally { $path.Dispose() }
}

function Add-Action($page, [string]$caption, [int]$x, [int]$y, [int]$width, [scriptblock]$action, [bool]$primary = $false) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $caption
    $button.Bounds = New-Object Drawing.Rectangle($x,$y,$width,40)
    Set-ButtonStyle $button $primary
    $button.add_Click($action)
    $page.Controls.Add($button)
}

$header = New-Object Windows.Forms.Panel
$header.BackColor = $theme.White
$header.Dock = 'Top'
$header.Height = 62
$form.Controls.Add($header)
if (Test-Path -LiteralPath $iconPath) {
    $brand = New-Object Windows.Forms.PictureBox
    $brand.Bounds = New-Object Drawing.Rectangle(30,10,42,42)
    $brand.SizeMode = 'Zoom'
    $brandIcon = [Drawing.Icon]::new($iconPath,48,48)
    try { $brand.Image = $brandIcon.ToBitmap() }
    finally { $brandIcon.Dispose() }
    $header.Controls.Add($brand)
}
$appName = Add-Heading $header 'Open Proxy Setup' 80 17 275 32 15
$siteLink = Add-Link $header '项目网站 ↗' 'https://openproxysetup.ccwu.cc/' 540 22 86
$docsLink = Add-Link $header '使用文档 ↗' 'https://github.com/lomgzhijie/OpenProxySetup#readme' 644 22 86
foreach ($headerLink in @($siteLink,$docsLink)) { $headerLink.Anchor = 'Top,Right' }
$windowTips = New-Object Windows.Forms.ToolTip
function Add-WindowButton([string]$glyph, [string]$name, [int]$x, [scriptblock]$action) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $glyph
    $button.AccessibleName = $name
    $button.Font = New-Object Drawing.Font('Segoe UI',14)
    $button.Bounds = New-Object Drawing.Rectangle($x,12,43,38)
    Set-ButtonStyle $button
    $button.FlatAppearance.BorderSize = 0
    $button.ForeColor = $theme.Ink
    $button.Anchor = 'Top,Right'
    $button.add_Click($action)
    $windowTips.SetToolTip($button,$name)
    $header.Controls.Add($button)
    return $button
}
[void](Add-WindowButton '−' '最小化' 752 { $form.WindowState = 'Minimized' })
$maximizeWindow = Add-WindowButton '□' '最大化' 794 { $form.ToggleMaximized() }
$closeWindow = Add-WindowButton '×' '关闭' 836 { $form.Close() }
$closeWindow.FlatAppearance.MouseOverBackColor = [Drawing.ColorTranslator]::FromHtml('#FDE9EB')
$closeWindow.FlatAppearance.MouseDownBackColor = $closeWindow.FlatAppearance.MouseOverBackColor
foreach ($dragArea in @($header,$appName,$brand)) {
    if ($dragArea) {
        $dragArea.add_MouseDown({
            param($sender,$event)
            if ($event.Button -eq 'Left') { $form.MoveFromHeader() }
        })
    }
}
$form.add_SizeChanged({
    $restoring = $form.WindowState -eq 'Maximized'
    $maximizeWindow.Text = if ($restoring) { '❐' } else { '□' }
    $maximizeWindow.AccessibleName = if ($restoring) { '还原' } else { '最大化' }
    $windowTips.SetToolTip($maximizeWindow,$maximizeWindow.AccessibleName)
})

$navigation = New-Object Windows.Forms.Panel
$navigation.Dock = 'Top'
$navigation.Height = 53
$navigation.BackColor = $theme.White
$form.Controls.Add($navigation)
$navigation.BringToFront()

$footer = New-Object Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 62
$footer.BackColor = $theme.White
$form.Controls.Add($footer)
$footer.BringToFront()
foreach ($bar in @($navigation,$footer)) {
    $bar.add_Paint({
        param($sender, $event)
        $pen = New-Object Drawing.Pen($theme.Line)
        try {
            $y = if ($sender -eq $footer) { 0 } else { $sender.Height - 1 }
            $event.Graphics.DrawLine($pen,0,$y,$sender.Width,$y)
        } finally { $pen.Dispose() }
    })
}
$footerText = Add-Text $footer 'Windows 部署向导 · v1.4.0' 32 20 320 26
$footerText.ForeColor = $theme.Muted

$viewport = New-Object Windows.Forms.Panel
$viewport.Dock = 'Fill'
$form.Controls.Add($viewport)
$viewport.BringToFront()
$script:pages = [System.Collections.Generic.List[Windows.Forms.Panel]]::new()
$navigationButtons = @{}
$script:currentPage = $null

function New-WizardPage {
    $page = New-Object Windows.Forms.Panel
    $page.BackColor = $theme.Background
    $page.AutoScroll = $true
    return $page
}

function Add-WizardPage($page, [string]$caption, [int]$width) {
    $x = if ($script:pages.Count -eq 0) { 29 } else { $last = $navigation.Controls[$navigation.Controls.Count-1]; $last.Right + 4 }
    $button = New-Object Windows.Forms.Button
    $button.Text = $caption
    $button.Bounds = New-Object Drawing.Rectangle($x,7,$width,37)
    Set-ButtonStyle $button
    $button.FlatAppearance.BorderSize = 0
    $button.Tag = $page
    $button.add_Click({ Show-WizardPage $this.Tag })
    $navigation.Controls.Add($button)
    $navigationButtons[$page] = $button
    $script:pages.Add($page)
    $page.Visible = $false
    $viewport.Controls.Add($page)
}

function Fit-WizardPage($page) {
    if ($page) {
        $width = [Math]::Min(854, $viewport.ClientSize.Width)
        $page.SetBounds([int](($viewport.ClientSize.Width-$width)/2),0,$width,$viewport.ClientSize.Height)
    }
}
$viewport.add_Resize({ Fit-WizardPage $script:currentPage })

function Update-PageActions {
    if (-not $script:currentPage) { return }
    $index = $script:pages.IndexOf($script:currentPage)
    $previous.Enabled = $index -gt 0 -and $index -le $script:guidesEnd
    $next.Enabled = $index -lt ($script:guidesEnd) -and ($script:currentPage -ne $authPage -or $script:cloudflareVerified)
}

function Show-WizardPage($page) {
    if (-not $page -or $page -eq $script:currentPage) { return }
    if ($script:currentPage) {
        $script:currentPage.Visible = $false
        $navigationButtons[$script:currentPage].BackColor = $theme.White
        $navigationButtons[$script:currentPage].ForeColor = $theme.Muted
    }
    $script:currentPage = $page
    $navigationButtons[$page].BackColor = $theme.PaleBlue
    $navigationButtons[$page].ForeColor = $theme.Blue
    Fit-WizardPage $page
    $page.Visible = $true
    $page.BringToFront()
    Update-PageActions
}

$homePage = New-WizardPage
Add-WizardPage $homePage '首页' 68
$title = Add-Heading $homePage ("部署自己的" + [Environment]::NewLine + "Cloudflare Pages 站点") 37 60 434 114 25
$summary = Add-Text $homePage '从浏览器授权、域名配置到打开站点后台，在一个 Windows 图形向导里完成。' 39 185 370 58
$summary.ForeColor = $theme.Muted
Add-Action $homePage '开始部署  →' 39 263 156 { Show-WizardPage $script:pages[1] } $true
Add-Action $homePage '管理已有站点' 209 263 152 { Show-WizardPage $managePage }

$workflow = Add-Card $homePage 469 39 346 292 $theme.PaleBlue 22
$workflowCard = Add-Card $workflow 18 18 310 256 $theme.White
[void](Add-Heading $workflowCard '部署流程' 19 15 270 34 13)
$flow = @(
    @{Title='准备域名'; Detail='DNSHE 域名和 API 授权'},
    @{Title='授权 Cloudflare'; Detail='在浏览器中登录并确认授权'},
    @{Title='部署站点'; Detail='创建 Pages 和 KV，绑定域名'}
)
for ($i = 0; $i -lt $flow.Count; $i++) {
    $y = 54 + ($i * 64)
    $stepBadge = Add-Card $workflowCard 19 $y 32 32 $theme.PaleBlue 8
    $number = Add-Text $stepBadge ($i+1) 0 0 32 32
    $number.TextAlign = 'MiddleCenter'
    $number.ForeColor = $theme.Blue
    [void](Add-Heading $workflowCard $flow[$i].Title 65 ($y-1) 221 27 11)
    $detail = Add-Text $workflowCard $flow[$i].Detail 65 ($y+27) 223 24
    $detail.ForeColor = $theme.Muted
}
$notice = Add-Card $homePage 34 345 781 75 $theme.White
[void](Add-Heading $notice '开始前' 20 9 700 29 13)
$legal = Add-Text $notice '请准备可访问 Cloudflare 的 VPN 环境。使用 VPN 或代理服务时，请遵守所在地适用的法律法规。' 20 38 733 30
$legal.ForeColor = $theme.Muted

$guideCards = @{}
function Add-GuidePage([string]$title,[string]$body,[string]$linkText,[string]$url,[string]$caption,[int]$width,[bool]$withActions = $false) {
    $page = New-WizardPage
    Add-WizardPage $page $caption $width
    $card = Add-Card $page 29 17 796 478 $theme.White
    $guideCards[$page] = $card
    [void](Add-Heading $card $title 26 20 730 41)
    $guide = New-Object Windows.Forms.TextBox
    $guide.Multiline = $true
    $guide.ReadOnly = $true
    $guide.ScrollBars = 'Vertical'
    $guide.BorderStyle = 'None'
    $guideTop = if ($withActions) { 124 } else { 80 }
    $guide.Bounds = New-Object Drawing.Rectangle(28,$guideTop,736,(403-$guideTop))
    $guide.BackColor = $theme.White
    $guide.ForeColor = $theme.Muted
    $guide.Font = New-Object Drawing.Font($form.Font.FontFamily,11)
    $guide.Text = $body.Trim()
    $card.Controls.Add($guide)
    [void](Add-Link $card $linkText $url 27 428 730)
}


Add-GuidePage '1 注册 DNSHE 域名' @'
如果还没有 DNSHE 账号，点击下方链接，在网站注册并登录。

左侧点击“免费域名”，再点击“注册新域名”。
在“选择根域名”下拉框中选择当前可用的后缀，例如 ccwu.cc。
在“域名前缀”中输入想要的名称，例如 myhome。
确认页面显示的完整域名，例如 myhome.ccwu.cc，点击“确认注册”。

如果已经注册过域名，打开 DNSHE 的“我的域名”，复制完整域名即可，不用重复注册。
可用后缀和名额以 DNSHE 网站当前显示为准。
'@ '打开 DNSHE，注册或查看我的域名 ↗' 'https://my.dnshe.com/' '1  注册域名' 108

Add-GuidePage '2 创建 DNSHE 授权' @'
在 DNSHE 左侧点击“免费域名”或首页的“域名管理”。
进入“API 管理”，创建一组 API Key 和 API Secret。

这组授权允许应用替你为所选域名添加 Pages 的 CNAME 记录，不是 DNSHE 的登录密码。
Secret 通常只显示一次；创建后复制到第 4 步的输入框。
不要把 Key、Secret 发到聊天、截图或 GitHub。

如果 DNSHE 域名已有冲突的 DNS 记录，应用会提示你检查，不会覆盖原记录。
'@ '打开 DNSHE API 管理入口 ↗' 'https://my.dnshe.com/' '2  DNSHE 授权' 125

Add-GuidePage '3 登录 Cloudflare' @'
点击下方链接注册或登录自己的 Cloudflare 账号。

你不需要自己创建 KV、Pages 或 DNS 记录。若浏览器授权失败，但部署 API 可访问，可按 README 中的备用方式使用 Cloudflare API Token。设置后从同一个 PowerShell 窗口启动应用，直接点击“我已完成授权，继续”。
点击本页“开始 Cloudflare 授权”。授权工具会打开浏览器。
在浏览器里完成登录和授权，再回到本页点击“我已完成授权，继续”。
应用验证授权有效后才会进入第 4 步，不会一直卡在等待中。

应用将创建 KV 与 Pages，绑定域名，并用 DNSHE API 添加 CNAME 记录。
DNS 和证书传播可能需要时间。应用会先显示 pages.dev 后台地址。
'@ '打开 Cloudflare 注册或登录页 ↗' 'https://dash.cloudflare.com/sign-up' '3  Cloudflare 授权' 143 $true

$script:cloudflareVerified = $false
$authPage = $script:pages[3]
$authCard = $guideCards[$authPage]
$authButton = New-Object Windows.Forms.Button
$authButton.Text = '开始 Cloudflare 授权'
$authButton.Location = New-Object Drawing.Point(29,70)
$authButton.Size = New-Object Drawing.Size(230,43)
Set-ButtonStyle $authButton $true
$authCard.Controls.Add($authButton)
$verifiedButton = New-Object Windows.Forms.Button
$verifiedButton.Text = '我已完成授权，继续'
$verifiedButton.Location = New-Object Drawing.Point(272,70)
$verifiedButton.Size = New-Object Drawing.Size(240,45)
$verifiedButton.add_Click({
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $json = & $bundledNode $bundledWrangler auth token --json 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Cloudflare 授权尚未完成。请先在打开的浏览器里完成授权。' }
        $auth = $json | ConvertFrom-Json
        if (-not $auth.token) { throw 'Cloudflare 授权尚未完成。' }
        if ($auth.type -eq 'api_token' -and $env:CLOUDFLARE_ACCOUNT_ID -notmatch '^[a-fA-F0-9]{32}$') {
            throw '请在启动应用前设置 32 位的 CLOUDFLARE_ACCOUNT_ID。'
        }
        $script:cloudflareVerified = $true
        $next.Enabled = $true
        Show-WizardPage $deployPage
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message) }
    finally { $ErrorActionPreference = $oldPreference; $json = $null; $auth = $null }
})
Set-ButtonStyle $verifiedButton
$authCard.Controls.Add($verifiedButton)

$authStatus = Add-Text $authCard '' 522 75 240 48
$authStatus.ForeColor = $theme.Blue
$authTimer = New-Object Windows.Forms.Timer
$authTimer.Interval = 200
$script:oauthProcess = $null
$script:oauthLine = $null
$script:oauthErrors = $null
$script:oauthBrowserOpened = $false

function Stop-BrowserAuthorization {
    $authTimer.Stop()
    if ($script:oauthProcess) {
        try {
            if (-not $script:oauthProcess.HasExited) { $script:oauthProcess.Kill() }
        } catch {} finally {
            $script:oauthProcess.Dispose()
        }
    }
    $script:oauthProcess = $null
    $script:oauthLine = $null
    $script:oauthErrors = $null
    $authButton.Enabled = $true
    $verifiedButton.Enabled = $true
}

$authButton.add_Click({
    if ($script:oauthProcess) { return }
    if ($env:CLOUDFLARE_API_TOKEN) {
        $authStatus.Text = '已设置 API Token，请直接点击继续。'
        return
    }

    $authButton.Enabled = $false
    $verifiedButton.Enabled = $false
    $script:cloudflareVerified = $false
    $next.Enabled = $false
    $script:oauthBrowserOpened = $false
    $authStatus.Text = '正在准备授权链接…'
    try {
        # Use the bundled CLI directly so the process we monitor owns the OAuth callback.
        $loginCli = Join-Path (Split-Path -Parent (Split-Path -Parent $bundledWrangler)) 'wrangler-dist\cli.js'
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $bundledNode
        $start.Arguments = '--no-warnings "' + $loginCli + '" login --no-browser'
        $start.WorkingDirectory = $PSScriptRoot
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $script:oauthProcess = [Diagnostics.Process]::Start($start)
        $script:oauthLine = $script:oauthProcess.StandardOutput.ReadLineAsync()
        $script:oauthErrors = $script:oauthProcess.StandardError.ReadToEndAsync()
        $authTimer.Start()
    } catch {
        Stop-BrowserAuthorization
        $authStatus.Text = '无法启动授权，请检查应用文件后重试。'
    }
})

$authTimer.add_Tick({
    try {
        while ($script:oauthLine -and $script:oauthLine.IsCompleted) {
            $line = $script:oauthLine.GetAwaiter().GetResult()
            if ($null -eq $line) {
                $script:oauthLine = $null
                break
            }
            $script:oauthLine = $script:oauthProcess.StandardOutput.ReadLineAsync()
            if (-not $script:oauthBrowserOpened -and $line -match 'Visit this link to authenticate:\s*(https://[^\s]+)') {
                $oauthUrl = [uri]$Matches[1]
                if ($oauthUrl.Scheme -eq 'https' -and $oauthUrl.Host -eq 'dash.cloudflare.com' -and $oauthUrl.AbsolutePath -eq '/oauth2/auth') {
                    Start-Process -FilePath $oauthUrl.AbsoluteUri
                    $script:oauthBrowserOpened = $true
                    $authStatus.Text = '请在浏览器完成授权。'
                }
            }
        }
        if ($script:oauthProcess.HasExited -and -not $script:oauthLine) {
            if ($script:oauthProcess.ExitCode -eq 0 -and $script:oauthBrowserOpened) {
                $authStatus.Text = '授权已结束，请点击继续验证。'
            } else {
                $authStatus.Text = '未完成授权，请检查网络后重试。'
            }
            Stop-BrowserAuthorization
        }
    } catch {
        Stop-BrowserAuthorization
        $authStatus.Text = '无法打开授权页，请重试。'
    }
})
$form.add_FormClosed({
    Stop-BrowserAuthorization
    $authTimer.Dispose()
})



$deployPage = New-WizardPage
Add-WizardPage $deployPage '4  填写并部署' 122
$script:guidesEnd = $script:pages.IndexOf($deployPage)
$deployCard = Add-Card $deployPage 29 17 796 450 $theme.White
[void](Add-Heading $deployCard '填写部署信息' 26 20 725 42)
[void](Add-Text $deployCard '完整域名' 30 79 145 30)
$domain = New-Object Windows.Forms.TextBox
$domain.Location = New-Object Drawing.Point(190,76)
$domain.Size = New-Object Drawing.Size(570,30)
$deployCard.Controls.Add($domain)
[void](Add-Text $deployCard '例如 myhome.ccwu.cc；从 DNSHE“我的域名”复制。' 190 108 570 28)
[void](Add-Text $deployCard 'DNSHE API Key' 30 154 150 30)
$apiKey = New-Object Windows.Forms.TextBox
$apiKey.Location = New-Object Drawing.Point(190,151)
$apiKey.Size = New-Object Drawing.Size(570,30)
$deployCard.Controls.Add($apiKey)
[void](Add-Text $deployCard 'DNSHE API Secret' 30 200 155 30)
$apiSecret = New-Object Windows.Forms.TextBox
$apiSecret.Location = New-Object Drawing.Point(190,197)
$apiSecret.Size = New-Object Drawing.Size(570,30)
$apiSecret.UseSystemPasswordChar = $true
$deployCard.Controls.Add($apiSecret)
[void](Add-Text $deployCard '后台管理员密码' 30 246 155 30)
$password = New-Object Windows.Forms.TextBox
$password.Location = New-Object Drawing.Point(190,243)
$password.Size = New-Object Drawing.Size(570,30)
$password.UseSystemPasswordChar = $true
$deployCard.Controls.Add($password)
foreach ($field in @($domain,$apiKey,$apiSecret,$password)) {
    $field.ShortcutsEnabled = $true
    $field.BorderStyle = 'FixedSingle'
    $field.Width = 390
    $pasteButton = New-Object Windows.Forms.Button
    $pasteButton.Text = '粘贴'
    $pasteButton.Location = New-Object Drawing.Point(590,$field.Top)
    $pasteButton.Size = New-Object Drawing.Size(75,30)
    Set-ButtonStyle $pasteButton
    $targetField = $field
    $pasteButton.add_Click({
        try {
            if ([Windows.Forms.Clipboard]::ContainsText()) {
                $targetField.SelectedText = [Windows.Forms.Clipboard]::GetText()
                $targetField.Focus()
            } else { [Windows.Forms.MessageBox]::Show('剪贴板里没有可粘贴的文字，请先复制。') }
        } catch { [Windows.Forms.MessageBox]::Show('无法读取剪贴板，请重新复制后再试。') }
    }.GetNewClosure())
    $deployCard.Controls.Add($pasteButton)
}
foreach ($field in @($apiSecret,$password)) {
    $toggleButton = New-Object Windows.Forms.Button
    $toggleButton.Text = '显示'
    $toggleButton.Location = New-Object Drawing.Point(675,$field.Top)
    $toggleButton.Size = New-Object Drawing.Size(85,30)
    Set-ButtonStyle $toggleButton
    $targetField = $field
    $targetButton = $toggleButton
    $toggleButton.add_Click({
        $targetField.UseSystemPasswordChar = -not $targetField.UseSystemPasswordChar
        if ($targetField.UseSystemPasswordChar) { $targetButton.Text = '显示' }
        else { $targetButton.Text = '隐藏' }
    }.GetNewClosure())
    $deployCard.Controls.Add($toggleButton)
}
[void](Add-Text $deployCard '自己设定至少 12 位；部署后用它登录订阅网站的 /admin。' 190 279 570 30)
$deployButton = New-Object Windows.Forms.Button
$deployButton.Text = '开始自动部署'
$deployButton.Location = New-Object Drawing.Point(190,324)
$deployButton.Size = New-Object Drawing.Size(260,42)
Set-ButtonStyle $deployButton $true
$deployCard.Controls.Add($deployButton)
$deployHint = Add-Text $deployCard '' 30 380 750 55

$managePage = New-WizardPage
Add-WizardPage $managePage '后台管理' 97
$manageCard = Add-Card $managePage 29 17 796 423 $theme.White
[void](Add-Heading $manageCard '站点后台' 26 20 730 42)
[void](Add-Text $manageCard '站点网址' 30 90 110 30)
$manageUrl = New-Object Windows.Forms.TextBox
$manageUrl.Location = New-Object Drawing.Point(150,90)
$manageUrl.Size = New-Object Drawing.Size(585,30)
$manageUrl.BorderStyle = 'FixedSingle'
$manageCard.Controls.Add($manageUrl)
[void](Add-Text $manageCard '输入 HTTPS 网址或域名，例如 example.pages.dev。' 150 128 585 32)
[void](Add-Text $manageCard '后台密码' 30 175 110 30)
$managePassword = New-Object Windows.Forms.TextBox
$managePassword.Location = New-Object Drawing.Point(150,175)
$managePassword.Size = New-Object Drawing.Size(585,30)
$managePassword.UseSystemPasswordChar = $true
$managePassword.BorderStyle = 'FixedSingle'
$manageCard.Controls.Add($managePassword)
[void](Add-Text $manageCard '密码仅保留在本次打开的窗口内。打开后台后，在浏览器中登录。' 150 215 585 46)
$manageStatus = Add-Text $manageCard '' 150 338 585 100

function Get-AdminUrl([string]$value) {
    $value = $value.Trim()
    if (-not $value) { throw '请输入站点网址。' }
    if ($value -notmatch '^[a-z][a-z0-9+.-]*://') { $value = "https://$value" }
    $uri = $null
    if (-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.Host) {
        throw '请输入有效的 HTTPS 网址。'
    }
    return ($uri.GetLeftPart([UriPartial]::Authority) + '/admin')
}

Add-Action $manageCard '打开后台' 150 275 145 {
    try {
        Start-Process -FilePath (Get-AdminUrl $manageUrl.Text)
        $manageStatus.Text = '已打开后台，请在浏览器登录。'
    } catch { $manageStatus.Text = $_.Exception.Message }
} $true
Add-Action $manageCard '复制密码' 310 275 145 {
    if (-not $managePassword.Text) { $manageStatus.Text = '请先输入后台密码。'; return }
    try {
        [Windows.Forms.Clipboard]::SetText($managePassword.Text)
        $manageStatus.Text = '密码已复制，可在后台登录框粘贴。'
    } catch { $manageStatus.Text = '暂时无法访问剪贴板，请重试。' }
}
Add-Action $manageCard '清空密码' 470 275 145 {
    $managePassword.Clear()
    $manageStatus.Text = '密码输入框已清空。'
}

$progressPage = New-WizardPage
$progressCard = Add-Card $progressPage 29 17 796 476 $theme.White
[void](Add-Heading $progressCard '部署进度' 26 18 730 40)
$stageNames = @('', '验证 Cloudflare 授权', '创建 Cloudflare KV', '发布 Cloudflare Pages', '绑定域名（Cloudflare / DNSHE）')
$stageRows = @(foreach ($i in 1..4) {
    $row = Add-Card $progressCard 26 (64 + ($i - 1) * 34) 742 30 $theme.PaleBlue 7
    $stageLabel = Add-Text $row '' 10 0 723 30
    $stageLabel.TextAlign = 'MiddleLeft'
    $stageLabel
})
$progress = Add-Text $progressCard '' 26 205 736 40
$progressDetail = New-Object Windows.Forms.TextBox
$progressDetail.Location = New-Object Drawing.Point(30,245)
$progressDetail.Size = New-Object Drawing.Size(735,82)
$progressDetail.Multiline = $true
$progressDetail.ReadOnly = $true
$progressDetail.ScrollBars = 'Vertical'
$progressDetail.BorderStyle = 'FixedSingle'
$progressDetail.BackColor = $theme.Background
$progressDetail.ForeColor = $theme.Muted
$progressCard.Controls.Add($progressDetail)
$result = Add-Link $progressCard '打开临时后台（pages.dev）' '' 30 340
$customResult = Add-Link $progressCard '打开自定义域名后台' '' 30 373
foreach ($link in @($result,$customResult)) {
    $link.Visible = $false
}
$retry = New-Object Windows.Forms.Button
$retry.Location = New-Object Drawing.Point(30,420)
$retry.Size = New-Object Drawing.Size(175,40)
$retry.Visible = $false
Set-ButtonStyle $retry $true
$progressCard.Controls.Add($retry)
$editDeployment = New-Object Windows.Forms.Button
$editDeployment.Location = New-Object Drawing.Point(218,420)
$editDeployment.Size = New-Object Drawing.Size(175,40)
$editDeployment.Visible = $false
Set-ButtonStyle $editDeployment
$editDeployment.add_Click({ Show-WizardPage $deployPage })
$progressCard.Controls.Add($editDeployment)
Add-Action $progressCard '进入后台管理' 406 420 175 { Show-WizardPage $managePage }

$previous = New-Object Windows.Forms.Button
$previous.Text = '上一步'
$previous.Location = New-Object Drawing.Point(571,11)
$previous.Size = New-Object Drawing.Size(132,40)
Set-ButtonStyle $previous
$previous.Anchor = 'Top,Right'
$previous.add_Click({ Show-WizardPage $script:pages[($script:pages.IndexOf($script:currentPage) - 1)] })
$footer.Controls.Add($previous)
$next = New-Object Windows.Forms.Button
$next.Text = '下一步'
$next.Location = New-Object Drawing.Point(721,11)
$next.Size = New-Object Drawing.Size(147,40)
Set-ButtonStyle $next $true
$next.Anchor = 'Top,Right'
$next.add_Click({ Show-WizardPage $script:pages[($script:pages.IndexOf($script:currentPage) + 1)] })
$footer.Controls.Add($next)

$script:deployment = $null
$script:deploymentHandle = $null
$script:deploymentTimer = New-Object Windows.Forms.Timer
$script:deploymentTimer.Interval = 300

function Show-DeploymentProgress {
    $state = $script:deployment
    $step = $state.Step
    $done = @($false, [bool]$state.AccountId, [bool]$state.KvId, $state.PagesReady, $state.DomainActive)
    for ($i = 1; $i -le 4; $i++) {
        $seconds = $state.Times[$i]
        $label = '未开始'
        if ($step -eq $i) {
            $label = '进行中'
            $seconds += ([DateTime]::UtcNow - $state.StepStarted).TotalSeconds
        } elseif ($state.FailedStep -eq $i) {
            $label = '失败，可重试'
        } elseif ($done[$i]) {
            $label = '已完成'
        } elseif ($i -eq 4 -and $state.LastStep -eq 4 -and -not $script:deploymentHandle) {
            $label = '等待验证'
        }
        $duration = if ($seconds -gt 0) { '（{0:0} 秒）' -f $seconds } else { '' }
        $stageRows[$i-1].Text = "$($stageNames[$i])  ·  $label$duration"
        $stageRows[$i-1].ForeColor = switch ($label) {
            '失败，可重试' { $theme.Red }
            '已完成' { $theme.Green }
            '未开始' { $theme.Muted }
            default { $theme.Blue }
        }
    }

    if ($state.PagesReady -and -not $result.Tag) {
        $result.Tag = "https://$($state.ProjectName).pages.dev/admin"
        $result.Visible = $true
        $manageUrl.Text = $result.Tag
        if ($script:runPassword) {
            $managePassword.Text = [System.Net.NetworkCredential]::new('', $script:runPassword).Password
        }
        $password.Clear()
    }
    if ($state.DomainActive) {
        $customResult.Tag = "https://$($state.Domain)/admin"
        $customResult.Visible = $true
    }
}

function Complete-Deployment([string]$detail, [bool]$failed) {
    $state = $script:deployment
    Show-DeploymentProgress
    $script:deploymentTimer.Stop()
    $script:deploymentHandle = $null
    if ($script:deploymentPowerShell) { $script:deploymentPowerShell.Dispose(); $script:deploymentPowerShell = $null }
    if ($script:deploymentRunspace) { $script:deploymentRunspace.Dispose(); $script:deploymentRunspace = $null }
    foreach ($credential in @($script:runPassword,$script:runKey,$script:runSecret)) {
        if ($credential) { $credential.Dispose() }
    }
    $script:runPassword = $script:runKey = $script:runSecret = $null

    $state.FailedStep = if ($failed) { [Math]::Max(1, $state.LastStep) } else { 0 }
    $elapsed = [DateTime]::UtcNow - $script:deploymentStarted
    if ($state.DomainActive) {
        $progress.Text = '部署完成。自定义域名已通过验证。'
        $progressDetail.Text = '现在可以打开自定义域名后台并登录。'
        $apiSecret.Clear()
        $apiKey.Clear()
    } elseif ($failed) {
        $progress.Text = "$($stageNames[$state.FailedStep])失败。修正后可以继续本次部署。"
        $advice = @(
            '请检查输入后重试。',
            '如授权已过期，请回到第 3 步重新授权。遇到 403 时请核对 Cloudflare 账号与权限。',
            '请检查 Cloudflare 的 KV 权限或配额，然后点「继续部署」。',
            '请检查 Cloudflare Pages 权限与网络，然后点「继续部署」。',
            '请根据下方信息修正 Cloudflare 或 DNSHE 配置，再点「重试域名绑定」。'
        )
        $progressDetail.Text = $advice[$state.FailedStep] + [Environment]::NewLine + $detail
    } else {
        $progress.Text = 'Pages 已上线，正在等待自定义域名的 DNS 或证书验证。'
        $progressDetail.Text = '现在可使用临时后台。等几分钟后可点击「重试域名绑定」查看是否已生效。'
    }
    $progress.Text += ' 本次用时 {0:hh\:mm\:ss}。' -f $elapsed
    $deployHint.Text = $progress.Text
    $manageStatus.Text = $progress.Text
    $domain.ReadOnly = $state.DomainStarted -and -not $state.DomainActive
    $apiKey.ReadOnly = $apiSecret.ReadOnly = $false
    $password.ReadOnly = $state.PagesReady -and -not $state.DomainActive
    $deployButton.Enabled = $true
    $deployButton.Text = if ($state.DomainActive) { '开始自动部署' } elseif ($state.PagesReady) { '重试域名绑定' } else { '继续部署' }
    $retry.Text = $deployButton.Text
    $retry.Visible = -not $state.DomainActive
    $editDeployment.Text = if ($state.PagesReady) { '修改 DNSHE 授权' } else { '返回修改信息' }
    $editDeployment.Visible = -not $state.DomainActive
    Show-DeploymentProgress
}

$script:deploymentTimer.add_Tick({
    if (-not $script:deploymentHandle) { return }
    Show-DeploymentProgress
    if (-not $script:deploymentHandle.IsCompleted) {
        $elapsed = [DateTime]::UtcNow - $script:deploymentStarted
        $progress.Text = '正在进行，已用 {0:hh\:mm\:ss}。首次部署通常约 3–10 分钟。' -f $elapsed
        return
    }

    $detail = ''
    $failed = $false
    try {
        $output = $script:deploymentPowerShell.EndInvoke($script:deploymentHandle)
        $warning = $output | Where-Object { $_.ToString().StartsWith('__DOMAIN_WARNING__:') } | Select-Object -First 1
        if ($warning) {
            $failed = $true
            $detail = $warning.ToString().Substring('__DOMAIN_WARNING__:'.Length)
        }
    } catch {
        $failed = $true
        $errorRecord = $script:deploymentPowerShell.Streams.Error | Select-Object -Last 1
        $detail = if ($errorRecord) { $errorRecord.Exception.Message } elseif ($_.Exception.InnerException) {
            $_.Exception.InnerException.Message
        } else { $_.Exception.Message }
    }
    if ($detail) {
        $detail = [regex]::Replace($detail, '\x1B\[[0-?]*[ -/]*[@-~]', '')
        foreach ($secret in @($apiKey.Text.Trim(),$apiSecret.Text,$password.Text,$managePassword.Text,$env:CLOUDFLARE_API_TOKEN)) {
            if ($secret) { $detail = $detail.Replace($secret,'[已隐藏]') }
        }
    }
    Complete-Deployment $detail $failed
})

function Start-Deployment {
    if ($script:deploymentHandle) { return }
    $state = $script:deployment
    $resume = $state -and -not $state.DomainActive
    $d = if ($resume -and $state.DomainStarted) { $state.Domain } else { $domain.Text.Trim() }
    if ($d -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        $deployHint.Text = '请填写 DNSHE“我的域名”中的完整域名。'
        Show-WizardPage $deployPage
        return
    }
    if (-not $apiKey.Text.Trim() -or -not $apiSecret.Text) {
        $deployHint.Text = '请填写 DNSHE API Key 和 Secret。'
        Show-WizardPage $deployPage
        return
    }
    if ((-not $resume -or -not $state.PagesReady) -and $password.Text.Length -lt 12) {
        $deployHint.Text = '后台管理员密码至少 12 位。'
        Show-WizardPage $deployPage
        return
    }

    if (-not $resume) {
        $state = [hashtable]::Synchronized(@{
            ProjectName = 'zijianjichang-' + ([guid]::NewGuid().ToString('N')).Substring(0,8)
            Domain = $d; Step = 0; LastStep = 0; FailedStep = 0
            StepStarted = [DateTime]::UtcNow; Times = @(0.0,0.0,0.0,0.0,0.0)
            AccountId = ''; KvId = ''; KvAttempted = $false; ProjectAttempted = $false
            ProjectCreated = $false; PagesReady = $false; DomainStarted = $false; DomainActive = $false
        })
        $script:deployment = $state
        foreach ($link in @($result,$customResult)) { $link.Tag = $null; $link.Visible = $false }
    }

    $state.Domain = $d
    $state.LastStep = 0
    $state.FailedStep = 0
    $script:deploymentStarted = [DateTime]::UtcNow
    $deployButton.Enabled = $false
    $retry.Visible = $editDeployment.Visible = $false
    $domain.ReadOnly = $apiKey.ReadOnly = $apiSecret.ReadOnly = $password.ReadOnly = $true
    $deployHint.Text = '部署进行中。请查看「部署进度」。'
    $progress.Text = '正在准备部署…'
    $progressDetail.Text = "目标域名：$($state.Domain)　项目：$($state.ProjectName)"
    if (-not $script:pages.Contains($progressPage)) { Add-WizardPage $progressPage '部署进度' 97 }
    Show-WizardPage $progressPage
    Show-DeploymentProgress
    try {
        $script:runPassword = if (-not $state.PagesReady) { ConvertTo-SecureString $password.Text -AsPlainText -Force }
        $script:runKey = ConvertTo-SecureString $apiKey.Text.Trim() -AsPlainText -Force
        $script:runSecret = ConvertTo-SecureString $apiSecret.Text -AsPlainText -Force
        $script:deploymentRunspace = [runspacefactory]::CreateRunspace()
        $script:deploymentRunspace.Open()
        $script:deploymentPowerShell = [powershell]::Create()
        $script:deploymentPowerShell.Runspace = $script:deploymentRunspace
        [void]$script:deploymentPowerShell.AddCommand($deployScript)
        [void]$script:deploymentPowerShell.AddParameters(@{
            ProjectName = $state.ProjectName; Domain = $state.Domain; Deployment = $state
            AdminPassword = $script:runPassword; DnsheKey = $script:runKey; DnsheSecret = $script:runSecret
        })
        $script:deploymentHandle = $script:deploymentPowerShell.BeginInvoke()
        $script:deploymentTimer.Start()
    } catch {
        Complete-Deployment '无法启动部署。请检查应用文件，或重新打开应用。' $true
    }
}

$deployButton.add_Click({ Start-Deployment })
$retry.add_Click({ Start-Deployment })
Show-WizardPage $homePage
[void]$form.ShowDialog()
