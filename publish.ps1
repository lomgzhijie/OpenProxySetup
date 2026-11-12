$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
try {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw '请先安装 GitHub CLI。' }
    & gh auth status
    if ($LASTEXITCODE -ne 0) { throw 'GitHub 登录无效。请先运行 gh auth login。' }
    $user = & gh api user --jq .login
    if ($LASTEXITCODE -ne 0 -or -not $user) { throw '无法读取 GitHub 用户名。' }
    Write-Host "即将发布到 https://github.com/$user/zijianjichang"
    if (-not (Test-Path .git)) { & git init -b main; if ($LASTEXITCODE -ne 0) { throw 'git init 失败。' } }
    & git add -- README.md LICENSE .gitignore app.ps1 deploy.ps1 dnshe.ps1 links.ps1 proxy.ps1 publish.ps1 CONTRIBUTING.md SECURITY.md CHANGELOG.md .github runtime/package.json runtime/package-lock.json runtime/NODE-LICENSE 启动应用.cmd Cloudflare授权.cmd 打包发布.ps1 vendor/edgetunnel/_worker.js vendor/edgetunnel/LICENSE vendor/edgetunnel/UPSTREAM_COMMIT
    if ($LASTEXITCODE -ne 0) { throw 'git add 失败。' }
    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) { & git commit -m 'Initial release'; if ($LASTEXITCODE -ne 0) { throw '提交失败。请配置 git user.name 和 user.email。' } }
    & gh repo create 'zijianjichang' --public --source . --remote origin --push --description 'Cloudflare Pages 自建节点部署向导'
    if ($LASTEXITCODE -ne 0) { throw '创建或推送仓库失败。请检查 GitHub 权限及同名仓库。' }
} finally { Pop-Location }
