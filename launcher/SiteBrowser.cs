using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

public sealed class SiteValidationEventArgs : EventArgs {
    public bool Success {get;private set;} public bool OpenRequested {get;private set;}
    public string Url {get;private set;} public string Message {get;private set;}
    public SiteValidationEventArgs(bool success,bool open,string url,string message) {Success=success;OpenRequested=open;Url=url;Message=message;}
}

public sealed class OpenProxySetupBrowser : UserControl
{
    private readonly WebView2 web = new WebView2();
    private readonly Panel bar = new Panel();
    private readonly Label status = new Label();
    private readonly Button refresh = new Button(), external = new Button();
    private readonly Panel fallback = new Panel();
    private readonly string template;
    private Uri site;
    private string scriptId;
    private bool dark, initialized;
    private Task initializeTask;
    private readonly Func<string,string,string,Task<string>> verifier;
    public event EventHandler ReturnRequested;
    public event EventHandler<SiteValidationEventArgs> ValidationCompleted;
    public event EventHandler ForgetCompleted;
    public bool LastForgetSucceeded { get; private set; }

    public OpenProxySetupBrowser(string root) : this(root,(url,secret,ua)=>OpenProxySetupSiteAuth.Verify(url,secret,ua)) {}
    internal OpenProxySetupBrowser(string root,Func<string,string,string,Task<string>> verifier)
    {
        this.verifier=verifier;
        template = File.ReadAllText(Path.Combine(root, "assets/admin-theme.js"));
        Dock = DockStyle.Fill;
        AutoScaleDimensions = new SizeF(96F, 96F); AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Microsoft YaHei UI", 10F);
        web.Dock = DockStyle.Fill;
        web.CreationProperties = new CoreWebView2CreationProperties {
            UserDataFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "OpenProxySetup", "BrowserProfile")
        };
        bar.Dock = DockStyle.Top; bar.Height = 44;
        Button back = new Button { Text = "返回", Dock = DockStyle.Left, Width = 75 };
        back.Click += delegate { if (ReturnRequested != null) ReturnRequested(this, EventArgs.Empty); };
        refresh.Text = "刷新"; refresh.Dock = DockStyle.Right; refresh.Width = 70;
        refresh.Click += delegate { if (initialized) web.Reload(); };
        external.Text = "在浏览器打开 ↗"; external.Dock = DockStyle.Right; external.Width = 150;
        external.Click += delegate { if (site != null) OpenExternal(web.Source ?? site); };
        status.Dock = DockStyle.Fill; status.TextAlign = ContentAlignment.MiddleLeft;
        status.Padding = new Padding(10, 0, 0, 0); status.AutoEllipsis = true;
        bar.Controls.Add(status); bar.Controls.Add(external); bar.Controls.Add(refresh); bar.Controls.Add(back);
        Controls.Add(web); Controls.Add(bar); ApplyColors();
        fallback.Dock = DockStyle.Fill; fallback.Visible = false;
        Label help = new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter,
            Text = "内置后台无法启动。\n请重新打开应用，或安装 Microsoft Edge WebView2 Runtime。\n也可以使用右上角按钮在浏览器中打开后台。" };
        Button runtime = new Button { Text = "获取 Microsoft WebView2 Runtime ↗", Dock = DockStyle.Bottom, Height = 60 };
        runtime.Click += delegate { OpenExternal(new Uri("https://developer.microsoft.com/microsoft-edge/webview2/")); };
        fallback.Controls.Add(help); fallback.Controls.Add(runtime); Controls.Add(fallback);
    }
    public static bool SameOrigin(string value, string origin)
    {
        Uri a, b;
        return Uri.TryCreate(value, UriKind.Absolute, out a) && Uri.TryCreate(origin, UriKind.Absolute, out b)
            && a.Scheme == "https" && a.UserInfo.Length == 0 && a.Host.Equals(b.Host, StringComparison.OrdinalIgnoreCase)
            && a.Port == b.Port;
    }
    private static string Quote(string text) { return new JavaScriptSerializer().Serialize(text); }
    private async Task Initialize()
    {
        await web.EnsureCoreWebView2Async(null);
        var settings = web.CoreWebView2.Settings;
        settings.IsPasswordAutosaveEnabled = false; settings.IsGeneralAutofillEnabled = false;
        settings.AreDevToolsEnabled = false; settings.AreHostObjectsAllowed = false;
        web.CoreWebView2.PermissionRequested += (s, e) => e.State = CoreWebView2PermissionState.Deny;
        web.CoreWebView2.ServerCertificateErrorDetected += (s, e) => e.Action = CoreWebView2ServerCertificateErrorAction.Cancel;
        web.CoreWebView2.NavigationStarting += (s, e) => {
            if (site == null || !SameOrigin(e.Uri, site.AbsoluteUri)) {
                e.Cancel = true;
                Uri destination;
                if (e.IsUserInitiated && Uri.TryCreate(e.Uri, UriKind.Absolute, out destination)) OpenExternal(destination);
            } else status.Text = "正在加载 · " + site.Host;
        };
        web.CoreWebView2.NewWindowRequested += (s, e) => {
            e.Handled = true; Uri destination;
            if (e.IsUserInitiated && Uri.TryCreate(e.Uri, UriKind.Absolute, out destination)) OpenExternal(destination);
        };
        web.CoreWebView2.DOMContentLoaded += async (s,e) => await ApplyDocument();
        web.CoreWebView2.NavigationCompleted += async (s, e) => {
            try {
                if (site == null || !SameOrigin(web.CoreWebView2.Source, site.AbsoluteUri)) return;
                if (!e.IsSuccess) { status.Text = "加载失败，请检查网络后刷新，或在浏览器中打开。"; return; }
                status.Text = site.Host + " · 登录会话保留在本机";
                await ApplyDocument();
            } catch { status.Text = "后台页面未就绪，可点击刷新重试。"; }
        };
        web.CoreWebView2.ProcessFailed += (s, e) => status.Text = "后台进程已停止，请返回后重新打开。";
        initialized = true;
    }
    private async Task ApplyDocument()
    {
        try {
            if (site == null || web.CoreWebView2 == null || !SameOrigin(web.CoreWebView2.Source, site.AbsoluteUri)) return;
            await web.ExecuteScriptAsync(ThemeScript());
        } catch { status.Text = "后台页面未就绪，可点击刷新重试。"; }
    }
    private Task Ready() { return initializeTask ?? (initializeTask = Initialize()); }
    private string ThemeScript()
    {
        return template.Replace("__OPS_ORIGIN__", Quote(site.GetLeftPart(UriPartial.Authority)))
            .Replace("__OPS_DARK__", dark ? "true" : "false");
    }
    public async void Open(string address, string secret, bool night, bool navigate=true)
    {
        try {
            Uri selected = new Uri(address);
            if (!SameOrigin(address, address)) throw new ArgumentException();
            status.Text = "正在验证密码…";
            await Ready();
            string value=await verifier(address,secret,web.CoreWebView2.Settings.UserAgent);
            var cookie=web.CoreWebView2.CookieManager.CreateCookie("auth",value,selected.Host,"/");
            cookie.IsSecure=true;cookie.IsHttpOnly=true;cookie.Expires=DateTime.Now.AddDays(1);
            cookie.SameSite=CoreWebView2CookieSameSiteKind.Lax;
            web.CoreWebView2.CookieManager.AddOrUpdateCookie(cookie);
            bool changed = site == null || site != selected;
            site = selected; dark = night; ApplyColors();
            if(ValidationCompleted!=null)ValidationCompleted(this,new SiteValidationEventArgs(true,navigate,address,"密码验证成功。"));
            if(!navigate)return;
            fallback.Visible = false;
            if (scriptId != null) web.CoreWebView2.RemoveScriptToExecuteOnDocumentCreated(scriptId);
            scriptId = await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(ThemeScript());
            if (changed || web.Source == null || !SameOrigin(web.Source.AbsoluteUri, site.AbsoluteUri)
                || web.Source.AbsolutePath == "/login") web.Source = site;
            else { await web.ExecuteScriptAsync(ThemeScript()); status.Text = site.Host + " · 登录会话保留在本机"; }
        } catch (Exception error) {
            string message=error is InvalidOperationException?error.Message:
                error is TaskCanceledException?"验证超时，请检查网络后重试。":
                initialized?"无法连接站点，请检查网络和 HTTPS 证书后重试。":"内置组件无法启动，请安装 WebView2 Runtime 后重试。";
            status.Text=message;
            if(ValidationCompleted!=null)ValidationCompleted(this,new SiteValidationEventArgs(false,navigate,address,message));
        }
    }
    public async void SetTheme(bool night)
    {
        dark = night; ApplyColors();
        if (initialized && site != null) {
            try {
                if (scriptId != null) web.CoreWebView2.RemoveScriptToExecuteOnDocumentCreated(scriptId);
                scriptId = await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(ThemeScript());
                await web.ExecuteScriptAsync(ThemeScript());
            } catch { }
        }
    }
    public async void Forget()
    {
        LastForgetSucceeded = false;
        try {
            await Ready(); web.Stop();
            if (scriptId != null) { web.CoreWebView2.RemoveScriptToExecuteOnDocumentCreated(scriptId); scriptId = null; }
            web.CoreWebView2.CookieManager.DeleteAllCookies();
            await web.CoreWebView2.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile);
            status.Text = "本机后台登录会话已清除。";
            LastForgetSucceeded = true;
            if (site != null) web.Reload();
        } catch { status.Text = "会话清除失败，请重新打开后台后重试。"; }
        if (ForgetCompleted != null) ForgetCompleted(this, EventArgs.Empty);
    }
    public async void ForgetSite(string address) {
        try {
            await Ready();var uri=new Uri(address);
            web.CoreWebView2.CookieManager.DeleteCookiesWithDomainAndPath("auth",uri.Host,"/");
            if(site!=null&&SameOrigin(site.AbsoluteUri,address))web.Reload();
        }catch{status.Text="站点登录会话清除失败，请重试。";}
    }
    private void ApplyColors()
    {
        BackColor = dark ? Color.FromArgb(16,24,39) : Color.FromArgb(243,246,252);
        bar.BackColor = dark ? Color.FromArgb(27,38,61) : Color.White;
        bar.ForeColor = dark ? Color.FromArgb(241,245,255) : Color.FromArgb(19,36,66);
        fallback.BackColor = BackColor; fallback.ForeColor = bar.ForeColor;
        foreach (Control item in bar.Controls) {
            item.BackColor = bar.BackColor; item.ForeColor = bar.ForeColor;
            Button b = item as Button;
            if (b != null) { b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderSize = 0; }
        }
        web.DefaultBackgroundColor = BackColor;
    }
    private void OpenExternal(Uri destination)
    {
        if (destination.Scheme != "https" || destination.UserInfo.Length != 0) return;
        try { Process.Start(new ProcessStartInfo(destination.AbsoluteUri) { UseShellExecute = true }); }
        catch { status.Text = "没有可用的浏览器。"; }
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) web.Dispose();
        base.Dispose(disposing);
    }
}
