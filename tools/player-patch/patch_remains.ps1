# patch_remains.ps1 - Remains ModLoader game patcher (player-facing, no deps)
# Applies RSPLICE1 binary patches to the player's own game files.
# Usage: powershell -ExecutionPolicy Bypass -File patch_remains.ps1 [-GameRoot <path>]
param(
    [string]$GameRoot = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Sha256File([string]$p) {
    return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
}

function Test-AlreadyPatched([string]$p) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($p)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        return $text.Contains('loadModsFromManifest')
    } catch { return $false }
}

# ---- load manifest ----
$manifestPath = Join-Path $here 'patch-manifest.json'
if (-not (Test-Path $manifestPath)) { throw "patch-manifest.json not found next to this script" }
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---- locate game root ----
if (-not $GameRoot) {
    $candidates = New-Object System.Collections.Generic.List[string]
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath } catch {}
    if ($steam) {
        $candidates.Add((Join-Path $steam 'steamapps\common\Remains'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in (Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -ErrorAction SilentlyContinue)) {
                foreach ($mm in $m.Matches) {
                    $lib = $mm.Groups[1].Value -replace '\\\\', '\'
                    $candidates.Add((Join-Path $lib 'steamapps\common\Remains'))
                }
            }
        }
    }
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\Remains')
    $candidates.Add('D:\Program Files\Steam\steamapps\common\Remains')
    foreach ($c in $candidates) { if (Test-Path (Join-Path $c 'pfe.swf')) { $GameRoot = $c; break } }
}
if (-not $GameRoot -or -not (Test-Path (Join-Path $GameRoot 'pfe.swf'))) {
    $GameRoot = Read-Host 'Game root not auto-detected. Enter the folder that contains pfe.swf'
}
if (-not (Test-Path (Join-Path $GameRoot 'pfe.swf'))) { throw "no pfe.swf under: $GameRoot" }
Write-Host "Game root: $GameRoot"
Write-Host ''

# ---- known patched outputs ----
$patchedShas = @{}
foreach ($t in $manifest.targets) { foreach ($v in $t.vanillas) { $patchedShas[$v.patched_sha256] = $true } }

$applied = 0
foreach ($t in $manifest.targets) {
    $dst = Join-Path $GameRoot ($t.target -replace '/', '\')
    if (-not (Test-Path -LiteralPath $dst)) { Write-Host "[skip] $($t.target): file not found"; continue }
    $sha = Sha256File $dst
    if ($patchedShas.ContainsKey($sha)) { Write-Host "[ok] $($t.target): already patched"; continue }

    $entry = $null
    foreach ($v in $t.vanillas) { if ($v.sha256 -eq $sha) { $entry = $v; break } }
    if (-not $entry) {
        if (Test-AlreadyPatched $dst) { Write-Host "[ok] $($t.target): already patched (marker found, unknown build)"; continue }
        Write-Host "[warn] $($t.target): sha256 $sha matches no known original build - skipped."
        Write-Host "       If Steam re-verified the game, files are original; otherwise this build is unsupported."
        continue
    }

    # ---- parse + apply RSPLICE1 ----
    $patchFile = Join-Path $here $entry.patch
    $pf = [System.IO.File]::ReadAllBytes($patchFile)
    if ($pf.Length -lt 7) { throw "bad patch file: $patchFile" }
    $magic = [System.Text.Encoding]::ASCII.GetString($pf, 0, 5)
    if ($magic -ne 'RSPL1') { throw "bad patch magic in $patchFile" }
    $src = [System.IO.File]::ReadAllBytes($dst)
    $out = New-Object System.Collections.Generic.List[byte]
    $pos = 7; $srcPos = 0; $rec = 0
    while ($pos -lt $pf.Length) {
        $off = [BitConverter]::ToUInt32($pf, $pos); $oldLen = [BitConverter]::ToUInt32($pf, $pos + 4); $newLen = [BitConverter]::ToUInt32($pf, $pos + 8)
        $pos += 12
        if ($off -lt $srcPos) { throw "patch records not ascending (record $rec)" }
        for ($i = $srcPos; $i -lt $off; $i++) { $out.Add($src[$i]) }
        $srcPos = $off + [int]$oldLen
        for ($i = 0; $i -lt $newLen; $i++) { $out.Add($pf[$pos + $i]) }
        $pos += [int]$newLen
        $rec++
    }
    for ($i = $srcPos; $i -lt $src.Length; $i++) { $out.Add($src[$i]) }
    $result = $out.ToArray()
    $gotSha = Sha256File $dst # placeholder to keep helper used
    $resultSha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($result)).Replace('-', '').ToLower()
    if ($resultSha -ne $entry.patched_sha256) {
        throw "verification failed for $($t.target): patched output sha mismatch. Nothing was written."
    }

    # ---- backup then write ----
    $dir = Split-Path -Parent $dst
    $base = [System.IO.Path]::GetFileNameWithoutExtension($dst)
    $ext = [System.IO.Path]::GetExtension($dst)
    $stamp = Get-Date -Format 'yyyyMMdd'
    $bak = Join-Path $dir ("{0}_before_modloader_{1}{2}" -f $base, $stamp, $ext)
    if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $dst -Destination $bak }
    [System.IO.File]::WriteAllBytes($dst, $result)
    Write-Host "[done] $($t.target): patched from build $($entry.build) (backup: $(Split-Path -Leaf $bak))"
    $applied++
}

Write-Host ''
if ($applied -gt 0) {
    Write-Host 'Patch installed. Next: copy the "mods" folder from the mod package into the game root, then start the game.'
    Write-Host 'Note: Steam "verify integrity" restores original files - just re-run this patcher afterwards.'
} else {
    Write-Host 'Nothing left to patch.'
}
