# Windows PowerShell 5.1 desktop wizard. Keep this file UTF-8 with BOM.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$script:appVersion = '1.4.5'
$deployScript = Join-Path $PSScriptRoot 'deploy.ps1'
$bundledNode = Join-Path $PSScriptRoot 'runtime\node.exe'
$bundledWrangler = Join-Path $PSScriptRoot 'runtime\node_modules\wrangler\bin\wrangler.js'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'readme-view.ps1')
. (Join-Path $PSScriptRoot 'site-store.ps1')
. (Join-Path $PSScriptRoot 'site-browser.ps1')

function Normalize-DeploymentDomain([string]$Value) {
    $value = $Value.Trim()
    if (-not $value) { return '' }
    if ($value -notmatch '^[a-z][a-z0-9+.-]*://') { $value = 'https://' + $value }
    $uri = $null
    if ([Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -in @('http','https') -and
            -not $uri.UserInfo -and $uri.IsDefaultPort) { return $uri.DnsSafeHost.TrimEnd('.').ToLowerInvariant() }
    return $Value.Trim()
}

function New-AdministratorPassword {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        do {
            $value = New-Object Text.StringBuilder
            while ($value.Length -lt 20) {
                $bytes = New-Object byte[] 1
                $random.GetBytes($bytes)
                if ($bytes[0] -lt (256 - (256 % $alphabet.Length))) {
                    [void]$value.Append($alphabet[$bytes[0] % $alphabet.Length])
                }
            }
            $passwordValue = $value.ToString()
        } until ($passwordValue -cmatch '[A-Z]' -and $passwordValue -cmatch '[a-z]' -and $passwordValue -match '[0-9]')
        return $passwordValue
    } finally { $random.Dispose() }
}

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class OpenProxySetupWindow : Form
{
    private Rectangle normalBounds;
    private bool hasTaskbarProperties;
    private static readonly Guid AppPropertySet = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    public OpenProxySetupWindow()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey
    {
        public Guid Format;
        public uint Id;
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct PropVariant
    {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Text;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }

    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out IPropertyStore store);

    [DllImport("user32.dll")]
    private static extern bool RedrawWindow(IntPtr window, IntPtr rect, IntPtr region, uint flags);

    public static void MarkDocumentLink(IntPtr window)
    {
        const int charFormatSize = 116; // CHARFORMAT2W
        IntPtr format = Marshal.AllocHGlobal(charFormatSize);
        try
        {
            Marshal.Copy(new byte[charFormatSize], 0, format, charFormatSize);
            Marshal.WriteInt32(format, 0, charFormatSize);
            Marshal.WriteInt32(format, 4, 0x20); // CFM_LINK
            Marshal.WriteInt32(format, 8, 0x20); // CFE_LINK
            SendMessage(window, 0x444, new IntPtr(1), format); // EM_SETCHARFORMAT, SCF_SELECTION
        }
        finally { Marshal.FreeHGlobal(format); }
    }

    private static void SetWindowProperty(IPropertyStore store, uint id, string text)
    {
        PropertyKey key = new PropertyKey { Format = AppPropertySet, Id = id };
        PropVariant value = new PropVariant();
        if (text != null)
        {
            value.Type = 31; // VT_LPWSTR
            value.Text = Marshal.StringToCoTaskMemUni(text);
        }
        try { store.SetValue(ref key, ref value); }
        finally { if (value.Text != IntPtr.Zero) Marshal.FreeCoTaskMem(value.Text); }
    }

    public void SetTaskbarIdentity(string command, string iconPath)
    {
        Guid iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        if (SHGetPropertyStoreForWindow(Handle, ref iid, out store) != 0) return;
        hasTaskbarProperties = true;
        try
        {
            SetWindowProperty(store, 2, command);
            SetWindowProperty(store, 3, iconPath + ",0");
            SetWindowProperty(store, 4, "Open Proxy Setup");
            SetWindowProperty(store, 5, "OpenProxySetup.DeploymentWizard");
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    protected override void OnFormClosed(FormClosedEventArgs args)
    {
        if (hasTaskbarProperties && IsHandleCreated)
        {
            Guid iid = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            if (SHGetPropertyStoreForWindow(Handle, ref iid, out store) == 0)
            {
                try
                {
                    foreach (uint id in new uint[] { 5, 4, 3, 2 })
                        SetWindowProperty(store, id, null);
                }
                catch (COMException) {}
                finally { Marshal.ReleaseComObject(store); }
            }
        }
        base.OnFormClosed(args);
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    public static void EnableDisplayScaling()
    {
        try
        {
            // The GUI runs inside a Windows PowerShell host, so set awareness on this thread.
            SetThreadDpiAwarenessContext(new IntPtr(-2));
        }
        catch (EntryPointNotFoundException) {}
    }

    public int DisplayPixels(int logicalPixels)
    {
        if (!IsHandleCreated) return logicalPixels;
        try
        {
            uint dpi = GetDpiForWindow(Handle);
            if (dpi != 0) return (int)Math.Round(logicalPixels * dpi / 96.0);
        }
        catch (EntryPointNotFoundException) {}
        return logicalPixels;
    }

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
        BeginInvoke(new MethodInvoker(RefreshWindow));
    }

    private void RefreshWindow()
    {
        // Invalidate children and erase the former window bounds after the layout passes.
        RedrawWindow(Handle, IntPtr.Zero, IntPtr.Zero, 0x0185);
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
            int grip = DisplayPixels(7);
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

[OpenProxySetupWindow]::EnableDisplayScaling()
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object OpenProxySetupWindow
$form.FormBorderStyle = 'None'
$form.Text = 'Open Proxy Setup'
$form.AutoScaleMode = 'None'
$proxyScript = Join-Path $PSScriptRoot 'proxy.ps1'
. $proxyScript

$palettes = @{
    light = @{
        Background='#F6F8FC'; Ink='#14213B'; Surface='#FFFFFF'; Blue='#2651D2'; BlueHover='#193AA8'
        Primary='#244ED8'; PrimaryHover='#193CAE'; OnPrimary='#FCFDFF'; PaleBlue='#EDF2FF'
        Line='#DCE5F2'; Muted='#485771'; Green='#216449'; Red='#9E2C32'; CloseHover='#FDE9EB'
    }
    dark = @{
        Background='#101827'; Ink='#EDF3FF'; Surface='#192336'; Blue='#A5BFFF'; BlueHover='#BCCFFF'
        Primary='#3259CB'; PrimaryHover='#2847A6'; OnPrimary='#FCFDFF'; PaleBlue='#253556'
        Line='#33435F'; Muted='#B2C0D8'; Green='#93D5B9'; Red='#FFADB6'; CloseHover='#51323D'
    }
}
foreach ($palette in $palettes.Values) {
    foreach ($key in @($palette.Keys)) { $palette[$key] = [Drawing.ColorTranslator]::FromHtml($palette[$key]) }
}
$script:theme = $palettes.light
$script:mode = 'light'
$themeFile = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenProxySetup\theme.txt'
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

function Set-TaskbarIdentity {
    if (-not (Test-Path -LiteralPath $iconPath)) { return }
    $exe = Join-Path $PSScriptRoot 'OpenProxySetup.exe'
    $command = if (Test-Path -LiteralPath $exe) { '"' + $exe + '"' } else {
        $powershell = Join-Path $PSHOME 'powershell.exe'
        '"' + $powershell + '" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
            (Join-Path $PSScriptRoot 'app.ps1') + '"'
    }
    try { $form.SetTaskbarIdentity($command, $iconPath) }
    catch [Runtime.InteropServices.COMException] { Write-Warning '无法设置应用的任务栏图标。' }
}

function Get-ChildControls($parent) {
    foreach ($child in $parent.Controls) {
        $child
        Get-ChildControls $child
    }
}

function Set-DisplayLayout {
    [void]$form.Handle
    if ($form.DisplayPixels(96) -eq 96) { return }

    # Set the existing logical bounds once. Restore anchoring after the docking layout
    # has run so WinForms doesn't move right-anchored buttons twice.
    $controls = @(foreach ($control in (Get-ChildControls $form)) {
        [pscustomobject]@{ Control=$control; Bounds=$control.Bounds; Anchor=$control.Anchor }
    })
    $form.SuspendLayout()
    foreach ($item in $controls) {
        $item.Control.SuspendLayout()
        if ($item.Control.Dock -eq 'None') { $item.Control.Anchor = 'Top,Left' }
    }
    try {
        $form.MinimumSize = [Drawing.Size]::new($form.DisplayPixels($form.MinimumSize.Width), $form.DisplayPixels($form.MinimumSize.Height))
        $form.ClientSize = [Drawing.Size]::new($form.DisplayPixels(900), $form.DisplayPixels(670))
        foreach ($item in $controls) {
            $bounds = $item.Bounds
            $control = $item.Control
            switch ($control.Dock) {
                'None' { $control.SetBounds($form.DisplayPixels($bounds.X), $form.DisplayPixels($bounds.Y),
                    $form.DisplayPixels($bounds.Width), $form.DisplayPixels($bounds.Height)) }
                'Top' { $control.Height = $form.DisplayPixels($bounds.Height) }
                'Bottom' { $control.Height = $form.DisplayPixels($bounds.Height) }
            }
        }
    } finally {
        $form.ResumeLayout($true)
        foreach ($item in $controls) { $item.Control.ResumeLayout($true) }
        foreach ($item in $controls) {
            if ($item.Control.Dock -eq 'None') { $item.Control.Anchor = $item.Anchor }
        }
    }
}

function Update-ThemeColors($control, [hashtable]$map) {
    foreach ($name in @('BackColor','ForeColor')) {
        $value = $control.$name.ToArgb()
        if ($map.ContainsKey($value)) { $control.$name = $map[$value] }
    }
    if ($control -is [Windows.Forms.LinkLabel]) {
        foreach ($name in @('LinkColor','ActiveLinkColor','VisitedLinkColor')) {
            $value = $control.$name.ToArgb()
            if ($map.ContainsKey($value)) { $control.$name = $map[$value] }
        }
    }
    if ($control -is [Windows.Forms.Button]) {
        foreach ($name in @('BorderColor','MouseOverBackColor','MouseDownBackColor')) {
            $value = $control.FlatAppearance.$name.ToArgb()
            if ($map.ContainsKey($value)) { $control.FlatAppearance.$name = $map[$value] }
        }
    }
    if ($control.Tag -is [hashtable] -and $control.Tag.ContainsKey('Fill')) {
        foreach ($name in @('Fill','Line')) {
            $value = $control.Tag[$name].ToArgb()
            if ($map.ContainsKey($value)) { $control.Tag[$name] = $map[$value] }
        }
    }
    foreach ($child in $control.Controls) { Update-ThemeColors $child $map }
}

function Set-Appearance([string]$mode, [switch]$Save) {
    if (-not $palettes.ContainsKey($mode)) { return }
    if ($script:mode -ne $mode) {
        $nextPalette = $palettes[$mode]
        $map = @{}
        foreach ($key in $theme.Keys) { $map[$theme[$key].ToArgb()] = $nextPalette[$key] }
        $script:theme = $nextPalette
        $script:mode = $mode
        Update-ThemeColors $form $map
    }
    foreach ($button in @($dayButton,$nightButton)) {
        $selected = $button.Tag -eq $script:mode
        $button.BackColor = if ($selected) { $theme.PaleBlue } else { $theme.Surface }
        $button.ForeColor = if ($selected) { $theme.Blue } else { $theme.Muted }
        $button.AccessibleDescription = if ($selected) { '当前模式' } else { '' }
    }
    $form.Invalidate($true)
    if ($script:readmeData) { Show-Readme -KeepPosition }
    if ($script:siteBrowser) { $script:siteBrowser.SetTheme($mode -eq 'dark') }
    if ($sectionDeployButton) { Update-AppSection }
    if ($Save) {
        try {
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $themeFile))
            [IO.File]::WriteAllText($themeFile,$mode)
        } catch {}
    }
}

function Read-Appearance {
    if (Test-Path -LiteralPath $themeFile) {
        try {
            $saved = [IO.File]::ReadAllText($themeFile).Trim()
            if ($palettes.ContainsKey($saved)) { return $saved }
        } catch {}
    }
    try {
        $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        if ((Get-ItemPropertyValue -LiteralPath $personalize -Name AppsUseLightTheme) -eq 0) { return 'dark' }
    } catch {}
    return 'light'
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
        $path = New-RoundedPath ($sender.Width-1) ($sender.Height-1) ($form.DisplayPixels($sender.Tag.Radius))
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
    $link.VisitedLinkColor = $theme.Blue
    $link.LinkBehavior = 'HoverUnderline'
    $link.Tag = $url
    $link.add_LinkClicked({
        if ($this.Tag) {
            if ($this.AccessibleDescription -eq 'app-dashboard') {
                try {
                    Open-DeploymentDashboard ([string]$this.Tag)
                } catch { $manageStatus.Text = '后台暂时无法打开，请在后台管理页面重试。'; Show-WizardPage $managePage }
            } else { Start-Process -FilePath $this.Tag }
        }
    })
    $parent.Controls.Add($link)
    return $link
}

function Set-ButtonStyle($button, [bool]$primary = $false) {
    $button.FlatStyle = 'Flat'
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = if ($primary) { $theme.Primary } else { $theme.Surface }
    $button.ForeColor = if ($primary) { $theme.OnPrimary } else { $theme.Blue }
    $button.FlatAppearance.BorderColor = if ($primary) { $theme.Primary } else { $theme.Line }
    $button.FlatAppearance.MouseOverBackColor = if ($primary) { $theme.PrimaryHover } else { $theme.PaleBlue }
    $button.FlatAppearance.MouseDownBackColor = $button.FlatAppearance.MouseOverBackColor
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    Update-ButtonRegion $button
    $button.add_SizeChanged({ Update-ButtonRegion $this })
}

function Update-ButtonRegion($button) {
    $radius = [Math]::Min($form.DisplayPixels(8), [Math]::Min($button.Width,$button.Height) / 2)
    if ($radius -lt 1) { return }
    $old = $button.Region
    $path = New-RoundedPath $button.Width $button.Height $radius
    try { $button.Region = New-Object Drawing.Region($path) }
    finally {
        $path.Dispose()
        if ($old) { $old.Dispose() }
    }
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
$header.BackColor = $theme.Surface
$header.Dock = 'Top'
$header.Height = 62
$form.Controls.Add($header)
if (Test-Path -LiteralPath $iconPath) {
    $brand = New-Object Windows.Forms.PictureBox
    $brand.Bounds = New-Object Drawing.Rectangle(30,10,42,42)
    $brand.SizeMode = 'Zoom'
    $brandIcon = [Drawing.Icon]::new($iconPath,128,128)
    try { $brand.Image = $brandIcon.ToBitmap() }
    finally { $brandIcon.Dispose() }
    $header.Controls.Add($brand)
}
$appName = Add-Heading $header 'Open Proxy Setup' 80 17 275 32 15
$siteLink = Add-Link $header '项目网站 ↗' 'https://openproxysetup.ccwu.cc/' 540 22 86
$docsLink = Add-Link $header '使用文档' '' 644 22 86
$docsLink.add_LinkClicked({ Open-Readme })
foreach ($headerLink in @($siteLink,$docsLink)) { $headerLink.Anchor = 'Top,Right' }
$script:appSection = 'deploy'
function Add-SectionButton([string]$caption,[string]$section,[int]$x) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $caption; $button.Tag = $section
    $button.Bounds = New-Object Drawing.Rectangle($x,12,46,38)
    $button.Anchor = 'Top,Right'
    Set-ButtonStyle $button
    $button.add_Click({
        if ($script:siteConnectionBusy) { return }
        if ($this.Tag -eq 'manage') { Update-SiteList; Show-WizardPage $managePage }
        else { Show-WizardPage $(if ($script:deploymentPage) { $script:deploymentPage } else { $homePage }) }
    })
    $header.Controls.Add($button)
    return $button
}
$sectionDeployButton = Add-SectionButton '部署' 'deploy' 540
$sectionManageButton = Add-SectionButton '管理' 'manage' 592
function Update-AppSection {
    $navigation.Visible = $script:appSection -eq 'deploy'
    foreach ($button in @($sectionDeployButton,$sectionManageButton)) {
        $button.BackColor = if ($button.Tag -eq $script:appSection) { $theme.PaleBlue } else { $theme.Surface }
        $button.ForeColor = if ($button.Tag -eq $script:appSection) { $theme.Blue } else { $theme.Muted }
    }
}
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
$dayButton = Add-WindowButton '☀' '日间模式' 437 { Set-Appearance 'light' -Save }
$nightButton = Add-WindowButton '☾' '暗夜模式' 481 { Set-Appearance 'dark' -Save }
foreach ($button in @($dayButton,$nightButton)) {
    $button.Font = New-Object Drawing.Font('Segoe UI Symbol',14)
    $button.Width = 39
}
$dayButton.Tag = 'light'
$nightButton.Tag = 'dark'
[void](Add-WindowButton '−' '最小化' 752 { $form.WindowState = 'Minimized' })
$maximizeWindow = Add-WindowButton '□' '最大化' 794 { $form.ToggleMaximized() }
$closeWindow = Add-WindowButton '×' '关闭' 836 { $form.Close() }
$closeWindow.FlatAppearance.MouseOverBackColor = $theme.CloseHover
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
$navigation.BackColor = $theme.Surface
$form.Controls.Add($navigation)
$navigation.BringToFront()

$footer = New-Object Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 62
$footer.BackColor = $theme.Surface
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
$footerText = Add-Text $footer ("Windows 部署向导 · v" + $script:appVersion) 32 20 275 26
$footerText.ForeColor = $theme.Muted
$updateLink = Add-Link $footer '检查更新' '' 318 20 160
$updateLink.Width = 100
$footer.Controls.Add($siteLink)
$siteLink.Bounds = New-Object Drawing.Rectangle(430,20,90,26)
$siteLink.Anchor = 'Top,Left'

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
    $page.Size = New-Object Drawing.Size(854,493)
    $page.AutoScroll = $true
    return $page
}

function Add-WizardPage($page, [string]$caption, [int]$width) {
    if ($width -le 0) {
        $script:pages.Add($page)
        $page.Visible = $false
        $viewport.Controls.Add($page)
        return
    }
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
        $available = $viewport.ClientSize.Width
        $preferred = [Math]::Max($form.DisplayPixels(854), $available - $form.DisplayPixels(46))
        $width = [Math]::Min($available, [Math]::Min($form.DisplayPixels(1180), $preferred))
        $page.SetBounds([int](($viewport.ClientSize.Width-$width)/2),0,$width,$viewport.ClientSize.Height)
        $content = $page.Tag
        if ($content) {
            if ($content.Expandable) {
                $content.Panel.Height = [Math]::Max($form.DisplayPixels($content.Height),
                    [Math]::Min($form.DisplayPixels(630), $page.ClientSize.Height-$form.DisplayPixels(48)))
            }
            $room = $page.ClientSize.Height - $content.Panel.Height - $form.DisplayPixels(24)
            $shift = [Math]::Min($form.DisplayPixels(115), [Math]::Max(0, [int]($room/2)))
            $content.Panel.Top = $form.DisplayPixels($content.Top) + $shift
        }
        if ($page -eq $homePage -and $workflow) {
            $extra = [Math]::Max(0, $homeBody.Width - $form.DisplayPixels(854))
            $workflow.Width = $form.DisplayPixels(346) + [Math]::Min($form.DisplayPixels(100), [int]($extra/4))
            $workflow.Left = $homeBody.Width - $workflow.Width - $form.DisplayPixels(39)
        }
    }
}
$form.add_Shown({ Fit-WizardPage $script:currentPage })
$viewport.add_Resize({ Fit-WizardPage $script:currentPage })

