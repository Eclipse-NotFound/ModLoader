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
    [string]$WorkDir  = (Join-Path $PSScriptRoot '..\work'),
    [switch]$DryRun,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

# ---- generic loader AS3 snippet (FFDec-compiler style: unassigned var decls
# ---- at function top, no return inside try/catch, internal : * methods) ----
$LoaderMethods = @'
      internal function loadModsFromManifest() : *
      {
         var so:SharedObject;
         this.modLoaderRunId = "run_" + String(new Date().time) + "_" + String(int(Math.random() * 1000000));
         this.modLoaderStatusReady = false;
         try
         {
            so = SharedObject.getLocal("ModLoader","/");
            so.clear();
            so.data["session"] = this.modLoaderRunId;
            this.modLoaderStatusReady = so.flush() == "flushed";
         }
         catch(err:*)
         {
            this.modLoaderStatusReady = false;
         }
         this.modLoaderStatus("boot_start","v2 run=" + this.modLoaderRunId);
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
         var line:String;
         var dir:String;
         var entry:String;
         var seen:Dictionary;
         var enabledCount:int;
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
            seen = new Dictionary();
            lines = String(this.manifestUrlLoader.data).split("\n");
            for(i = 0; i < lines.length; i++)
            {
               line = this.modLoaderTrimText(String(lines[i]).split("\r").join(""));
               if(line.length > 0 && line.charAt(0) != "#")
               {
                  parts = line.split("|");
                  if(parts.length != 5)
                  {
                     this.modLoaderStatus("err_manifest_" + i,"line " + (i + 1) + " needs 5 columns");
                  }
                  else
                  {
                     dir = this.modLoaderTrimText(String(parts[0]));
                     entry = this.modLoaderTrimText(String(parts[1]));
                     if(dir.length == 0 || entry.length == 0 || dir == "." || dir.indexOf("..") >= 0 || dir.indexOf("/") >= 0 || dir.indexOf("\\") >= 0 || dir.indexOf(":") >= 0 || dir.indexOf("?") >= 0 || dir.indexOf("#") >= 0 || dir.indexOf("%") >= 0 || entry.indexOf("/") >= 0 || entry.indexOf("\\") >= 0 || entry.indexOf(".") >= 0 || entry.indexOf(" ") >= 0 || entry.indexOf(":") >= 0 || entry.indexOf("?") >= 0 || entry.indexOf("#") >= 0 || entry.indexOf("%") >= 0)
                     {
                        this.modLoaderStatus("err_manifest_" + i,"line " + (i + 1) + " invalid directory or entry");
                     }
                     else if(this.modLoaderTrimText(String(parts[2])) != "0" && this.modLoaderTrimText(String(parts[2])) != "1" || this.modLoaderTrimText(String(parts[3])) != "0" && this.modLoaderTrimText(String(parts[3])) != "1" || this.modLoaderTrimText(String(parts[4])) != "0" && this.modLoaderTrimText(String(parts[4])) != "1")
                     {
                        this.modLoaderStatus("err_manifest_" + i,"line " + (i + 1) + " invalid switch");
                     }
                     else if(seen[entry] != null)
                     {
                        this.modLoaderStatus("err_manifest_" + i,"line " + (i + 1) + " duplicate entry " + entry);
                     }
                     else
                     {
                        seen[entry] = true;
                        if(this.modLoaderTrimText(String(parts[colIdx])) == "1")
                        {
                           try
                           {
                              ldr = new Loader();
                              ctxt = new LoaderContext(false);
                              this.modEntryByLoader[ldr] = entry;
                              ldr.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onModSwfLoaded);
                              ldr.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onModSwfError);
                              this.modLoaderStatus("requested_" + entry,"line " + (i + 1));
                              ldr.load(new URLRequest("app:/mods/" + dir + "/release/" + entry + ".swf"),ctxt);
                              enabledCount++;
                           }
                           catch(rowErr:*)
                           {
                              this.modLoaderStatus("err_" + entry,"line " + (i + 1) + " load threw " + rowErr);
                           }
                        }
                     }
                  }
               }
            }
            this.modLoaderStatus("boot","v2 col=" + colIdx + " requested=" + enabledCount);
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_loader","manifest parse threw " + err);
         }
      }

      internal function onModSwfError(param1:IOErrorEvent) : *
      {
         var ldr:Loader;
         try
         {
            ldr = LoaderInfo(param1.currentTarget).loader;
            this.modLoaderStatus("err_" + this.modEntryByLoader[ldr],"IOError " + param1.text);
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_loader","SWF IOError handler threw " + err);
         }
      }

      internal function onModSwfLoaded(param1:Event) : *
      {
         var ldr:Loader;
         var entry:String;
         var cls:*;
         try
         {
            ldr = LoaderInfo(param1.currentTarget).loader;
            entry = String(this.modEntryByLoader[ldr]);
            cls = LoaderInfo(param1.currentTarget).applicationDomain.getDefinition(entry);
            cls.init(this);
            this.modLoaderStatus("ok_" + entry,"init");
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_" + entry,"load/init error " + err);
         }
      }

      internal function modLoaderTrimText(value:String) : String
      {
         var textValue:String = String(value).split("\uFEFF").join("");
         while(textValue.length > 0 && (textValue.charAt(0) == " " || textValue.charAt(0) == "\t"))
         {
            textValue = textValue.substr(1);
         }
         while(textValue.length > 0 && (textValue.charAt(textValue.length - 1) == " " || textValue.charAt(textValue.length - 1) == "\t"))
         {
            textValue = textValue.substr(0,textValue.length - 1);
         }
         return textValue;
      }

      internal function modLoaderStatus(key:String, message:String) : *
      {
         var so:SharedObject;
         trace("ModLoader[" + key + "] " + message);
         if(!this.modLoaderStatusReady)
         {
            return;
         }
         try
         {
            so = SharedObject.getLocal("ModLoader","/");
            so.data[key] = this.modLoaderRunId + "|" + message + " @" + new Date().time;
            if(so.flush() != "flushed")
            {
               this.modLoaderStatusReady = false;
            }
         }
         catch(err:*)
         {
            this.modLoaderStatusReady = false;
         }
      }
