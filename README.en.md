# 自建机场

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[Download Windows x64](https://github.com/lomgzhijie/zijianjichang/releases/latest) · [Report an issue](https://github.com/lomgzhijie/zijianjichang/issues/new/choose) · [Contribute](CONTRIBUTING.md)

This Windows deployment app signs in with your own Cloudflare account and lets you set an administrator password. It uses the bundled [edgetunnel](https://github.com/cmliu/edgetunnel) source to create Cloudflare KV and Pages resources and displays a clickable site address. Open the site’s `/admin` page and enter the password to view nodes and subscription links in the upstream dashboard.

The project provides a deployment wizard. Each user deploys to their own Cloudflare account. Shared nodes, accounts, and hosting are outside the scope of the project.

## Download and use

The home screen shows a legal notice and offers direct access to the admin dashboard. After deployment, the app fills in the site address and administrator password. For an existing site, enter them manually. Sign in to the dashboard in your browser. The password remains in the current app window and can be copied or cleared.

1. Download the [Windows x64 installer](https://github.com/lomgzhijie/zijianjichang/releases/download/v1.3.1/zijianjichang-windows-x64-setup.exe), double-click it, and select an installation location. Setup creates a `自建机场` folder and opens the wizard. To reopen the app, double-click `自建机场.exe` in that folder.
2. Use the app’s links to sign up for or sign in to [Cloudflare](https://dash.cloudflare.com/sign-up) and [DNSHE](https://my.dnshe.com/). Obtain a domain in DNSHE, and create an API Key and API Secret under Domain Management → API Management. In step 3, select “开始 Cloudflare 授权” (Start Cloudflare authorization), complete authorization in the browser, then select “我已完成授权，继续” (I’ve authorized, continue). The app verifies authorization before opening the deployment screen. Enter your account credentials on Cloudflare’s website.
3. Enter the DNSHE domain, API Key, API Secret, and an administrator password of at least 12 characters. Start deployment. The app creates KV, Pages, and the secret, deploys the site, requests the custom domain binding in Pages, and uses the DNSHE API to add a CNAME pointing to `pages.dev`. Existing conflicting DNS records are preserved.
4. When deployment succeeds, open the displayed admin address and sign in with the password you set. Copy a node or subscription link from the dashboard and import it into a compatible client. Available formats depend on the upstream version used for deployment. Use the displayed `pages.dev` address while the custom domain is taking effect.

The window stays responsive and shows elapsed time during deployment. Allow roughly 3–10 minutes, depending on the network and browser authorization. DNS and certificate activation for the custom domain may take several more minutes to a few hours.

The DNSHE API Key and Secret authorize adding the CNAME. The app uses them during the current session and keeps them out of project files. If existing DNS records conflict or DNSHE rejects the write, existing records are preserved. Use the `pages.dev` admin address while Cloudflare issues the certificate and DNS propagates. The Cloudflare Pages documentation allows a subdomain managed by external DNS to be bound via CNAME without creating a Cloudflare zone for it.

### System requirements

- Windows 10 or 11
- Network access to Cloudflare and DNSHE. Node.js, Wrangler, and the upstream node source are bundled. Git and a separate Node.js installation are unnecessary for running the app.

## Client compatibility

The platform and client list follows the [upstream edgetunnel documentation](https://github.com/cmliu/edgetunnel). Check that your client version supports your subscription format before importing.

| Platform | Clients |
| --- | --- |
| Windows | [v2rayN](https://github.com/2dust/v2rayN/releases), [Hiddify](https://github.com/hiddify/hiddify-app/releases), [FlClash](https://github.com/chen08209/FlClash/releases), [mihomo-party](https://github.com/mihomo-party-org/clash-party/releases), [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev/releases), [Clashmi](https://github.com/KaringX/clashmi/releases), [FlyClash](https://github.com/GtxFury/FlyClash/releases), [Karing](https://github.com/KaringX/karing/releases), [Bettbox](https://github.com/appshubcc/Bettbox/releases) |
| Android | [v2rayNG](https://github.com/2dust/v2rayNG/releases), [ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid/releases/), [FlClash](https://github.com/chen08209/FlClash/releases), [Clashmi](https://github.com/KaringX/clashmi/releases), [Hiddify](https://github.com/hiddify/hiddify-app/releases), [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases), [FlyClash](https://github.com/GtxFury/FlyClash/releases), [Karing](https://github.com/KaringX/karing/releases), [Bettbox](https://github.com/appshubcc/Bettbox/releases) |
| iOS | Surge, Shadowrocket, Stash, [Hiddify](https://github.com/hiddify/hiddify-app/releases), Loon, Egern, [Clashmi](https://github.com/KaringX/clashmi/releases), [Karing](https://github.com/KaringX/karing/releases), Quantumult X |
| macOS | [FlClash](https://github.com/chen08209/FlClash/releases), [mihomo-party](https://github.com/mihomo-party-org/clash-party/releases), [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev/releases), [Surge](https://nssurge.com/), [Clashmi](https://clashmi.app/download), [Karing](https://karing.app/), [FlyClash](https://github.com/GtxFury/FlyClash/releases) |
| HarmonyOS | [ClashBox](https://github.com/xiaobaigroup/ClashBox/releases) |

## Portable ZIP

Extract the entire `自建机场-Windows-EXE-v1.3.1.zip` archive and double-click `自建机场.exe`. Keep the EXE, `runtime`, `vendor`, and scripts in the same directory. The app uses Windows’ .NET Framework and Windows PowerShell 5.1. If it fails to launch, run `启动应用.cmd` to see the error.

You can also download the [v1.3 CMD edition](https://github.com/lomgzhijie/zijianjichang/releases/download/v1.3.1/zijianjichang-windows-x64-cmd-v1.3.zip). Extract the entire ZIP and double-click `启动应用.cmd`.

## Packaging for maintainers

Run `npm ci --prefix runtime` in PowerShell to install the pinned Wrangler version, then place the Windows x64 `node.exe` and its `NODE-LICENSE` in `runtime`. Run `./打包发布.ps1` in Windows PowerShell 5.1 to compile the EXE and build `自建机场-Windows-EXE-v1.3.1.zip`. Run `./构建应用.ps1` to compile the launcher separately, or `./构建安装程序.ps1` to turn the ZIP into an installer EXE. Launcher source is in `launcher/Launcher.cs`. These commands are for maintainers. To launch from source, run `./app.ps1`.

## How it works and scope

1. The package bundles a pinned upstream `_worker.js`, its GPL-2.0 license, and the upstream commit ID. The app uses the bundled files at runtime without running `git clone`.
2. The app uses Cloudflare’s official Wrangler CLI for browser authorization, KV creation, setting the `ADMIN` secret, and creating and deploying the Pages project. It binds the custom domain through the Cloudflare Pages API and adds the CNAME through the DNSHE API.
3. The app displays `https://<project-name>.pages.dev/admin`, the admin dashboard address. The upstream dashboard generates the subscription link.

The app passes the administrator password to Cloudflare in the current process and keeps it out of project files. Keep passwords and subscription links private. Cloudflare’s free quotas, platform rules, and upstream features may change. Follow local laws and the platform terms.

## Sources and licenses

The project uses [upstream edgetunnel code](https://github.com/cmliu/edgetunnel) and follows the [Cloudflare Pages documentation](https://developers.cloudflare.com/pages/) for deployment. The repository’s own scripts and documentation are MIT-licensed. The bundled upstream code is GPL-2.0 licensed. See `vendor/edgetunnel/LICENSE`. The bundled Node.js license is in `runtime/NODE-LICENSE`, and Wrangler and its dependencies ship their licenses in their npm packages. Retain the corresponding source code and licenses when redistributing.