function Update-PageActions {
    if (-not $script:currentPage) { return }
    $index = $script:pages.IndexOf($script:currentPage)
    $reading = $script:currentPage -eq $readmePage -or $script:currentPage -eq $browserPage
    $previous.Text = if ($reading) { '返回' } else { '上一步' }
    $previous.Enabled = $reading -or ($index -gt 0 -and $index -le $script:guidesEnd)
    $previous.Left = if ($reading) { $next.Left } else { $next.Left - $form.DisplayPixels(150) }
    $next.Visible = -not $reading
    $next.Enabled = $index -lt ($script:guidesEnd) -and ($script:currentPage -ne $authPage -or $script:cloudflareVerified)
    $previous.Visible = $reading -or $script:appSection -eq 'deploy'
    $next.Visible = -not $reading -and $script:appSection -eq 'deploy'
}

function Show-WizardPage($page) {
    if (-not $page -or $page -eq $script:currentPage) { return }
    if ($script:currentPage) {
        $script:currentPage.Visible = $false
        $oldButton = $navigationButtons[$script:currentPage]
        if ($oldButton) {
            $oldButton.BackColor = $theme.Surface
            $oldButton.ForeColor = $theme.Muted
        }
    }
    $script:currentPage = $page
    if ($page -ne $readmePage) {
        if ($page -eq $managePage -or $page -eq $siteEditPage -or $page -eq $browserPage) { $script:appSection = 'manage' }
        else { $script:appSection = 'deploy'; $script:deploymentPage = $page }
        try {
            $sectionPath = Join-Path (Split-Path -Parent (Get-SiteStorePath)) 'section.txt'
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $sectionPath))
            [IO.File]::WriteAllText($sectionPath,$script:appSection)
        } catch {}
    }
    Update-AppSection
    $selectedButton = $navigationButtons[$page]
    if ($selectedButton) {
        $selectedButton.BackColor = $theme.PaleBlue
        $selectedButton.ForeColor = $theme.Blue
    }
    Fit-WizardPage $page
    $page.Visible = $true
    $page.BringToFront()
    Update-PageActions
}

