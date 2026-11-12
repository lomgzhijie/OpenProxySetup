# Windows PowerShell 5.1 desktop wizard. Keep this file UTF-8 with BOM.
$ErrorActionPreference = 'Stop'
$deployScript = Join-Path $PSScriptRoot 'deploy.ps1'
$authLauncher = Join-Path $PSScriptRoot 'Cloudflare授权.cmd'
$bundledNode = Join-Path $PSScriptRoot 'runtime\node.exe'
$bundledWrangler = Join-Path $PSScriptRoot 'runtime\node_modules\wrangler\bin\wrangler.js'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = '自建机场 · 一步一步部署订阅网站 v1.3'
$proxyScript = Join-Path $PSScriptRoot 'proxy.ps1'
. $proxyScript
$form.Size = New-Object Drawing.Size(920,740)
$form.MinimumSize = New-Object Drawing.Size(850,680)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI',10)

function Add-Text($parent,[string]$value,[int]$x,[int]$y,[int]$w,[int]$h) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $value
    $label.Location = New-Object Drawing.Point($x,$y)
    $label.Size = New-Object Drawing.Size($w,$h)
    $parent.Controls.Add($label)
    return $label
}
function Add-Link($parent,[string]$value,[string]$url,[int]$x,[int]$y) {
    $link = New-Object Windows.Forms.LinkLabel
    $link.Text = $value
    $link.Location = New-Object Drawing.Point($x,$y)
    $link.Size = New-Object Drawing.Size(760,34)
    $target = $url
    $link.add_LinkClicked({ Start-Process $target }.GetNewClosure())
    $parent.Controls.Add($link)
    return $link
}
function Add-GuidePage([string]$title,[string]$body,[string]$linkText,[string]$url) {
    $page = New-Object Windows.Forms.TabPage
    $page.Text = $title
    [void](Add-Text $page $title 24 23 760 42)
    $guide = New-Object Windows.Forms.TextBox
    $guide.Multiline = $true
    $guide.ReadOnly = $true
    $guide.ScrollBars = 'Vertical'
    $guide.BorderStyle = 'None'
    $guide.Location = New-Object Drawing.Point(30,130)
    $guide.Size = New-Object Drawing.Size(780,340)
    $guide.Font = New-Object Drawing.Font('Microsoft YaHei UI',11)
    $guide.Text = $body.Trim()
    $page.Controls.Add($guide)
    [void](Add-Link $page $linkText $url 30 490)
    $tabs.TabPages.Add($page)
}

$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(20,18)
$tabs.Size = New-Object Drawing.Size(860,590)
$tabs.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($tabs)

function Add-Action($page, [string]$caption, [int]$x, [int]$y, [int]$width, [scriptblock]$action) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $caption
    $button.Location = New-Object Drawing.Point($x,$y)
    $button.Size = New-Object Drawing.Size($width,40)
    $button.add_Click($action)
    $page.Controls.Add($button)
}

$homePage = New-Object Windows.Forms.TabPage
$homePage.Text = '首页'
$title = Add-Text $homePage '自建机场' 30 30 720 55
$title.Font = New-Object Drawing.Font('Microsoft YaHei UI',24)
$legal = Add-Text $homePage '使用 VPN 或代理服务前，请了解并遵守所在地适用的法律法规。' 30 100 740 60
$legal.ForeColor = [Drawing.Color]::DarkGoldenrod
[void](Add-Text $homePage '首次使用可开始部署；已有站点可直接进入后台管理。' 30 165 740 38)
Add-Action $homePage '开始部署' 30 220 160 { $tabs.SelectedIndex = 1 }
Add-Action $homePage '管理已有站点' 210 220 160 { $tabs.SelectedTab = $managePage }
$tabs.TabPages.Add($homePage)


Add-GuidePage '1 注册 DNSHE 域名' @'
如果还没有 DNSHE 账号，点击下方链接，在网站注册并登录。

左侧点击“免费域名”，再点击“注册新域名”。
在“选择根域名”下拉框中选择当前可用的后缀，例如 ccwu.cc。
在“域名前缀”中输入想要的名称，例如 myhome。
确认页面显示的完整域名，例如 myhome.ccwu.cc，点击“确认注册”。

