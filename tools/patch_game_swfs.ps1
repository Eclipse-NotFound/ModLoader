# patch_game_swfs.ps1 - Remains generic mod loader patcher (Route B)
# ============================================================================
# Purpose:
#   Replace the per-mod loader CALL SITES in MainFE with ONE generic,
#   manifest-driven loader. After this patch, adding/removing/reordering
#   mods only requires editing mods\loader-manifest.txt - game SWFs are
#   never touched again (until a Steam update restores vanilla files,
#   in which case re-run this script).
#
# What it does per target SWF:
#   1. ffdec -export script (full export, ~40s)
#   2. Idempotency check: skip if "loadModsFromManifest" already present
#   3. Text transform on MainFE.as:
#      a. add missing imports (SharedObject / URLLoader / Dictionary)
#      b. add fields (manifestUrlLoader / modEntryByLoader) after mainMenu
#      c. REMOVE known legacy loader call lines; insert loadModsFromManifest()
#         right after "this.mainMenu = new MainMenu(this);"
#      d. append generic loader methods before class tail
#      (legacy loader method bodies / fields stay as harmless dead code -
#       minimal surgery; their markers also keep other mods' patch scripts
#       idempotent)
#   4. ffdec -importScript (MainFE only) -> patched.swf in work dir
#   5. Verify by re-export: marker present, legacy CALLS gone, game logic
#      anchors intact
#   6. Unless -DryRun: timestamped backup in game root, then atomic replace
#
# Toolchain (probed 2026-09-22): ffdec-cli.jar must run via java:
#   java = D:\Program Files\Adobe Animate 2024\jre\bin\java.exe
#   ffdec = D:\RemainsMod\mods\Sandevistan\build\tools\ffdec\ffdec-cli.jar
#
# Auth: user approved Route B implementation 2026-09-22 (this patch is the
# one-time game-file modification described in
# shared-knowledge\knowledge-validation\experiments\independent-mod-loader-feasibility.md)
# ============================================================================
[CmdletBinding()]
param(
    [string]$GameRoot = (Split-Path -Parent $PSScriptRoot | Split-Path -Parent | Split-Path -Parent),
    [string]$FfdecJar = 'D:\RemainsMod\mods\Sandevistan\build\tools\ffdec\ffdec-cli.jar',
    [string]$JavaExe  = 'D:\Program Files\Adobe Animate 2024\jre\bin\java.exe',
    [string[]]$Targets = @('pfe.swf', 'DLC/pfe.swf', 'DLC/pfeUI.swf'),
    [string]$WorkDir  = (Join-Path $PSScriptRoot '..\work' -Resolve),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ---- generic loader AS3 snippet (FFDec-compiler style: unassigned var decls
# ---- at function top, no return inside try/catch, internal : * methods) ----
$LoaderMethods = @'
      internal function loadModsFromManifest() : *
      {
         try
         {
            this.manifestUrlLoader = new URLLoader();
            this.manifestUrlLoader.addEventListener(Event.COMPLETE,this.onManifestLoaded);
            this.manifestUrlLoader.addEventListener(IOErrorEvent.IO_ERROR,this.onManifestLoaderError);
            this.manifestUrlLoader.load(new URLRequest("app:/mods/loader-manifest.txt"));
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_loader","manifest load threw " + err);
         }
      }

      internal function onManifestLoaderError(param1:IOErrorEvent) : *
      {
         this.modLoaderStatus("err_loader","manifest IOError " + param1.text);
      }

      internal function onManifestLoaded(param1:Event) : *
      {
         var colIdx:int;
         var urlText:String;
         var lines:Array;
         var i:int;
         var parts:Array;
         var ldr:Loader;
         var ctxt:LoaderContext;
         try
         {
            urlText = this.loaderInfo.url;
            colIdx = 2;
            if(urlText.indexOf("pfeUI") >= 0)
            {
               colIdx = 4;
            }
            else if(urlText.indexOf("DLC") >= 0)
            {
               colIdx = 3;
            }
            this.modEntryByLoader = new Dictionary();
            lines = String(this.manifestUrlLoader.data).split("\n");
            for(i = 0; i < lines.length; i++)
            {
               parts = String(lines[i]).split("\r").join("").split("|");
               if(parts.length >= 5 && String(parts[0]).charAt(0) != "#" && parts[colIdx] == "1")
               {
                  ldr = new Loader();
                  ctxt = new LoaderContext(false);
                  this.modEntryByLoader[ldr] = String(parts[1]);
                  ldr.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onModSwfLoaded);
                  ldr.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onModSwfError);
                  ldr.load(new URLRequest("app:/mods/" + parts[0] + "/release/" + parts[1] + ".swf"),ctxt);
               }
            }
            this.modLoaderStatus("boot","col=" + colIdx);
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_loader","manifest parse threw " + err);
         }
      }

      internal function onModSwfError(param1:IOErrorEvent) : *
      {
         var ldr:Loader;
         ldr = LoaderInfo(param1.currentTarget).loader;
         this.modLoaderStatus("err_" + this.modEntryByLoader[ldr],"IOError " + param1.text);
      }

      internal function onModSwfLoaded(param1:Event) : *
      {
         var ldr:Loader;
         var entry:String;
         var cls:*;
         ldr = LoaderInfo(param1.currentTarget).loader;
         entry = String(this.modEntryByLoader[ldr]);
         try
         {
            cls = LoaderInfo(param1.currentTarget).applicationDomain.getDefinition(entry);
            cls.init(this);
            this.modLoaderStatus("ok_" + entry,"init");
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_" + entry,"init error " + err);
         }
      }

      internal function modLoaderStatus(key:String, message:String) : *
      {
         var so:SharedObject;
         trace("ModLoader[" + key + "] " + message);
         try
         {
            so = SharedObject.getLocal("ModLoader","/");
            so.data[key] = message + " @" + new Date().time;
            so.flush();
         }
         catch(err:*)
         {
         }
      }
