const translations = {
  en: {
    navDownload: "Download", docs: "Docs", headline: "Deploy your own\nCloudflare Pages site",
    summary: "Authorize Cloudflare, connect a domain, and deploy your site with the Windows or Android setup wizard.",
    heroDownload: "Download ↓", heroAndroid: "Android APK ↓", step1: "Authorize Cloudflare", step2: "Prepare your domain", step3: "Deploy your site",
    downloads: "Download OpenProxySetup", setup: "Windows installer", setupDesc: "Choose an installation folder, then open the deployment wizard.", setupLink: "Download installer ↓",
    portable: "Portable edition", portableDesc: "Extract the full archive and run OpenProxySetup.exe.", portableLink: "Download portable ZIP ↓",
    cmd: "Classic CMD edition", cmdDesc: "Extract the full archive and run OpenProxySetup.cmd.", cmdLink: "Download CMD edition ↓",
    android: "Android preview", androidDesc: "Requires Android 8.0 or later. Open the downloaded APK to install.", androidLink: "Download Android APK ↓",
    faq: "Frequently asked questions", q1: "Which build should I download first?", a1: "On Windows, use the installer or run the portable edition from a folder. On Android, download the APK.",
    q2: "What do I need before deploying?", a2: "Prepare your Cloudflare account, DNSHE domain, and DNSHE API credentials. The wizard guides you through browser authorization and deployment.",
    releases: "Releases", issues: "Report an issue"
  },
  ja: {
    navDownload: "ダウンロード", docs: "ドキュメント", headline: "自分の Cloudflare Pages\nサイトをデプロイ",
    summary: "Windows または Android のウィザードで、Cloudflare の認証、ドメイン設定、サイトのデプロイを進められます。",
    heroDownload: "ダウンロード ↓", heroAndroid: "Android APK ↓", step1: "Cloudflare を認証", step2: "ドメインを準備", step3: "サイトをデプロイ",
    downloads: "OpenProxySetup のダウンロード", setup: "インストーラー版", setupDesc: "インストール先を選ぶと、デプロイウィザードが開きます。", setupLink: "インストーラーを入手 ↓",
    portable: "ポータブル版", portableDesc: "すべて展開して「OpenProxySetup.exe」を実行します。", portableLink: "ポータブル ZIP を入手 ↓",
    cmd: "クラシック CMD 版", cmdDesc: "すべて展開して「OpenProxySetup.cmd」を実行します。", cmdLink: "CMD 版を入手 ↓",
    android: "Android プレビュー版", androidDesc: "Android 8.0 以降に対応。ダウンロードした APK を開いてインストールします。", androidLink: "Android APK を入手 ↓",
    faq: "よくある質問", q1: "初めて使う場合はどの版を選べばよいですか？", a1: "Windows ではインストーラー版か、フォルダーから直接起動できるポータブル版を選べます。Android では APK をダウンロードしてください。",
    q2: "デプロイ前に何を準備しますか？", a2: "ご自身の Cloudflare アカウント、DNSHE ドメイン、DNSHE API 認証情報を用意します。ブラウザー認証とデプロイはウィザードが案内します。",
    releases: "リリース", issues: "問題を報告"
  },
  ko: {
    navDownload: "다운로드", docs: "문서", headline: "나만의 Cloudflare Pages\n사이트 배포",
    summary: "Windows 또는 Android 배포 마법사에서 Cloudflare 인증, 도메인 설정 및 사이트 배포를 진행할 수 있습니다.",
    heroDownload: "다운로드 ↓", heroAndroid: "Android APK ↓", step1: "Cloudflare 인증", step2: "도메인 준비", step3: "사이트 배포",
    downloads: "OpenProxySetup 다운로드", setup: "설치 버전", setupDesc: "설치 위치를 선택하면 배포 마법사가 열립니다.", setupLink: "설치 프로그램 다운로드 ↓",
    portable: "포터블 버전", portableDesc: "압축을 모두 풀고 OpenProxySetup.exe를 실행합니다.", portableLink: "포터블 ZIP 다운로드 ↓",
    cmd: "클래식 CMD 버전", cmdDesc: "압축을 모두 풀고 OpenProxySetup.cmd를 실행합니다.", cmdLink: "CMD 버전 다운로드 ↓",
    android: "Android 미리보기", androidDesc: "Android 8.0 이상을 지원합니다. 다운로드한 APK를 열어 설치하세요.", androidLink: "Android APK 다운로드 ↓",
    faq: "자주 묻는 질문", q1: "처음에는 어떤 버전을 받으면 되나요?", a1: "Windows에서는 설치 버전이나 폴더에서 바로 실행하는 포터블 버전을 선택하세요. Android에서는 APK를 다운로드하세요.",
    q2: "배포 전에 무엇을 준비해야 하나요?", a2: "본인의 Cloudflare 계정, DNSHE 도메인, DNSHE API 인증 정보를 준비하세요. 마법사가 브라우저 인증과 배포를 안내합니다.",
    releases: "릴리스", issues: "문제 신고"
  }
};

const select = document.querySelector("#language");
const nodes = Array.from(document.querySelectorAll("[data-i]"));
const chinese = new Map(nodes.map(node => [node, node.innerHTML]));
const docsPaths = { "zh-CN": "docs/", en: "docs/en.html", ja: "docs/ja.html", ko: "docs/ko.html" };
const titles = {
  "zh-CN": "OpenProxySetup — Windows 和 Android 部署向导",
  en: "OpenProxySetup — Windows and Android Deployment Wizard",
  ja: "OpenProxySetup — Windows・Android デプロイウィザード",
  ko: "OpenProxySetup — Windows 및 Android 배포 마법사"
};

function changeLanguage(language) {
  const dictionary = translations[language];
  document.documentElement.lang = language;
  document.title = titles[language];
  select.value = language;
  for (const node of nodes) {
    if (dictionary) node.textContent = dictionary[node.dataset.i];
    else node.innerHTML = chinese.get(node);
  }
  for (const link of document.querySelectorAll(".docs")) {
    link.href = docsPaths[language];
  }
}

function readLanguage() {
  const query = new URLSearchParams(window.location.search).get("lang");
  if (Object.hasOwn(titles, query)) return query;
  try {
    const stored = localStorage.getItem("ops-language");
    if (Object.hasOwn(titles, stored)) return stored;
  } catch {}
  return "zh-CN";
}

changeLanguage(readLanguage());
select.addEventListener("change", () => {
  changeLanguage(select.value);
  try { localStorage.setItem("ops-language", select.value); } catch {}
  const url = new URL(window.location.href);
  url.searchParams.set("lang", select.value);
  history.replaceState(null, "", url);
});