如果已经注册过域名，打开 DNSHE 的“我的域名”，复制完整域名即可，不用重复注册。
可用后缀和名额以 DNSHE 网站当前显示为准。
'@ '打开 DNSHE，注册或查看我的域名' 'https://my.dnshe.com/'

Add-GuidePage '2 创建 DNSHE 授权' @'
在 DNSHE 左侧点击“免费域名”或首页的“域名管理”。
进入“API 管理”，创建一组 API Key 和 API Secret。

这组授权允许应用替你为所选域名添加 Pages 的 CNAME 记录，不是 DNSHE 的登录密码。
Secret 通常只显示一次；创建后复制到第 4 步的输入框。
不要把 Key、Secret 发到聊天、截图或 GitHub。

如果 DNSHE 域名已有冲突的 DNS 记录，应用会提示你检查，不会覆盖原记录。
'@ '打开 DNSHE API 管理入口' 'https://my.dnshe.com/'

Add-GuidePage '3 登录 Cloudflare' @'
点击下方链接注册或登录自己的 Cloudflare 账号。

你不需要自己创建 KV、Pages 或 DNS 记录。
点击本页“开始 Cloudflare 授权”。授权工具会打开浏览器。
在浏览器里完成登录和授权，再回到本页点击“我已完成授权，继续”。
应用验证授权有效后才会进入第 4 步，不会一直卡在等待中。

应用将创建 KV 与 Pages，绑定域名，并用 DNSHE API 添加 CNAME 记录。
DNS 和证书传播可能需要时间。应用会先显示 pages.dev 后台地址。
'@ '打开 Cloudflare 注册或登录页' 'https://dash.cloudflare.com/sign-up'

$script:cloudflareVerified = $false
$authPage = $tabs.TabPages[3]
$authButton = New-Object Windows.Forms.Button
$authButton.Text = '开始 Cloudflare 授权'
$authButton.Location = New-Object Drawing.Point(30,70)
$authButton.Size = New-Object Drawing.Size(240,45)
$authButton.add_Click({ Start-Process -FilePath $authLauncher -WindowStyle Normal })
$authPage.Controls.Add($authButton)
$verifiedButton = New-Object Windows.Forms.Button
$verifiedButton.Text = '我已完成授权，继续'
$verifiedButton.Location = New-Object Drawing.Point(290,70)
$verifiedButton.Size = New-Object Drawing.Size(240,45)
$verifiedButton.add_Click({
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $json = & $bundledNode $bundledWrangler auth token --json 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Cloudflare 授权尚未完成。请先在打开的浏览器里完成授权。' }
        $auth = $json | ConvertFrom-Json
        if (-not $auth.token) { throw 'Cloudflare 授权尚未完成。' }
        $script:cloudflareVerified = $true
        $next.Enabled = $true
        $tabs.SelectedTab = $deployPage
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message) }
    finally { $ErrorActionPreference = $oldPreference; $json = $null; $auth = $null }
})
$authPage.Controls.Add($verifiedButton)