'@

# Known legacy loader call lines (12-space indent, exact literals from
# live SWF exports 2026-09-22). Absent ones are simply no-ops (vanilla).
$LegacyCalls = @(
    '            this.loadModSettingsMod();',
    '            this.loadSandevistanMod();',
    '            this.loadRConnectMod();',
    '            this.loadRVisionMod();',
    '            this.loadMSWMod();',
    '            this.loadTDFCMod();',
    '            this.loadRandomRoomsMod();'
)

$Marker      = 'loadModsFromManifest'
$CallAnchor  = '            this.mainMenu = new MainMenu(this);'
$FieldAnchor = '      internal var mainMenu:MainMenu;'

function Write-Log([string]$msg) { Write-Host "[generic-loader] $msg" }

function Invoke-Ffdec([string[]]$ArgList) {
    # PS 5.1: with $ErrorActionPreference='Stop', redirecting native stderr via
    # 2>&1 turns the first stderr line (ffdec/java logging noise) into a
    # terminating error. Locally relax to 'Continue' and rely on $LASTEXITCODE.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $script:JavaExe -jar $script:FfdecJar @ArgList 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    if ($code -ne 0) {
        throw "ffdec failed ($($ArgList -join ' ')):`n$($out | Out-String)"
    }
    return $out
}

function Convert-Eol([string]$Text, [string]$Eol) {
    return ($Text -replace "`r`n", "`n") -replace "`n", $Eol
}

