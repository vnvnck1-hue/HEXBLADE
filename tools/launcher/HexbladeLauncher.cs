// HEXBLADE.exe — 게임(로비)을 고정 Godot 버전으로 실행하는 아이콘 달린 실행기.
// 하는 일은 launchers\dev\run_game.cmd 와 같다: tools\godot.ps1 run [인자...]
// 고정 Godot 이 이미 .tools\godot 에 있으면 창 없이 바로 띄우고, 없으면 설치·다운로드 진행이 보이게 콘솔 창을 연다.
// 다시 빌드: tools\launcher\build_launcher.cmd (Windows 기본 .NET Framework csc 사용)
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows.Forms;

static class HexbladeLauncher
{
    [STAThread]
    static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "tools", "godot.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("tools\\godot.ps1 을 찾을 수 없습니다.\nHEXBLADE.exe 는 프로젝트 폴더 맨 위에 있어야 합니다.", "HEXBLADE", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        bool ready = false;
        try
        {
            string ver = File.ReadAllLines(Path.Combine(root, "godot-version.txt"))[0].Trim();
            ready = File.Exists(Path.Combine(root, ".tools", "godot", "Godot_v" + ver + "_win64.exe"));
            // pull · 브랜치 전환 뒤 첫 실행은 godot.ps1 이 임포트부터 하므로 진행 창을 보여 준다
            ready = ready && ImportedHead(root) == GitHead(root);
        }
        catch (Exception) { ready = false; }

        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        string extra = string.Join(" ", args.Select(a => "\"" + a.Replace("\"", "\\\"") + "\""));
        var psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" run " + extra)
        {
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = ready,
        };
        try { Process.Start(psi); }
        catch (Exception e)
        {
            MessageBox.Show("PowerShell 을 실행하지 못했습니다.\n" + e.Message, "HEXBLADE", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }

    // godot.ps1 이 마지막 임포트 때 적어 둔 커밋 (없으면 null)
    static string ImportedHead(string root)
    {
        string f = Path.Combine(root, ".godot", "hexblade_import_head.txt");
        return File.Exists(f) ? File.ReadAllLines(f)[0].Trim() : null;
    }

    // git 없이 .git 폴더에서 현재 커밋을 읽는다 (못 읽으면 "?" — 임포트가 필요한 것으로 본다)
    static string GitHead(string root)
    {
        string git = Path.Combine(root, ".git");
        string head = File.ReadAllText(Path.Combine(git, "HEAD")).Trim();
        if (!head.StartsWith("ref: ")) return head;
        string name = head.Substring(5).Trim();
        string loose = Path.Combine(git, name.Replace('/', Path.DirectorySeparatorChar));
        if (File.Exists(loose)) return File.ReadAllText(loose).Trim();
        string packed = Path.Combine(git, "packed-refs");
        if (File.Exists(packed))
            foreach (string line in File.ReadAllLines(packed))
                if (line.EndsWith(" " + name)) return line.Split(' ')[0];
        return "?";
    }
}
