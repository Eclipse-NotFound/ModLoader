param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][ValidateSet('A','B','C','D','I','L','P','Q','Z','W','X','Y','V','R','E0','E1','E2','E3','E4','E5','C1','V3')][string]$Arm,
    [int]$Seed = 2026110411,
    [int]$WindowMs = 70000,
    [int]$SettleMs = 8000,
    [double]$TurnPx = 220,
    [int]$TimeoutSeconds = 300,
    [string]$ProbeDisable = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime = Join-Path $here 'runtime'
$gameRoot = (Resolve-Path (Join-Path $here '../../../..')).Path
if (-not (Test-Path (Join-Path $gameRoot 'adl64.exe'))) { throw "adl64.exe not found at gameRoot=$gameRoot" }
$evidence = Join-Path $here "evidence/$Name"
$store = $null
$appid = 'pfe-modsettings-csrv-rv-20261104-' + ([guid]::NewGuid().ToString('N').Substring(0, 12))

function Sha256([string]$path) { if (Test-Path $path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() } else { $null } }

New-Item -ItemType Directory -Force -Path $evidence | Out-Null

# ---- frozen input check (sandbox must still match the pinned build) ----
$inputsJson = Get-Content (Join-Path $here 'inputs/inputs.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function PinSha([string]$key) { $p = $inputsJson.PSObject.Properties[$key]; if ($p) { $p.Value.sha256 } else { $null } }
$pins = [ordered]@{
    'rv-swf'     = PinSha 'rv-release.swf'
    'cs-swf'     = PinSha 'cs-release.swf'
    'cs-scene'   = PinSha 'cs-release-scene.xml'
    'pfe-swf'    = PinSha 'host-pfe.swf'
    'rooms-mane' = PinSha 'rooms_mane.xml'
}
$hashNow = @{
    'rv-swf'     = Sha256 (Join-Path $runtime 'mods/RealisticVision/release/RealisticVisionMod.swf')
    'cs-swf'     = Sha256 (Join-Path $runtime 'mods/ContinuousScene/release/ContinuousSceneMod.swf')
    'cs-scene'   = Sha256 (Join-Path $runtime 'mods/ContinuousScene/release/scene.xml')
    'driver-swf' = Sha256 (Join-Path $runtime 'mods/CsRvMoveProbe/release/CsRvMoveProbeMod.swf')
    'pfe-swf'    = Sha256 (Join-Path $runtime 'pfe.swf')
    'rooms-mane' = Sha256 (Join-Path $runtime 'Rooms/rooms_mane.xml')
}

# ---- arm config: exact formal config with arm overrides ----
$cfgTemplate = Get-Content (Join-Path $here 'inputs/rv-release-config.txt') -Raw -Encoding UTF8
function Set-Key([string]$text, [string]$key, [string]$value) {
    $pattern = '(?m)^' + [regex]::Escape($key) + '=.*$'
    if ($text -match $pattern) { return [regex]::Replace($text, $pattern, "$key=$value") }
    return $text.TrimEnd() + "`n$key=$value`n"
}
$rvEnabled = if ($Arm -eq 'A' -or $Arm -eq 'W') { '0' } else { '1' }
$cfgTemplate = Set-Key $cfgTemplate 'enabled' $rvEnabled
$rvMode = if ($Arm -eq 'V') { 'vanilla' } else { 'current' }
$cfgTemplate = Set-Key $cfgTemplate 'mode' $rvMode
$cfgTemplate = Set-Key $cfgTemplate 'cs_window' '1'
$cfgTemplate = Set-Key $cfgTemplate 'autotest' '1'
$cfgTemplate = Set-Key $cfgTemplate 'debug' '0'
if ($ProbeDisable -ne '') { $cfgTemplate = Set-Key $cfgTemplate 'probe_disable' $ProbeDisable }
[IO.File]::WriteAllText((Join-Path $runtime 'mods/RealisticVision/release/config.txt'), $cfgTemplate, (New-Object System.Text.UTF8Encoding($false)))
$cfgSha = Sha256 (Join-Path $runtime 'mods/RealisticVision/release/config.txt')

# ---- per-run app descriptor + arm file ----
$descriptor = Join-Path $runtime 'application.xml'
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<application xmlns="http://ns.adobe.com/air/application/30.0">
  <id>$appid</id><versionNumber>0.1.0</versionNumber>
  <filename>CsRvGrid</filename><name>Remains CS RV Grid</name>
  <initialWindow><content>pfe.swf</content><visible>false</visible><width>1280</width><height>800</height><renderMode>direct</renderMode><resizable>true</resizable></initialWindow>
  <supportedProfiles>extendedDesktop</supportedProfiles>
</application>
"@
[IO.File]::WriteAllText($descriptor, $xml, (New-Object System.Text.UTF8Encoding($false)))
$armJson = @{ arm = $Arm; appId = $appid; seed = $Seed; windowMs = $WindowMs; settleMs = $SettleMs; turnPx = $TurnPx; outDir = $evidence } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $runtime 'arm.json'), $armJson, (New-Object System.Text.UTF8Encoding($false)))