'@

$KnownTargets = @{
    'pfe.swf'       = 7
    'DLC/pfe.swf'   = 3
    'DLC/pfeUI.swf' = 2
}
$LegacyNames = @('loadModSettingsMod', 'loadSandevistanMod', 'loadRConnectMod',
                 'loadRVisionMod', 'loadMSWMod', 'loadTDFCMod', 'loadRandomRoomsMod')
$GenericNames = @('loadModsFromManifest', 'onManifestLoaderError', 'onManifestLoaded',
                  'onModSwfError', 'onModSwfLoaded', 'modLoaderTrimText', 'modLoaderStatus')
$V2Marker = 'modLoaderStatusReady:Boolean'
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

function Get-MethodSpan([string]$source, [string]$name) {
    $pattern = '(?m)^[ \t]*internal function ' + [regex]::Escape($name) + '\s*\('
    $matches = [regex]::Matches($source, $pattern)
    if ($matches.Count -gt 1) { throw "duplicate MainFE method: $name" }
    if ($matches.Count -eq 0) { return $null }
    $start = $matches[0].Index
    $open = $source.IndexOf('{', $matches[0].Index + $matches[0].Length)
    if ($open -lt 0) { throw "method body missing: $name" }
    $depth = 0
    for ($i = $open; $i -lt $source.Length; $i++) {
        if ($source[$i] -eq '{') { $depth++ }
        elseif ($source[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return @{ Start = $start; End = ($i + 1); Text = $source.Substring($start, $i + 1 - $start) }
            }
        }
    }
    throw "method body unclosed: $name"
}

function Get-LegacyCallMatches([string]$methodText) {
    return ,([regex]::Matches($methodText, '(?m)^[ \t]*this\.(load[A-Za-z0-9_]+Mod)\s*\(\s*\)\s*;[ \t]*(?:\r?\n|$)'))
}