$homePage = New-WizardPage
Add-WizardPage $homePage '首页' 68
$homeBody = New-Object Windows.Forms.Panel
$homeBody.Bounds = New-Object Drawing.Rectangle(0,0,854,345)
$homeBody.Anchor = 'Top,Left,Right'
$homePage.Controls.Add($homeBody)
$homePage.Tag = @{ Panel=$homeBody; Height=345; Top=0 }
$title = Add-Heading $homeBody ("部署自己的" + [Environment]::NewLine + "Cloudflare Pages 站点") 37 60 434 114 25
$summary = Add-Text $homeBody '从浏览器授权、域名配置到打开站点后台，在一个 Windows 图形向导里完成。' 39 185 370 58
$summary.ForeColor = $theme.Muted
function Start-DeploymentWizard {
    $networkNotice = New-Object Windows.Forms.Form
    $networkNotice.Text = '开始部署前'
    $networkNotice.ClientSize = New-Object Drawing.Size(530,235)
    $networkNotice.StartPosition = 'CenterParent'; $networkNotice.FormBorderStyle = 'FixedDialog'
    $networkNotice.MaximizeBox = $false; $networkNotice.MinimizeBox = $false
    $networkNotice.ShowInTaskbar = $false
    $networkNotice.BackColor = $theme.Surface; $networkNotice.ForeColor = $theme.Ink
    $networkNotice.Font = $form.Font
    $networkText = Add-Text $networkNotice ("请先开启 VPN 或代理，并确认 Cloudflare 和 DNSHE 均可正常访问。" + [Environment]::NewLine + [Environment]::NewLine + "使用 VPN 或代理服务时，请遵守所在地适用的法律法规。") 24 24 482 130
    $networkText.ForeColor = $theme.Ink
    $continue = New-Object Windows.Forms.Button
    $continue.Text = '已准备好，继续'; $continue.Bounds = New-Object Drawing.Rectangle(320,177,184,38)
    $continue.DialogResult = 'OK'; Set-ButtonStyle $continue $true
    $networkNotice.Controls.Add($continue); $networkNotice.AcceptButton = $continue
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '暂不部署'; $cancel.Bounds = New-Object Drawing.Rectangle(174,177,132,38)
    $cancel.DialogResult = 'Cancel'; Set-ButtonStyle $cancel
    $networkNotice.Controls.Add($cancel); $networkNotice.CancelButton = $cancel
    try { if ($networkNotice.ShowDialog($form) -eq 'OK') { Show-WizardPage $authPage } }
    finally { $networkNotice.Dispose() }
}
Add-Action $homeBody '开始部署  →' 39 263 156 { Start-DeploymentWizard } $true
Add-Action $homeBody '管理已有站点' 209 263 152 { Show-WizardPage $managePage }