$store = Join-Path $env:APPDATA "$appid/Local Store"
$started = (Get-Date).ToUniversalTime().ToString('o')
$rvLogProbe = Join-Path $here 'rvlogs/RVision.log'
Remove-Item $rvLogProbe -Force -ErrorAction SilentlyContinue
. (Join-Path $gameRoot 'mods/ModLoader/tools/Invoke-AirTest.ps1')
$resultPath = Join-Path $evidence 'result.json'
$air = Invoke-AirTest -Executable (Join-Path $gameRoot 'adl64.exe') `
    -Arguments @('-runtime', (Join-Path $gameRoot 'runtimes/air/win64'), $descriptor) `
    -WorkingDirectory $runtime -EvidenceDirectory $evidence `
    -TimeoutSeconds $TimeoutSeconds -UntilFile $resultPath
$timedOut = $air.timedOut
$exitCode = $air.exitCode
Start-Sleep -Milliseconds 800

# Opportunistic: RVision.log only exists when app storage is writable.
if (Test-Path $store) {
    foreach ($artifact in @('RVision.log', 'RealisticVision_config.txt')) {
        $source = Join-Path $store $artifact
        if (Test-Path $source) { Copy-Item $source $evidence -Force }
    }
}
# Log-probe arm (L): the same RV autotest lines redirected to a workspace file.
if (Test-Path $rvLogProbe) { Copy-Item $rvLogProbe (Join-Path $evidence 'RVision.log') -Force }

$result = $null
if (Test-Path $resultPath) {
    try { $result = Get-Content $resultPath -Raw | ConvertFrom-Json } catch { $result = $null }
}
$run = [ordered]@{
    name = $Name; arm = $Arm; appId = $appid; pid = $air.pid; desktopMode = $air.desktopMode; desktopName = $air.desktopName; startedUtc = $started
    endedUtc = (Get-Date).ToUniversalTime().ToString('o'); exitCode = $exitCode; timedOut = $timedOut
    seed = $Seed; windowMs = $WindowMs; settleMs = $SettleMs; turnPx = $TurnPx
    rvConfigSha256 = $cfgSha; store = $store
    inputs = $hashNow
    pins = $pins
    hasResult = [bool](Test-Path $resultPath)
    resultOk = if ($result) { [bool]$result.ok } else { $false }
    resultPhase = if ($result) { $result.phase } else { $null }
    resultError = if ($result) { $result.error } else { $null }
}
[IO.File]::WriteAllText((Join-Path $evidence 'run.json'), ($run | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("run {0} arm={1} exit={2} timedOut={3} resultOk={4} phase={5} err={6}" -f $Name, $Arm, $exitCode, $timedOut, $run.resultOk, $run.resultPhase, $run.resultError)

if ($timedOut) { exit 2 }
if (-not $result) { exit 3 }
if (-not $result.ok) { exit 4 }
exit 0