$deployPage = New-Object Windows.Forms.TabPage
$deployPage.Text = '4 填写并部署'
$tabs.TabPages.Add($deployPage)
[void](Add-Text $deployPage '填写以下信息，然后点击部署' 24 22 760 40)
[void](Add-Text $deployPage '完整域名' 30 79 145 30)
$domain = New-Object Windows.Forms.TextBox
$domain.Location = New-Object Drawing.Point(190,76)
$domain.Size = New-Object Drawing.Size(570,30)
$deployPage.Controls.Add($domain)
[void](Add-Text $deployPage '例如 myhome.ccwu.cc；从 DNSHE“我的域名”复制。' 190 108 570 28)
[void](Add-Text $deployPage 'DNSHE API Key' 30 154 150 30)
$apiKey = New-Object Windows.Forms.TextBox
$apiKey.Location = New-Object Drawing.Point(190,151)
$apiKey.Size = New-Object Drawing.Size(570,30)
$deployPage.Controls.Add($apiKey)
[void](Add-Text $deployPage 'DNSHE API Secret' 30 200 155 30)
$apiSecret = New-Object Windows.Forms.TextBox
$apiSecret.Location = New-Object Drawing.Point(190,197)
$apiSecret.Size = New-Object Drawing.Size(570,30)
$apiSecret.UseSystemPasswordChar = $true
$deployPage.Controls.Add($apiSecret)
[void](Add-Text $deployPage '后台管理员密码' 30 246 155 30)
$password = New-Object Windows.Forms.TextBox
$password.Location = New-Object Drawing.Point(190,243)
$password.Size = New-Object Drawing.Size(570,30)
$password.UseSystemPasswordChar = $true
$deployPage.Controls.Add($password)
foreach ($field in @($domain,$apiKey,$apiSecret,$password)) {
    $field.ShortcutsEnabled = $true
    $field.Width = 390
    $pasteButton = New-Object Windows.Forms.Button
    $pasteButton.Text = '粘贴'
    $pasteButton.Location = New-Object Drawing.Point(590,$field.Top)
    $pasteButton.Size = New-Object Drawing.Size(75,30)
    $targetField = $field
    $pasteButton.add_Click({
        try {
            if ([Windows.Forms.Clipboard]::ContainsText()) {
                $targetField.SelectedText = [Windows.Forms.Clipboard]::GetText()
                $targetField.Focus()
            } else { [Windows.Forms.MessageBox]::Show('剪贴板里没有可粘贴的文字，请先复制。') }
        } catch { [Windows.Forms.MessageBox]::Show('无法读取剪贴板，请重新复制后再试。') }
    }.GetNewClosure())
    $deployPage.Controls.Add($pasteButton)
}
foreach ($field in @($apiSecret,$password)) {
    $toggleButton = New-Object Windows.Forms.Button
    $toggleButton.Text = '显示'
    $toggleButton.Location = New-Object Drawing.Point(675,$field.Top)
    $toggleButton.Size = New-Object Drawing.Size(85,30)
    $targetField = $field
    $targetButton = $toggleButton
    $toggleButton.add_Click({
        $targetField.UseSystemPasswordChar = -not $targetField.UseSystemPasswordChar
        if ($targetField.UseSystemPasswordChar) { $targetButton.Text = '显示' }
        else { $targetButton.Text = '隐藏' }
    }.GetNewClosure())
    $deployPage.Controls.Add($toggleButton)
}
[void](Add-Text $deployPage '自己设定至少 12 位；部署后用它登录订阅网站的 /admin。' 190 279 570 30)
$deployButton = New-Object Windows.Forms.Button
$deployButton.Text = '开始自动部署'
$deployButton.Location = New-Object Drawing.Point(190,324)
$deployButton.Size = New-Object Drawing.Size(260,42)
$deployPage.Controls.Add($deployButton)
$progress = Add-Text $deployPage '' 30 374 760 32
$result = New-Object Windows.Forms.LinkLabel
$result.Text = ''
$result.Location = New-Object Drawing.Point(30,415)
$result.Size = New-Object Drawing.Size(760,42)
$deployPage.Controls.Add($result)
$result.add_LinkClicked({ Start-Process -FilePath $this.Links[0].LinkData })

$managePage = New-Object Windows.Forms.TabPage
$managePage.Text = '后台管理'
$tabs.TabPages.Add($managePage)
[void](Add-Text $managePage '站点后台' 30 30 720 38)
[void](Add-Text $managePage '站点网址' 30 90 110 30)
$manageUrl = New-Object Windows.Forms.TextBox
$manageUrl.Location = New-Object Drawing.Point(150,90)
$manageUrl.Size = New-Object Drawing.Size(585,30)
$managePage.Controls.Add($manageUrl)
[void](Add-Text $managePage '输入 HTTPS 网址或域名，例如 example.pages.dev。' 150 128 585 32)
[void](Add-Text $managePage '后台密码' 30 175 110 30)
$managePassword = New-Object Windows.Forms.TextBox
$managePassword.Location = New-Object Drawing.Point(150,175)
$managePassword.Size = New-Object Drawing.Size(585,30)
$managePassword.UseSystemPasswordChar = $true
$managePage.Controls.Add($managePassword)
[void](Add-Text $managePage '密码仅保留在本次打开的窗口内。打开后台后，在浏览器中登录。' 150 215 585 46)
$manageStatus = Add-Text $managePage '' 150 338 585 100

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