$workflow = Add-Card $homeBody 469 39 346 292 $theme.PaleBlue 22
$workflow.Anchor = 'Top,Right'
$workflowCard = Add-Card $workflow 18 18 310 256 $theme.Surface
$workflowCard.Anchor = 'Top,Left,Right'
[void](Add-Heading $workflowCard '部署流程' 19 15 270 34 13)
$flow = @(
    @{Title='授权 Cloudflare'; Detail='在浏览器中登录并确认授权'},
    @{Title='准备域名'; Detail='DNSHE 域名和 API 授权'},
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

$guideCards = @{}
function Add-GuidePage([string]$title,[string]$body,[string]$linkText,[string]$url,[string]$caption,[int]$width,[bool]$withActions = $false) {
    $page = New-WizardPage
    Add-WizardPage $page $caption $width
    $card = Add-Card $page 29 17 796 478 $theme.Surface
    $card.Anchor = 'Top,Left,Right'
    $page.Tag = @{ Panel=$card; Height=478; Top=17; Expandable=$true }
    $guideCards[$page] = $card
    [void](Add-Heading $card $title 26 20 730 41)
    $guide = New-Object Windows.Forms.TextBox
    $guide.Multiline = $true
    $guide.ReadOnly = $true
    $guide.ScrollBars = 'Vertical'
    $guide.BorderStyle = 'None'
    $guideTop = if ($withActions) { 124 } else { 80 }
    $guide.Bounds = New-Object Drawing.Rectangle(28,$guideTop,736,(403-$guideTop))
    $guide.Anchor = 'Top,Bottom,Left,Right'
    $guide.BackColor = $theme.Surface
    $guide.ForeColor = $theme.Muted
    $guide.Font = New-Object Drawing.Font($form.Font.FontFamily,11)
    $guide.Text = $body.Trim()
    $card.Controls.Add($guide)
    $guideLink = Add-Link $card $linkText $url 27 428 730
    $guideLink.Anchor = 'Bottom,Left,Right'
    return $page
}


$authPage = Add-GuidePage '1 登录 Cloudflare' @'
点击下方链接注册或登录自己的 Cloudflare 账号。

你不需要自己创建 KV、Pages 或 DNS 记录。若浏览器授权失败，但部署 API 可访问，可按 README 中的备用方式使用 Cloudflare API Token。设置后从同一个 PowerShell 窗口启动应用，直接点击“我已完成授权，继续”。
点击本页“开始 Cloudflare 授权”。授权工具会打开浏览器。
在浏览器里完成登录和授权，再回到本页点击“我已完成授权，继续”。
应用验证授权后会进入第 2 步，引导你注册或选择 DNSHE 域名。

应用将创建 KV 与 Pages，绑定域名，并用 DNSHE API 添加 CNAME 记录。
DNS 和证书传播可能需要时间。应用会先显示 pages.dev 后台地址。
'@ '打开 Cloudflare 注册或登录页 ↗' 'https://dash.cloudflare.com/sign-up' '1  Cloudflare 授权' 143 $true

$domainGuidePage = Add-GuidePage '2 注册 DNSHE 域名' @'
如果还没有 DNSHE 账号，点击下方链接，在网站注册并登录。

左侧点击“免费域名”，再点击“注册新域名”。
在“选择根域名”下拉框中选择当前可用的后缀，例如 ccwu.cc。
在“域名前缀”中输入想要的名称，例如 myhome。
确认页面显示的完整域名，例如 myhome.ccwu.cc，点击“确认注册”。

如果已经注册过域名，打开 DNSHE 的“我的域名”，复制完整域名即可，不用重复注册。
可用后缀和名额以 DNSHE 网站当前显示为准。
'@ '打开 DNSHE，注册或查看我的域名 ↗' 'https://my.dnshe.com/' '2  注册域名' 108

[void](Add-GuidePage '3 创建 DNSHE 授权' @'
在 DNSHE 左侧点击“免费域名”或首页的“域名管理”。
进入“API 管理”，创建一组 API Key 和 API Secret。

这组授权允许应用替你为所选域名添加 Pages 的 CNAME 记录，不是 DNSHE 的登录密码。
Secret 通常只显示一次；创建后复制到第 4 步的输入框。
不要把 Key、Secret 发到聊天、截图或 GitHub。

如果 DNSHE 域名已有冲突的 DNS 记录，应用会提示你检查，不会覆盖原记录。
'@ '打开 DNSHE API 管理入口 ↗' 'https://my.dnshe.com/' '3  DNSHE 授权' 125)

$script:cloudflareVerified = $false
$script:selectedCloudflareAccount = ''

function Select-CloudflareAccount([string]$Token) {
    $accounts = @()
    for ($page = 1; ; $page++) {
        $reply = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts?per_page=50&page=$page" -Headers @{Authorization="Bearer $Token"} -TimeoutSec 15
        if (-not $reply.success) { throw '无法读取 Cloudflare 账户列表。' }
        $batch = @($reply.result)
        $accounts += $batch
        if ($batch.Count -lt 50) { break }
    }
    if ($script:deployment -and $script:deployment.AccountId -and -not $script:deployment.DomainActive) {
        $accounts = @($accounts | Where-Object id -eq $script:deployment.AccountId)
    }
    if ($env:CLOUDFLARE_ACCOUNT_ID) { $accounts = @($accounts | Where-Object id -eq $env:CLOUDFLARE_ACCOUNT_ID) }
    if (-not $accounts.Count) { throw '未找到可部署的账户。继续部署时请授权原来的账户。' }
    if ($accounts.Count -eq 1) { return $accounts[0] }
    $picker = New-Object Windows.Forms.Form
    $picker.Text = '选择 Cloudflare 部署账户'; $picker.ClientSize = New-Object Drawing.Size(460,150)
    $picker.BackColor = $theme.Surface; $picker.ForeColor = $theme.Ink
    $picker.StartPosition = 'CenterParent'; $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false; $picker.MinimizeBox = $false
    $options = New-Object Windows.Forms.ComboBox
    $options.DropDownStyle = 'DropDownList'; $options.Bounds = New-Object Drawing.Rectangle(20,30,420,32)
    $options.BackColor = $theme.Surface; $options.ForeColor = $theme.Ink
    foreach ($entry in $accounts) { [void]$options.Items.Add(($entry.name + ' · ' + $entry.id.Substring(24))) }
    $options.SelectedIndex = 0; $picker.Controls.Add($options)
    $confirm = New-Object Windows.Forms.Button
    $confirm.Text = '使用此账户'; $confirm.Bounds = New-Object Drawing.Rectangle(300,95,140,35)
    Set-ButtonStyle $confirm $true
    $confirm.DialogResult = 'OK'; $picker.Controls.Add($confirm); $picker.AcceptButton = $confirm
    try { if ($picker.ShowDialog($form) -eq 'OK') { return $accounts[$options.SelectedIndex] } }
    finally { $picker.Dispose() }
    throw '已取消选择 Cloudflare 账户。'
}
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
        $selected = Select-CloudflareAccount $auth.token
        $script:selectedCloudflareAccount = $selected.id
        $authStatus.Text = '已授权：' + $selected.name
        $script:cloudflareVerified = $true
        Show-WizardPage $domainGuidePage
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message) }
    finally { $ErrorActionPreference = $oldPreference; $json = $null; $auth = $null }
})
Set-ButtonStyle $verifiedButton
$authCard.Controls.Add($verifiedButton)

