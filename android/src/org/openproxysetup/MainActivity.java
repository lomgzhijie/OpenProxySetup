package org.openproxysetup;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.os.SystemClock;
import android.text.Editable;
import android.text.InputType;
import android.text.SpannableStringBuilder;
import android.text.TextWatcher;
import android.text.method.LinkMovementMethod;
import android.text.method.PasswordTransformationMethod;
import android.text.style.ClickableSpan;
import android.text.style.StyleSpan;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class MainActivity extends Activity {
    private static final int HOME = 0, AUTH = 1, DOMAIN = 2, DNSHE = 3, DEPLOY = 4, PROGRESS = 5, MANAGE = 6, DOCS = 7;
    private static final int CLOUDFLARE_GUIDE = 8, DNSHE_GUIDE = 9;
    private static final String SITE = "https://openproxysetup.ccwu.cc/";
    private static final String CLOUDFLARE = "https://dash.cloudflare.com/";
    private static final String DNSHE_SITE = "https://my.dnshe.com/";
    private static final String TOKEN_PAGE = CLOUDFLARE + "profile/api-tokens";
    private static final String WORKERS_AND_PAGES = CLOUDFLARE + "?to=/:account/workers-and-pages";
    private static final String HOST = "(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}";
    private static final String[] STEP_LABELS = {"授权 Cloudflare", "注册域名", "DNSHE 授权", "填写并部署"};
    private static final String[] PHASE_LABELS = {"验证 Cloudflare 授权", "准备 Cloudflare KV", "发布 Cloudflare Pages", "绑定域名与验证证书"};
    private static final long RECHECK_DELAY_MS = 60_000;
    private static final String[] DOC_LANGUAGES = {"简体中文", "English", "日本語", "한국어"};
    private static final String[] DOC_FILES = {"README.md", "README.en.md", "README.ja.md", "README.ko.md"};
    private static final Pattern MARKDOWN = Pattern.compile("\\[([^\\]]+)]\\(([^)]+)\\)|\\*\\*(.+?)\\*\\*|\u0060([^\u0060]+)\u0060");
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable progressTick = this::tick;
    private final long[] phaseTimes = new long[5];
    private final TextView[] phaseViews = new TextView[4];
    private LinearLayout shell, body, section;
    private ScrollView scroll;
    private TextView status, elapsed;
    private Button recheckButton;
    private EditText managePasswordField;
    private int screen = HOME, docReturn = HOME, manageReturn = HOME, docLanguage, phase, completedPhase, failedPhase;
    private long phaseStarted, runStarted, waitStarted, totalTime;
    private boolean resumed;
    private boolean busy, dark, pagesReady, domainActive, pending, runAttempted, bindOnRetry;
    private int background, surface, panel, border, ink, muted, accent, primary, good, danger;
    private String account = "", token = "", verifiedAccount = "", verifiedToken = "";
    private String domain = "", key = "", secret = "", password = "", submittedPassword = "", boundDomain = "";
    private String manageUrl = "", managePassword = "", progressMessage = "";
    private boolean rememberSite = true;
    private String savedSiteError = "";
    private Deployment deployment;
    private boolean updateChecking;
    private UpdateChecker availableUpdate;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        boolean systemDark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        dark = getPreferences(MODE_PRIVATE).getBoolean("dark", systemDark);
        docLanguage = getPreferences(MODE_PRIVATE).getInt("docLanguage", 0);
        rememberSite = getPreferences(MODE_PRIVATE).getBoolean("rememberSite", true);
        try {
            org.json.JSONObject saved = SavedSite.read(this);
            if (saved != null) {
                manageUrl = saved.optString("url"); managePassword = saved.optString("password");
            }
        } catch (Exception e) { savedSiteError = "保存的站点无法解密，请重新输入并保存，或清除本机记录。"; }
        render(HOME);
        handler.post(() -> checkForUpdates(false));
    }

    @Override
    protected void onResume() {
        super.onResume();
        boolean selectedDark = getPreferences(MODE_PRIVATE).getBoolean("dark", dark);
        if (selectedDark != dark) { dark = selectedDark; render(screen); }
        resumed = true;
        tick();
        showAvailableUpdate();
    }

    @Override
    protected void onPause() {
        resumed = false;
        handler.removeCallbacks(progressTick);
        super.onPause();
    }

    private void render(int destination) {
        screen = destination;
        colors();
        status = null;
        shell = column();
        shell.setBackgroundColor(background);
        if (Build.VERSION.SDK_INT >= 35) {
            shell.setOnApplyWindowInsetsListener((view, insets) -> {
                android.graphics.Insets space = insets.getInsets(WindowInsets.Type.systemBars()
                        | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                view.setPadding(space.left, space.top, space.right, space.bottom);
                return insets;
            });
        }
        getWindow().setStatusBarColor(background);
        getWindow().setNavigationBarColor(background);
        shell.addView(toolbar());
        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        body = column();
        body.setPadding(dp(18), dp(16), dp(18), dp(28));
        scroll.addView(body);
        setContentView(shell);
        shell.post(() -> {
            if (Build.VERSION.SDK_INT >= 30) {
                WindowInsetsController bars = getWindow().getInsetsController();
                if (bars == null) return;
                int lightBars = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                bars.setSystemBarsAppearance(dark ? 0 : lightBars, lightBars);
            } else {
                getWindow().getDecorView().setSystemUiVisibility(
                        dark ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
            }
        });
        if (destination >= AUTH && destination <= DEPLOY) steps();
        switch (destination) {
            case AUTH: authorization(); break;
            case DOMAIN: domainGuide(); break;
            case DNSHE: credentialsGuide(); break;
            case DEPLOY: deployForm(); break;
            case PROGRESS: progress(); break;
            case MANAGE: manage(); break;
            case DOCS: documentation(); break;
            case CLOUDFLARE_GUIDE: cloudflareGuide(); break;
            case DNSHE_GUIDE: dnsheMobileGuide(); break;
            default: home();
        }
        updateControls(shell, !busy);
        tick();
    }

    private LinearLayout toolbar() {
        LinearLayout bar = row();
        bar.setPadding(dp(16), dp(6), dp(10), dp(6));
        bar.setBackgroundColor(surface);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.app_icon);
        bar.addView(logo, new LinearLayout.LayoutParams(dp(30), dp(30)));
        TextView brand = text("Open Proxy Setup", 16, ink, true);
        brand.setPadding(dp(8), 0, dp(4), 0);
        brand.setMaxLines(2);
        bar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
        Button theme = action(dark ? "☾" : "☀", false, () -> {
            dark = !dark;
            getPreferences(MODE_PRIVATE).edit().putBoolean("dark", dark).apply();
            int y = scroll.getScrollY();
            render(screen);
            scroll.post(() -> scroll.scrollTo(0, y));
        });
        theme.setContentDescription(dark ? "切换至日间模式" : "切换至暗夜模式");
        bar.addView(theme, new LinearLayout.LayoutParams(dp(49), dp(48)));
        if (screen != DOCS) {
            Button docs = action("文档", false, () -> {
                docReturn = screen;
                render(DOCS);
            });
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(59), dp(48));
            params.leftMargin = dp(6);
            bar.addView(docs, params);
        }
        return bar;
    }

    private void steps() {
        LinearLayout strip = row();
        for (int i = 1; i <= STEP_LABELS.length; i++) {
            TextView item = text(i == screen ? "第 " + i + " 步" : Integer.toString(i),
                    12, i == screen ? accent : muted, i == screen);
            item.setContentDescription("第 " + i + " 步 " + STEP_LABELS[i - 1] + (i == screen ? " 当前步骤" : ""));
            item.setGravity(Gravity.CENTER);
            item.setBackground(shape(i == screen ? panel : surface, i == screen ? accent : border, 12));
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(39), 1);
            if (i > 1) params.leftMargin = dp(7);
            strip.addView(item, params);
        }
        append(body, strip, 0);
    }

    private void home() {
        card();
        heading("部署自己的\nCloudflare Pages 站点");
        copy("在手机上完成 Cloudflare 授权、DNSHE 域名配置和站点部署。");
        button(runAttempted ? "查看本次部署  →" : "开始部署  →", true,
                () -> render(runAttempted ? PROGRESS : AUTH));
        button("管理已有站点", false, () -> openManage(HOME));
        card();
        title("部署流程");
        guideLine("1", "授权 Cloudflare", "连接你自己的账号");
        guideLine("2", "准备 DNSHE 域名", "注册域名并创建 API 授权");
        guideLine("3", "部署并管理", "发布 Pages，绑定域名，打开后台");
        card();
        title("开始前");
        copy("请确认手机网络可以访问 Cloudflare。使用 VPN 或代理服务时，请遵守所在地适用的法律法规。");
        button("项目网站 ↗", false, () -> open(SITE));
        button("检查更新 · v" + currentVersion(), false, () -> checkForUpdates(true));
    }

    private String currentVersion() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (android.content.pm.PackageManager.NameNotFoundException error) {
            throw new IllegalStateException(error);
        }
    }

    private void checkForUpdates(boolean manual) {
        if (updateChecking) return;
        updateChecking = true;
        if (manual) android.widget.Toast.makeText(this, "正在检查新版本…", android.widget.Toast.LENGTH_SHORT).show();
        final String installed = currentVersion();
        new Thread(() -> {
            UpdateChecker found = null;
            boolean failed = false;
            try { found = UpdateChecker.check(installed); }
            catch (Exception error) { failed = true; }
            final UpdateChecker result = found;
            final boolean unavailable = failed;
            runOnUiThread(() -> {
                updateChecking = false;
                if (isFinishing() || isDestroyed()) return;
                availableUpdate = result;
                if (result != null) showAvailableUpdate();
                else if (manual && resumed) {
                    dialog().setTitle(unavailable ? "暂时无法检查更新" : "已是最新版本")
                            .setMessage(unavailable ? "请检查网络后重试，或前往官网下载更新。" : "当前版本 v" + installed)
                            .setPositiveButton("前往官网", (window, which) -> open(SITE + "#android-download"))
                            .setNegativeButton("关闭", null).show();
                }
            });
        }, "OpenProxySetup-Update").start();
    }

    private void showAvailableUpdate() {
        if (!resumed || busy || availableUpdate == null || isFinishing() || isDestroyed()) return;
        UpdateChecker update = availableUpdate;
        availableUpdate = null;
        dialog().setTitle("发现新版本 v" + update.version)
                .setMessage("当前版本 v" + currentVersion() + "。下载完成后，打开 APK 覆盖安装。")
                .setPositiveButton("下载更新", (window, which) -> open(update.downloadUrl))
                .setNeutralButton("前往官网", (window, which) -> open(SITE + "#android-download"))
                .setNegativeButton("稍后", null).show();
    }

    private void authorization() {
        card();
        heading("授权 Cloudflare");
        copy("在浏览器登录 Cloudflare，确认账号 ID，然后创建目标账号的 API Token。完成后回到这里验证并继续。");
        button("登录或注册 Cloudflare ↗", false, () -> open(CLOUDFLARE));
        button("手机端图解：创建令牌与查找 Account ID", false, () -> render(CLOUDFLARE_GUIDE));
        card();
        title("连接 Cloudflare 账号");
        copy("创建自定义 Token 时，为目标账号授予 Cloudflare Pages 编辑和 Workers KV Storage 编辑权限。");
        button("打开 API Token 页面 ↗", false, () -> open(TOKEN_PAGE));
        field("Cloudflare Account ID", "粘贴 32 位账号 ID", account, false, v -> account = v.trim());
        button("打开 Cloudflare 查看 Account ID ↗", false, () -> open(WORKERS_AND_PAGES));
        field("Cloudflare API Token", "粘贴刚创建的 Token", token, true, v -> token = v.trim());
        statusLine();
        button("验证授权并继续", true, () -> verify(false));
        button("返回首页", false, () -> render(HOME));
    }

    private void cloudflareGuide() {
        card();
        heading("Cloudflare 授权图解");
        button("打开 API 令牌页面 ↗", false, () -> open(TOKEN_PAGE));
        guideLine("1", "创建自定义令牌", "在「创建令牌」里填名称，例如 Open Proxy Setup。找到「策略」，点「从头开始」。");
        guidePath(1, "从头开始（Custom）", "从 Account 策略开始", "从 Zone 策略开始", "从 User 策略开始");
        guideLine("2", "选择部署账号", "「包括」保持原样，把「所有账户」切换成你要部署的那一个账号。");
        guidePath(1, "包括", "所有账户 ▾ → 你的部署账号");
        guideLine("3", "选两项写入权限", "在「搜索权限组」里先搜 Pages，再搜 KV。只添加下面两项，分别选编辑或 Write。");
        guidePath(1, "搜索权限组", "Pages Write（Cloudflare Pages 编辑）\nWorkers KV Storage Write（编辑）");
        guideLine("4", "设有效期并创建", "测试可选 7 天。确认创建后立即复制令牌，创建页面通常只显示一次。");
        guideLine("5", "复制 Account ID", "打开 Workers & Pages，选中要部署的账户，在「账户详情」里复制 32 位 Account ID。");
        guidePath(1, "Workers & Pages", "账户详情 → Account ID → 复制");
        button("打开 Workers & Pages ↗", false, () -> open(WORKERS_AND_PAGES));
        guideLine("6", "回应用验证", "把 Account ID 和 API Token 分别粘贴进同名输入框，点「验证授权并继续」。");
        button("返回 Cloudflare 授权", true, () -> render(AUTH));
    }

    private void verify(boolean forProgress) {
        if (!account.matches("[a-fA-F0-9]{32}") || token.isEmpty()) {
            message("请输入 32 位 Account ID 和 API Token。");
            return;
        }
        final String selectedAccount = account.toLowerCase(Locale.ROOT);
        final String credential = token;
        if (runAttempted && !selectedAccount.equals(verifiedAccount)) {
            message("本次部署已创建资源。请用原账号重新授权，或在部署页开始新站点。");
            return;
        }
        background("正在验证 Cloudflare 授权…", () -> {
            Deployment selected = deployment;
            if (selected == null || !selectedAccount.equals(verifiedAccount)) {
                try (InputStream worker = getAssets().open("_worker.js")) {
                    selected = new Deployment(selectedAccount, Deployment.readBytes(worker));
                }
            }
            selected.verify(credential);
            final Deployment checked = selected;
            return () -> {
                deployment = checked;
                verifiedAccount = selectedAccount;
                verifiedToken = credential;
                render(forProgress ? DEPLOY : DOMAIN);
            };
        });
    }

    private void domainGuide() {
        card();
        heading("注册 DNSHE 域名");
        guideLine("1", "进入免费域名", "在 DNSHE 登录，打开「免费域名」并选择「注册新域名」。");
        guideLine("2", "选择后缀并注册", "选择可用的域名后缀，填写前缀并确认完整域名。");
        guideLine("3", "复制完整域名", "已有域名可以直接到「我的域名」复制。");
        button("打开 DNSHE 我的域名 ↗", false, () -> open(DNSHE_SITE));
        field("完整域名", "例如 myhome.ccwu.cc", domain, false, v -> domain = normalizeDomain(v));
        statusLine();
        button("下一步", true, () -> {
            if (!domain.isEmpty() && !domain.matches(HOST)) {
                message("请输入完整域名，例如 myhome.ccwu.cc。");
                return;
            }
            render(DNSHE);
        });
        button("上一步", false, () -> render(AUTH));
    }

    private void credentialsGuide() {
        card();
        heading("创建 DNSHE 授权");
        copy("在 DNSHE 手机网页展开上方「域名管理」，在「功能导航」里点带钥匙图标的「API 管理」。");
        button("手机端图解：找到 API 管理", false, () -> render(DNSHE_GUIDE));
        button("打开 DNSHE API 管理入口 ↗", false, () -> open(DNSHE_SITE));
        copy("部署时应用会添加指向 Pages 的 CNAME。已有冲突记录时会提示你检查。");
        button("下一步", true, () -> render(DEPLOY));
        button("上一步", false, () -> render(DOMAIN));
    }

    private void dnsheMobileGuide() {
        card();
        heading("DNSHE API 授权图解");
        button("打开 DNSHE ↗", false, () -> open(DNSHE_SITE));
        guideLine("1", "展开域名管理", "登录 DNSHE 手机网页，点页面上方「域名管理」右侧的箭头，展开「功能导航」。");
        guidePath(0, "域名管理 ▾", "功能导航");
        guideLine("2", "点带钥匙的 API 管理", "向下找到「域名转赠」，紧接着的「API 管理」就是入口。");
        guidePath(1, "域名转赠", "🔑  API 管理", "WHOIS 查询");
        guideLine("3", "获取 API 凭据", "在 API 管理中创建一组密钥，分别复制 API Key 和 API Secret。Secret 通常只在创建时显示一次。");
        guideLine("4", "回应用填写", "到第 4 步「填写并部署」，把两个值粘贴进各自的输入框。");
        button("返回 DNSHE 授权", true, () -> render(DNSHE));
    }

    private void deployForm() {
        card();
        heading("填写并部署");
        if (pending || domainActive) {
            copy(boundDomain + (domainActive ? " 已通过验证。" : " 已提交，正在等待 DNS 与证书验证。"));
            button("查看部署进度", true, () -> render(PROGRESS));
            button("开始新站点", false, this::confirmReset);
            return;
        }
        copy("填入 DNSHE 凭据和管理员密码。Pages 发布完成后即可先用 pages.dev 后台，域名可等验证完成后再使用。");
        if (!boundDomain.isEmpty()) copy("本次部署的域名为 " + boundDomain + "，可修改 DNSHE 凭据后继续绑定。");
        if (boundDomain.isEmpty()) field("完整域名", "例如 myhome.ccwu.cc", domain, false, v -> domain = normalizeDomain(v));
        field("DNSHE API Key", "粘贴 API Key", key, true, v -> key = v.trim());
        field("DNSHE API Secret", "粘贴 API Secret", secret, true, v -> secret = v.trim());
        if (!pagesReady && submittedPassword.isEmpty()) {
            field("后台管理员密码", "至少 12 个字符", password, true, v -> password = v);
        } else {
            copy(pagesReady ? "Pages 已发布，此处可继续配置自定义域名。" : "本次部署会继续使用已提交的管理员密码。");
        }
        statusLine();
        button(pagesReady ? "绑定域名" : runAttempted ? "继续部署" : "开始自动部署",
                true, () -> startDeploy(true));
        if (!pagesReady && !runAttempted) {
            button("暂时只发布 Pages", false, () -> startDeploy(false));
        }
        if (runAttempted) button("查看部署进度", false, () -> render(PROGRESS));
        if (runAttempted) button("开始新站点", false, this::confirmReset);
        button("上一步", false, () -> render(DNSHE));
    }

    private void startDeploy(boolean withDomain) {
        if (deployment == null || !token.equals(verifiedToken) || !account.equalsIgnoreCase(verifiedAccount)) {
            verify(true);
            return;
        }
        String selectedDomain = boundDomain.isEmpty() ? domain : boundDomain;
        if (withDomain && (!selectedDomain.matches(HOST) || key.isEmpty() || secret.isEmpty())) {
            message("请填写完整域名、DNSHE API Key 和 API Secret。");
            return;
        }
        if (!pagesReady && submittedPassword.isEmpty() && password.trim().length() < 12) {
            message("后台管理员密码至少需要 12 个字符。");
            return;
        }
        if (!pagesReady && submittedPassword.isEmpty()) submittedPassword = password;
        password = "";
        runAttempted = true;
        bindOnRetry = withDomain;
        failedPhase = 0;
        pending = false;
        progressMessage = "";
        runStarted = SystemClock.elapsedRealtime();
        render(PROGRESS);
        final String credential = verifiedToken;
        final String admin = submittedPassword;
        final String apiKey = key;
        final String apiSecret = secret;
        final boolean publish = !pagesReady;
        final Deployment current = deployment;
        background("正在开始部署…", () -> {
            if (publish) {
                runOnUiThread(() -> setPhase(1));
                current.verify(credential);
                current.deploy(credential, admin, stage -> runOnUiThread(() -> setPhase(stage)));
                runOnUiThread(() -> {
                    pagesReady = true;
                    manageUrl = "https://" + current.pagesHost() + "/admin";
                    managePassword = admin;
                    saveSite(false);
                    submittedPassword = "";
                    setPhase(0);
                    completedPhase = 3;
                    render(PROGRESS);
                });
            }
            if (withDomain) {
                runOnUiThread(() -> setPhase(4));
                current.bind(credential, selectedDomain, apiKey, apiSecret,
                        () -> runOnUiThread(() -> boundDomain = selectedDomain));
                return readDomainStatus(current, credential, selectedDomain);
            }
            return () -> finish(false, false, "Pages 已上线，可以打开后台。");
        });
    }

    private void checkDomainStatus() {
        if (!pending || waitStarted == 0 || SystemClock.elapsedRealtime() - waitStarted < RECHECK_DELAY_MS) return;
        background("正在查询域名验证状态…", () -> readDomainStatus(deployment, verifiedToken, boundDomain));
    }

    private Runnable readDomainStatus(Deployment current, String credential, String selectedDomain) {
        try {
            boolean active = current.domainActive(credential, selectedDomain);
            String detail = active ? "域名验证成功。" : "Pages 已上线，Cloudflare 正在验证 DNS 或签发证书。";
            return () -> finish(active, !active, detail);
        } catch (Exception error) {
            return () -> finish(false, true,
                    "域名已提交，暂时无法查询验证状态。可继续使用 Pages 后台。");
        }
    }

    private void setPhase(int next) {
        if (phase > 0) {
            phaseTimes[phase] += SystemClock.elapsedRealtime() - phaseStarted;
            if (next > phase) completedPhase = phase;
        }
        phase = next;
        phaseStarted = SystemClock.elapsedRealtime();
        updateProgress();
    }

    private void stopProgress() {
        setPhase(0);
        if (runStarted != 0) totalTime += SystemClock.elapsedRealtime() - runStarted;
        runStarted = 0;
    }

    private void finish(boolean active, boolean waits, String detail) {
        stopProgress();
        long now = SystemClock.elapsedRealtime();
        if (waits) {
            if (waitStarted == 0) waitStarted = now;
        } else if (waitStarted != 0) {
            long waited = now - waitStarted;
            totalTime += waited;
            phaseTimes[4] += waited;
            waitStarted = 0;
        }
        failedPhase = 0;
        pending = waits;
        domainActive = active;
        if (active) {
            completedPhase = 4;
            manageUrl = "https://" + boundDomain + "/admin";
            saveSite(false);
        }
        progressMessage = detail;
        render(PROGRESS);
    }

    private void progress() {
        card();
        heading("部署进度");
        elapsed = copy("");
        for (int i = 0; i < PHASE_LABELS.length; i++) {
            TextView stage = text("", 14, muted, false);
            stage.setPadding(dp(12), dp(11), dp(12), dp(11));
            stage.setBackground(shape(panel, border, 9));
            append(section, stage, 8);
            phaseViews[i] = stage;
        }
        statusLine();
        status.setText(progressMessage);
        if (pending) {
            copy("建议预留约 5 分钟，DNS 或证书签发较慢时可能更久。");
            copy("等待满 1 分钟仍未成功，可点「重新验证」查看状态。");
        }
        recheckButton = null;
        if (pagesReady) {
            card();
            title("站点后台");
            Button pages = action("打开 Pages 后台", !domainActive, null);
            pages.setTag("availableDuringDeployment");
            pages.setOnClickListener(view -> openDashboard("https://" + deployment.pagesHost() + "/admin"));
            append(section, pages, 9);
            if (domainActive) button("打开自定义域名后台", true, () -> openDashboard("https://" + boundDomain + "/admin"));
            button("进入后台管理", false, () -> openManage(PROGRESS));
        }
        if (!busy) {
            if (pending) {
                recheckButton = action("重新验证", false, this::checkDomainStatus);
                append(section, recheckButton, 9);
                button("在 Cloudflare 查看进度 ↗", false, () -> open(CLOUDFLARE + verifiedAccount + "/pages/view/" + deployment.pagesHost().split("\\.")[0]));
            } else if (failedPhase > 0) {
                button(pagesReady ? "重试域名绑定" : "继续部署", true,
                        () -> startDeploy(bindOnRetry));
                button("重新授权 Cloudflare", false, () -> render(AUTH));
            }
            if (!pending && !domainActive) {
                button(pagesReady ? "返回域名设置" : "返回修改信息", false, () -> render(DEPLOY));
            }
            button("返回首页", false, () -> render(HOME));
        }
        updateProgress();
    }

    private void updateProgress() {
        if (screen != PROGRESS || elapsed == null) return;
        long now = SystemClock.elapsedRealtime();
        long waited = waitStarted == 0 ? 0 : now - waitStarted;
        long seconds = (totalTime + (runStarted == 0 ? 0 : now - runStarted) + waited) / 1000;
        elapsed.setText(String.format(Locale.ROOT, "已用 %02d:%02d", seconds / 60, seconds % 60));
        if (recheckButton != null) {
            boolean canRecheck = !busy && waited >= RECHECK_DELAY_MS;
            recheckButton.setEnabled(canRecheck);
            recheckButton.setAlpha(canRecheck ? 1f : 0.62f);
        }
        for (int i = 1; i <= phaseViews.length; i++) {
            TextView stage = phaseViews[i - 1];
            if (stage == null) continue;
            String label = "未开始";
            int color = muted;
            if (phase == i) { label = "进行中"; color = accent; }
            else if (failedPhase == i) { label = "失败，可重试"; color = danger; }
            else if (completedPhase >= i) { label = "已完成"; color = good; }
            else if (i == 4 && pending) { label = "等待验证"; color = accent; }
            long duration = (phaseTimes[i] + (phase == i ? now - phaseStarted : 0) + (i == 4 ? waited : 0)) / 1000;
            stage.setText(PHASE_LABELS[i - 1] + " · " + label + (duration > 0 ? "（" + duration + " 秒）" : ""));
            stage.setTextColor(color);
        }
    }

    private void tick() {
        handler.removeCallbacks(progressTick);
        if (screen != PROGRESS || !resumed || isDestroyed() || isFinishing()) return;
        updateProgress();
        if (runStarted != 0 || waitStarted != 0) handler.postDelayed(progressTick, 1_000);
    }

    private void confirmReset() {
        dialog().setTitle("开始新站点？")
                .setMessage("已创建的 Cloudflare 资源会留在原账号内。")
                .setNegativeButton("取消", null)
                .setPositiveButton("开始新站点", (dialog, which) -> {
                    deployment = null;
                    pagesReady = domainActive = pending = runAttempted = false;
                    progressMessage = submittedPassword = boundDomain = password = "";
                    failedPhase = completedPhase = phase = 0;
                    waitStarted = totalTime = 0;
                    java.util.Arrays.fill(phaseTimes, 0);
                    render(AUTH);
                }).show();
    }

    private void openManage(int from) {
        manageReturn = from;
        render(MANAGE);
    }

    private void manage() {
        card();
        heading("站点后台");
        copy("在应用内管理站点，后台跟随日间与暗夜模式。开启记住后，网址和密码加密保存在本机，下次打开自动恢复。");
        field("站点网址", "域名或 HTTPS 网址", manageUrl, false, v -> {
            if (!java.util.Objects.equals(adminUrl(manageUrl), adminUrl(v.trim())) && !managePassword.isEmpty()) {
                managePassword = "";
                if (managePasswordField != null) managePasswordField.setText("");
            }
            manageUrl = v.trim();
        });
        EditText admin = field("后台密码", "输入部署时设置的密码", managePassword, true, v -> managePassword = v);
        managePasswordField = admin;
        CheckBox remember = new CheckBox(this);
        remember.setText("记住此站点和密码（本机加密）"); remember.setTextColor(ink);
        remember.setButtonTintList(ColorStateList.valueOf(accent)); remember.setChecked(rememberSite);
        remember.setOnCheckedChangeListener((v, checked) -> {
            rememberSite = checked;
            getPreferences(MODE_PRIVATE).edit().putBoolean("rememberSite", checked).apply();
            if (!checked) {
                try { SavedSite.clear(this); message("已停止保存并移除本机保存的网址和密码。"); }
                catch (Exception e) { message("清除失败，请重试。"); }
            }
        });
        append(section, remember, 8);
        button("在应用内打开后台", true, () -> {
            String address = adminUrl(manageUrl);
            if (address == null) message("请输入有效的 HTTPS 网址或域名。");
            else if (saveSite(true)) {
                openDashboard(address);
            }
        });
        button("保存站点", false, () -> { if (saveSite(true)) message(rememberSite ? "网址和密码已加密保存。" : "请先开启记住此站点。"); });
        LinearLayout controls = row();
        addHalf(controls, action("复制密码", false, () -> {
            if (managePassword.isEmpty()) {
                message("请先输入后台密码。");
                return;
            }
            ClipData clip = ClipData.newPlainText("后台密码", managePassword);
            if (Build.VERSION.SDK_INT >= 33) {
                PersistableBundle extras = new PersistableBundle();
                extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
                clip.getDescription().setExtras(extras);
            }
            getSystemService(ClipboardManager.class).setPrimaryClip(clip);
            message("密码已复制，在后台登录框粘贴即可。");
        }));
        addHalf(controls, action("清空密码", false, () -> {
            admin.setText("");
            message("密码输入框已清空。");
        }));
        append(section, controls, 8);
        button("清除本机站点与登录会话", false, () -> dialog().setTitle("清除本机记录？")
                .setMessage("将清除保存的网址、密码以及内置后台的登录会话。")
                .setPositiveButton("清除", (d, w) -> {
                    try {
                        SavedSite.clear(this); manageUrl = managePassword = savedSiteError = "";
                        android.webkit.CookieManager.getInstance().removeAllCookies(ok -> {
                            android.webkit.CookieManager.getInstance().flush();
                            android.webkit.WebStorage.getInstance().deleteAllData();
                            render(MANAGE); message("本机站点、密码与登录会话已清除。");
                        });
                    } catch (Exception e) { message("清除失败，请重试。"); }
                }).setNegativeButton("取消", null).show());
        statusLine();
        if (!savedSiteError.isEmpty()) message(savedSiteError);
        button("返回", false, () -> render(manageReturn));
    }

    private boolean saveSite(boolean notify) {
        String address = adminUrl(manageUrl);
        if (address == null) { if (notify) message("请输入有效的 HTTPS 网址或域名。"); return false; }
        try {
            if (rememberSite) SavedSite.save(this, address, managePassword);
            else SavedSite.clear(this);
            savedSiteError = ""; return true;
        } catch (Exception e) {
            savedSiteError = "站点保存失败，请检查设备存储后重试。";
            if (notify) message(savedSiteError);
            return false;
        }
    }

    private void openDashboard(String address) {
        String savedAddress = adminUrl(manageUrl);
        Intent intent = new Intent(this, SiteBrowserActivity.class);
        intent.putExtra("url", address).putExtra("dark", dark);
        if (address.equals(savedAddress)) intent.putExtra("password", managePassword);
        startActivity(intent);
    }

    private static String adminUrl(String input) {
        try {
            String address = input.contains("://") ? input : "https://" + input;
            URI parsed = new URI(address);
            if (!"https".equalsIgnoreCase(parsed.getScheme()) || parsed.getHost() == null || parsed.getUserInfo() != null) return null;
            return new URI("https", null, parsed.getHost(), parsed.getPort(), "/admin", null, null).toASCIIString();
        } catch (java.net.URISyntaxException error) {
            return null;
        }
    }

    private void documentation() {
        card();
        heading("使用文档");
        LinearLayout controls = row();
        addHalf(controls, action(DOC_LANGUAGES[docLanguage] + " ▾", false, () -> dialog()
                .setTitle("文档语言").setSingleChoiceItems(DOC_LANGUAGES, docLanguage, (dialog, selected) -> {
                    dialog.dismiss();
                    docLanguage = selected;
                    getPreferences(MODE_PRIVATE).edit().putInt("docLanguage", selected).apply();
                    render(DOCS);
                }).show()));
        addHalf(controls, action("返回", false, () -> render(docReturn)));
        append(section, controls, 10);
        List<String> titles = new ArrayList<>();
        List<TextView> anchors = new ArrayList<>();
        button("本页目录", false, () -> dialog().setTitle("本页目录")
                .setItems(titles.toArray(new String[0]), (dialog, i) -> {
                    android.graphics.Rect bounds = new android.graphics.Rect();
                    anchors.get(i).getDrawingRect(bounds);
                    body.offsetDescendantRectToMyCoords(anchors.get(i), bounds);
                    scroll.smoothScrollTo(0, bounds.top);
                }).show());
        try (InputStream file = getAssets().open(DOC_FILES[docLanguage])) {
            boolean code = false;
            for (String line : new String(Deployment.readBytes(file), StandardCharsets.UTF_8).split("\\r?\\n")) {
                if (line.startsWith("\u0060\u0060\u0060")) { code = !code; continue; }
                if (line.trim().isEmpty() || line.startsWith("[简体中文](README.md)") || line.matches("\\|[ :|\\-]+\\|")) continue;
                if (!code && line.matches("^#{1,4} .+")) {
                    String title = line.replaceFirst("^#+ ", "");
                    TextView heading = text(title, 20, ink, true);
                    append(section, heading, 17);
                    titles.add(title);
                    anchors.add(heading);
                } else {
                    String formatted = line.startsWith("|") ? line.substring(1, line.length() - 1).replace(" | ", "  ·  ").trim()
                            : line.replaceFirst("^[-*] ", "• ");
                    TextView paragraph = copy("");
                    paragraph.setText(code ? formatted : markdown(formatted));
                    paragraph.setMovementMethod(LinkMovementMethod.getInstance());
                    if (code) paragraph.setTypeface(Typeface.MONOSPACE);
                }
            }
        } catch (IOException error) {
            copy("无法读取随包文档。");
        }
    }

    private CharSequence markdown(String line) {
        SpannableStringBuilder styled = new SpannableStringBuilder();
        Matcher match = MARKDOWN.matcher(line);
        int offset = 0;
        while (match.find()) {
            styled.append(line.substring(offset, match.start()));
            int start = styled.length();
            if (match.group(1) != null) {
                styled.append(match.group(1));
                String url = Uri.parse(match.group(2)).isAbsolute() ? match.group(2)
                        : "https://github.com/lomgzhijie/OpenProxySetup/blob/main/" + match.group(2);
                if (url.startsWith("https://")) styled.setSpan(new ClickableSpan() {
                    @Override public void onClick(View view) { open(url); }
                }, start, styled.length(), 0);
            } else {
                styled.append(match.group(3) == null ? match.group(4) : match.group(3));
                styled.setSpan(new StyleSpan(Typeface.BOLD), start, styled.length(), 0);
            }
            offset = match.end();
        }
        return styled.append(line.substring(offset));
    }

    @Override
    public void onBackPressed() {
        if (busy) return;
        switch (screen) {
            case DOCS: render(docReturn); break;
            case CLOUDFLARE_GUIDE: render(AUTH); break;
            case DNSHE_GUIDE: render(DNSHE); break;
            case MANAGE: render(manageReturn); break;
            case PROGRESS: render(DEPLOY); break;
            case DEPLOY: render(DNSHE); break;
            case DNSHE: render(DOMAIN); break;
            case DOMAIN: render(AUTH); break;
            case AUTH: render(HOME); break;
            default: super.onBackPressed();
        }
    }

    private void card() {
        section = column();
        section.setPadding(dp(17), dp(16), dp(17), dp(16));
        section.setBackground(shape(surface, border, 18));
        append(body, section, body.getChildCount() == 0 ? 0 : 12);
    }

    private void guideLine(String number, String name, String detail) {
        LinearLayout item = row();
        item.setGravity(Gravity.TOP);
        TextView label = text(number, 14, accent, true);
        label.setGravity(Gravity.CENTER);
        label.setBackground(shape(panel, border, 9));
        item.addView(label, new LinearLayout.LayoutParams(dp(37), dp(37)));
        LinearLayout content = column();
        content.setPadding(dp(12), 0, 0, 0);
        item.addView(content, new LinearLayout.LayoutParams(0, -2, 1));
        append(content, text(name, 16, ink, true), 0);
        TextView summary = text(detail, 14, muted, false);
        summary.setLineSpacing(dp(3), 1f);
        append(content, summary, 3);
        append(section, item, 14);
    }

    private void guidePath(int highlight, String... captions) {
        LinearLayout preview = column();
        preview.setPadding(dp(8), dp(8), dp(8), dp(8));
        preview.setBackground(shape(background, border, 12));
        for (int i = 0; i < captions.length; i++) {
            boolean selected = i == highlight;
            TextView entry = text(captions[i], 14, selected ? accent : muted, selected);
            entry.setPadding(dp(10), dp(8), dp(10), dp(8));
            if (selected) entry.setBackground(shape(panel, accent, 8));
            append(preview, entry, i == 0 ? 0 : 3);
        }
        append(section, preview, 8);
    }

    private void heading(String name) { append(section, text(name, 27, ink, true), 0); }
    private void title(String name) { append(section, text(name, 19, ink, true), 0); }

    private TextView copy(String detail) {
        TextView view = text(detail, 15, muted, false);
        view.setLineSpacing(dp(4), 1f);
        append(section, view, 9);
        return view;
    }

    private EditText field(String label, String hint, String value, boolean masked, Consumer<String> change) {
        TextView caption = text(label, 14, ink, true);
        append(section, caption, 14);
        EditText input = new EditText(this);
        input.setId(View.generateViewId());
        caption.setLabelFor(input.getId());
        input.setSingleLine();
        input.setInputType(InputType.TYPE_CLASS_TEXT |
                (masked ? InputType.TYPE_TEXT_VARIATION_PASSWORD : InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS));
        if (masked) input.setTransformationMethod(PasswordTransformationMethod.getInstance());
        input.setSaveEnabled(false);
        input.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        input.setTextColor(ink);
        input.setHintTextColor(muted);
        input.setTextSize(15);
        input.setText(value);
        input.setHint(hint);
        input.setMinHeight(dp(49));
        input.setPadding(dp(12), dp(8), dp(12), dp(8));
        input.setBackground(shape(background, border, 10));
        input.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { change.accept(s.toString()); }
            @Override public void afterTextChanged(Editable s) {}
        });
        LinearLayout tools = row();
        tools.addView(input, new LinearLayout.LayoutParams(0, -2, 1));
        Button paste = action("粘贴", false, () -> {
            ClipboardManager clipboard = getSystemService(ClipboardManager.class);
            ClipData clip = clipboard.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0 || clip.getItemAt(0).getText() == null) {
                message("剪贴板没有可粘贴的文字。");
                return;
            }
            input.setText(clip.getItemAt(0).getText().toString());
            input.setSelection(input.length());
        });
        paste.setContentDescription("粘贴 " + label);
        addFieldAction(tools, paste);
        if (masked) {
            Button reveal = action("显示", false, null);
            reveal.setContentDescription("显示或隐藏 " + label);
            reveal.setOnClickListener(view -> {
                if (busy) return;
                boolean show = input.getTransformationMethod() != null;
                input.setTransformationMethod(show ? null : PasswordTransformationMethod.getInstance());
                reveal.setText(show ? "隐藏" : "显示");
                input.setSelection(input.length());
            });
            addFieldAction(tools, reveal);
        }
        append(section, tools, 5);
        return input;
    }

    private Button action(String caption, boolean main, Runnable run) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(caption);
        view.setTextSize(14);
        view.setTextColor(main ? 0xfffdfdff : accent);
        view.setMinWidth(0);
        view.setMinimumWidth(0);
        view.setMinimumHeight(dp(46));
        view.setPadding(dp(8), dp(7), dp(8), dp(7));
        view.setBackground(new RippleDrawable(ColorStateList.valueOf(0x316d8fed),
                shape(main ? primary : panel, main ? primary : border, 11), null));
        if (run != null) view.setOnClickListener(button -> { if (!busy) run.run(); });
        return view;
    }

    private void button(String label, boolean primary, Runnable run) { append(section, action(label, primary, run), 9); }

    private void statusLine() {
        status = copy("");
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
    }

    private void message(String text) {
        if (status == null) statusLine();
        status.setText(text);
    }

    private void background(String label, Work work) {
        View focused = getCurrentFocus();
        if (focused != null) {
            getSystemService(InputMethodManager.class).hideSoftInputFromWindow(focused.getWindowToken(), 0);
            focused.clearFocus();
        }
        busy = true;
        updateControls(shell, false);
        message(label);
        new Thread(() -> {
            try {
                Runnable done = work.run();
                runOnUiThread(() -> {
                    if (isDestroyed() || isFinishing()) return;
                    busy = false;
                    updateControls(shell, true);
                    done.run();
                    showAvailableUpdate();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (isDestroyed() || isFinishing()) return;
                    busy = false;
                    String reason = error instanceof IOException ? error.getMessage() : "服务返回的数据格式异常。";
                    if (screen == PROGRESS) {
                        failedPhase = phase;
                        stopProgress();
                        progressMessage = reason;
                        render(PROGRESS);
                    } else {
                        updateControls(shell, true);
                        message(reason);
                    }
                    showAvailableUpdate();
                });
            }
        }, "OpenProxySetup").start();
    }

    private void updateControls(LinearLayout parent, boolean enabled) {
        for (int i = 0; i < parent.getChildCount(); i++) {
            View view = parent.getChildAt(i);
            if (view instanceof LinearLayout) updateControls((LinearLayout) view, enabled);
            else if (view instanceof ScrollView && ((ScrollView) view).getChildCount() > 0)
                updateControls((LinearLayout) ((ScrollView) view).getChildAt(0), enabled);
            else if ((view instanceof Button || view instanceof EditText) && !"availableDuringDeployment".equals(view.getTag())) {
                view.setEnabled(enabled);
                view.setAlpha(enabled ? 1f : 0.62f);
            }
        }
    }

    private void open(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (android.content.ActivityNotFoundException error) {
            message("手机上没有可打开此网址的浏览器。");
        }
    }

    private void colors() {
        background = dark ? 0xff101827 : 0xfff1f5fc;
        surface = dark ? 0xff19243a : 0xffffffff;
        panel = dark ? 0xff22324d : 0xffedf3ff;
        border = dark ? 0xff384b69 : 0xffd8e3f6;
        ink = dark ? 0xfff1f5ff : 0xff101d36;
        muted = dark ? 0xffbecce3 : 0xff445877;
        accent = dark ? 0xffadc5ff : 0xff264dcc;
        primary = dark ? 0xff385ecf : 0xff244bdb;
        good = dark ? 0xff9ae4bb : 0xff197148;
        danger = dark ? 0xffffb0a8 : 0xffa5282b;
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setLinkTextColor(accent);
        if (bold) view.setTypeface(null, Typeface.BOLD);
        return view;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private GradientDrawable shape(int fill, int stroke, int radius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setStroke(dp(1), stroke);
        drawable.setCornerRadius(dp(radius));
        return drawable;
    }

    private void append(LinearLayout parent, View child, int top) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.topMargin = dp(top);
        parent.addView(child, params);
    }

    private void addHalf(LinearLayout parent, View view) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -2, 1);
        if (parent.getChildCount() > 0) params.leftMargin = dp(7);
        parent.addView(view, params);
    }

    private void addFieldAction(LinearLayout parent, View view) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(51), dp(48));
        params.leftMargin = dp(5);
        parent.addView(view, params);
    }

    private AlertDialog.Builder dialog() {
        return new AlertDialog.Builder(this, dark
                ? android.R.style.Theme_Material_Dialog_Alert
                : android.R.style.Theme_Material_Light_Dialog_Alert);
    }

    private static String normalizeDomain(String value) {
        return value.trim().toLowerCase(Locale.ROOT).replaceFirst("\\.$", "");
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    private interface Work {
        Runnable run() throws Exception;
    }
}
