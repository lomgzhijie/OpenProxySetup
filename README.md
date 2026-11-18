# 自建机场

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[下载 Windows x64 版](https://github.com/lomgzhijie/OpenProxySetup/releases/latest) · [Android 预览版 APK](https://github.com/lomgzhijie/OpenProxySetup/releases/tag/android-v0.3.4) · [报告问题](https://github.com/lomgzhijie/OpenProxySetup/issues/new/choose) · [参与贡献](CONTRIBUTING.md)

一个供用户下载的 Windows 部署应用。用户用自己的 Cloudflare 账号登录，设置后台管理员密码，应用使用包内的 [edgetunnel](https://github.com/cmliu/edgetunnel) 源码创建 Cloudflare KV 和 Pages，并给出可点击的网站地址。用户访问网站的 `/admin`，输入刚设置的密码，即可在上游后台查看节点和订阅链接。

本项目提供部署向导，不提供共享节点、账号或云服务。每位用户部署到自己的 Cloudflare 账号。

## 下载与使用

首页提示使用前准备可访问 Cloudflare 的 VPN 环境，并提供法律法规提示。你也可直接进入「后台管理」。部署成功后会预填网址和后台密码；已有站点可手动填写。打开后台后，在浏览器中登录。密码只保留在当前应用窗口内，可按需复制或清空。

1. 下载 [Windows x64 安装程序](https://github.com/lomgzhijie/OpenProxySetup/releases/download/v1.4.0/OpenProxySetup-windows-x64-setup.exe)，双击运行并选择安装位置。安装程序会创建「自建机场」文件夹并打开部署向导。之后可从该目录双击 OpenProxySetup.exe。
2. 先在应用第 1 步点击「开始 Cloudflare 授权」，在浏览器注册或登录 [Cloudflare](https://dash.cloudflare.com/sign-up) 并完成授权，再回到向导点击「我已完成授权，继续」。授权验证后，在第 2 步从 [DNSHE](https://my.dnshe.com/) 获取域名，在第 3 步通过「域名管理 → API 管理」创建 API Key 和 API Secret。Cloudflare 账号密码只在 Cloudflare 网站输入。
3. 在应用中填写 DNSHE 域名、API Key / Secret，并设置至少 12 位的后台管理员密码，然后点击部署。应用负责创建 KV、Pages、密钥并部署，然后向 Pages 提交自定义域名绑定，通过 DNSHE API 为该域名添加指向 `pages.dev` 的 CNAME。已有的冲突 DNS 记录不会被覆盖。
4. 部署成功后点击应用显示的后台网址，输入刚才设置的密码。在后台复制需要的节点或订阅链接，导入兼容客户端。实际可用格式由部署时的上游版本决定。自定义域名生效前，先使用应用显示的 `pages.dev` 地址。

「部署进度」显示 Cloudflare 授权、KV 创建、Pages 发布和域名绑定的状态。Pages 发布后可先打开临时后台。域名绑定失败时，在同一个应用窗口修改 DNSHE 授权，并点击「重试域名绑定」，继续使用已创建的 Pages 和 KV。

点击部署后窗口会保持可操作，并显示已用时间。部署通常估计需要约 3–10 分钟，取决于网络和浏览器授权；自定义域名的 DNS 与证书生效可能另需数分钟至数小时。

DNSHE 的 API Key / Secret 是添加 CNAME 所必需的授权。应用只在本次运行中使用它们，不写入项目文件。如果该域名已有 DNS 记录或 DNSHE 拒绝写入，应用不会覆盖原记录。Cloudflare 证书签发和 DNS 传播可能需要等待；在此之前先使用 `pages.dev` 后台地址。Cloudflare Pages 官方文档允许外部 DNS 管理的子域名通过 CNAME 绑定，无须把该域名创建为 Cloudflare Zone。

### API Token 备用授权

如果浏览器授权卡住，但 Cloudflare 部署 API 有响应，可以使用自己账号的 [Cloudflare API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)。将 Token 权限限制在要部署的账号，并授予 **Cloudflare Pages: Edit** 与 **Workers KV Storage: Edit**。同时准备该账号的 [Account ID](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/)。

在应用目录打开一个新的 Windows PowerShell 窗口，运行以下命令。Token 输入时会隐藏，仅设置在当前 PowerShell 进程内。

```powershell
$env:CLOUDFLARE_ACCOUNT_ID = Read-Host 'Cloudflare Account ID'
$cloudflareToken = Read-Host 'Cloudflare API Token' -AsSecureString
try {
    $env:CLOUDFLARE_API_TOKEN = [Net.NetworkCredential]::new('', $cloudflareToken).Password
    .\app.ps1
} finally {
    Remove-Item Env:CLOUDFLARE_API_TOKEN, Env:CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue
    $cloudflareToken.Dispose()
}
```

在第 1 步直接点击「我已完成授权，继续」。点击部署后，应用会先检查该 Token 能否读取指定账号的 Pages 项目，再创建云端资源。

### 系统要求

- Windows 10/11
- 可访问 Cloudflare 和 DNSHE 的网络。下载包已包含 Node.js、Wrangler 和上游节点源码，运行时无需另装 Git 或 Node.js

## 客户端适配情况

平台和客户端列表参考 [edgetunnel 上游文档](https://github.com/cmliu/edgetunnel)。导入前请确认客户端版本支持你的订阅格式。

| 平台 | 客户端 |
| --- | --- |
| Windows | [v2rayN](https://github.com/2dust/v2rayN/releases), [Hiddify](https://github.com/hiddify/hiddify-app/releases), [FlClash](https://github.com/chen08209/FlClash/releases), [mihomo-party](https://github.com/mihomo-party-org/clash-party/releases), [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev/releases), [Clashmi](https://github.com/KaringX/clashmi/releases), [FlyClash](https://github.com/GtxFury/FlyClash/releases), [Karing](https://github.com/KaringX/karing/releases), [Bettbox](https://github.com/appshubcc/Bettbox/releases) |
| Android | [v2rayNG](https://github.com/2dust/v2rayNG/releases), [ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid/releases/), [FlClash](https://github.com/chen08209/FlClash/releases), [Clashmi](https://github.com/KaringX/clashmi/releases), [Hiddify](https://github.com/hiddify/hiddify-app/releases), [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases), [FlyClash](https://github.com/GtxFury/FlyClash/releases), [Karing](https://github.com/KaringX/karing/releases), [Bettbox](https://github.com/appshubcc/Bettbox/releases) |
| iOS | Surge, Shadowrocket, Stash, [Hiddify](https://github.com/hiddify/hiddify-app/releases), Loon, Egern, [Clashmi](https://github.com/KaringX/clashmi/releases), [Karing](https://github.com/KaringX/karing/releases), Quantumult X |
| macOS | [FlClash](https://github.com/chen08209/FlClash/releases), [mihomo-party](https://github.com/mihomo-party-org/clash-party/releases), [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev/releases), Surge, [Clashmi](https://github.com/KaringX/clashmi/releases), [Karing](https://github.com/KaringX/karing/releases), [FlyClash](https://github.com/GtxFury/FlyClash/releases) |
| 鸿蒙 | [ClashBox](https://github.com/xiaobaigroup/ClashBox/releases) |

## ZIP 免安装版

完整解压 `OpenProxySetup-windows-x64-portable.zip` 后，双击 `OpenProxySetup.exe`。EXE 与 runtime、vendor 及脚本应放在同一个目录。运行依赖 Windows 自带的 .NET Framework 和 Windows PowerShell 5.1。启动失败时，可运行 `启动应用.cmd` 查看错误。

也可下载 [v1.4.0 CMD 版](https://github.com/lomgzhijie/OpenProxySetup/releases/download/v1.4.0/OpenProxySetup-windows-x64-cmd-v1.4.0.zip)，完整解压后双击 `OpenProxySetup.cmd`。

## 项目维护者打包

在 PowerShell 里运行 `npm ci --prefix runtime` 安装固定版本的 Wrangler，并将 Windows x64 版 `node.exe` 及其 `NODE-LICENSE` 放入 `runtime`，使用 Windows PowerShell 5.1 运行 `./打包发布.ps1`，自动编译 EXE 并生成 `OpenProxySetup-windows-x64-portable.zip` 和 CMD ZIP。单独编译可运行 `./构建应用.ps1`，运行 ./构建安装程序.ps1 可将 ZIP 打包成安装 EXE。启动入口源码位于 `launcher/Launcher.cs`。下载者无需执行这些维护命令。源码可直接运行 `./app.ps1`。

## 工作原理与边界

1. 下载包内含固定版本的上游 `_worker.js`、上游 GPL-2.0 许可证及提交号；运行时直接使用包内文件，不执行 `git clone`。
2. 调用 Cloudflare 官方 Wrangler CLI 完成浏览器授权，创建 KV、设置 `ADMIN` 密钥、创建 Pages 项目并部署，再通过 Cloudflare Pages API 绑定自定义域名，通过 DNSHE API 创建 CNAME。
3. 展示 `https://<项目名>.pages.dev/admin`。该地址是管理后台，**不是订阅地址**；订阅链接由上游后台生成。

管理员密码仅在当前进程中传给 Cloudflare，不写入项目文件。请勿分享密码或订阅链接。Cloudflare 免费额度、平台规则和上游功能可能变化；使用者应遵守当地法律及平台条款。

## 来源与许可证

本项目使用 [edgetunnel 上游代码](https://github.com/cmliu/edgetunnel)，部署流程参照 [Cloudflare Pages 文档](https://developers.cloudflare.com/pages/)。本仓库的自有脚本和文档采用 MIT 许可证；包内上游代码采用 GPL-2.0，见 `vendor/edgetunnel/LICENSE`。打包的 Node.js 许可证在 `runtime/NODE-LICENSE`，Wrangler 及其依赖的许可证随 npm 包提供。再分发时须保留相应源码和许可证。

发布包中的 edgetunnel 源文件和 GPL-2.0 许可证与[固定的上游提交](https://github.com/cmliu/edgetunnel/tree/a8ab11125ece9bc27983f609a6359be81b21050c)一致。部署脚本直接复制 `_worker.js`。下载发布页上的 `Source code (zip)` 可查看对应版本的项目源码和构建脚本。
