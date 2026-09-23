using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal static class ModScanner
{
    private static readonly StringComparer IgnoreCase = StringComparer.OrdinalIgnoreCase;
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    private static readonly Regex EntryPattern = new Regex(@"^[A-Za-z_][A-Za-z0-9_]*Mod$", RegexOptions.CultureInvariant);

    private sealed class Mod
    {
        public string Directory;
        public string Entry;
        public int[] Versions;
        public bool Discovered;
    }

    private sealed class ScanResult
    {
        public readonly List<Mod> Mods = new List<Mod>();
        public readonly List<string> Warnings = new List<string>();
        public bool Changed;
        public string BackupPath;
        public string ManifestPath;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool noUi = args.Contains("--no-ui");
        bool dryRun = args.Contains("--dry-run");
        string gameRoot = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".."));
        try
        {
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--root" && i + 1 < args.Length)
                    gameRoot = Path.GetFullPath(args[++i]);
                else if (args[i] != "--no-ui" && args[i] != "--dry-run")
                    throw new ArgumentException("未知参数或缺少参数值：" + args[i]);
            }
            ScanResult result = Scan(gameRoot, dryRun);
            string message = Describe(result, dryRun);
            if (noUi) Console.WriteLine(message);
            else MessageBox.Show(message, "Remains 模组检测", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }
        catch (Exception error)
        {
            string message = "模组检测失败，原名单保持不变。\n\n" + error.Message;
            if (noUi) Console.Error.WriteLine(message);
            else MessageBox.Show(message, "Remains 模组检测", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static ScanResult Scan(string gameRoot, bool dryRun)
    {
        string modsRoot = Path.Combine(gameRoot, "mods");
        string scannerRoot = Path.Combine(modsRoot, "ModLoader");
        string catalogPath = Path.Combine(scannerRoot, "supported-mods.txt");
        string manifestPath = Path.Combine(modsRoot, "loader-manifest.txt");
        if (!Directory.Exists(modsRoot)) throw new DirectoryNotFoundException("找不到 mods 目录：" + modsRoot);
        if (!File.Exists(catalogPath)) throw new FileNotFoundException("找不到已核验模组目录", catalogPath);

        ScanResult result = new ScanResult();
        result.ManifestPath = manifestPath;
        List<Mod> known = ReadCatalog(catalogPath);
        Dictionary<string, string> directories = Directory.GetDirectories(modsRoot)
            .ToDictionary(Path.GetFileName, path => path, IgnoreCase);
        HashSet<string> knownEntries = new HashSet<string>(IgnoreCase);
        foreach (Mod mod in known)
        {
            knownEntries.Add(mod.Entry);
            string actualDirectory;
            string file = directories.TryGetValue(mod.Directory, out actualDirectory)
                ? FindFile(Path.Combine(actualDirectory, "release"), mod.Entry + ".swf") : null;
            if (file == null || !LooksLikeSwf(file))
            {
                mod.Versions = new[] { 0, 0, 0 };
                result.Warnings.Add(mod.Directory + "：未找到有效的 " + mod.Entry + ".swf，已跳过");
            }
            result.Mods.Add(mod);
        }

        List<Mod> discovered = new List<Mod>();
        HashSet<string> discoveredEntries = new HashSet<string>(IgnoreCase);
        foreach (KeyValuePair<string, string> directory in directories.OrderBy(pair => pair.Key, IgnoreCase))
        {
            if (!IsSafeDirectory(directory.Key)) continue;
            string release = Path.Combine(directory.Value, "release");
            if (!Directory.Exists(release)) continue;
            foreach (string file in Directory.GetFiles(release, "*.swf", SearchOption.TopDirectoryOnly).OrderBy(Path.GetFileName, IgnoreCase))
            {
                string entry = Path.GetFileNameWithoutExtension(file);
                if (!EntryPattern.IsMatch(entry)) continue;
                if (knownEntries.Contains(entry)) continue;
                if (!LooksLikeSwf(file))
                {
                    result.Warnings.Add(directory.Key + "/" + Path.GetFileName(file) + "：SWF 文件头不合格，已跳过");
                    continue;
                }
                if (!discoveredEntries.Add(entry))
                {
                    result.Warnings.Add(entry + "：入口名与另一个新模组重复，已跳过重复项");
                    continue;
                }
                discovered.Add(new Mod { Directory = directory.Key, Entry = entry,
                    Versions = new[] { 1, 1, 1 }, Discovered = true });
            }
        }
        result.Mods.AddRange(discovered.OrderBy(mod => mod.Directory, IgnoreCase).ThenBy(mod => mod.Entry, IgnoreCase));
        string content = BuildManifest(result.Mods);
        string previous = File.Exists(manifestPath) ? File.ReadAllText(manifestPath, Utf8) : null;
        result.Changed = !String.Equals(previous, content, StringComparison.Ordinal);
        if (result.Changed && !dryRun) WriteManifest(manifestPath, scannerRoot, content, result);
        return result;
    }

    private static List<Mod> ReadCatalog(string path)
    {
        List<Mod> mods = new List<Mod>();
        HashSet<string> entries = new HashSet<string>(IgnoreCase);
        int lineNumber = 0;
        foreach (string raw in File.ReadAllLines(path, Utf8))
        {
            lineNumber++;
            string line = raw.Trim().Trim('\uFEFF');
            if (line.Length == 0 || line.StartsWith("#")) continue;
            string[] columns = line.Split('|').Select(part => part.Trim()).ToArray();
            if (columns.Length != 5 || !IsSafeDirectory(columns[0]) || !EntryPattern.IsMatch(columns[1]) ||
                columns.Skip(2).Any(flag => flag != "0" && flag != "1") || !entries.Add(columns[1]))
                throw new InvalidDataException("已核验模组目录第 " + lineNumber + " 行格式错误或入口重复");
            mods.Add(new Mod { Directory = columns[0], Entry = columns[1],
                Versions = columns.Skip(2).Select(Int32.Parse).ToArray() });
        }
        if (mods.Count == 0) throw new InvalidDataException("已核验模组目录为空");
        return mods;
    }

    private static bool IsSafeDirectory(string name)
    {
        return !String.IsNullOrWhiteSpace(name) && name != "." && !name.Contains("..") &&
            name.IndexOfAny(new[] { '/', '\\', ':', '?', '#', '%' }) < 0;
    }

    private static string FindFile(string directory, string filename)
    {
        if (!Directory.Exists(directory)) return null;
        return Directory.GetFiles(directory, "*.swf", SearchOption.TopDirectoryOnly)
            .FirstOrDefault(file => IgnoreCase.Equals(Path.GetFileName(file), filename));
    }

    private static bool LooksLikeSwf(string path)
    {
        using (FileStream stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            if (stream.Length < 8) return false;
            byte[] header = new byte[8];
            if (stream.Read(header, 0, header.Length) != header.Length) return false;
            bool signature = (header[0] == 'F' || header[0] == 'C' || header[0] == 'Z') &&
                header[1] == 'W' && header[2] == 'S';
            uint expandedLength = BitConverter.ToUInt32(header, 4);
            return signature && expandedLength >= 8;
        }
    }

    private static string BuildManifest(List<Mod> mods)
    {
        StringBuilder text = new StringBuilder();
        text.Append("# Remains 模组加载名单，由 ModLoaderScanner 自动生成。\r\n");
        text.Append("# 来源：mods/ModLoader/supported-mods.txt + 各模组顶层 release/*.swf。\r\n");
        text.Append("# 格式：目录名|入口类名|1.02|1.03|1.04；1=加载，0=跳过。\r\n");
        text.Append("# 新发现的模组默认三个版本都启用；实际兼容性仍需运行验证。\r\n");
        text.Append("# 修改名单或模组包后，请重新运行扫描器，再重启游戏。\r\n");
        foreach (Mod mod in mods)
            text.Append(mod.Directory).Append('|').Append(mod.Entry).Append('|')
                .Append(mod.Versions[0]).Append('|').Append(mod.Versions[1]).Append('|')
                .Append(mod.Versions[2]).Append("\r\n");
        return text.ToString();
    }

    private static void WriteManifest(string manifestPath, string scannerRoot, string content, ScanResult result)
    {
        string temporary = manifestPath + ".new-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temporary, content, Utf8);
        try
        {
            if (File.Exists(manifestPath))
            {
                string backupDirectory = Path.Combine(scannerRoot, "work", "manifest-backups");
                Directory.CreateDirectory(backupDirectory);
                string backup = Path.Combine(backupDirectory,
                    "loader-manifest-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" +
                    Guid.NewGuid().ToString("N").Substring(0, 6) + ".txt");
                File.Replace(temporary, manifestPath, backup);
                result.BackupPath = backup;
            }
            else File.Move(temporary, manifestPath);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private static string Describe(ScanResult result, bool dryRun)
    {
        int[] counts = new int[3];
        foreach (Mod mod in result.Mods)
            for (int i = 0; i < 3; i++) counts[i] += mod.Versions[i];
        int found = result.Mods.Count(mod => mod.Versions.Any(flag => flag == 1));
        int newlyFound = result.Mods.Count(mod => mod.Discovered);
        StringBuilder text = new StringBuilder();
        text.AppendLine(dryRun ? "检测预览完成，尚未写入名单。" :
            result.Changed ? "模组名单已更新。" : "模组名单已经是最新的。");
        text.AppendLine();
        text.AppendLine("找到 " + found + " 个通过目录与文件头检查的模组包，其中 " + newlyFound + " 个是新发现的。");
        text.AppendLine("1.02：" + counts[0] + " 个    1.03：" + counts[1] + " 个    1.04：" + counts[2] + " 个");
        if (newlyFound > 0)
        {
            text.AppendLine();
            text.AppendLine("新模组（三个版本均启用）：");
            foreach (Mod mod in result.Mods.Where(mod => mod.Discovered))
                text.AppendLine("  " + mod.Directory + "/" + mod.Entry + ".swf");
        }
        if (result.Warnings.Count > 0)
        {
            text.AppendLine();
            text.AppendLine("跳过或需注意：");
            foreach (string warning in result.Warnings) text.AppendLine("  " + warning);
        }
        text.AppendLine();
        text.AppendLine("名单：" + result.ManifestPath);
        if (result.BackupPath != null) text.AppendLine("旧名单备份：" + result.BackupPath);
        text.Append(dryRun ? "这只是预览；正式运行扫描器后，再手动启动游戏。" :
            "现在可以手动启动游戏；已打开的游戏需重启。");
        return text.ToString();
    }
}