function Assert-PatchStructure([string]$src, [string]$relPath) {
    $startup = Get-MethodSpan $src 'onEnterFrameLoader'
    if ($null -eq $startup) { throw "$relPath : onEnterFrameLoader missing" }
    if ([regex]::Matches($startup.Text, '\bthis\.loadModsFromManifest\s*\(\s*\)\s*;').Count -ne 1) {
        throw "$relPath : expected exactly one generic startup call"
    }
    if ((Get-LegacyCallMatches $startup.Text).Count -ne 0) {
        throw "$relPath : legacy startup loader call remains"
    }
    foreach ($field in @('manifestUrlLoader:URLLoader', 'modEntryByLoader:Dictionary',
                        'modLoaderRunId:String', $V2Marker)) {
        if (-not $src.Contains($field)) { throw "$relPath : missing field $field" }
    }
    foreach ($name in $GenericNames) {
        if ($null -eq (Get-MethodSpan $src $name)) { throw "$relPath : missing method $name" }
    }
    foreach ($needle in @('app:/mods/loader-manifest.txt', 'so.clear()',
                          'err_manifest_', 'requested_', 'new MainMenu(this);')) {
        if (-not $src.Contains($needle)) { throw "$relPath : missing required code $needle" }
    }
}

function Transform-MainFe([string]$src, [string]$relPath) {
    if (-not $KnownTargets.ContainsKey($relPath)) { throw "unknown SWF target: $relPath" }
    if ($src.Contains($V2Marker)) {
        Assert-PatchStructure $src $relPath
        return @{ Text = $src; RemovedCalls = 0; AlreadyPatched = $true; Notes = @('v2 structure verified') }
    }
    $notes = @()
    $eol = if ($src.Contains("`r`n")) { "`r`n" } else { "`n" }

    $importAnchorNet = '   import flash.net.URLRequest;'
    $importAnchorUi = '   import flash.ui.ContextMenu;'
    foreach ($imp in @('   import flash.net.SharedObject;', '   import flash.net.URLLoader;',
                       '   import flash.utils.Dictionary;')) {
        if ($src.Contains($imp)) { continue }
        $anchor = if ($imp.Contains('Dictionary')) {
            if ($src.Contains('   import flash.utils.getQualifiedClassName;')) {
                '   import flash.utils.getQualifiedClassName;'
            } else { $importAnchorUi }
        } elseif ($src.Contains($importAnchorNet)) { $importAnchorNet } else { $importAnchorUi }
        if (-not $src.Contains($anchor)) { throw "import anchor missing for $imp" }
        $src = $src.Replace($anchor, $imp + $eol + $anchor)
        $notes += "added $imp"
    }

    foreach ($field in @('      internal var manifestUrlLoader:URLLoader;',
                        '      internal var modEntryByLoader:Dictionary;',
                        '      internal var modLoaderRunId:String;',
                        '      internal var modLoaderStatusReady:Boolean;')) {
        if ($src.Contains($field)) { continue }
        if (-not $src.Contains($FieldAnchor)) { throw 'field anchor mainMenu missing' }
        $src = $src.Replace($FieldAnchor, $FieldAnchor + $eol + $field)
        $notes += "added $field"
    }

    $startup = Get-MethodSpan $src 'onEnterFrameLoader'
    if ($null -eq $startup) { throw 'onEnterFrameLoader missing' }
    $legacy = Get-LegacyCallMatches $startup.Text
    if ($legacy.Count -ne 0 -and $legacy.Count -ne $KnownTargets[$relPath]) {
        throw "$relPath : found $($legacy.Count) legacy startup calls, expected 0 or $($KnownTargets[$relPath])"
    }
    foreach ($match in $legacy) {
        if ($match.Groups[1].Value -notin $LegacyNames) {
            throw "$relPath : unknown loader call $($match.Groups[1].Value)"
        }
    }
    $startupText = [regex]::Replace($startup.Text,
        '(?m)^[ \t]*this\.load[A-Za-z0-9_]+Mod\s*\(\s*\)\s*;[ \t]*(?:\r?\n|$)', '')
    $genericCalls = [regex]::Matches($startupText, '\bthis\.loadModsFromManifest\s*\(\s*\)\s*;')
    if ($genericCalls.Count -gt 1) { throw "$relPath : duplicate generic startup calls" }
    if ($genericCalls.Count -eq 0) {
        $anchors = [regex]::Matches($startupText,
            '(?m)^([ \t]*)this\.mainMenu\s*=\s*new MainMenu\(this\);[ \t]*\r?$')
        if ($anchors.Count -ne 1) { throw "$relPath : MainMenu call anchor missing or duplicated" }
        $anchor = $anchors[0]
        $replacement = $anchor.Value + $eol + $anchor.Groups[1].Value + 'this.loadModsFromManifest();'
        $startupText = $startupText.Substring(0, $anchor.Index) + $replacement +
                       $startupText.Substring($anchor.Index + $anchor.Length)
    }
    $src = $src.Substring(0, $startup.Start) + $startupText + $src.Substring($startup.End)
    $notes += "removed $($legacy.Count) legacy startup calls"

    $tail = $src.TrimEnd()
    if (-not $tail.EndsWith($eol + '   }' + $eol + '}')) {
        throw "$relPath : class tail changed; manual adaptation required"
    }
    $bodyEnd = $tail.LastIndexOf($eol + '   }')
    $methods = (Convert-Eol $LoaderMethods $eol).TrimEnd()
    $oldGeneric = Get-MethodSpan $tail 'loadModsFromManifest'
    if ($null -eq $oldGeneric) {
        foreach ($name in $GenericNames) {
            if ($null -ne (Get-MethodSpan $tail $name)) {
                throw "$relPath : partial generic methods found"
            }
        }
        $src = $tail.Substring(0, $bodyEnd) + $eol + $methods + $tail.Substring($bodyEnd)
        $notes += 'generic methods appended'
    } else {
        foreach ($name in ($GenericNames | Where-Object { $_ -ne 'modLoaderTrimText' })) {
            if ($null -eq (Get-MethodSpan $tail $name)) { throw "$relPath : incomplete v1 method set ($name)" }
        }
        $genericTail = $tail.Substring($oldGeneric.Start, $bodyEnd - $oldGeneric.Start)
        foreach ($found in [regex]::Matches($genericTail, 'internal function ([A-Za-z0-9_]+)')) {
            if ($found.Groups[1].Value -notin $GenericNames) {
                throw "$relPath : another method follows generic loader; manual merge required"
            }
        }
        $src = $tail.Substring(0, $oldGeneric.Start) + $methods + $tail.Substring($bodyEnd)
        $notes += 'v1 generic methods replaced with v2'
    }
    Assert-PatchStructure $src $relPath
    return @{ Text = $src; RemovedCalls = $legacy.Count; AlreadyPatched = $false; Notes = $notes }
}

