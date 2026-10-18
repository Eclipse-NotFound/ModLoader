using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;

internal static class LauncherTests
{
    private static int count;
    private static string root;
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL: " + message);
        Console.WriteLine("PASS " + (++count) + ": " + message);
    }
    private static void Fails(Action action, string message)
    {
        bool failed = false;
        try { action(); } catch (Exception) { failed = true; }
        Check(failed, message);
    }
    private static ModScanner.Mod Get(ModScanner.ScanResult scan, string entry) { return scan.Mods.Single(mod => mod.Entry == entry); }
    private static int Backups()
    {
        string path = Path.Combine(root, "mods", "ModLoader", "work", "manifest-backups");
        return Directory.Exists(path) ? Directory.GetFiles(path).Length : 0;
    }
    private static void Package(string directory, string entry)
    {
        string path = Path.Combine(root, "mods", directory, "release");
        Directory.CreateDirectory(path);
        File.WriteAllBytes(Path.Combine(path, entry + ".swf"), new byte[] { 70, 87, 83, 9, 8, 0, 0, 0 });
    }
    private static void Render(LauncherForm form, string path)
    {
        form.PerformLayout(); Application.DoEvents();
        using (Bitmap bitmap = new Bitmap(form.Width, form.Height))
        {
            form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
    }
    private static void Show(LauncherForm form)
    {
        form.TestWindow = true; form.StartPosition = FormStartPosition.Manual;
        form.Location = new Point(-20000, -20000); form.ShowInTaskbar = false;
        form.Show(); Application.DoEvents();
    }
    [STAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = Utf8;
        try
        {
            root = args[0]; string output = args[1]; string installedRoot = args[2];
            Directory.CreateDirectory(Path.Combine(root, "mods", "ModLoader")); Directory.CreateDirectory(output);
            File.WriteAllText(Path.Combine(root, "mods", "ModLoader", "supported-mods.txt"),
                "ModLoader|ModLoaderMod|1|0|0\nModSettings|ModSettingsMod|0|0|0\nAlpha&One|AlphaMod|1|1|1\nBeta|BetaMod|1|0|0\nMissing|MissingMod|1|1|0\n", Utf8);
            File.WriteAllText(Path.Combine(root, "application.xml"), "<application><initialWindow><content>pfe.swf</content></initialWindow></application>", Utf8);
            File.WriteAllText(Path.Combine(root, "app.xml"), "<application><initialWindow><content>DLC/pfe.swf</content></initialWindow></application>", Utf8);
            Package("ModLoader", "ModLoaderMod"); Package("ModSettings", "ModSettingsMod");
            Package("Alpha&One", "AlphaMod"); Package("Beta", "BetaMod");
            Package("新模组-中文名字很长用于检查显示", "NewDiscoveryMod");
            ModScanner.ScanResult scan = ModLauncher.Open(root);
            string manifest = scan.ManifestPath;
            Check(!File.Exists(manifest), "opening does not create manifest");
            Check(scan.Mods.Count == 6, "known and discovered entries scanned");
            Check(!Get(scan, "MissingMod").Installed, "missing package marked unavailable");
            Check(Get(scan, "ModSettingsMod").Versions.Sum() == 0, "legacy settings cannot auto-enable");
            Fails(delegate { ModLauncher.Select(scan, 0, "--enable", "ModSettingsMod"); }, "blocked package cannot enable");
            Fails(delegate { ModLauncher.Select(scan, 1, "--enable", "BetaMod"); }, "incompatible version cannot enable");
            Fails(delegate { ModLauncher.Select(scan, 0, "--only", "AlphaMod,TypoMod"); }, "unknown name rejects entire operation");
            Check(Get(scan, "BetaMod").Versions[0] == 1, "invalid operation has no partial selection effects");
            ModLauncher.Select(scan, 0, "--only", "AlphaMod"); ModScanner.SaveSelection(scan);
            Check(Get(scan, "AlphaMod").Versions[0] == 1 && scan.Mods.Sum(mod => mod.Versions[0]) == 1, "exact one-mod isolation");
            Check(Get(scan, "AlphaMod").Versions[1] == 1, "other versions retain choices");
            ModScanner.Scan(root, false);
            scan = ModLauncher.Open(root);
            Check(scan.Mods.Sum(mod => mod.Versions[0]) == 1, "scanner retains launcher selection");
            string stable = File.ReadAllText(manifest);
            int backups = Backups();
            ModScanner.SaveSelection(scan);
            Check(File.ReadAllText(manifest) == stable, "save is idempotent");
            Check(Backups() == backups, "unchanged save makes no backup");
            string alpha = Path.Combine(root, "mods", "Alpha&One", "release", "AlphaMod.swf");
            File.Delete(alpha); ModScanner.Scan(root, false);
            Check(Get(ModLauncher.Open(root), "AlphaMod").Versions[0] == 0, "missing selected package skipped");
            Package("Alpha&One", "AlphaMod"); ModScanner.Scan(root, false);
            Check(Get(ModLauncher.Open(root), "AlphaMod").Versions[0] == 1, "selection restored after package returns");
            scan = ModLauncher.Open(root); ModLauncher.Select(scan, 0, "--disable", "AlphaMod"); ModScanner.SaveSelection(scan);
            File.Delete(alpha); ModScanner.Scan(root, false); Package("Alpha&One", "AlphaMod"); ModScanner.Scan(root, false);
            Check(Get(ModLauncher.Open(root), "AlphaMod").Versions[0] == 0, "disabled package stays disabled after return");
            scan = ModLauncher.Open(root); stable = File.ReadAllText(manifest);
            File.AppendAllText(manifest, "# external edit\n");
            Fails(delegate { ModScanner.SaveSelection(scan); }, "stale manifest cannot overwrite another writer");
            Check(File.ReadAllText(manifest).EndsWith("# external edit\n"), "concurrent edit retained");
            scan = ModLauncher.Open(root); Package("Later", "LaterMod");
            Fails(delegate { ModScanner.SaveSelection(scan); }, "new package requires rescan before save");
            File.WriteAllText(manifest, stable + "Bad|BadMod|1|x|0\n", Utf8);
            Fails(delegate { ModScanner.Scan(root, false); }, "malformed manifest fails without overwrite");
            Check(File.ReadAllText(manifest).Contains("|x|"), "malformed manifest preserved");
            File.WriteAllText(manifest, stable, Utf8);
            Check(ModLauncher.DescriptorVersion(root, "app.xml", false) == 1, "descriptor routes DLC correctly");
            Fails(delegate { ModLauncher.DescriptorVersion(root, "../application.xml", false); }, "descriptor cannot escape root");
            Fails(delegate { ModLauncher.ValidateLaunch(root, 0, "application.xml"); }, "missing game files block launch");
            File.WriteAllText(Path.Combine(root, "bad.xml"), "<!DOCTYPE a [<!ENTITY secret SYSTEM 'file:///secret'>]><application>&secret;</application>");
            Fails(delegate { ModLauncher.DescriptorVersion(root, "bad.xml", false); }, "external XML entities rejected");
            scan = ModLauncher.Open(root);
            ModLauncher.WriteReport(Path.Combine(output, "configuration.json"), scan, 0, "application.xml");
            Check(File.ReadAllText(Path.Combine(output, "configuration.json")).Contains("sha256"), "report contains package fingerprints");
            Fails(delegate { ModLauncher.WriteReport(manifest, scan, 0, "application.xml"); }, "export cannot overwrite manifest");
            Fails(delegate { ModLauncher.WriteReport(Path.Combine(output, "configuration.json"), scan, 0, "application.xml"); }, "export cannot overwrite existing file");

            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            using (LauncherForm form = new LauncherForm(root, 0, "application.xml"))
            {
                Show(form);
                Check(form.Grid.Rows.Count == 7, "real WinForms grid populated");
                DataGridViewRow blocked = form.Grid.Rows.Cast<DataGridViewRow>().Single(row => ((ModScanner.Mod)row.Tag).Entry == "ModSettingsMod");
                Check(blocked.Cells[0].ReadOnly, "blocked checkbox is read-only");
                form.All.PerformClick();
                Check(form.Grid.Rows.Cast<DataGridViewRow>().Count(row => Convert.ToBoolean(row.Cells[0].Value)) == 5, "all button selects eligible packages");
                form.None.PerformClick();
                Check(form.Grid.Rows.Cast<DataGridViewRow>().All(row => !Convert.ToBoolean(row.Cells[0].Value)), "none button clears eligible packages");
                form.Grid.ClearSelection();
                DataGridViewRow chosen = form.Grid.Rows.Cast<DataGridViewRow>().Single(row => ((ModScanner.Mod)row.Tag).Entry == "AlphaMod");
                form.Grid.CurrentCell = chosen.Cells[1]; chosen.Selected = true;
                form.Only.PerformClick();
                Check(form.Grid.Rows.Cast<DataGridViewRow>().Count(row => Convert.ToBoolean(row.Cells[0].Value)) == 1, "only-selected button isolates one package");
                form.Rescan.PerformClick();
                Check(form.Grid.Rows.Cast<DataGridViewRow>().Count(row => Convert.ToBoolean(row.Cells[0].Value)) == 1, "rescan preserves unsaved choice");
                form.Save.PerformClick();
                Check(ModLauncher.Open(root).Mods.Sum(mod => mod.Versions[0]) == 1, "save button writes effective selection");
                form.Version.SelectedIndex = 1;
                Check(form.Grid.Rows.Cast<DataGridViewRow>().Single(row => ((ModScanner.Mod)row.Tag).Entry == "BetaMod").Cells[0].ReadOnly, "switching version updates availability");
                form.Version.SelectedIndex = 0;
                Render(form, Path.Combine(output, "fixture-default.png"));
                form.Size = form.MinimumSize;
                Render(form, Path.Combine(output, "fixture-minimum.png"));
                Check(form.Launch.Bounds.Right <= form.Launch.Parent.ClientSize.Width, "launch button fits minimum window");
                form.Close();
            }
            string actualManifest = Path.Combine(installedRoot, "mods", "loader-manifest.txt");
            byte[] actualBefore = File.ReadAllBytes(actualManifest);
            using (LauncherForm form = new LauncherForm(installedRoot, 0, "application.xml"))
            {
                Show(form); Render(form, Path.Combine(output, "installed-preview.png"));
                form.Size = form.MinimumSize; Render(form, Path.Combine(output, "installed-minimum.png"));
                form.Close();
            }
            Check(actualBefore.SequenceEqual(File.ReadAllBytes(actualManifest)), "installed preview leaves real manifest unchanged");
            Console.WriteLine("PASS " + count + " assertions");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
