using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class Setup
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        bool test = args.Length == 2 && args[0] == "--check-install";
        try
        {
            if (test)
            {
                Install(args[1]);
                return 0;
            }

            using (var picker = new FolderBrowserDialog())
            {
                picker.Description = "请选择安装位置。安装程序将在其中创建「自建机场」文件夹。";
                picker.SelectedPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (picker.ShowDialog() != DialogResult.OK) return 0;
                string destination = Path.Combine(picker.SelectedPath, "自建机场");
                Install(destination);
                Process.Start(Path.Combine(destination, "自建机场.exe"));
            }
            return 0;
        }
        catch (Exception error)
        {
            if (test) Console.Error.WriteLine(error);
            else MessageBox.Show(error.Message, "自建机场安装程序", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static void Install(string destination)
    {
        destination = Path.GetFullPath(destination);
        if (Directory.Exists(destination) || File.Exists(destination))
            throw new IOException("安装目录已存在。请选择其他位置。" + Environment.NewLine + destination);

        string staging = destination + ".installing-" + Guid.NewGuid().ToString("N");
        string zip = staging + ".zip";
        Directory.CreateDirectory(staging);
        try
        {
            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppPayload"))
            using (FileStream file = File.Create(zip))
                payload.CopyTo(file);

            ZipFile.ExtractToDirectory(zip, staging);
            Directory.Move(staging, destination);
        }
        finally
        {
            if (File.Exists(zip)) File.Delete(zip);
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
        }
    }
}