Add-Action $managePage '打开后台' 150 275 145 {
    try {
        Start-Process -FilePath (Get-AdminUrl $manageUrl.Text)
        $manageStatus.Text = '已打开后台，请在浏览器登录。'
    } catch { $manageStatus.Text = $_.Exception.Message }
}
Add-Action $managePage '复制密码' 310 275 145 {
    if (-not $managePassword.Text) { $manageStatus.Text = '请先输入后台密码。'; return }
    try {
        [Windows.Forms.Clipboard]::SetText($managePassword.Text)
        $manageStatus.Text = '密码已复制，可在后台登录框粘贴。'
    } catch { $manageStatus.Text = '暂时无法访问剪贴板，请重试。' }
}
Add-Action $managePage '清空密码' 470 275 145 {
    $managePassword.Clear()
    $manageStatus.Text = '密码输入框已清空。'
}
$hint = Add-Text $deployPage '' 30 465 760 60

$previous = New-Object Windows.Forms.Button
$previous.Text = '上一步'
$previous.Location = New-Object Drawing.Point(555,625)
$previous.Size = New-Object Drawing.Size(130,42)
$previous.Anchor = 'Bottom,Right'
$previous.add_Click({ if($tabs.SelectedIndex -gt 0){$tabs.SelectedIndex--} })
$form.Controls.Add($previous)
$next = New-Object Windows.Forms.Button
$next.Text = '下一步'
$next.Location = New-Object Drawing.Point(705,625)
$next.Size = New-Object Drawing.Size(130,42)
$next.Anchor = 'Bottom,Right'
$next.add_Click({ if($tabs.SelectedIndex -lt $tabs.TabPages.Count-1){$tabs.SelectedIndex++} })
$form.Controls.Add($next)
$tabs.add_SelectedIndexChanged({
    $previous.Enabled = $tabs.SelectedIndex -gt 0
    $next.Enabled = ($tabs.SelectedIndex -lt $tabs.TabPages.Count-1) -and ($tabs.SelectedTab -ne $authPage -or $script:cloudflareVerified)
})
$previous.Enabled = $false

$script:deploymentTimer = New-Object Windows.Forms.Timer
$script:deploymentTimer.Interval = 1000
$script:deploymentTimer.add_Tick({
    if (-not $script:deploymentHandle) { return }
    $elapsed = (Get-Date) - $script:deploymentStarted
    $progress.Text = ('正在部署，已用 {0:mm\:ss}；通常约 3–10 分钟，正在处理 DNSHE 与 Cloudflare 配置。' -f $elapsed)
    if (-not $script:deploymentHandle.IsCompleted) { return }
    $script:deploymentTimer.Stop()
    try {
        $output = $script:deploymentPowerShell.EndInvoke($script:deploymentHandle)
        if (-not ($output | Where-Object { $_.ToString() -eq '__DEPLOY_SUCCESS__' })) {
            $lastError = $script:deploymentPowerShell.Streams.Error | Select-Object -Last 1
            if ($lastError) { throw $lastError.ToString() }
            throw '部署未返回成功结果，请查看命令窗口或稍后重试。'
        }
        $domainWarning = $output | Where-Object { $_.ToString().StartsWith('__DOMAIN_WARNING__:') } | Select-Object -First 1
        if ($domainWarning) { $progress.Text = 'Pages 已部署，自定义域名绑定未完成。' }
        else { $progress.Text = '部署命令已完成。自定义域名的 DNS 与证书生效可能还需等待。' }
        $adminUrl = "https://$script:pendingProject.pages.dev/admin"
        $result.Text = "点击打开后台：$adminUrl"
        $result.Links.Clear()
        [void]$result.Links.Add(0,$result.Text.Length,$adminUrl)
        $manageUrl.Text = $adminUrl
        $managePassword.Text = [System.Net.NetworkCredential]::new('', $script:pendingPassword).Password
        $manageStatus.Text = $progress.Text
        $tabs.SelectedTab = $managePage
        if ($domainWarning) { $hint.Text = "Pages 后台可用；域名未完成：$($domainWarning.ToString().Substring(19))" }
        else { $hint.Text = "用刚设置的密码登录后台，复制节点或订阅链接。域名 $script:pendingDomain 未生效前，可先用 pages.dev 地址。" }
    } catch {
        $progress.Text = '部署未完成。'
        $detail = $_.Exception.Message
        if ($_.Exception.InnerException) { $detail = $_.Exception.InnerException.Message }
        [Windows.Forms.MessageBox]::Show("部署未完成：$detail")
    } finally {
        $deployButton.Enabled = $true
        $script:deploymentPowerShell.Dispose()
        $script:deploymentRunspace.Dispose()
        $script:deploymentHandle = $null
        $script:pendingSecret.Dispose()
        $script:pendingKey.Dispose()
        $script:pendingPassword.Dispose()
    }
})

