# 自建机场

[下载 Windows x64 版](https://github.com/lomgzhijie/zijianjichang/releases/latest) · [报告问题](https://github.com/lomgzhijie/zijianjichang/issues/new/choose) · [参与贡献](CONTRIBUTING.md)

一个供用户下载的 Windows 部署应用。用户用自己的 Cloudflare 账号登录，设置后台管理员密码，应用使用包内的 [edgetunnel](https://github.com/cmliu/edgetunnel) 源码创建 Cloudflare KV 和 Pages，并给出可点击的网站地址。用户访问网站的 `/admin`，输入刚设置的密码，即可在上游后台查看节点和订阅链接。

本项目提供部署向导，不提供共享节点、账号或云服务。每位用户部署到自己的 Cloudflare 账号。

## 部署教程

[下载 Windows 部署视频教程（MP4）](https://github.com/lomgzhijie/zijianjichang/releases/download/v1.3/zijianjichang-v1.3-tutorial.mp4)

视频约 2 分 49 秒，无声。开头用说明卡介绍 DNSHE 域名、Cloudflare 授权和部署参数，随后用实录演示部署结果、管理后台和 v2rayN 导入界面。画面中的敏感字段已遮挡。

使用 Windows 部署向导可以把服务部署到自己的 Cloudflare 账号，并通过管理后台获取订阅。部署和 DNS 生效时间以应用及服务商显示的状态为准。

- **准备域名和授权**：在 DNSHE 注册域名并创建 API 密钥，在浏览器中完成 Cloudflare 授权。
- **运行部署向导**：填写域名、DNSHE 授权和后台密码，等待应用返回管理后台地址。
- **验证和导入**：打开管理后台，登录后复制订阅链接，在 v2rayN 中导入并测试。

跟做时请使用自己的账号和域名。录屏或截图发布前，请遮挡 API 密钥、后台密码和完整订阅地址。

## 下载与使用

首页提供法律法规提示，也可直接进入「后台管理」。部署成功后会预填网址和后台密码；已有站点可手动填写。打开后台后，在浏览器中登录。密码只保留在当前应用窗口内，可按需复制或清空。

1. 下载项目发布页的 `zijianjichang-windows-x64-v1.3.zip`，解压后双击 **启动应用.cmd**。注册说明、授权说明和填写部署都在同一个窗口的四个步骤页；可点“上一步”“下一步”切换。如 Windows 显示安全提示，请先确认文件来自本项目仓库并自行审查脚本。
2. 按应用中的链接注册或登录 [Cloudflare](https://dash.cloudflare.com/sign-up) 和 [DNSHE](https://my.dnshe.com/)。在 DNSHE 取得域名，并在“域名管理 → API 管理”创建 API Key 和 API Secret。到应用第 3 步点击“开始 Cloudflare 授权”，在浏览器完成授权，再点“我已完成授权，继续”。应用会先验证授权，再进入部署页；账号密码只在 Cloudflare 网站输入。
3. 在应用中填写 DNSHE 域名、API Key / Secret，并设置至少 12 位的后台管理员密码，然后点击部署。应用负责创建 KV、Pages、密钥并部署，然后向 Pages 提交自定义域名绑定，通过 DNSHE API 为该域名添加指向 `pages.dev` 的 CNAME。已有的冲突 DNS 记录不会被覆盖。
4. 部署成功后点击应用显示的后台网址，输入刚才设置的密码。在后台复制需要的节点或订阅链接，导入兼容客户端。实际可用格式由部署时的上游版本决定。自定义域名生效前，先使用应用显示的 `pages.dev` 地址。

点击部署后窗口会保持可操作，并显示已用时间。部署通常估计需要约 3–10 分钟，取决于网络和浏览器授权；自定义域名的 DNS 与证书生效可能另需数分钟至数小时。

DNSHE 的 API Key / Secret 是添加 CNAME 所必需的授权。应用只在本次运行中使用它们，不写入项目文件。如果该域名已有 DNS 记录或 DNSHE 拒绝写入，应用不会覆盖原记录。Cloudflare 证书签发和 DNS 传播可能需要等待；在此之前先使用 `pages.dev` 后台地址。Cloudflare Pages 官方文档允许外部 DNS 管理的子域名通过 CNAME 绑定，无须把该域名创建为 Cloudflare Zone。

### 系统要求

- Windows 10/11
- 可访问 Cloudflare 和 DNSHE 的网络。下载包已包含 Node.js、Wrangler 和上游节点源码，运行时无需另装 Git 或 Node.js

## 项目维护者打包

在 PowerShell 里运行 `npm ci --prefix runtime` 安装固定版本的 Wrangler，并将 Windows x64 版 `node.exe` 及其 `NODE-LICENSE` 放入 `runtime`，再运行 `./打包发布.ps1` 生成 `自建机场-Windows-v1.3.zip`。下载者无需执行这些维护命令。源码可直接运行 `./app.ps1`。

## 工作原理与边界

1. 下载包内含固定版本的上游 `_worker.js`、上游 GPL-2.0 许可证及提交号；运行时直接使用包内文件，不执行 `git clone`。
2. 调用 Cloudflare 官方 Wrangler CLI 完成浏览器授权，创建 KV、设置 `ADMIN` 密钥、创建 Pages 项目并部署，再通过 Cloudflare Pages API 绑定自定义域名，通过 DNSHE API 创建 CNAME。
3. 展示 `https://<项目名>.pages.dev/admin`。该地址是管理后台，**不是订阅地址**；订阅链接由上游后台生成。

管理员密码仅在当前进程中传给 Cloudflare，不写入项目文件。请勿分享密码或订阅链接。Cloudflare 免费额度、平台规则和上游功能可能变化；使用者应遵守当地法律及平台条款。

## 来源与许可证

本项目使用 [edgetunnel 上游代码](https://github.com/cmliu/edgetunnel)，部署流程参照 [Cloudflare Pages 文档](https://developers.cloudflare.com/pages/)。本仓库的自有脚本和文档采用 MIT 许可证；包内上游代码采用 GPL-2.0，见 `vendor/edgetunnel/LICENSE`。打包的 Node.js 许可证在 `runtime/NODE-LICENSE`，Wrangler 及其依赖的许可证随 npm 包提供。再分发时须保留相应源码和许可证。