function Transform-MainFe([string]$src) {
    # returns hashtable: { Text, RemovedCalls, Notes[] }
    $notes = @()

    # detect EOL
    $eol = if ($src.Contains("`r`n")) { "`r`n" } else { "`n" }

    # ---- 1. imports (each idempotent) ----
    $importAnchorNet = '   import flash.net.URLRequest;'
    $importAnchorUi  = '   import flash.ui.ContextMenu;'
    foreach ($imp in @('   import flash.net.SharedObject;', '   import flash.net.URLLoader;')) {
        $name = ($imp -replace '.*import ', '' -replace ';', '')
        if ($src.Contains($imp)) { $notes += "import $name already present"; continue }
        $anchor = if ($src.Contains($importAnchorNet)) { $importAnchorNet } else { $importAnchorUi }
        if (-not $src.Contains($anchor)) { throw "no import anchor found for $name" }
        $src = $src.Replace($anchor, ($imp + $eol + $anchor))
        $notes += "import $name added"
    }
    $impDict = '   import flash.utils.Dictionary;'
    if ($src.Contains($impDict)) { $notes += 'import Dictionary already present' }
    else {
        $anchor = if ($src.Contains('   import flash.utils.getQualifiedClassName;')) { '   import flash.utils.getQualifiedClassName;' } else { $importAnchorUi }
        if (-not $src.Contains($anchor)) { throw 'no import anchor found for Dictionary' }
        $src = $src.Replace($anchor, ($impDict + $eol + $anchor))
        $notes += 'import Dictionary added'
    }

    # ---- 2. fields ----
    if ($src.Contains('manifestUrlLoader:URLLoader')) { $notes += 'fields already present' }
    else {
        if (-not $src.Contains($FieldAnchor)) { throw 'field anchor (mainMenu) missing - MainFE structure changed, manual adaptation required' }
        $addField = '      internal var manifestUrlLoader:URLLoader;' + $eol +
                    '      internal var modEntryByLoader:Dictionary;'
        $src = $src.Replace($FieldAnchor, ($FieldAnchor + $eol + $addField))
        $notes += 'fields added'
    }

    # ---- 3. call site ----
    $removed = 0
    foreach ($call in $LegacyCalls) {
        $hit = $src.Replace($call + $eol, '')
        if ($hit.Length -ne $src.Length) { $removed++ }
        $src = $hit
    }
    $notes += "legacy call lines removed: $removed"
    if ($src.Contains('this.loadModsFromManifest();')) { $notes += 'generic call already present' }
    else {
        if (-not $src.Contains($CallAnchor)) { throw 'call anchor (new MainMenu) missing - MainFE structure changed, manual adaptation required' }
        $src = $src.Replace($CallAnchor, ($CallAnchor + $eol + '            this.loadModsFromManifest();'))
        $notes += 'generic call inserted'
    }

    # ---- 4. methods before class tail ----
    if ($src.Contains('internal function loadModsFromManifest')) { $notes += 'methods already present' }
    else {
        $tail = $src.TrimEnd()
        if (-not $tail.EndsWith($eol + '   }' + $eol + '}')) { throw 'class tail structure mismatch, manual adaptation required' }
        $bodyEnd = $tail.LastIndexOf($eol + '   }')
        $methods = Convert-Eol $LoaderMethods $eol
        if (-not $methods.EndsWith($eol)) { $methods += $eol }
        $src = $tail.Substring(0, $bodyEnd) + $methods + $eol + $tail.Substring($bodyEnd).TrimStart($eol.ToCharArray() -join '')
        $notes += 'methods appended'
    }

    return @{ Text = $src; RemovedCalls = $removed; Notes = $notes }
}

