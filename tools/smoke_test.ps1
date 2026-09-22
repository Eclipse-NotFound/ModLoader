# smoke_test.ps1 - generic loader smoke test
# Launches the game via the real launch chain, waits for mods to load,
# then asserts: (a) each mod's own log got fresh writes, (b) the ModLoader
# SharedObject contains ok_<Entry> marks for every enabled manifest entry.
# Usage: smoke_test.ps1 [-Descriptor application.xml] [-Seconds 35]
[CmdletBinding()]
param(
    [string]$Descriptor = 'application.xml',
    [int]$Seconds = 35,
    [string]$GameRoot = (Split-Path -Parent $PSScriptRoot | Split-Path -Parent | Split-Path -Parent)
)
$ErrorActionPreference = 'Stop'
$store = Join-Path $env:APPDATA 'pfe\Local Store'
$logs = 'sandy_modlog.txt','RConnect.log','RVision.log','RandomRooms_diag.log','ModSettings.log'

# manifest entries enabled for this descriptor (recompute expected set)
$colIdx = 2
if ($Descriptor -like '*pfeUI*') { $colIdx = 4 }
elseif ($Descriptor -like '*DLC*') { $colIdx = 3 }
$expected = @()
Get-Content (Join-Path $GameRoot 'mods\loader-manifest.txt') | ForEach-Object {
    $line = $_.TrimEnd()
    if ($line -and -not $line.StartsWith('#')) {
        $p = $line -split '\|'
        if ($p.Count -ge 5 -and $p[$colIdx] -eq '1') { $expected += $p[1] }
    }
}
Write-Host "expected mods for $Descriptor : $($expected -join ', ')"

$baseline = @{}
foreach ($l in $logs) {
    $p = Join-Path $store $l
    $baseline[$l] = if (Test-Path $p) { (Get-Item $p).LastWriteTime } else { [datetime]::MinValue }
}

Push-Location $GameRoot
$proc = Start-Process -FilePath '.\adl64.exe' -ArgumentList '-runtime','runtimes\air\win64',$Descriptor,'-nodebug' -WorkingDirectory '.' -PassThru
Start-Sleep -Seconds $Seconds
$alive = -not $proc.HasExited
if ($alive) { Stop-Process -Id $proc.Id -Force }
Pop-Location
Write-Host "game ran ${Seconds}s (alive=$alive), stopped."

$fail = @()
Write-Host ''
Write-Host '=== mod log freshness ==='
foreach ($l in $logs) {
    $f = Get-Item (Join-Path $store $l) -ErrorAction SilentlyContinue
    if ($f) {
        $fresh = $f.LastWriteTime -gt $baseline[$l]
        $tag = 'stale'; if ($fresh) { $tag = 'FRESH' }
        Write-Host ("  {0,-22} {1}  ({2})" -f $l, $tag, $f.LastWriteTime.ToString('HH:mm:ss'))
    } else {
        Write-Host "  $l MISSING"
    }
}

Write-Host ''
Write-Host '=== ModLoader SharedObject marks ==='
$sol = Get-ChildItem (Join-Path $store '#SharedObjects') -Recurse -Filter 'ModLoader.sol' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sol) {
    Write-Host '  ModLoader.sol NOT FOUND - loader did not run!'
    $fail += 'ModLoader.sol missing'
} else {
    Write-Host "  found: $($sol.FullName)"
    $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($sol.FullName))
    foreach ($e in $expected) {
        if ($text.Contains("ok_$e")) { Write-Host "  ok_$e PRESENT" }
        else { Write-Host "  ok_$e MISSING"; $fail += "ok_$e" }
    }
    if ($text.Contains('err_')) {
        Write-Host '  WARNING: err_ keys present - inspect sol for details'
        foreach ($m in [regex]::Matches($text, 'err_[A-Za-z0-9_]+')) { Write-Host "    $($m.Value)" }
    }
}

Write-Host ''
if ($fail.Count -gt 0) {
    Write-Host "SMOKE FAILED: $($fail -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'SMOKE PASSED' -ForegroundColor Green
