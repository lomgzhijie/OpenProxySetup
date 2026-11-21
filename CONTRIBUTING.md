# 参与贡献

提交前请在 Windows PowerShell 5.1 中验证改动。修改界面时，从「启动应用.cmd」进入对应页面，检查正常流程和失败提示。涉及部署的改动请用独立测试资源验证，并在 PR 中说明验证范围。

提交问题或日志前请移除 API 密钥、后台密码、订阅链接和账号标识。安全问题请按 [安全政策](SECURITY.md) 私下报告。

## 构建 Android APK

`android/build.ps1` 支持 Windows PowerShell 和 Linux PowerShell。使用 JDK 17、Android 35 SDK 和 Build Tools 35，传入 `-Jdk`、`-BuildTools`、`-AndroidJar` 和 `-OutputApk`。

- **测试构建**使用 `-TestBuild`。默认生成临时测试密钥。如果要给应用和测试 APK 使用同一个测试签名，传入专用的 `-SigningKey` 路径。CI 使用合成 OAuth Client ID 和模拟响应。
- **正式构建**传入现有发布密钥的 `-SigningKey` 路径，在当前终端进程中设置 `OPS_ANDROID_SIGNING_PASSWORD`。签名证书须与现有发行版一致。发布前核对签名和官网下载关联文件，并妥善保管离线备份及解密口令。