function Patch-One([string]$relPath) {
    $swf = Join-Path $GameRoot $relPath
    $name = ($relPath -replace '[\\/]', '_') -replace '\.swf$', ''
    if (-not (Test-Path $swf)) { return "skip(missing): $relPath" }
    Write-Log "=== $relPath ==="

    # 1. export
    $exportDir = Join-Path $WorkDir "export-$name"
    if (Test-Path $exportDir) { Remove-Item $exportDir -Recurse -Force }
    [void](Invoke-Ffdec @('-export', 'script', $exportDir, $swf))
    $mainfe = Join-Path $exportDir 'scripts\MainFE.as'
    if (-not (Test-Path $mainfe)) { throw "MainFE.as not found in export of $relPath" }
    $src = [System.IO.File]::ReadAllText($mainfe, [System.Text.Encoding]::UTF8)

    # 2. idempotency
    if ($src.Contains($Marker)) {
        Write-Log "  already patched (marker present), skipped"
        return "skip(already-patched): $relPath"
    }

    # 3. transform
    $r = Transform-MainFe $src
    foreach ($n in $r.Notes) { Write-Log "  $n" }
    $newSrc = $r.Text

    # 4. import to work swf
    $importDir = Join-Path $WorkDir "import-$name"
    New-Item -ItemType Directory -Force $importDir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $importDir 'MainFE.as'), $newSrc, (New-Object System.Text.UTF8Encoding($false)))
    $patched = Join-Path $WorkDir "$name.patched.swf"
    if (Test-Path $patched) { Remove-Item $patched -Force }
    [void](Invoke-Ffdec @('-importScript', $swf, $patched, $importDir))

    # 5. verify by re-export
    $verifyDir = Join-Path $WorkDir "verify-$name"
    if (Test-Path $verifyDir) { Remove-Item $verifyDir -Recurse -Force }
    [void](Invoke-Ffdec @('-export', 'script', $verifyDir, $patched))
    $vsrc = [System.IO.File]::ReadAllText((Join-Path $verifyDir 'scripts\MainFE.as'), [System.Text.Encoding]::UTF8)
    if (-not $vsrc.Contains($Marker)) { throw "verify failed: $relPath marker missing after import" }
    if (-not $vsrc.Contains('app:/mods/loader-manifest.txt')) { throw "verify failed: $relPath manifest path missing" }
    if (-not $vsrc.Contains('new MainMenu(this);')) { throw "verify failed: $relPath game logic anchor (MainMenu) missing" }
    if (-not $vsrc.Contains('onEnterFrameLoader')) { throw "verify failed: $relPath game logic anchor (onEnterFrameLoader) missing" }
    foreach ($call in $LegacyCalls) {
        if ($vsrc.Contains($call)) { throw "verify failed: $relPath legacy call still present: $call" }
    }
    $sizeDelta = (Get-Item $patched).Length - (Get-Item $swf).Length
    Write-Log ("  verify OK; size delta {0:+0;-0;0} bytes" -f $sizeDelta)

    if ($DryRun) {
        Write-Log "  DRY-RUN: game file NOT touched; patched swf at $patched"
        return "dryrun(ok): $relPath"
    }

    # 6. backup + atomic replace
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $baseName = ($relPath -replace '[\\/]', '_') -replace '\.swf$', ''   # pfe / DLC_pfe / DLC_pfeUI
    $backup = Join-Path $GameRoot ("{0}_before_genericloader_{1}.swf" -f $baseName, $stamp)
    Copy-Item $swf $backup
    Write-Log "  backup: $(Split-Path -Leaf $backup)"

    $tmp = "$swf.tmp_new"
    Copy-Item $patched $tmp -Force
    Move-Item $tmp $swf -Force
    Write-Log "  deployed: $swf"
    return "patched: $relPath"
}

# ---- main ----
if (-not (Test-Path $FfdecJar)) { throw "ffdec-cli.jar not found: $FfdecJar" }
if (-not (Test-Path $JavaExe))  { throw "java.exe not found: $JavaExe" }
if (-not (Test-Path (Join-Path $GameRoot 'mods\loader-manifest.txt'))) {
    Write-Log 'WARNING: mods\loader-manifest.txt missing - mods will NOT load until it exists!'
}
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$results = @()
$failed  = @()
foreach ($rel in $Targets) {
    try { $results += Patch-One $rel }
    catch { $failed += "$rel : $_"; Write-Log "!! FAILED $rel : $_" }
}

''
$results | ForEach-Object { Write-Host "  $_" }
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'done.'