$deployButton.add_Click({
    $d = $domain.Text.Trim()
    if($d -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'){
        [Windows.Forms.MessageBox]::Show('请填写 DNSHE“我的域名”中的完整域名。'); return
    }
    if(-not $apiKey.Text.Trim() -or -not $apiSecret.Text){
        [Windows.Forms.MessageBox]::Show('请先完成第 2 步，填写 DNSHE API Key 和 Secret。'); return
    }
    if($password.Text.Length -lt 12){
        [Windows.Forms.MessageBox]::Show('后台管理员密码至少 12 位。'); return
    }
    $secure = ConvertTo-SecureString $password.Text -AsPlainText -Force
    $secureKey = ConvertTo-SecureString $apiKey.Text.Trim() -AsPlainText -Force
    $secureSecret = ConvertTo-SecureString $apiSecret.Text -AsPlainText -Force
    $password.Clear(); $apiKey.Clear(); $apiSecret.Clear()
    $project = 'zijianjichang-' + ([guid]::NewGuid().ToString('N')).Substring(0,8)
    $deployButton.Enabled = $false
    $script:pendingDomain = $d
    $script:pendingProject = $project
    $script:pendingPassword = $secure
    $script:pendingKey = $secureKey
    $script:pendingSecret = $secureSecret
    $progress.Text = '正在部署，通常约 3–10 分钟；正在处理 DNSHE 与 Cloudflare 配置。'
    $hint.Text = '网站部署完成后，DNS 与证书生效可能还需数分钟至数小时。'
    try {
        $script:deploymentRunspace = [runspacefactory]::CreateRunspace()
        $script:deploymentRunspace.ApartmentState = 'STA'
        $script:deploymentRunspace.ThreadOptions = 'ReuseThread'
        $script:deploymentRunspace.Open()
        $script:deploymentPowerShell = [powershell]::Create()
        $script:deploymentPowerShell.Runspace = $script:deploymentRunspace
        $code = 'param($scriptPath,$projectName,$domainName,$adminPassword,$dnsheKey,$dnsheSecret) & $scriptPath -ProjectName $projectName -Domain $domainName -AdminPassword $adminPassword -DnsheKey $dnsheKey -DnsheSecret $dnsheSecret; if (-not $?) { throw "部署脚本失败" }; "__DEPLOY_SUCCESS__"'
        [void]$script:deploymentPowerShell.AddScript($code)
        foreach ($value in @($deployScript,$project,$d,$secure,$secureKey,$secureSecret)) {
            [void]$script:deploymentPowerShell.AddArgument($value)
        }
        $script:deploymentHandle = $script:deploymentPowerShell.BeginInvoke()
        $script:deploymentStarted = Get-Date
        $script:deploymentTimer.Start()
    } catch {
        $progress.Text = '部署未完成，请查看错误提示。'
        [Windows.Forms.MessageBox]::Show("部署未完成：$($_.Exception.Message)")
        $deployButton.Enabled = $true
        if ($script:deploymentPowerShell) { $script:deploymentPowerShell.Dispose() }
        if ($script:deploymentRunspace) { $script:deploymentRunspace.Dispose() }
        $secure.Dispose(); $secureKey.Dispose(); $secureSecret.Dispose()
    }
})
$tabs.SelectedIndex = 0
[void]$form.ShowDialog()
