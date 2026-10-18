using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Xml;

internal static class ModLauncher
{
    internal static readonly string[] Versions = { "1.02", "1.03", "1.04" };
    internal static readonly string[] Descriptors = { "application.xml", "app.xml", "app104.xml" };
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);

    [STAThread]
    private static int Main(string[] args)
    {
        ModScanner.PrepareConsole();
        bool headless = args.Length > 0 && args.Any(arg => arg != "--root");
        try
        {
            string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".."));
            string descriptor = "application.xml", action = null, names = null, report = null;
            int version = -1;
            bool launch = false, dry = false, json = false, noUi = false, list = false, descriptorProvided = false;
            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i];
                if (arg == "--help")
                {
                    Console.WriteLine("RemainsModLauncher [--root <game>] [--version 1.02|1.03|1.04] [--descriptor <relative.xml>]\n" +
                        "  --list [--json]                    Read-only installed-mod list\n" +
                        "  --enable|--disable|--only <EntryMod,OtherMod>\n" +
                        "  --all | --none                     Select for ONE version\n" +
                        "  --dry-run                          Preview without saving or launching\n" +
                        "  --launch                           Save and launch (requires game closed)\n" +
                        "  --report <file.json>               Export selection and SWF hashes\n" +
                        "  --no-ui                            Never open dialogs; errors exit 1\n" +
                        "No action opens the graphical launcher. --only is exact, including ModLoaderMod if needed.");
                    return 0;
                }
                if (arg == "--root" || arg == "--version" || arg == "--descriptor" || arg == "--report" ||
                    arg == "--enable" || arg == "--disable" || arg == "--only")
                {
                    if (++i == args.Length || args[i].StartsWith("--")) throw new ArgumentException("参数缺少值：" + arg);
                    if (arg == "--root") root = Path.GetFullPath(args[i]);
                    else if (arg == "--descriptor") { descriptor = args[i]; descriptorProvided = true; }
                    else if (arg == "--report") report = Path.GetFullPath(args[i]);
                    else if (arg == "--version")
                    {
                        version = Array.IndexOf(Versions, args[i]);
                        if (version < 0) throw new ArgumentException("版本必须是 1.02、1.03 或 1.04。");
                    }
                    else
                    {
                        if (action != null) throw new ArgumentException("一次只能使用一种选择操作。");
                        action = arg; names = args[i];
                    }
                }
                else if (arg == "--all" || arg == "--none")
                {
                    if (action != null) throw new ArgumentException("一次只能使用一种选择操作。");
                    action = arg;
                }
                else if (arg == "--launch") launch = true;
                else if (arg == "--dry-run") dry = true;
                else if (arg == "--json") json = true;
                else if (arg == "--no-ui") noUi = true;
                else if (arg == "--list") list = true;
                else throw new ArgumentException("未知参数：" + arg);
            }
            headless = noUi || list || json || action != null || launch || dry || report != null;
            if (report != null) ValidateReportPath(report);
            if (version >= 0 && !descriptorProvided) descriptor = Descriptors[version];
            if (version < 0) version = DescriptorVersion(root, descriptor, false);
            if (!headless)
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new LauncherForm(root, version, descriptor));
                return 0;
            }
            ModScanner.ScanResult scan = Open(root);
            if (action != null) Select(scan, version, action, names);
            if (launch) ValidateLaunch(root, version, descriptor);
            string launchReport = null;
            if (!dry && (action != null || launch)) ModScanner.SaveSelection(scan);
            if (!dry && launch) launchReport = StartGame(scan, version, descriptor);
            object snapshot = Snapshot(scan, version, descriptor, false);
            if (report != null) WriteReport(report, scan, version, descriptor);
            if (json) Console.WriteLine(new JavaScriptSerializer().Serialize(snapshot));
            else
            {
                Console.WriteLine((dry ? "预览（未保存、未启动）" : action != null || launch ? "选择已保存" : "只读扫描") + " · " + Versions[version]);
                foreach (ModScanner.Mod mod in scan.Mods)
                    Console.WriteLine((mod.Versions[version] == 1 ? "[x] " : "[ ] ") + mod.Entry + "  " + Status(mod, version));
                if (launchReport != null) Console.WriteLine("已请求启动；本次配置：" + launchReport);
            }
            return 0;
        }
        catch (Exception error)
        {
            if (headless) Console.Error.WriteLine(error.Message);
            else MessageBox.Show(error.Message, "Remains 模组启动器", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    internal static ModScanner.ScanResult Open(string root)
    {
        ModScanner.ScanResult scan = ModScanner.Scan(root, true);
        ModScanner.ImportCurrentSelection(scan);
        return scan;
    }

    internal static void Select(ModScanner.ScanResult scan, int version, string action, string names)
    {
        List<ModScanner.Mod> targets = new List<ModScanner.Mod>();
        if (names != null)
        {
            foreach (string name in names.Split(',').Select(item => item.Trim()))
            {
                ModScanner.Mod mod = scan.Mods.FirstOrDefault(item => item.Entry.Equals(name, StringComparison.OrdinalIgnoreCase));
                if (mod == null) throw new ArgumentException("未找到入口：" + name + "。请用 --list 查看入口名。");
                if (action != "--disable" && (!mod.Installed || mod.Supported[version] == 0))
                    throw new ArgumentException(name + "：" + Status(mod, version));
                targets.Add(mod);
            }
        }
        if (action == "--all" || action == "--none" || action == "--only")
            foreach (ModScanner.Mod mod in scan.Mods)
                if (mod.Installed) ModScanner.SetChoice(scan, mod, version, action == "--all" && mod.Supported[version] == 1);
        foreach (ModScanner.Mod mod in targets) ModScanner.SetChoice(scan, mod, version, action != "--disable");
    }

    internal static string Status(ModScanner.Mod mod, int version)
    {
        if (!mod.Installed) return "未安装或文件损坏";
        if (mod.Supported.All(flag => flag == 0)) return "已停用的旧组件";
        if (mod.Supported[version] == 0) return "不支持 " + Versions[version];
        if (mod.Discovered) return "新发现 · 兼容性未核验";
        return mod.Versions[version] == 1 ? "将加载" : "已停用";
    }

    private static string LocalPath(string root, string relative)
    {
        if (Path.IsPathRooted(relative)) throw new ArgumentException("描述符或游戏文件必须使用游戏目录内的相对路径。");
        string path = Path.GetFullPath(Path.Combine(root, relative));
        if (!path.StartsWith(Path.GetFullPath(root).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("路径不能离开游戏目录。");
        return path;
    }

    internal static int DescriptorVersion(string root, string descriptor, bool requireContent)
    {
        string path = LocalPath(root, descriptor);
        XmlReaderSettings settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
        XmlDocument document = new XmlDocument { XmlResolver = null };
        using (XmlReader reader = XmlReader.Create(path, settings)) document.Load(reader);
        XmlNode node = document.SelectSingleNode("/*[local-name()='application']/*[local-name()='initialWindow']/*[local-name()='content']");
        if (node == null) throw new InvalidDataException("启动描述符缺少游戏文件位置。");
        string content = node.InnerText.Trim().Replace('\\', '/');
        string[] known = { "pfe.swf", "DLC/pfe.swf", "DLC/pfeUI.swf" };
        int version = Array.FindIndex(known, item => item.Equals(content, StringComparison.OrdinalIgnoreCase));
        if (version < 0) throw new InvalidDataException("无法识别描述符指向的游戏版本：" + content);
        if (requireContent && !File.Exists(LocalPath(root, content))) throw new FileNotFoundException("找不到游戏文件：" + content);
        return version;
    }

    internal static void ValidateLaunch(string root, int version, string descriptor)
    {
        if (DescriptorVersion(root, descriptor, true) != version)
            throw new InvalidDataException("描述符指向的游戏版本与所选版本不符。");
        if (!File.Exists(Path.Combine(root, "adl64.exe")) || !Directory.Exists(Path.Combine(root, "runtimes", "air", "win64")))
            throw new FileNotFoundException("找不到游戏自带的 adl64.exe 或 AIR 运行时，请把启动器放在 mods/ModLoader 下。");
        foreach (Process process in Process.GetProcessesByName("adl64"))
        {
            using (process)
            {
                string executable;
                try { executable = process.MainModule.FileName; }
                catch (InvalidOperationException) { continue; }
                catch (System.ComponentModel.Win32Exception)
                { throw new IOException("无法检查正在运行的 AIR 游戏，请先关闭游戏再启动。"); }
                if (String.Equals(executable, Path.Combine(root, "adl64.exe"), StringComparison.OrdinalIgnoreCase))
                    throw new IOException("这个目录的游戏已经在运行。请保存并退出游戏，再点“保存并启动”。");
            }
        }
    }

    internal static string StartGame(ModScanner.ScanResult scan, int version, string descriptor)
    {
        // ShellExecute starts this exact EXE without a command interpreter and without
        // inheriting a CLI caller's redirected stdout pipe (which would keep it open).
        string history = Path.Combine(scan.GameRoot, "mods", "ModLoader", "work", "launch-history");
        Directory.CreateDirectory(history);
        string report = Path.Combine(history, DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6) + ".json");
        WriteReport(report, scan, version, descriptor);
        ProcessStartInfo info = new ProcessStartInfo(Path.Combine(scan.GameRoot, "adl64.exe"),
            "-runtime \"" + Path.Combine(scan.GameRoot, "runtimes", "air", "win64") + "\" \"" + LocalPath(scan.GameRoot, descriptor) + "\"")
            { WorkingDirectory = scan.GameRoot, UseShellExecute = true };
        using (Process process = Process.Start(info))
        {
            if (process == null) throw new IOException("选择已保存，但游戏进程未启动。");
            if (process.WaitForExit(1200)) throw new IOException("选择已保存，但游戏提前退出（代码 " + process.ExitCode + "）。配置记录：" + report);
        }
        return report;
    }

    internal static object Snapshot(ModScanner.ScanResult scan, int version, string descriptor, bool hashes)
    {
        return new {
            formatVersion = 1, launcherVersion = "1.0.0", gameRoot = scan.GameRoot,
            gameVersion = Versions[version], descriptor = descriptor, manifest = scan.ManifestPath,
            selected = scan.Mods.Where(mod => mod.Versions[version] == 1).Select(mod => mod.Entry).ToArray(),
            mods = scan.Mods.Select(mod => new {
                directory = mod.Directory, entry = mod.Entry, installed = mod.Installed,
                enabled = mod.Versions[version] == 1, versions = mod.Versions, supported = mod.Supported,
                discovered = mod.Discovered, status = Status(mod, version),
                sha256 = hashes && mod.Installed ? Hash(Path.Combine(scan.GameRoot, "mods", mod.Directory, "release", mod.Entry + ".swf")) : null
            }).ToArray(), warnings = scan.Warnings.ToArray()
        };
    }

    private static string Hash(string path)
    {
        using (SHA256 algorithm = SHA256.Create())
        using (FileStream file = File.OpenRead(path))
            return BitConverter.ToString(algorithm.ComputeHash(file)).Replace("-", "");
    }

    internal static void WriteReport(string path, ModScanner.ScanResult scan, int version, string descriptor)
    {
        // Export cannot overwrite game files or the manifest by mistake.
        ValidateReportPath(path);
        string content = new JavaScriptSerializer().Serialize(new {
            capturedAt = DateTimeOffset.Now.ToString("o"), evidence = "selection-only; not proof of runtime load success",
            configuration = Snapshot(scan, version, descriptor, true)
        });
        using (FileStream file = new FileStream(path, FileMode.CreateNew, FileAccess.Write))
        using (StreamWriter writer = new StreamWriter(file, Utf8)) writer.Write(content);
    }

    private static void ValidateReportPath(string path)
    {
        if (!path.EndsWith(".json", StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("诊断文件请使用 .json 后缀。");
        if (File.Exists(path)) throw new IOException("诊断文件已存在，请选择新文件名。");
        if (!Directory.Exists(Path.GetDirectoryName(Path.GetFullPath(path)))) throw new DirectoryNotFoundException("诊断文件的目标目录不存在。");
    }
}

internal sealed class LauncherForm : Form
{
    private readonly string root;
    private string descriptor;
    private ModScanner.ScanResult scan;
    private bool binding;
    private bool dirty;
    internal readonly DataGridView Grid = new DataGridView();
    internal readonly ComboBox Version = new ComboBox();
    internal readonly Button All = MakeButton("全部启用", "All");
    internal readonly Button None = MakeButton("全部停用", "None");
    internal readonly Button Only = MakeButton("仅启用选中项", "Only");
    internal readonly Button Rescan = MakeButton("重新扫描", "Rescan");
    internal readonly Button Save = MakeButton("保存选择", "Save");
    internal readonly Button Launch = MakeButton("保存并启动", "Launch");
    internal bool TestWindow { get; set; }
    protected override bool ShowWithoutActivation { get { return TestWindow; } }
    private readonly Label summary = new Label();
    private readonly Label details = new Label();
    private readonly Label feedback = new Label();

    internal LauncherForm(string root, int version, string descriptor)
    {
        SuspendLayout();
        this.root = root; this.descriptor = descriptor;
        Text = "Remains · 模组启动器";
        Name = "RemainsModLauncher";
        Font = new Font("Microsoft YaHei UI", 10F);
        AutoScaleDimensions = new SizeF(96F, 96F); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(980, 710); MinimumSize = new Size(850, 680);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(245, 247, 249);
        TableLayoutPanel layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 8 };
        foreach (int height in new[] { 48, 36, 48, 38 }) layout.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        Controls.Add(layout);
        layout.Controls.Add(new Label { Text = "选择模组，开始游戏", Dock = DockStyle.Fill, Font = new Font(Font.FontFamily, 22F, FontStyle.Bold) }, 0, 0);
        layout.Controls.Add(new Label { Text = "勾选本次要加载的内容。扫描会保留选择，已运行的游戏需退出后再启动。", Dock = DockStyle.Fill, ForeColor = Color.FromArgb(74, 85, 99) }, 0, 1);
        FlowLayoutPanel toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
        toolbar.Controls.Add(new Label { Text = "游戏版本", AutoSize = true, Margin = new Padding(0, 9, 10, 0) });
        Version.Name = "Version"; Version.DropDownStyle = ComboBoxStyle.DropDownList; Version.Width = 170;
        Version.Items.AddRange(new object[] { "1.02 · 日常游玩", "1.03 · DLC", "1.04 · DLC UI" });
        Version.SelectedIndex = version;
        toolbar.Controls.Add(Version);
        toolbar.Controls.Add(Rescan);
        toolbar.Controls.Add(All); toolbar.Controls.Add(None); toolbar.Controls.Add(Only);
        layout.Controls.Add(toolbar, 0, 2);
        summary.Dock = DockStyle.Fill; summary.ForeColor = Color.FromArgb(40, 65, 78);
        summary.Click += delegate { if (scan != null && scan.Warnings.Count > 0) MessageBox.Show(this, String.Join("\n", scan.Warnings), "扫描提示", MessageBoxButtons.OK, MessageBoxIcon.Information); };
        layout.Controls.Add(summary, 0, 3);
        Grid.Name = "Mods"; Grid.Dock = DockStyle.Fill; Grid.BackgroundColor = Color.White;
        Grid.BorderStyle = BorderStyle.None; Grid.RowHeadersVisible = false;
        Grid.AllowUserToAddRows = false; Grid.AllowUserToDeleteRows = false; Grid.AllowUserToResizeRows = false;
        Grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect; Grid.MultiSelect = true;
        Grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        Grid.ColumnHeadersHeight = 38; Grid.RowTemplate.Height = 34;
        Grid.EnableHeadersVisualStyles = false; Grid.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(226, 234, 237);
        Grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(222, 239, 236);
        Grid.DefaultCellStyle.SelectionForeColor = Color.FromArgb(22, 55, 54);
        Grid.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(249, 250, 251);
        Grid.GridColor = Color.FromArgb(230, 234, 238);
        Grid.Columns.Add(new DataGridViewCheckBoxColumn { Name = "Enabled", HeaderText = "加载", FillWeight = 12 });
        Grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Mod", HeaderText = "模组", FillWeight = 54, ReadOnly = true });
        Grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "State", HeaderText = "状态", FillWeight = 43, ReadOnly = true });
        Grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Entry", HeaderText = "入口名（排障用）", FillWeight = 63, ReadOnly = true });
        foreach (DataGridViewColumn column in Grid.Columns) column.SortMode = DataGridViewColumnSortMode.NotSortable;
        layout.Controls.Add(Grid, 0, 4);
        details.Dock = DockStyle.Fill; details.Padding = new Padding(0, 10, 0, 0); details.ForeColor = Color.FromArgb(74, 85, 99);
        layout.Controls.Add(details, 0, 5);
        feedback.Dock = DockStyle.Fill; feedback.ForeColor = Color.FromArgb(30, 98, 91);
        layout.Controls.Add(feedback, 0, 6);
        FlowLayoutPanel bottom = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, WrapContents = false };
        Launch.Width = 160; Launch.BackColor = Color.FromArgb(26, 103, 91); Launch.ForeColor = Color.White; Launch.FlatStyle = FlatStyle.Flat;
        bottom.Controls.Add(Launch); bottom.Controls.Add(Save);
        Button export = MakeButton("导出排障记录", "Export"); export.Width = 140; bottom.Controls.Add(export);
        layout.Controls.Add(bottom, 0, 7);
        AcceptButton = Launch;
        Grid.CurrentCellDirtyStateChanged += delegate { if (Grid.IsCurrentCellDirty) Grid.CommitEdit(DataGridViewDataErrorContexts.Commit); };
        Grid.CellValueChanged += delegate(object sender, DataGridViewCellEventArgs e) {
            if (binding || e.RowIndex < 0 || e.ColumnIndex != 0) return;
            ModScanner.Mod mod = (ModScanner.Mod)Grid.Rows[e.RowIndex].Tag;
            if (!mod.Installed || mod.Supported[Version.SelectedIndex] == 0) return;
            ModScanner.SetChoice(scan, mod, Version.SelectedIndex, Convert.ToBoolean(Grid.Rows[e.RowIndex].Cells[0].Value));
            dirty = true; RefreshStatus();
        };
        Grid.SelectionChanged += delegate { ShowDetails(); };
        Version.SelectedIndexChanged += delegate { this.descriptor = ModLauncher.Descriptors[Version.SelectedIndex]; Bind(); };
        All.Click += delegate { ChangeSelection("--all"); };
        None.Click += delegate { ChangeSelection("--none"); };
        Only.Click += delegate { ChangeSelection("--only"); };
        Rescan.Click += delegate { Try(delegate { Reload(true); }); };
        Save.Click += delegate { Try(delegate { SaveNow(); }); };
        Launch.Click += delegate { Try(delegate {
            ModLauncher.ValidateLaunch(root, Version.SelectedIndex, this.descriptor);
            SaveNow();
            string report = ModLauncher.StartGame(scan, Version.SelectedIndex, this.descriptor);
            feedback.Text = "已请求启动游戏。本次配置已记录到 work/launch-history。";
            feedback.Tag = report;
        }); };
        export.Click += delegate { Try(delegate {
            using (SaveFileDialog dialog = new SaveFileDialog { Filter = "排障记录 (*.json)|*.json", FileName = "Remains-mods-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".json", OverwritePrompt = false })
                if (dialog.ShowDialog(this) == DialogResult.OK) {
                    ModLauncher.WriteReport(dialog.FileName, scan, Version.SelectedIndex, this.descriptor);
                    feedback.Text = "已导出当前选择与模组指纹（尚未保存的选择也包含在内）。";
                }
        }); };
        FormClosing += delegate(object sender, FormClosingEventArgs e) {
            if (dirty && MessageBox.Show(this, "选择还未保存，直接关闭并放弃修改？", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) e.Cancel = true;
        };
        Reload(false);
        ResumeLayout(true);
        Shown += delegate { ShowDetails(); };
    }

    private static Button MakeButton(string text, string name)
    {
        return new Button { Text = text, Name = name, Width = text.Length > 5 ? 145 : 105, Height = 36, Margin = new Padding(4, 0, 4, 0), UseVisualStyleBackColor = true };
    }

    internal void Reload(bool preserve)
    {
        ModScanner.ScanResult fresh = ModLauncher.Open(root);
        if (preserve && dirty && scan != null)
        {
            foreach (ModScanner.Mod mod in fresh.Mods)
            {
                ModScanner.Mod old;
                if (scan.Choices.TryGetValue(mod.Entry, out old) && old.Directory.Equals(mod.Directory, StringComparison.OrdinalIgnoreCase))
                    fresh.Choices[mod.Entry] = old;
            }
            ModScanner.ApplyChoices(fresh);
        }
        scan = fresh; Bind();
        feedback.Text = preserve && dirty ? "扫描完成，已保留窗口中尚未保存的选择。" : "扫描完成。勾选后保存，或直接保存并启动。";
    }

    private void Bind()
    {
        if (scan == null) return;
        string[] selected = Grid.SelectedRows.Cast<DataGridViewRow>().Where(row => row.Tag != null).Select(row => ((ModScanner.Mod)row.Tag).Entry).ToArray();
        string current = Grid.CurrentRow != null && Grid.CurrentRow.Tag != null ? ((ModScanner.Mod)Grid.CurrentRow.Tag).Entry : null;
        binding = true;
        Grid.Rows.Clear();
        foreach (ModScanner.Mod mod in scan.Mods.OrderByDescending(mod => mod.Installed))
        {
            int row = Grid.Rows.Add(mod.Versions[Version.SelectedIndex] == 1, mod.Directory, ModLauncher.Status(mod, Version.SelectedIndex), mod.Entry);
            Grid.Rows[row].Tag = mod;
            bool eligible = mod.Installed && mod.Supported[Version.SelectedIndex] == 1;
            Grid.Rows[row].Cells[0].ReadOnly = !eligible;
            if (!eligible) Grid.Rows[row].DefaultCellStyle.ForeColor = Color.FromArgb(120, 125, 132);
        }
        if (selected.Length > 0)
        {
            Grid.ClearSelection();
            foreach (DataGridViewRow row in Grid.Rows)
            {
                string entry = ((ModScanner.Mod)row.Tag).Entry;
                if (entry == current) Grid.CurrentCell = row.Cells[1];
                row.Selected = selected.Contains(entry);
            }
        }
        binding = false; RefreshStatus(); ShowDetails();
    }

    private void RefreshStatus()
    {
        int version = Version.SelectedIndex;
        int count = scan.Mods.Count(mod => mod.Versions[version] == 1);
        summary.Text = "已安装 " + scan.Mods.Count(mod => mod.Installed) + " 个 · 将加载 " + count + " 个" + (dirty ? "    ● 选择未保存" : "") +
            (scan.Warnings.Count > 0 ? "    · " + scan.Warnings.Count + " 项扫描提示（点击查看）" : "");
        summary.Cursor = scan.Warnings.Count > 0 ? Cursors.Hand : Cursors.Default;
        foreach (DataGridViewRow row in Grid.Rows) row.Cells[2].Value = ModLauncher.Status((ModScanner.Mod)row.Tag, version);
        bool settingsOff = scan.Mods.Any(mod => mod.Entry == "ModLoaderMod" && mod.Installed && mod.Versions[version] == 0);
        if (dirty) feedback.Text = count == 0 ? "全部模组均已停用，适合检查无模组时是否仍有故障。" :
            settingsOff && version == 0 ? "ModLoader 设置组件已停用；游戏仍可加载所选模组，但不提供统一设置菜单。" : "保存后，下次启动游戏会使用这组选择。";
    }

    private void ShowDetails()
    {
        if (Grid.CurrentRow == null || Grid.CurrentRow.Tag == null) return;
        ModScanner.Mod mod = (ModScanner.Mod)Grid.CurrentRow.Tag;
        details.Text = "包位置：mods/" + mod.Directory + "/release/" + mod.Entry + ".swf\n" +
            (mod.Discovered ? "未登记的包仅通过文件头检查，尚未验证实际兼容性。" : "排障：选中一行或多行，再点“仅启用选中项”。Ctrl / Shift 可多选。");
    }

    private void ChangeSelection(string action)
    {
        Try(delegate {
            string names = action == "--only" ? String.Join(",", Grid.SelectedRows.Cast<DataGridViewRow>()
                .Select(row => (ModScanner.Mod)row.Tag).Where(mod => mod.Installed && mod.Supported[Version.SelectedIndex] == 1).Select(mod => mod.Entry)) : null;
            if (action == "--only" && String.IsNullOrEmpty(names)) throw new InvalidOperationException("请先选中一个可加载的模组行。");
            ModLauncher.Select(scan, Version.SelectedIndex, action, names); dirty = true; Bind();
        });
    }

    internal void SaveNow()
    {
        ModScanner.SaveSelection(scan); dirty = false; RefreshStatus();
        feedback.Text = "选择已保存，下次启动生效。" + (scan.BackupPath == null ? "" : "旧名单已自动备份。");
    }

    private void Try(Action action)
    {
        try { action(); }
        catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }
}