function Assert-WorkChild([string]$path) {
    $base = [System.IO.Path]::GetFullPath($WorkDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $child = [System.IO.Path]::GetFullPath($path)
    if (-not $child.StartsWith($base + [System.IO.Path]::DirectorySeparatorChar,
                               [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "work artifact outside WorkDir: $child"
    }
}

function Assert-Manifest([string]$manifestPath) {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "required manifest missing: $manifestPath" }
    $entries = @{}
    $lineNo = 0
    foreach ($rawLine in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
        $lineNo++
        $line = $rawLine.Trim().Trim([char]0xFEFF)
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        $parts = @($line.Split('|') | ForEach-Object { $_.Trim() })
        if ($parts.Count -ne 5) { throw "manifest line $lineNo needs 5 columns" }
        if ($parts[0] -notmatch '^[A-Za-z0-9_.&-]+$' -or $parts[0].Contains('..') -or
            $parts[1] -notmatch '^[A-Za-z_$][A-Za-z0-9_$]*$') {
            throw "manifest line $lineNo has invalid directory or entry"
        }
        foreach ($flag in $parts[2..4]) {
            if ($flag -notin @('0','1')) { throw "manifest line $lineNo has invalid switch" }
        }
        if ($entries.ContainsKey($parts[1])) { throw "manifest duplicate entry $($parts[1])" }
        $entries[$parts[1]] = $true
        if ('1' -in $parts[2..4]) {
            $release = Join-Path (Join-Path (Join-Path $GameRoot 'mods') $parts[0]) (Join-Path 'release' ($parts[1] + '.swf'))
            if (-not (Test-Path -LiteralPath $release)) { throw "enabled mod SWF missing: $release" }
        }
    }
    if ($entries.Count -eq 0) { throw 'manifest has no entries' }
}

function Patch-One([string]$relPath) {
    $swf = Join-Path $GameRoot ($relPath -replace '/', '\')
    $name = ($relPath -replace '[\\/]', '_') -replace '\.swf$', ''
    if (-not (Test-Path -LiteralPath $swf)) { throw "required target missing: $swf" }
    Write-Log "=== $relPath ==="

    $exportDir = Join-Path $WorkDir "export-$name"
    Assert-WorkChild $exportDir
    if (Test-Path -LiteralPath $exportDir) { Remove-Item -LiteralPath $exportDir -Recurse -Force }
    [void](Invoke-Ffdec @('-export', 'script', $exportDir, $swf))
    $mainfe = Join-Path $exportDir 'scripts\MainFE.as'
    if (-not (Test-Path -LiteralPath $mainfe)) { throw "MainFE.as not found in export of $relPath" }
    $src = [System.IO.File]::ReadAllText($mainfe, [System.Text.Encoding]::UTF8)
    $r = Transform-MainFe $src $relPath
    foreach ($n in $r.Notes) { Write-Log "  $n" }
    $originalHash = (Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash
    if ($r.AlreadyPatched) {
        return [pscustomobject]@{ Target = $relPath; Swf = $swf; Changed = $false;
                                  OriginalHash = $originalHash; Patched = $null; PatchedHash = $null }
    }

    $importDir = Join-Path $WorkDir "import-$name"
    Assert-WorkChild $importDir
    if (Test-Path -LiteralPath $importDir) { Remove-Item -LiteralPath $importDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $importDir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $importDir 'MainFE.as'), $r.Text, (New-Object System.Text.UTF8Encoding($false)))
    $patched = Join-Path $WorkDir "$name.patched.swf"
    Assert-WorkChild $patched
    if (Test-Path -LiteralPath $patched) { Remove-Item -LiteralPath $patched -Force }
    [void](Invoke-Ffdec @('-importScript', $swf, $patched, $importDir))
    if (-not (Test-Path -LiteralPath $patched)) { throw "FFDec did not create $patched" }

    $verifyDir = Join-Path $WorkDir "verify-$name"
    Assert-WorkChild $verifyDir
    if (Test-Path -LiteralPath $verifyDir) { Remove-Item -LiteralPath $verifyDir -Recurse -Force }
    [void](Invoke-Ffdec @('-export', 'script', $verifyDir, $patched))
    $verifyMainFe = Join-Path $verifyDir 'scripts\MainFE.as'
    if (-not (Test-Path -LiteralPath $verifyMainFe)) { throw "verify export missing MainFE.as: $relPath" }
    $vsrc = [System.IO.File]::ReadAllText($verifyMainFe, [System.Text.Encoding]::UTF8)
    Assert-PatchStructure $vsrc $relPath
    $sizeDelta = (Get-Item $patched).Length - (Get-Item $swf).Length
    Write-Log ("  verify OK; size delta {0:+0;-0;0} bytes" -f $sizeDelta)
    return [pscustomobject]@{ Target = $relPath; Swf = $swf; Changed = $true;
                              OriginalHash = $originalHash; Patched = $patched;
                              PatchedHash = (Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash }
}

if ($FunctionsOnly) { return }

$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
if (-not (Test-Path -LiteralPath $FfdecJar)) { throw "ffdec-cli.jar not found: $FfdecJar" }
if (-not (Test-Path -LiteralPath $JavaExe)) { throw "java.exe not found: $JavaExe" }
Assert-Manifest (Join-Path $GameRoot 'mods\loader-manifest.txt')
if ($Targets.Count -eq 0) { throw 'Targets is empty' }
$normalizedTargets = @($Targets | ForEach-Object { $_ -replace '\\', '/' })
foreach ($target in $normalizedTargets) {
    if (-not $KnownTargets.ContainsKey($target)) { throw "unknown target: $target" }
}
if (@($normalizedTargets | Select-Object -Unique).Count -ne $normalizedTargets.Count) {
    throw 'duplicate target in Targets'
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# Stage and verify every target before the first game-file replacement.
$plans = @()
foreach ($target in $normalizedTargets) { $plans += Patch-One $target }
$changed = @($plans | Where-Object { $_.Changed })
if ($DryRun) {
    foreach ($plan in $plans) {
        if ($plan.Changed) { Write-Log "DRY-RUN ready: $($plan.Target) -> $($plan.Patched)" }
        else { Write-Log "DRY-RUN verified existing v2: $($plan.Target)" }
    }
    Write-Log 'game SWFs untouched'
    return
}
if ($changed.Count -eq 0) { Write-Log 'all targets already have verified v2 loader'; return }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$backups = @()
foreach ($plan in $changed) {
    if ((Get-FileHash -LiteralPath $plan.Swf -Algorithm SHA256).Hash -ne $plan.OriginalHash) {
        throw "target changed during staging: $($plan.Target)"
    }
    $baseName = ($plan.Target -replace '[\\/]', '_') -replace '\.swf$', ''
    $backup = Join-Path $GameRoot ("{0}_before_genericloader_v2_{1}.swf" -f $baseName, $stamp)
    if (Test-Path -LiteralPath $backup) { throw "backup already exists: $backup" }
    $backups += [pscustomobject]@{ Plan = $plan; Backup = $backup }
}
foreach ($record in $backups) {
    Copy-Item -LiteralPath $record.Plan.Swf -Destination $record.Backup
    if ((Get-FileHash -LiteralPath $record.Backup -Algorithm SHA256).Hash -ne $record.Plan.OriginalHash) {
        throw "backup hash mismatch: $($record.Backup)"
    }
    Write-Log "backup: $($record.Backup)"
}

try {
    foreach ($record in $backups) {
        $plan = $record.Plan
        if ((Get-FileHash -LiteralPath $plan.Swf -Algorithm SHA256).Hash -ne $plan.OriginalHash) {
            throw "target changed before deploy: $($plan.Target)"
        }
        $temp = $plan.Swf + '.tmp_new_' + [guid]::NewGuid().ToString('N')
        Copy-Item -LiteralPath $plan.Patched -Destination $temp
        if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ne $plan.PatchedHash) {
            throw "staged copy hash mismatch: $($plan.Target)"
        }
        Move-Item -LiteralPath $temp -Destination $plan.Swf -Force
        if ((Get-FileHash -LiteralPath $plan.Swf -Algorithm SHA256).Hash -ne $plan.PatchedHash) {
            throw "deployed hash mismatch: $($plan.Target)"
        }
        Write-Log "deployed: $($plan.Target)"
    }
} catch {
    $failure = $_
    foreach ($record in $backups) {
        if (-not (Test-Path -LiteralPath $record.Plan.Swf) -or
            (Get-FileHash -LiteralPath $record.Plan.Swf -Algorithm SHA256).Hash -ne $record.Plan.OriginalHash) {
            Copy-Item -LiteralPath $record.Backup -Destination $record.Plan.Swf -Force
            Write-Log "rolled back: $($record.Plan.Target)"
        }
    }
    throw $failure
}
Write-Log 'done; restart the game for the new loader to take effect'
