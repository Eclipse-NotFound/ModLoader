using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

internal static class ModScanner
{
    private static readonly StringComparer IgnoreCase = StringComparer.OrdinalIgnoreCase;
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    private static readonly Regex EntryPattern = new Regex(@"^[A-Za-z_][A-Za-z0-9_]*Mod$", RegexOptions.CultureInvariant);

    internal sealed class Mod
    {
        public string Directory;
        public string Entry;
        public int[] Versions;
        public bool Discovered;
        public bool Installed;
        public int[] Supported;
    }

    internal sealed class ScanResult
    {
        public readonly List<Mod> Mods = new List<Mod>();
        public readonly List<string> Warnings = new List<string>();
        public bool Changed;
        public string BackupPath;
        public string ManifestPath;
        public string GameRoot;
        public string Previous;
        public string Catalog;
        public readonly Dictionary<string, Mod> Choices = new Dictionary<string, Mod>(IgnoreCase);
        public readonly Dictionary<string, Mod> PreviousRows = new Dictionary<string, Mod>(IgnoreCase);
    }

    [STAThread]
    private static int Main(string[] args)
    {
        PrepareConsole();
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

    internal static void PrepareConsole()
    {
        // winexe has no console code page. Write UTF-8 directly to redirected handles.
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), Utf8) { AutoFlush = true });
        Console.SetError(new StreamWriter(Console.OpenStandardError(), Utf8) { AutoFlush = true });
    }

    internal static ScanResult Scan(string gameRoot, bool dryRun)
    {
        string modsRoot = Path.Combine(gameRoot, "mods");
        string scannerRoot = Path.Combine(modsRoot, "ModLoader");
        string catalogPath = Path.Combine(scannerRoot, "supported-mods.txt");
        string manifestPath = Path.Combine(modsRoot, "loader-manifest.txt");
        if (!Directory.Exists(modsRoot)) throw new DirectoryNotFoundException("找不到 mods 目录：" + modsRoot);
        if (!File.Exists(catalogPath)) throw new FileNotFoundException("找不到已核验模组目录", catalogPath);

        ScanResult result = new ScanResult();
        result.ManifestPath = manifestPath;
        result.GameRoot = gameRoot;
        result.Previous = File.Exists(manifestPath) ? File.ReadAllText(manifestPath, Utf8) : null;
        result.Catalog = File.ReadAllText(catalogPath, Utf8);
        ReadPrevious(result);
        List<Mod> known = ReadCatalog(catalogPath);
        Dictionary<string, string> directories = Directory.GetDirectories(modsRoot)
            .ToDictionary(Path.GetFileName, path => path, IgnoreCase);
        HashSet<string> knownEntries = new HashSet<string>(IgnoreCase);
        foreach (Mod mod in known)
        {
            mod.Supported = (int[])mod.Versions.Clone();
            knownEntries.Add(mod.Entry);
            string actualDirectory;
            string file = directories.TryGetValue(mod.Directory, out actualDirectory)
                ? FindFile(Path.Combine(actualDirectory, "release"), mod.Entry + ".swf") : null;
            mod.Installed = file != null && LooksLikeSwf(file);
            if (!mod.Installed)
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
                    Versions = new[] { 1, 1, 1 }, Supported = new[] { 1, 1, 1 }, Installed = true, Discovered = true });
            }
        }
        result.Mods.AddRange(discovered.OrderBy(mod => mod.Directory, IgnoreCase).ThenBy(mod => mod.Entry, IgnoreCase));
        ApplyChoices(result);
        string content = BuildManifest(result);
        result.Changed = !String.Equals(result.Previous, content, StringComparison.Ordinal);
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

    // Explicit choices live in comments in the SAME atomic manifest as effective flags.
    // Missing packages and compatibility masks must not erase the user's intention.
    private static void ReadPrevious(ScanResult result)
    {
        if (result.Previous == null) return;
        foreach (string raw in result.Previous.Split('\n'))
        {
            string line = raw.Trim().Trim('\uFEFF');
            bool choice = line.StartsWith("# selection|", StringComparison.Ordinal);
            if (choice) line = line.Substring(12);
            else if (line.Length == 0 || line.StartsWith("#")) continue;
            string[] parts = line.Split('|').Select(part => part.Trim()).ToArray();
            if (parts.Length != 5 || !IsSafeDirectory(parts[0]) || !EntryPattern.IsMatch(parts[1]) ||
                parts.Skip(2).Any(flag => flag != "0" && flag != "1"))
                throw new InvalidDataException("现有名单格式错误，请检查或恢复备份：" + result.ManifestPath);
            Dictionary<string, Mod> target = choice ? result.Choices : result.PreviousRows;
            if (target.ContainsKey(parts[1])) throw new InvalidDataException("现有名单入口重复：" + parts[1]);
            target.Add(parts[1], new Mod { Directory = parts[0], Entry = parts[1], Versions = parts.Skip(2).Select(Int32.Parse).ToArray() });
        }
    }

    internal static void ImportCurrentSelection(ScanResult result)
    {
        foreach (Mod mod in result.Mods.Where(mod => mod.Installed))
        {
            Mod previous;
            if (!result.Choices.ContainsKey(mod.Entry) && result.PreviousRows.TryGetValue(mod.Entry, out previous) &&
                IgnoreCase.Equals(previous.Directory, mod.Directory))
                result.Choices.Add(mod.Entry, previous);
        }
        ApplyChoices(result);
    }

    internal static void ApplyChoices(ScanResult result)
    {
        foreach (Mod mod in result.Mods)
        {
            Mod choice;
            bool hasChoice = result.Choices.TryGetValue(mod.Entry, out choice) && IgnoreCase.Equals(choice.Directory, mod.Directory);
            for (int i = 0; i < 3; i++)
                mod.Versions[i] = mod.Installed && mod.Supported[i] == 1 && (!hasChoice || choice.Versions[i] == 1) ? 1 : 0;
        }
    }

    internal static void SetChoice(ScanResult result, Mod mod, int version, bool enabled)
    {
        Mod choice;
        if (!result.Choices.TryGetValue(mod.Entry, out choice) || !IgnoreCase.Equals(choice.Directory, mod.Directory))
        {
            choice = new Mod { Directory = mod.Directory, Entry = mod.Entry, Versions = (int[])mod.Versions.Clone() };
            result.Choices[mod.Entry] = choice;
        }
        choice.Versions[version] = enabled ? 1 : 0;
        ApplyChoices(result);
    }

    internal static void SaveSelection(ScanResult result)
    {
        ScanResult fresh = Scan(result.GameRoot, true);
        if (fresh.Previous != result.Previous || fresh.Catalog != result.Catalog ||
            !fresh.Mods.Select(Identity).SequenceEqual(result.Mods.Select(Identity)))
            throw new IOException("名单或已安装模组在窗口打开后发生变化，请重新扫描后再保存。");
        string content = BuildManifest(result);
        result.Changed = content != result.Previous;
        if (result.Changed)
            WriteManifest(result.ManifestPath, Path.Combine(result.GameRoot, "mods", "ModLoader"), content, result);
        result.Previous = content;
    }

    private static string Identity(Mod mod)
    {
        return mod.Directory + "|" + mod.Entry + "|" + mod.Installed + "|" + String.Join(",", mod.Supported);
    }

    private static string BuildManifest(ScanResult result)
    {
        StringBuilder text = new StringBuilder();
        text.Append("# Remains 模组加载名单，由 ModLoaderScanner 自动生成。\r\n");
        text.Append("# 来源：mods/ModLoader/supported-mods.txt + 各模组顶层 release/*.swf。\r\n");
        text.Append("# 格式：目录名|入口类名|1.02|1.03|1.04；1=加载，0=跳过。\r\n");
        text.Append("# 新发现的模组默认三个版本都启用；实际兼容性仍需运行验证。\r\n");
        text.Append("# 使用 RemainsModLauncher 选择模组；重新扫描保留选择，重启游戏后生效。\r\n");
        foreach (Mod choice in result.Choices.Values.OrderBy(mod => mod.Entry, IgnoreCase))
            text.Append("# selection|").Append(choice.Directory).Append('|').Append(choice.Entry).Append('|')
                .Append(String.Join("|", choice.Versions)).Append("\r\n");
        foreach (Mod mod in result.Mods)
            text.Append(mod.Directory).Append('|').Append(mod.Entry).Append('|')
                .Append(mod.Versions[0]).Append('|').Append(mod.Versions[1]).Append('|')
                .Append(mod.Versions[2]).Append("\r\n");
        return text.ToString();
    }

    private static void WriteManifest(string manifestPath, string scannerRoot, string content, ScanResult result)
    {
        string key;
        using (SHA256 hash = SHA256.Create())
            key = BitConverter.ToString(hash.ComputeHash(Utf8.GetBytes(Path.GetFullPath(manifestPath).ToUpperInvariant()))).Replace("-", "");
        using (Mutex mutex = new Mutex(false, "Local\\RemainsModManifest-" + key))
        {
            bool locked;
            try { locked = mutex.WaitOne(0); } catch (AbandonedMutexException) { locked = true; }
            if (!locked) throw new IOException("另一个模组工具正在保存名单，请稍后重新扫描。");
            try { WriteManifestLocked(manifestPath, scannerRoot, content, result); }
            finally { mutex.ReleaseMutex(); }
        }
    }

    private static void WriteManifestLocked(string manifestPath, string scannerRoot, string content, ScanResult result)
    {
        string temporary = manifestPath + ".new-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temporary, content, Utf8);
        try
        {
            string current = File.Exists(manifestPath) ? File.ReadAllText(manifestPath, Utf8) : null;
            if (current != result.Previous) throw new IOException("名单已由另一个程序修改，请重新扫描。");
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
        int found = result.Mods.Count(mod => mod.Installed);
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
            text.AppendLine("自动发现的模组（保留已有选择；首次发现默认三个版本启用）：");
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
