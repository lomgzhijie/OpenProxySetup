# 自建机场

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

## インストールと使い方

1. [Windows x64 インストーラーをダウンロード](https://github.com/lomgzhijie/zijianjichang/releases/download/v1.3.1/zijianjichang-windows-x64-setup.exe)して実行し、インストール先を選択します。「自建机场」フォルダーが作成され、デプロイウィザードが開きます。次回からはフォルダー内の 自建机场.exe を起動してください。
2. ウィザードに従って DNSHE のドメインと API 認証情報を用意し、ブラウザーで自分の Cloudflare アカウントを認証します。
3. ドメイン、DNSHE の認証情報、12 文字以上の管理者パスワードを入力し、デプロイを開始します。
4. 表示された管理画面を開いてログインし、サブスクリプション URL を対応クライアントに追加します。独自ドメインの検証中は Pages のアドレスを利用できます。

Windows x64 と DNSHE・Cloudflare へのネットワーク接続が必要です。Node.js と Wrangler は同梱されています。ご自身が管理するアカウントとドメインを使用し、適用される法令と利用規約を守ってください。

[MIT](LICENSE) · [edgetunnel GPL-2.0](vendor/edgetunnel/LICENSE)
