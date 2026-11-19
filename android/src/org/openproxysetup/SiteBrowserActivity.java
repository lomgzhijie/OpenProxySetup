package org.openproxysetup;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URI;

/** A private Activity: credentials are only filled in the explicitly selected HTTPS origin. */
public final class SiteBrowserActivity extends Activity {
    private WebView web;
    private TextView status;
    private String address, origin, themeScript;
    private boolean dark;
    private LinearLayout frame, toolbar;
    private int bg, fg, surface;

    static boolean sameOrigin(String url, String origin) {
        try {
            URI a = new URI(url), b = new URI(origin);
            return "https".equalsIgnoreCase(a.getScheme()) && a.getUserInfo() == null
                    && a.getHost() != null && a.getHost().equalsIgnoreCase(b.getHost())
                    && (a.getPort() == -1 ? 443 : a.getPort()) == (b.getPort() == -1 ? 443 : b.getPort());
        } catch (Exception e) { return false; }
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getIntent().removeExtra("password");
        if(!getIntent().getBooleanExtra("verified",false)){finish();return;}
        address = getIntent().getStringExtra("url");
        dark = getIntent().getBooleanExtra("dark", false);
        try {
            URI uri = new URI(address);
            origin = new URI(uri.getScheme(), null, uri.getHost(), uri.getPort(), null, null, null).toString();
            if (!sameOrigin(address, origin)) throw new IllegalArgumentException();
            try (InputStream input = getAssets().open("admin-theme.js")) {
                ByteArrayOutputStream output = new ByteArrayOutputStream(); byte[] buffer = new byte[4096]; int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                themeScript = output.toString("UTF-8");
            }
        } catch (Exception e) { finish(); return; }
        frame = new LinearLayout(this); frame.setOrientation(LinearLayout.VERTICAL);
        if (android.os.Build.VERSION.SDK_INT >= 35) frame.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets i = insets.getInsets(android.view.WindowInsets.Type.systemBars()
                    | android.view.WindowInsets.Type.displayCutout() | android.view.WindowInsets.Type.ime());
            v.setPadding(i.left, i.top, i.right, i.bottom); return insets;
        });
        toolbar = new LinearLayout(this); toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(8), dp(4), dp(8), dp(4));
        toolbar.addView(button("返回", () -> finish()));
        TextView title = new TextView(this); title.setText("站点后台"); title.setTextSize(17);
        toolbar.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        toolbar.addView(button("☀ / ☾", () -> {
            dark = !dark;
            getSharedPreferences("MainActivity", MODE_PRIVATE).edit().putBoolean("dark", dark).apply();
            colors(); inject(false);
        }));
        toolbar.addView(button("刷新", () -> { if (web != null) web.reload(); }));
        toolbar.addView(button("↗", this::external));
        toolbar.addView(button("部署", () -> {
            setResult(RESULT_OK,new Intent().putExtra("deployment",true));finish();
        }));
        frame.addView(toolbar);
        status = new TextView(this); status.setTextSize(12); status.setPadding(dp(12), dp(4), dp(12), dp(6));
        frame.addView(status);
        try { web = new WebView(this); }
        catch (RuntimeException error) {
            setContentView(frame); colors();
            status.setText("内置后台无法启动。请启用或更新 Android System WebView，或用右上角 ↗ 在浏览器中打开。");
            return;
        }
        web.setSaveEnabled(false);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true);
        String ua=getIntent().getStringExtra("userAgent");
        if(ua!=null)settings.setUserAgentString(ua);
        settings.setAllowFileAccess(false); settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSafeBrowsingEnabled(true); settings.setSupportMultipleWindows(false);
        settings.setBuiltInZoomControls(true); settings.setDisplayZoomControls(false);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!request.isForMainFrame()) return false;
                if (sameOrigin(request.getUrl().toString(), origin)) return false;
                if (request.hasGesture() && "https".equalsIgnoreCase(request.getUrl().getScheme()))
                    confirmExternal(request.getUrl().toString());
                return true;
            }
            @Override public void onPageStarted(WebView view, String url, android.graphics.Bitmap icon) {
                status.setText("正在加载 · " + Uri.parse(origin).getHost());
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!sameOrigin(url, origin)) return;
                status.setText(Uri.parse(origin).getHost() + " · 登录会话保留在本机");
                inject(true); CookieManager.getInstance().flush();
            }
            @Override public void onPageCommitVisible(WebView view, String url) { inject(true); }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) status.setText("加载失败，请检查网络后点击刷新，或用右上角 ↗ 在浏览器打开。");
            }
        });
        web.setDownloadListener((url, userAgent, disposition, mime, length) -> {
            if (url.startsWith("https://")) confirmExternal(url);
            else status.setText("此类文件请用右上角 ↗ 在浏览器打开后保存。");
        });
        frame.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(frame); colors(); web.loadUrl(address);
    }
    private void inject(boolean fill) {
        if (web == null || !sameOrigin(web.getUrl(), origin)) return;
        web.evaluateJavascript(themeScript.replace("__OPS_ORIGIN__", JSONObject.quote(origin))
                .replace("__OPS_DARK__", Boolean.toString(dark)), null);
    }

    private void external() { confirmExternal(web != null && sameOrigin(web.getUrl(), origin) ? web.getUrl() : address); }
    private void confirmExternal(String url) {
        Uri target = Uri.parse(url);
        if (!"https".equalsIgnoreCase(target.getScheme()) || target.getUserInfo() != null) return;
        try { startActivity(new Intent(Intent.ACTION_VIEW, target)); }
        catch (Exception e) { status.setText("没有可用的浏览器。"); }
    }
    private Button button(String title, Runnable action) {
        Button button = new Button(this); button.setText(title); button.setTextSize(13);
        button.setMinWidth(0); button.setMinimumWidth(0); button.setPadding(dp(8), 0, dp(8), 0);
        button.setOnClickListener(v -> action.run()); return button;
    }
    private void colors() {
        bg = Color.parseColor(dark ? "#101827" : "#f1f5fc");
        fg = Color.parseColor(dark ? "#f1f5ff" : "#132442");
        surface = Color.parseColor(dark ? "#19243a" : "#ffffff");
        frame.setBackgroundColor(bg); toolbar.setBackgroundColor(surface);
        status.setTextColor(fg); if (web != null) web.setBackgroundColor(bg);
        getWindow().setStatusBarColor(bg); getWindow().setNavigationBarColor(bg);
        getWindow().getDecorView().setSystemUiVisibility(dark ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        for (int i = 0; i < toolbar.getChildCount(); i++) {
            View child = toolbar.getChildAt(i);
            if (child instanceof TextView) ((TextView)child).setTextColor(fg);
            if (child instanceof Button) child.setBackgroundTintList(android.content.res.ColorStateList.valueOf(surface));
        }
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    @Override public void onBackPressed() { if (web != null && web.canGoBack()) web.goBack(); else super.onBackPressed(); }
    @Override public void onPause() { CookieManager.getInstance().flush(); super.onPause(); }
    @Override public void onDestroy() {
        if (web != null) { frame.removeView(web); web.destroy(); web = null; }
        super.onDestroy();
    }
}
