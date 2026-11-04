param(
    [Parameter(Mandatory=$true)][string]$Name,
    [int]$WindowMs = 20000,
    [int]$SettleMs = 6000,
    [int]$TimeoutSeconds = 240,
    [string]$RvSwf = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime = Join-Path $here 'runtime-smoke'
$gameRoot = (Resolve-Path (Join-Path $here '../../../..')).Path
if (-not (Test-Path (Join-Path $gameRoot 'adl64.exe'))) { throw "adl64.exe not found at gameRoot=$gameRoot" }
$evidence = Join-Path $here "evidence/$Name"
$appid = 'pfe-modsettings-rvshadow-' + ([guid]::NewGuid().ToString('N').Substring(0, 12))

function Sha256([string]$path) { if (Test-Path $path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() } else { $null } }

New-Item -ItemType Directory -Force -Path $evidence | Out-Null

# ---- 放入待验证的 RV 产物 ----
$rvTarget = Join-Path $runtime 'mods/RealisticVision/release/RealisticVisionMod.swf'
if ($RvSwf -ne '') { Copy-Item $RvSwf $rvTarget -Force }
$rvSha = Sha256 $rvTarget
$rvBytes = (Get-Item $rvTarget).Length

# ---- 正式配置 + 本轮新键 + autotest ----
$cfg = Get-Content (Join-Path $here '../../release/config.txt') -Raw -Encoding UTF8
function Set-Key([string]$text, [string]$key, [string]$value) {
    $pattern = '(?m)^' + [regex]::Escape($key) + '=.*$'
    if ($text -match $pattern) { return [regex]::Replace($text, $pattern, "$key=$value") }
    return $text.TrimEnd() + "`n$key=$value`n"
}
$cfg = Set-Key $cfg 'enabled' '1'
$cfg = Set-Key $cfg 'mode' 'current'
$cfg = Set-Key $cfg 'cs_window' '1'
$cfg = Set-Key $cfg 'autotest' '1'
$cfg = Set-Key $cfg 'debug' '0'
$cfg = Set-Key $cfg 'proj_shadow_clip' '1'
$cfg = Set-Key $cfg 'turret_wall_guard' '1'
$cfgPath = Join-Path $runtime 'mods/RealisticVision/release/config.txt'
[IO.File]::WriteAllText($cfgPath, $cfg, (New-Object System.Text.UTF8Encoding($false)))

$descriptor = Join-Path $runtime 'application.xml'
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<application xmlns="http://ns.adobe.com/air/application/30.0">
  <id>$appid</id><versionNumber>0.1.0</versionNumber>
  <filename>RvShadowSmoke</filename><name>Remains RV Shadow Smoke</name>
  <initialWindow><content>pfe.swf</content><visible>false</visible><width>1280</width><height>800</height><renderMode>direct</renderMode><resizable>true</resizable></initialWindow>
  <supportedProfiles>extendedDesktop</supportedProfiles>
</application>
"@
[IO.File]::WriteAllText($descriptor, $xml, (New-Object System.Text.UTF8Encoding($false)))
$armJson = @{ arm = 'B'; appId = $appid; seed = 2026110411; windowMs = $WindowMs; settleMs = $SettleMs; turnPx = 220; outDir = $evidence } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $runtime 'arm.json'), $armJson, (New-Object System.Text.UTF8Encoding($false)))

$store = Join-Path $env:APPDATA "$appid/Local Store"
$started = (Get-Date).ToUniversalTime().ToString('o')
. (Join-Path $gameRoot 'mods/ModLoader/tools/Invoke-AirTest.ps1')
$resultPath = Join-Path $evidence 'result.json'
$air = Invoke-AirTest -Executable (Join-Path $gameRoot 'adl64.exe') `
    -Arguments @('-runtime', (Join-Path $gameRoot 'runtimes/air/win64'), $descriptor) `
    -WorkingDirectory $runtime -EvidenceDirectory $evidence `
    -TimeoutSeconds $TimeoutSeconds -UntilFile $resultPath
$timedOut = $air.timedOut
$exitCode = $air.exitCode
Start-Sleep -Milliseconds 800

# ---- store 产物（本轮 APPDATA 可写）----
if (Test-Path $store) {
    Get-ChildItem $store -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $evidence $_.Name) -Force -ErrorAction SilentlyContinue
    }
}

$result = $null
if (Test-Path $resultPath) { try { $result = Get-Content $resultPath -Raw | ConvertFrom-Json } catch { $result = $null } }
$run = [ordered]@{
    name = $Name; appId = $appid; pid = $air.pid; desktopMode = $air.desktopMode; desktopName = $air.desktopName; startedUtc = $started
    endedUtc = (Get-Date).ToUniversalTime().ToString('o'); exitCode = $exitCode; timedOut = $timedOut
    rvSwfSha256 = $rvSha; rvSwfBytes = $rvBytes; store = $store
    hasResult = [bool](Test-Path $resultPath)
    resultOk = if ($result) { [bool]$result.ok } else { $false }
    resultPhase = if ($result) { $result.phase } else { $null }
    resultError = if ($result) { $result.error } else { $null }
}
[IO.File]::WriteAllText((Join-Path $evidence 'run.json'), ($run | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("run {0} exit={1} timedOut={2} resultOk={3} phase={4} err={5}" -f $Name, $exitCode, $timedOut, $run.resultOk, $run.resultPhase, $run.resultError)
Write-Output ("rv swf = {0} bytes / {1}" -f $rvBytes, $rvSha)
if ($timedOut) { exit 2 }
if (-not $result) { exit 3 }
if (-not $result.ok) { exit 4 }
exit 0