$authStatus = Add-Text $authCard '' 522 75 240 48
$authStatus.ForeColor = $theme.Blue
Add-Action $authCard '切换 / 退出授权' 29 120 230 {
    if ($script:deploymentHandle -or $script:oauthProcess) { $authStatus.Text = '请等待当前操作完成。'; return }
    try {
        $cli = Join-Path (Split-Path -Parent (Split-Path -Parent $bundledWrangler)) 'wrangler-dist\cli.js'
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $bundledNode; $start.Arguments = '--no-warnings "' + $cli + '" logout'
        $start.UseShellExecute = $false; $start.CreateNoWindow = $true
        $process = [Diagnostics.Process]::Start($start)
        try { if (-not $process.WaitForExit(15000)) { $process.Kill(); throw '退出授权超时，请重试。' }; if ($process.ExitCode -ne 0) { throw '退出授权失败，请重试。' } }
        finally { $process.Dispose() }
        $script:cloudflareVerified = $false; $script:selectedCloudflareAccount = ''
        $env:CLOUDFLARE_API_TOKEN = $null; $env:CLOUDFLARE_ACCOUNT_ID = $null
        $authStatus.Text = '已退出。点「开始 Cloudflare 授权」登录。'
    } catch { $authStatus.Text = $_.Exception.Message }
}
foreach ($control in $authCard.Controls) {
    if ($control -is [Windows.Forms.TextBox] -and $control.Multiline) {
        $control.Top = 170; $control.Height = 233
    }
}
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
        $start.Arguments = '--no-warnings "' + $loginCli + '" login --no-browser --scopes account:read user:read pages:write workers_kv:write'
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
$deployCard = Add-Card $deployPage 29 17 796 450 $theme.Surface
$deployCard.Anchor = 'Top,Left,Right'
$deployPage.Tag = @{ Panel=$deployCard; Height=450; Top=17 }
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
    $field.BackColor = $theme.Surface
    $field.ForeColor = $theme.Ink
    $field.Width = 390
    $field.Anchor = 'Top,Left,Right'
    $pasteButton = New-Object Windows.Forms.Button
    $pasteButton.Text = '粘贴'
    $pasteButton.Location = New-Object Drawing.Point(590,$field.Top)
    $pasteButton.Size = New-Object Drawing.Size(75,30)
    $pasteButton.Anchor = 'Top,Right'
    Set-ButtonStyle $pasteButton
    $targetField = $field
    $pasteButton.add_Click({
        try {
            if ([Windows.Forms.Clipboard]::ContainsText()) {
                $pasted = [Windows.Forms.Clipboard]::GetText()
                if ($targetField -ne $password) { $pasted = $pasted.Trim() }
                if ($targetField -eq $domain) { $pasted = Normalize-DeploymentDomain $pasted }
                $targetField.Text = $pasted
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
    $toggleButton.Anchor = 'Top,Right'
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
$domain.add_Leave({ $domain.Text = Normalize-DeploymentDomain $domain.Text })
Add-Action $deployCard '生成强密码' 190 278 135 { $password.Text = New-AdministratorPassword }
Add-Action $deployCard '复制密码' 335 278 110 {
    if (-not $password.Text) { $deployHint.Text = '请先填写或生成管理员密码。'; return }
    try { [Windows.Forms.Clipboard]::SetText($password.Text); $deployHint.Text = '管理员密码已复制。' }
    catch { $deployHint.Text = '暂时无法访问剪贴板，请重试。' }
}
$deployButton = New-Object Windows.Forms.Button
$deployButton.Text = '开始自动部署'
$deployButton.Location = New-Object Drawing.Point(190,324)
$deployButton.Size = New-Object Drawing.Size(260,42)
Set-ButtonStyle $deployButton $true
$deployCard.Controls.Add($deployButton)
Add-Action $deployCard '暂时只发布 Pages' 470 324 240 { Start-Deployment -PagesOnly }
$deployHint = Add-Text $deployCard '' 30 380 750 55
$deployHint.Anchor = 'Top,Left,Right'

$managePage = New-WizardPage
Add-WizardPage $managePage '' 0
$manageCard = Add-Card $managePage 29 17 796 478 $theme.Surface
$manageCard.Anchor = 'Top,Left,Right'
$managePage.Tag = @{ Panel=$manageCard; Height=478; Top=17; Expandable=$true }
[void](Add-Heading $manageCard '站点管理' 26 20 720 42)
[void](Add-Text $manageCard '双击域名验证密码并进入后台，可添加和管理多个站点。' 30 70 730 36)
Add-Action $manageCard '＋ 添加站点' 30 114 190 { Edit-ManagedSite $null } $true
$siteList = New-Object Windows.Forms.ListBox
$siteList.Bounds = New-Object Drawing.Rectangle(30,171,735,214)
$siteList.Anchor = 'Top,Bottom,Left,Right'
$siteList.BorderStyle = 'None'
$siteList.BackColor = $theme.Surface
$siteList.ForeColor = $theme.Ink
$siteList.Font = New-Object Drawing.Font('Microsoft YaHei UI',12)
$siteList.DisplayMember = 'Domain'
$siteList.DrawMode = 'OwnerDrawFixed'
$siteList.ItemHeight = 44
$siteList.IntegralHeight = $false
$siteList.add_DrawItem({
    param($sender,$event)
    if ($event.Index -lt 0) { return }
    $selected = ($event.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0
    $fill = New-Object Drawing.SolidBrush($(if ($selected) { $theme.PaleBlue } else { $theme.Surface }))
    try { $event.Graphics.FillRectangle($fill,$event.Bounds) } finally { $fill.Dispose() }
    $bounds = $event.Bounds; $bounds.Inflate(-$form.DisplayPixels(12),0)
    [Windows.Forms.TextRenderer]::DrawText($event.Graphics,$sender.Items[$event.Index].Display,$sender.Font,$bounds,$theme.Ink,
        ([Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))
})
$siteList.add_DoubleClick({ Open-SelectedSite })
$manageCard.Controls.Add($siteList)
$siteEmpty = Add-Text $manageCard '还没有保存的站点，添加一个即可开始管理。' 40 184 705 42
$manageStatus = Add-Text $manageCard '' 245 119 505 38
$manageStatus.Anchor = 'Top,Left,Right'
Add-Action $manageCard '打开站点' 30 411 142 { Open-SelectedSite } $true
Add-Action $manageCard '编辑' 187 411 90 { if ($siteList.SelectedItem) { Edit-ManagedSite $siteList.SelectedItem } }
Add-Action $manageCard '复制密码' 292 411 110 {
    if (-not $siteList.SelectedItem) { $manageStatus.Text = '请先选择一个站点。'; return }
    try { [Windows.Forms.Clipboard]::SetText($siteList.SelectedItem.password); $manageStatus.Text = '后台密码已复制。' }
    catch { $manageStatus.Text = '暂时无法访问剪贴板，请重试。' }
}
Add-Action $manageCard '复制网址' 410 411 100 {
    if (-not $siteList.SelectedItem) { $manageStatus.Text = '请先选择一个站点。'; return }
    try { [Windows.Forms.Clipboard]::SetText($siteList.SelectedItem.url); $manageStatus.Text = '后台网址已复制。' }
    catch { $manageStatus.Text = '暂时无法访问剪贴板，请重试。' }
}
Add-Action $manageCard '移除' 515 411 70 { Remove-SelectedSite }
Add-Action $manageCard '清除全部记录' 590 411 160 {
    if ([Windows.Forms.MessageBox]::Show($form,'清除全部保存的站点、密码和登录会话？','Open Proxy Setup','OKCancel','Question') -ne 'OK') { return }
    try {
        Remove-SavedSite
        Update-SiteList
        Open-ManageBrowser
        $script:siteBrowser.Forget()
        $manageStatus.Text = '正在清除全部登录会话…'
    } catch { $manageStatus.Text = '清除失败，请重试。' }
}
foreach ($control in $manageCard.Controls) { if ($control -is [Windows.Forms.Button] -and $control.Top -gt 400) { $control.Anchor = 'Bottom,Left' } }
$form.add_Shown({ $siteList.ItemHeight = $form.DisplayPixels(44) })

$siteEditPage = New-WizardPage
Add-WizardPage $siteEditPage '' 0
$siteEditCard = Add-Card $siteEditPage 29 17 796 444 $theme.Surface
$siteEditCard.Anchor = 'Top,Left,Right'
$siteEditPage.Tag = @{ Panel=$siteEditCard; Height=444; Top=17 }
$siteEditTitle = Add-Heading $siteEditCard '添加站点' 26 20 730 42
[void](Add-Text $siteEditCard '密码验证成功后才保存。网址和密码加密保存在本机。' 30 72 730 36)
[void](Add-Text $siteEditCard '站点域名' 30 132 110 30)
$manageUrl = New-Object Windows.Forms.TextBox
$manageUrl.Bounds = New-Object Drawing.Rectangle(150,132,585,30)
$manageUrl.Anchor = 'Top,Left,Right'
$manageUrl.BorderStyle = 'FixedSingle'; $manageUrl.BackColor = $theme.Surface; $manageUrl.ForeColor = $theme.Ink
$siteEditCard.Controls.Add($manageUrl)
[void](Add-Text $siteEditCard '例如 example.pages.dev，支持粘贴完整 HTTPS 网址。' 150 170 585 32)
[void](Add-Text $siteEditCard '后台密码' 30 220 110 30)
$managePassword = New-Object Windows.Forms.TextBox
$managePassword.Bounds = New-Object Drawing.Rectangle(150,220,585,30)
$managePassword.Anchor = 'Top,Left,Right'; $managePassword.UseSystemPasswordChar = $true
$managePassword.BorderStyle = 'FixedSingle'; $managePassword.BackColor = $theme.Surface; $managePassword.ForeColor = $theme.Ink
$siteEditCard.Controls.Add($managePassword)
[void](Add-Text $siteEditCard '备注（可选）' 30 265 110 30)
$manageNote = New-Object Windows.Forms.TextBox
$manageNote.Bounds = New-Object Drawing.Rectangle(150,265,585,30)
$manageNote.Anchor = 'Top,Left,Right'; $manageNote.MaxLength = 120
$manageNote.BackColor = $theme.Surface; $manageNote.ForeColor = $theme.Ink; $manageNote.BorderStyle = 'FixedSingle'
$siteEditCard.Controls.Add($manageNote)
$siteEditStatus = Add-Text $siteEditCard '' 150 355 585 65
$siteEditStatus.Anchor = 'Top,Left,Right'
Add-Action $siteEditCard '验证并打开后台' 150 310 205 { Start-SiteConnection $manageUrl.Text $managePassword.Text $true $script:editingSite -Note $manageNote.Text.Trim() } $true
Add-Action $siteEditCard '验证并保存' 375 310 170 { Start-SiteConnection $manageUrl.Text $managePassword.Text $false $script:editingSite -Note $manageNote.Text.Trim() }
Add-Action $siteEditCard '返回列表' 565 310 170 { Show-WizardPage $managePage }

function Get-AdminUrl([string]$value) {
    $value = $value.Trim()
    if (-not $value) { throw '请输入站点域名。' }
    if ($value -notmatch '^[a-z][a-z0-9+.-]*://') { $value = "https://$value" }
    $uri = $null
    if (-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.Host) {
        throw '请输入有效的 HTTPS 网址或域名。'
    }
    return ($uri.GetLeftPart([UriPartial]::Authority) + '/admin')
}
function Update-SiteList {
    $siteList.Items.Clear()
    try {
        foreach ($site in @(Get-SavedSites)) {
            try { $url = Get-AdminUrl $site.url } catch { continue }
            $uri = [Uri]$url
            $domainName = $uri.Host + $(if (-not $uri.IsDefaultPort) { ':' + $uri.Port } else { '' })
            $note = if ($site.PSObject.Properties['note']) { $site.note } else { '' }
            $display = $domainName + $(if ($note) { '  ·  ' + $note } else { '' })
            [void]$siteList.Items.Add([pscustomobject]@{url=$url; password=$site.password; Domain=$domainName; Note=$note; Display=$display})
        }
        $siteEmpty.Visible = $siteList.Items.Count -eq 0
        if ($siteList.Items.Count) { $siteList.SelectedIndex = 0 }
    } catch { $manageStatus.Text = '保存的站点无法解密，请清除本机记录后重新添加。' }
}
function Edit-ManagedSite($site) {
    $manageUrl.Clear(); $managePassword.Clear(); $manageNote.Clear(); $siteEditStatus.Text = ''
    $script:editingSite = if ($site) { $site.url } else { '' }
    $siteEditTitle.Text = if ($site) { '编辑站点' } else { '添加站点' }
    if ($site) { $manageUrl.Text = $site.Domain; $managePassword.Text = $site.password; $manageNote.Text = $site.Note }
    Show-WizardPage $siteEditPage
}
$manageUrl.add_TextChanged({
    $address = try { Get-AdminUrl $manageUrl.Text } catch { '' }
    if ($address -ne $script:lastManageAddress) { $managePassword.Clear() }
    $script:lastManageAddress = $address
})
function Open-SelectedSite {
    $entry = $siteList.SelectedItem
    if (-not $entry) { $manageStatus.Text = '请先添加或选择一个站点。'; return }
    Start-SiteConnection $entry.url $entry.password $true ''
}
function Remove-SelectedSite {
    $entry = $siteList.SelectedItem
    if (-not $entry) { return }
    if ([Windows.Forms.MessageBox]::Show($form,('移除 ' + $entry.Domain + ' 及其本机登录会话？'),'Open Proxy Setup','OKCancel','Question') -ne 'OK') { return }
    try {
        Remove-SiteEntry $entry.url
        Update-SiteList
        Open-ManageBrowser
        $script:siteBrowser.ForgetSite($entry.url)
        $manageStatus.Text = '已移除该站点。'
    } catch { $manageStatus.Text = '移除失败，请重试。' }
}
function Set-SiteConnectionBusy([bool]$busy) {
    $script:siteConnectionBusy = $busy
    $manageCard.Enabled = $siteEditCard.Enabled = -not $busy
    $sectionDeployButton.Enabled = $sectionManageButton.Enabled = -not $busy
}
function Open-ManageBrowser {
    if ($script:siteBrowser) { return }
    $script:siteBrowser = New-SiteBrowser
    $browserPage.Controls.Add($script:siteBrowser)
    $script:siteBrowser.add_ReturnRequested({ Show-WizardPage $managePage })
    $script:siteBrowser.add_ForgetCompleted({
        $manageStatus.Text = if ($script:siteBrowser.LastForgetSucceeded) { '全部本机站点与登录会话已清除。' } else { '会话清除失败，请重试。' }
    })
    $script:siteBrowser.add_ValidationCompleted({
        param($sender,$event)
        Set-SiteConnectionBusy $false
        if (-not $event.Success) {
            $script:pendingSitePassword = $null
            $siteEditStatus.Text = $manageStatus.Text = $event.Message
            if ($script:currentPage -eq $managePage -and $event.Message.StartsWith('密码不正确')) { $manageStatus.Text += ' 请点「编辑」更新密码。' }
            return
        }
        try {
            $options = @{ PreviousUrl=$script:pendingPreviousSite }
            if ($null -ne $script:pendingSiteNote) { $options.Note = $script:pendingSiteNote }
            Save-SavedSite $event.Url $script:pendingSitePassword @options
            Update-SiteList
            $manageStatus.Text = '密码验证成功，站点已保存。'
            if ($event.OpenRequested) { Show-WizardPage $browserPage } else { Show-WizardPage $managePage }
        } catch { $siteEditStatus.Text = $manageStatus.Text = '验证成功，但站点保存失败，请重试。' }
        finally { $script:pendingSitePassword = $null }
    })
}
function Start-SiteConnection([string]$inputUrl,[string]$secret,[bool]$open,[string]$previousUrl,[string]$Note) {
    if ($script:siteConnectionBusy) { return }
    try {
        $address = Get-AdminUrl $inputUrl
        if (-not $secret) { throw '请输入后台密码。' }
        $script:pendingSitePassword = $secret
        $script:pendingPreviousSite = $previousUrl
        $script:pendingSiteNote = if ($PSBoundParameters.ContainsKey('Note')) { $Note } else { $null }
        Open-ManageBrowser
        Set-SiteConnectionBusy $true
        $manageStatus.Text = $siteEditStatus.Text = '正在验证密码…'
        $script:siteBrowser.Open($address,$secret,($script:mode -eq 'dark'),$open)
    } catch { Set-SiteConnectionBusy $false; $manageStatus.Text = $siteEditStatus.Text = $_.Exception.Message }
}
function Open-DeploymentDashboard([string]$address) {
    $secret = $script:deploymentAdminPassword
    foreach ($entry in @(Get-SavedSites)) { if ($entry.url -eq $address) { $secret = $entry.password; break } }
    if (-not $secret) { Edit-ManagedSite $null; $manageUrl.Text = ([Uri]$address).Host; return }
    Start-SiteConnection $address $secret $true ''
}
$browserPage = New-WizardPage
Add-WizardPage $browserPage '' 0
Update-SiteList

$progressPage = New-WizardPage
Add-WizardPage $progressPage '部署进度' 97
$navigationButtons[$progressPage].Visible = $false
$progressCard = Add-Card $progressPage 29 17 796 476 $theme.Surface
$progressCard.Anchor = 'Top,Left,Right'
$progressPage.Tag = @{ Panel=$progressCard; Height=476; Top=17 }
[void](Add-Heading $progressCard '部署进度' 26 18 730 40)
$stageNames = @('', '验证 Cloudflare 授权', '创建 Cloudflare KV', '发布 Cloudflare Pages', '绑定域名（Cloudflare / DNSHE）')
$stageRows = @(foreach ($i in 1..4) {
    $row = Add-Card $progressCard 26 (64 + ($i - 1) * 34) 742 30 $theme.PaleBlue 7
    $row.Anchor = 'Top,Left,Right'
    $stageLabel = Add-Text $row '' 10 0 723 30
    $stageLabel.Anchor = 'Top,Left,Right'
    $stageLabel.TextAlign = 'MiddleLeft'
    $stageLabel
})
$progress = Add-Text $progressCard '' 26 205 736 40
$progressDetail = New-Object Windows.Forms.TextBox
$progressDetail.Location = New-Object Drawing.Point(30,245)
$progressDetail.Size = New-Object Drawing.Size(735,82)
$progressDetail.Anchor = 'Top,Left,Right'
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
    $link.AccessibleDescription = 'app-dashboard'
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
Add-Action $progressCard '复制诊断信息' 594 420 175 {
    $state = $script:deployment
    if (-not $state) { $progress.Text = '当前尚无部署记录。'; return }
    $kind = [regex]::Matches($progressDetail.Text,'HTTP [0-9]{3}|超时|DNS|HTTPS|403|权限|配额|连接中断|授权已过期') |
        ForEach-Object { $_.Value } | Select-Object -Unique
    $hasFailure = $state.FailedStep -gt 0 -and $state.FailedStep -lt $stageNames.Count
    $stage = if ($hasFailure) { $stageNames[$state.FailedStep] } else { '无' }
    $category = if (-not $hasFailure) { '未记录失败' } elseif ($kind) { $kind -join '、' } else { '服务请求失败，请对照应用提示' }
    $report = "Open Proxy Setup Windows v$script:appVersion" + [Environment]::NewLine +
        "失败阶段：$stage" + [Environment]::NewLine +
        "Pages 已发布：$($state.PagesReady)；域名已验证：$($state.DomainActive)" + [Environment]::NewLine + "错误类别：$category"
    try { [Windows.Forms.Clipboard]::SetText($report); $progress.Text = '诊断信息已复制。' }
    catch { $progress.Text = '暂时无法访问剪贴板，请重试。' }
}

$readmePage = New-WizardPage
Add-WizardPage $readmePage '' 0
$readmeCard = Add-Card $readmePage 29 17 796 478 $theme.Surface
$readmeCard.Anchor = 'Top,Left,Right'
$readmePage.Tag = @{ Panel=$readmeCard; Height=478; Top=17; Expandable=$true }
[void](Add-Heading $readmeCard '使用文档' 26 18 270 40)
$readmeFiles = @('README.md','README.en.md','README.ja.md','README.ko.md')
$readmeLanguage = New-Object Windows.Forms.ComboBox
$readmeLanguage.DropDownStyle = 'DropDownList'
$readmeLanguage.Bounds = New-Object Drawing.Rectangle(612,23,156,30)
$readmeLanguage.Anchor = 'Top,Right'
$readmeLanguage.BackColor = $theme.Surface
$readmeLanguage.ForeColor = $theme.Ink
$readmeLanguage.AccessibleName = '文档语言'
$readmeLanguage.Items.AddRange([object[]]@('简体中文','English','日本語','한국어'))
$readmeLanguage.SelectedIndex = 0
$readmeCard.Controls.Add($readmeLanguage)
$readmeToc = New-Object Windows.Forms.ListBox
$readmeToc.Bounds = New-Object Drawing.Rectangle(26,73,180,376)
$readmeToc.Anchor = 'Top,Bottom,Left'
$readmeToc.IntegralHeight = $false
$readmeToc.HorizontalScrollbar = $true
$readmeToc.BorderStyle = 'FixedSingle'
$readmeToc.AccessibleName = '本页目录'
$readmeToc.BackColor = $theme.Surface
$readmeToc.ForeColor = $theme.Ink
$readmeCard.Controls.Add($readmeToc)
$readmeBox = New-Object Windows.Forms.RichTextBox
$readmeBox.Bounds = New-Object Drawing.Rectangle(228,70,540,380)
$readmeBox.Anchor = 'Top,Bottom,Left,Right'
$readmeBox.BorderStyle = 'None'
$readmeBox.BackColor = $theme.Surface
$readmeBox.ForeColor = $theme.Ink
$readmeBox.ReadOnly = $true
$readmeBox.DetectUrls = $false
$readmeBox.ScrollBars = 'Vertical'
$readmeBox.AccessibleName = '文档正文'
$readmeCard.Controls.Add($readmeBox)

function Show-Readme([switch]$KeepPosition) {
    $position = if ($KeepPosition) { $readmeBox.GetCharIndexFromPosition([Drawing.Point]::new(1,1)) } else { 0 }
    $readmeToc.Items.Clear()
    try {
        $path = Join-Path $PSScriptRoot $readmeFiles[$readmeLanguage.SelectedIndex]
        $script:readmeData = ConvertTo-ReadmeDocument ([IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)) $theme.Ink $theme.Blue
        $readmeBox.Rtf = $script:readmeData.Rtf
        # Mark only Markdown link spans. Rich Edit drops imported RTF hyperlink fields.
        $spans = [regex]::Matches($readmeBox.Text, '\uE000([^\uE001]+)\uE001')
        $readmeBox.ReadOnly = $false
        try {
            for ($i=$spans.Count-1; $i -ge 0; $i--) {
                $span = $spans[$i]
                $readmeBox.Select($span.Index + $span.Length - 1,1)
                $readmeBox.SelectedText = ''
                $readmeBox.Select($span.Index,1)
                $readmeBox.SelectedText = ''
                $readmeBox.Select($span.Index,$span.Length - 2)
                [OpenProxySetupWindow]::MarkDocumentLink($readmeBox.Handle)
            }
        } finally { $readmeBox.ReadOnly = $true }
        $readmeToc.Items.AddRange([object[]]$script:readmeData.Headings)
        $readmeBox.Select([Math]::Min($position,$readmeBox.TextLength),0)
        $readmeBox.ScrollToCaret()
    } catch {
        $script:readmeData = $null
        $readmeBox.Text = '无法读取随包文档，请完整解压下载包后重试。'
    }
}

function Open-Readme {
    if ($script:currentPage -eq $readmePage) { return }
    $script:readmeReturnPage = $script:currentPage
    Show-WizardPage $readmePage
    if (-not $script:readmeData) { Show-Readme }
    [void]$readmeLanguage.Focus()
}

$readmeLanguage.add_SelectedIndexChanged({ Show-Readme })
$readmeToc.add_SelectedIndexChanged({
    if ($this.SelectedIndex -lt 0) { return }
    $heading = [regex]::Match($readmeBox.Text, '(?m)^' + [regex]::Escape([string]$this.SelectedItem) + '$')
    if ($heading.Success) {
        $readmeBox.Select($heading.Index,0)
        $readmeBox.ScrollToCaret()
    }
})
$readmeBox.add_LinkClicked({
    param($sender,$event)
    $target = $event.LinkText
    if ($script:readmeData -and $script:readmeData.Links.ContainsKey($target)) {
        $target = $script:readmeData.Links[$target]
    }
    $uri = $null
    if ([uri]::TryCreate($target,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -in @('https','http')) {
        Start-Process -FilePath $uri.AbsoluteUri
    }
})
$form.KeyPreview = $true
$form.add_KeyDown({
    param($sender,$event)
    if ($event.KeyCode -eq 'Escape' -and $script:currentPage -eq $readmePage -and -not $readmeLanguage.DroppedDown) {
        Show-WizardPage $script:readmeReturnPage
        $event.SuppressKeyPress = $true
    }
})

$previous = New-Object Windows.Forms.Button
$previous.Text = '上一步'
$previous.Location = New-Object Drawing.Point(571,11)
$previous.Size = New-Object Drawing.Size(132,40)
Set-ButtonStyle $previous
$previous.Anchor = 'Top,Right'
$previous.add_Click({
    if ($script:currentPage -eq $readmePage) { Show-WizardPage $script:readmeReturnPage }
    elseif ($script:currentPage -eq $browserPage) { Show-WizardPage $managePage }
    else { Show-WizardPage $script:pages[($script:pages.IndexOf($script:currentPage) - 1)] }
})
$footer.Controls.Add($previous)
$next = New-Object Windows.Forms.Button
$next.Text = '下一步'
$next.Location = New-Object Drawing.Point(721,11)
$next.Size = New-Object Drawing.Size(147,40)
Set-ButtonStyle $next $true
$next.Anchor = 'Top,Right'
$next.add_Click({
    if ($script:currentPage -eq $homePage) { Start-DeploymentWizard }
    else { Show-WizardPage $script:pages[($script:pages.IndexOf($script:currentPage) + 1)] }
})
$footer.Controls.Add($next)

$script:deployment = $null
$script:deploymentHandle = $null
$script:deploymentTimer = New-Object Windows.Forms.Timer
$script:deploymentTimer.Interval = 300
$script:domainCheckUntil = [DateTime]::MinValue
$script:domainCheckAfter = [DateTime]::MinValue
$domainPollTimer = New-Object Windows.Forms.Timer
$domainPollTimer.Interval = 1000
$domainPollTimer.add_Tick({
    if ($script:currentPage -ne $progressPage -or -not $form.ContainsFocus -or $script:deploymentHandle) { return }
    $now = [DateTime]::UtcNow
    $state = $script:deployment
    if ($state -and $state.PagesReady -and $state.DomainConfigured -and -not $state.DomainActive -and
            $now -lt $script:domainCheckUntil -and $now -ge $script:domainCheckAfter) {
        $script:domainCheckAfter = $now.AddSeconds(30)
        Start-Deployment -CheckDomainOnly
    }
})
$domainPollTimer.Start()
$form.add_FormClosed({ $domainPollTimer.Stop(); $domainPollTimer.Dispose() })

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
        if ($script:runPassword) { $script:deploymentAdminPassword = [System.Net.NetworkCredential]::new('', $script:runPassword).Password }
        try {
            Save-SavedSite $result.Tag $script:deploymentAdminPassword
            $script:deploymentSiteUrl = $result.Tag
            Update-SiteList
        } catch { $manageStatus.Text = '部署完成，但站点未保存，请手动添加。' }
        $password.Clear()
    }
    if ($state.DomainActive) {
        $customResult.Tag = "https://$($state.Domain)/admin"
        $customResult.Visible = $true
        if ($script:deploymentSiteUrl -ne $customResult.Tag) {
            try {
                Save-SavedSite $customResult.Tag $script:deploymentAdminPassword -PreviousUrl $script:deploymentSiteUrl
                $script:deploymentSiteUrl = $customResult.Tag
                Update-SiteList
            } catch { $manageStatus.Text = '请在管理页面手动添加站点。' }
        }
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
            '如授权已过期，请回到第 1 步重新授权。遇到 403 时请核对 Cloudflare 账号与权限。',
            '请检查 Cloudflare 的 KV 权限或配额，然后点「继续部署」。',
            '请检查 Cloudflare Pages 权限与网络，然后点「继续部署」。',
            '请根据下方信息修正 Cloudflare 或 DNSHE 配置，再点「重试域名绑定」。'
        )
        $progressDetail.Text = $advice[$state.FailedStep] + [Environment]::NewLine + $detail
    } elseif (-not $state.Domain) {
        $progress.Text = 'Pages 已发布，可以打开后台。'
        $progressDetail.Text = '之后可返回填写域名和 DNSHE 授权，继续绑定自定义域名。'
    } else {
        $progress.Text = 'Pages 已上线，正在等待自定义域名的 DNS 或证书验证。'
        $progressDetail.Text = '保持进度页打开，应用每 30 秒查询状态，持续约 5 分钟；也可手动重新验证。'
        if ($script:domainCheckUntil -eq [DateTime]::MinValue) {
            $script:domainCheckUntil = [DateTime]::UtcNow.AddMinutes(5)
            $script:domainCheckAfter = [DateTime]::UtcNow.AddSeconds(30)
        }
    }
    $progress.Text += ' 本次用时 {0:hh\:mm\:ss}。' -f $elapsed
    $deployHint.Text = $progress.Text
    $manageStatus.Text = $progress.Text
    $domain.ReadOnly = $state.DomainStarted -and -not $state.DomainActive
    $apiKey.ReadOnly = $apiSecret.ReadOnly = $false
    $password.ReadOnly = $state.PagesReady -and -not $state.DomainActive
    $deployButton.Enabled = $true
    $deployButton.Text = if ($state.DomainActive) { '开始自动部署' } elseif ($state.PagesReady -and $state.DomainConfigured) { '重新验证' } elseif ($state.PagesReady) { '绑定域名' } else { '继续部署' }
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

function Start-Deployment([switch]$PagesOnly, [switch]$CheckDomainOnly) {
    if ($script:deploymentHandle) { return }
    $state = $script:deployment
    $resume = $state -and -not $state.DomainActive
    if ($resume -and -not $state.Domain -and -not $domain.Text.Trim()) { $PagesOnly = $true }
    if ($resume -and $state.PagesReady -and $state.DomainConfigured) { $CheckDomainOnly = $true }
    $d = if ($PagesOnly) { '' } elseif ($resume -and $state.DomainStarted) { $state.Domain } else { Normalize-DeploymentDomain $domain.Text }
    if ($PagesOnly -and $resume -and $state.DomainStarted) { $deployHint.Text = '本次部署已提交域名，请继续查询域名验证。'; return }
    if (-not $PagesOnly -and $d -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        $deployHint.Text = '请填写 DNSHE“我的域名”中的完整域名。'
        Show-WizardPage $deployPage
        return
    }
    if (-not $PagesOnly -and -not $CheckDomainOnly -and (-not $apiKey.Text.Trim() -or -not $apiSecret.Text)) {
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
        $script:domainCheckUntil = [DateTime]::MinValue
        $script:deploymentSiteUrl = $script:deploymentAdminPassword = ''
        $state = [hashtable]::Synchronized(@{
            ProjectName = 'zijianjichang-' + ([guid]::NewGuid().ToString('N')).Substring(0,8)
            Domain = $d; Step = 0; LastStep = 0; FailedStep = 0
            StepStarted = [DateTime]::UtcNow; Times = @(0.0,0.0,0.0,0.0,0.0)
            AccountId = $script:selectedCloudflareAccount; KvId = ''; KvAttempted = $false; ProjectAttempted = $false
            ProjectCreated = $false; PagesReady = $false; DomainStarted = $false; DomainConfigured = $false; DomainActive = $false
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
    $navigationButtons[$progressPage].Visible = $true
    Show-WizardPage $progressPage
    Show-DeploymentProgress
    try {
        $script:runPassword = if (-not $state.PagesReady) { ConvertTo-SecureString $password.Text -AsPlainText -Force }
        $script:runKey = if ($d -and -not $CheckDomainOnly) { ConvertTo-SecureString $apiKey.Text.Trim() -AsPlainText -Force }
        $script:runSecret = if ($d -and -not $CheckDomainOnly) { ConvertTo-SecureString $apiSecret.Text -AsPlainText -Force }
        $script:deploymentRunspace = [runspacefactory]::CreateRunspace()
        $script:deploymentRunspace.Open()
        $script:deploymentPowerShell = [powershell]::Create()
        $script:deploymentPowerShell.Runspace = $script:deploymentRunspace
        [void]$script:deploymentPowerShell.AddCommand($deployScript)
        [void]$script:deploymentPowerShell.AddParameters(@{
            ProjectName = $state.ProjectName; Domain = $state.Domain; Deployment = $state
            AdminPassword = $script:runPassword; DnsheKey = $script:runKey; DnsheSecret = $script:runSecret
            PagesOnly = [bool]$PagesOnly
            CheckDomainOnly = [bool]$CheckDomainOnly
        })
        $script:deploymentHandle = $script:deploymentPowerShell.BeginInvoke()
        $script:deploymentTimer.Start()
    } catch {
        Complete-Deployment '无法启动部署。请检查应用文件，或重新打开应用。' $true
    }
}

$deployButton.add_Click({ Start-Deployment })
$retry.add_Click({ Start-Deployment })

$script:updateHandle = $null
$script:updateResult = $null
$script:updatePowerShell = $null
$script:updateRunspace = $null
$script:updateManual = $false
$updateTimer = New-Object Windows.Forms.Timer
$updateTimer.Interval = 500

function Show-AppUpdate($available) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Open Proxy Setup 更新'
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(480,185)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $dialog.MinimizeBox = $false
    $dialog.BackColor = $theme.Surface
    $dialog.Font = $form.Font
    $message = Add-Text $dialog ("发现新版本 v" + $available.Version + [Environment]::NewLine +
        "当前版本 v" + $script:appVersion + "。下载完成后运行安装程序进行更新。") 22 24 436 76
    $message.ForeColor = $theme.Ink
    Add-Action $dialog '下载更新' 22 123 135 {} $true
    Add-Action $dialog '前往官网' 172 123 135 {}
    Add-Action $dialog '稍后' 322 123 135 {}
    $buttons = @($dialog.Controls | Where-Object { $_ -is [Windows.Forms.Button] })
    $buttons[0].DialogResult = 'Yes'
    $buttons[1].DialogResult = 'No'
    $buttons[2].DialogResult = 'Cancel'
    $dialog.CancelButton = $buttons[2]
    try {
        $choice = $dialog.ShowDialog($form)
        if ($choice -eq 'Yes') { Start-Process -FilePath $available.DownloadUrl }
        elseif ($choice -eq 'No') { Start-Process -FilePath 'https://openproxysetup.ccwu.cc/#downloads' }
    } finally { $dialog.Dispose() }
}

function Start-AppUpdateCheck([bool]$manual) {
    if ($script:updateHandle) { return }
    if ($manual -and $script:updateResult) {
        if (-not $script:deploymentHandle) {
            $ready = $script:updateResult
            $script:updateResult = $null
            Show-AppUpdate $ready
        }
        return
    }
    $script:updateManual = $manual
    if ($manual) { $updateLink.Text = '正在检查更新…' }
    try {
        $script:updateRunspace = [runspacefactory]::CreateRunspace()
        $script:updateRunspace.Open()
        $script:updatePowerShell = [powershell]::Create()
        $script:updatePowerShell.Runspace = $script:updateRunspace
        [void]$script:updatePowerShell.AddScript({
            param($path, $installed)
            . $path
            Get-OpenProxySetupUpdate -CurrentVersion $installed
        }.ToString()).AddArgument((Join-Path $PSScriptRoot 'update.ps1')).AddArgument($script:appVersion)
        $script:updateHandle = $script:updatePowerShell.BeginInvoke()
        $updateTimer.Start()
    } catch {
        if ($script:updatePowerShell) { $script:updatePowerShell.Dispose() }
        if ($script:updateRunspace) { $script:updateRunspace.Dispose() }
        $script:updateHandle = $null
        $updateLink.Text = '检查更新'
        if ($manual) { [Windows.Forms.MessageBox]::Show($form,'暂时无法检查更新，请前往官网下载。','检查更新') }
    }
}

$updateTimer.add_Tick({
    if ($script:updateHandle -and $script:updateHandle.IsCompleted) {
        $failed = $false
        try {
            $found = @($script:updatePowerShell.EndInvoke($script:updateHandle))
            $failed = $script:updatePowerShell.HadErrors
            if (-not $failed -and $found.Count -gt 0) { $script:updateResult = $found[0] }
        } catch { $failed = $true }
        finally {
            $script:updatePowerShell.Dispose()
            $script:updateRunspace.Dispose()
            $script:updateHandle = $null
        }
        $updateLink.Text = '检查更新'
        if ($script:updateManual -and -not $script:updateResult) {
            $detail = if ($failed) { '暂时无法检查更新，请检查网络或前往官网下载。' } else { '当前已是最新版本 v' + $script:appVersion }
            [Windows.Forms.MessageBox]::Show($form,$detail,'检查更新') | Out-Null
        }
    }
    if ($script:updateResult -and -not $script:deploymentHandle -and -not $script:siteConnectionBusy -and $form.ContainsFocus) {
        $ready = $script:updateResult
        $script:updateResult = $null
        $updateTimer.Stop()
        Show-AppUpdate $ready
    }
    if (-not $script:updateHandle -and -not $script:updateResult) { $updateTimer.Stop() }
})
$updateLink.add_LinkClicked({ Start-AppUpdateCheck $true })
$form.add_Shown({ Start-AppUpdateCheck $false })
$form.add_FormClosed({
    $updateTimer.Stop()
    $updateTimer.Dispose()
    if ($script:updatePowerShell) { $script:updatePowerShell.Dispose() }
    if ($script:updateRunspace) { $script:updateRunspace.Dispose() }
})
$initialSection = try { [IO.File]::ReadAllText((Join-Path (Split-Path -Parent (Get-SiteStorePath)) 'section.txt')).Trim() } catch { 'deploy' }
Show-WizardPage $(if ($initialSection -eq 'manage') { $managePage } else { $homePage })
Set-Appearance (Read-Appearance)
Set-DisplayLayout
Set-TaskbarIdentity
[void]$form.ShowDialog()
