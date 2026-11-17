using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("自建机场")]
[assembly: AssemblyProduct("自建机场")]
[assembly: AssemblyDescription("Windows 部署向导")]
[assembly: AssemblyVersion("1.3.2.0")]
[assembly: AssemblyFileVersion("1.3.2.0")]

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool checkOnly = args.Length == 1 && args[0] == "--check";
        Application.EnableVisualStyles();
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string[] required = {
            "app.ps1", "deploy.ps1", "proxy.ps1", "dnshe.ps1", "links.ps1",
            "Cloudflare授权.cmd", "runtime/node.exe",
            "runtime/node_modules/wrangler/bin/wrangler.js",
            "vendor/edgetunnel/_worker.js"
        };
        try
        {
            foreach (string relative in required)
            {
                if (!File.Exists(Path.Combine(root, relative)))
                    throw new FileNotFoundException("缺少运行文件：" + relative +
                        "\n请完整解压下载包后，再运行「OpenProxySetup.exe」。");
            }
            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell))
                throw new FileNotFoundException("找不到 Windows PowerShell，请检查 Windows 系统组件。");
            if (checkOnly) return 0;

            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = powershell;
            start.Arguments = "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
                Path.Combine(root, "app.ps1") + "\"";
            start.WorkingDirectory = root;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            using (Process child = Process.Start(start))
            {
                child.WaitForExit();
                if (child.ExitCode != 0)
                    throw new InvalidOperationException(
                        "应用启动或运行失败（退出码 " + child.ExitCode +
                        "）。\n请运行下载包内的「启动应用.cmd」查看具体错误。");
            }
            return 0;
        }
        catch (Exception error)
        {
            if (!checkOnly)
                MessageBox.Show(error.Message, "自建机场", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
