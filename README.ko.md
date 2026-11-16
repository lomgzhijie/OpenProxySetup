# 自建机场

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[Windows x64 다운로드](https://github.com/lomgzhijie/zijianjichang/releases/latest) · [문제 신고](https://github.com/lomgzhijie/zijianjichang/issues/new/choose) · [기여하기](CONTRIBUTING.md)

Windows용 배포 앱입니다. 본인의 Cloudflare 계정으로 로그인하고 관리자 비밀번호를 설정합니다. 앱은 함께 제공되는 [edgetunnel](https://github.com/cmliu/edgetunnel) 소스로 Cloudflare KV와 Pages를 만들고 클릭할 수 있는 사이트 주소를 표시합니다. 사이트의 `/admin`에 접속해 설정한 비밀번호로 로그인하면 업스트림 관리 화면에서 노드와 구독 링크를 확인할 수 있습니다.

이 프로젝트는 배포 마법사를 제공합니다. 각 사용자는 본인의 Cloudflare 계정에 배포합니다. 공유 노드, 계정, 클라우드 서비스 제공은 프로젝트 범위에 포함되지 않습니다.

## 다운로드 및 사용

홈 화면에 법률 관련 안내가 표시되며 「后台管理」(관리 화면)로 바로 이동할 수도 있습니다. 배포에 성공하면 사이트 주소와 관리자 비밀번호가 자동 입력됩니다. 기존 사이트는 직접 입력한 뒤 브라우저에서 관리 화면에 로그인합니다. 비밀번호는 현재 앱 창에만 남으며 필요할 때 복사하거나 지울 수 있습니다.

1. [Windows x64 설치 프로그램](https://github.com/lomgzhijie/zijianjichang/releases/download/v1.3.1/zijianjichang-windows-x64-setup.exe)을 다운로드하고 실행한 뒤 설치 위치를 선택합니다. 설치 프로그램이 `自建机场` 폴더를 만들고 배포 마법사를 엽니다. 다음부터는 이 폴더의 `自建机场.exe`를 실행합니다.
2. 앱의 링크를 이용해 [Cloudflare](https://dash.cloudflare.com/sign-up)와 [DNSHE](https://my.dnshe.com/)에 가입하거나 로그인합니다. DNSHE에서 도메인을 발급받고 ‘도메인 관리 → API 관리’에서 API Key와 API Secret을 만듭니다. 3단계에서 ‘开始 Cloudflare 授权’을 눌러 브라우저 인증을 완료하고 ‘我已完成授权，继续’를 선택합니다. 앱은 인증을 확인한 뒤 배포 화면을 엽니다. Cloudflare 계정 인증 정보는 Cloudflare 웹사이트에서 입력합니다.
3. DNSHE 도메인, API Key, API Secret, 12자 이상의 관리자 비밀번호를 입력하고 배포를 시작합니다. 앱이 KV, Pages, 시크릿을 만들고 배포한 다음 Pages에 사용자 지정 도메인 연결을 요청합니다. DNSHE API로 `pages.dev`를 가리키는 CNAME도 추가합니다. 충돌하는 기존 DNS 레코드는 보존합니다.
4. 배포가 끝나면 앱에 표시된 관리 주소를 열고 설정한 비밀번호로 로그인합니다. 관리 화면에서 노드 또는 구독 링크를 복사해 호환 클라이언트에 가져옵니다. 사용 가능한 형식은 배포에 사용한 업스트림 버전에 따라 달라집니다. 사용자 지정 도메인이 활성화될 때까지 앱에 표시된 `pages.dev` 주소를 사용할 수 있습니다.

배포 중에도 창을 사용할 수 있으며 경과 시간이 표시됩니다. 네트워크와 브라우저 인증 상태에 따라 보통 약 3~10분이 걸립니다. 사용자 지정 도메인의 DNS와 인증서가 활성화되기까지 몇 분에서 몇 시간이 더 걸릴 수 있습니다.

CNAME을 추가하려면 DNSHE API Key와 API Secret이 필요합니다. 앱은 현재 실행 중에만 이 값을 사용하며 프로젝트 파일에 기록하지 않습니다. 기존 DNS 레코드가 충돌하거나 DNSHE가 쓰기를 거부하면 기존 레코드를 보존합니다. 인증서 발급과 DNS 전파를 기다리는 동안에는 `pages.dev` 관리 주소를 사용할 수 있습니다. Cloudflare Pages 공식 문서에 따르면 외부 DNS에서 관리하는 하위 도메인을 별도의 Cloudflare 영역으로 만들지 않고 CNAME을 통해 연결할 수 있습니다.

### 시스템 요구 사항

- Windows 10 또는 Windows 11
- Cloudflare와 DNSHE에 접속 가능한 네트워크. Node.js, Wrangler, 업스트림 노드 소스가 포함되어 있어 Git이나 Node.js를 따로 설치할 필요가 없습니다.

## ZIP 포터블 버전

`自建机场-Windows-EXE-v1.3.1.zip`의 전체 압축을 푼 후 `自建机场.exe`를 더블 클릭합니다. EXE, `runtime`, `vendor`, 스크립트를 같은 폴더에 둡니다. Windows의 .NET Framework와 Windows PowerShell 5.1을 사용합니다. 시작에 실패하면 `启动应用.cmd`를 실행해 오류를 확인할 수 있습니다.

## 유지보수용 패키징

PowerShell에서 `npm ci --prefix runtime`을 실행하여 고정된 버전의 Wrangler를 설치하고 Windows x64용 `node.exe`와 `NODE-LICENSE`를 `runtime`에 놓습니다. Windows PowerShell 5.1에서 `./打包发布.ps1`을 실행하면 EXE를 컴파일하고 `自建机场-Windows-EXE-v1.3.1.zip`을 생성합니다. 런처만 컴파일하려면 `./构建应用.ps1`을 실행하고 ZIP을 설치 EXE로 만들려면 `./构建安装程序.ps1`을 실행합니다. 런처 소스는 `launcher/Launcher.cs`에 있습니다. 이 명령은 유지보수용입니다. 소스에서 바로 실행하려면 `./app.ps1`을 사용합니다.

## 작동 방식과 범위

1. 패키지에는 버전이 고정된 업스트림 `_worker.js`, GPL-2.0 라이선스, 업스트림 커밋 ID가 포함됩니다. 실행 시 동봉된 파일을 사용하므로 `git clone`을 실행하지 않습니다.
2. Cloudflare 공식 Wrangler CLI로 브라우저 인증을 완료하고 KV를 생성하고 `ADMIN` 시크릿을 설정한 뒤 Pages 프로젝트를 만들고 배포합니다. Cloudflare Pages API로 사용자 지정 도메인을 연결하고 DNSHE API로 CNAME을 추가합니다.
3. 앱에는 관리 화면 주소인 `https://<프로젝트-이름>.pages.dev/admin`이 표시됩니다. 구독 링크는 업스트림 관리 화면에서 생성됩니다.

관리자 비밀번호는 현재 프로세스에서 Cloudflare에 전달되며 프로젝트 파일에는 저장되지 않습니다. 비밀번호와 구독 링크는 공개하지 마세요. Cloudflare 무료 할당량, 플랫폼 규칙, 업스트림 기능은 바뀔 수 있습니다. 현지 법률과 서비스 약관을 준수하세요.

## 출처 및 라이선스

이 프로젝트는 [edgetunnel 업스트림 코드](https://github.com/cmliu/edgetunnel)를 사용하며 배포 과정은 [Cloudflare Pages 문서](https://developers.cloudflare.com/pages/)를 참고합니다. 저장소 자체의 스크립트와 문서는 MIT 라이선스이며, 함께 제공되는 업스트림 코드는 GPL-2.0 라이선스입니다. 자세한 내용은 `vendor/edgetunnel/LICENSE`를 참조하세요. Node.js 라이선스는 `runtime/NODE-LICENSE`에 있으며 Wrangler와 종속 패키지의 라이선스는 npm 패키지에 포함됩니다. 재배포할 때는 해당 소스 코드와 라이선스를 보존해야 합니다.
