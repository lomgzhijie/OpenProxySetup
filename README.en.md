# 自建机场

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

## Install and use

1. [Download the Windows x64 installer](https://github.com/lomgzhijie/zijianjichang/releases/download/v1.3.1/zijianjichang-windows-x64-setup.exe). Run it and choose an installation location. Setup creates a 自建机场 folder and opens the deployment wizard. To open it again, run 自建机场.exe from that folder.
2. Follow the wizard to prepare a DNSHE domain and API credentials, then authorize your own Cloudflare account in the browser.
3. Enter the domain, DNSHE credentials, and an administrator password of at least 12 characters. Start deployment.
4. Open the admin address shown by the wizard, sign in, and copy the subscription URL into a compatible client. You can use the Pages address while the custom domain is being verified.

Windows x64 and network access to DNSHE and Cloudflare are required. Node.js and Wrangler are bundled. Use accounts and domains you control and follow applicable laws and service terms.

[MIT](LICENSE) · [edgetunnel GPL-2.0](vendor/edgetunnel/LICENSE)
