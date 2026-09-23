# Launch one isolated AIR instance. Never use the player's pfe storage or process.
[CmdletBinding()]
param(
    [string]$Descriptor = 'application.xml',
    [ValidateRange(10,300)][int]$Seconds = 45,
    [string]$GameRoot = (Split-Path -Parent $PSScriptRoot | Split-Path -Parent | Split-Path -Parent),
    [string]$SwfOverride = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'smoke_assertions.ps1')

$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$descriptorPath = if ([System.IO.Path]::IsPathRooted($Descriptor)) {
    $Descriptor
} else {
    Join-Path $GameRoot $Descriptor
}
if (-not (Test-Path -LiteralPath $descriptorPath)) { throw "descriptor missing: $descriptorPath" }
[xml]$descriptorXml = [System.IO.File]::ReadAllText($descriptorPath)
$contentNode = $descriptorXml.SelectSingleNode('/*[local-name()="application"]/*[local-name()="initialWindow"]/*[local-name()="content"]')
$idNode = $descriptorXml.SelectSingleNode('/*[local-name()="application"]/*[local-name()="id"]')
if ($null -eq $contentNode -or $null -eq $idNode) { throw 'descriptor missing id or content' }
$plan = Get-ManifestPlan (Join-Path $GameRoot 'mods\loader-manifest.txt') $contentNode.InnerText
if ($SwfOverride.Length -gt 0) {
    $override = $SwfOverride.Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($override) -or $override.Contains('..')) {
        throw 'SwfOverride must be a relative path within GameRoot'
    }
    $overridePath = Join-Path $GameRoot $override
    if (-not (Test-Path -LiteralPath $overridePath)) { throw "override SWF missing: $overridePath" }
    $routeColumn = if ($override.Contains('pfeUI')) { 4 } elseif ($override.Contains('DLC')) { 3 } else { 2 }
    if ($routeColumn -ne $plan.Column) { throw "override path routes to column $routeColumn, expected $($plan.Column)" }
    $contentNode.InnerText = $override
}
$appId = 'pfe-modloader-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$idNode.InnerText = $appId
$tempDescriptor = Join-Path $GameRoot ("app-modloader-test-$appId.xml")
if (Test-Path -LiteralPath $tempDescriptor) { throw "test descriptor already exists: $tempDescriptor" }
$store = Join-Path (Join-Path $env:APPDATA $appId) 'Local Store'
$process = $null
$startedAtUtc = [datetime]::UtcNow
$endedAtUtc = $startedAtUtc
$alive = $false

Write-Host "content=$($plan.Content); expected=$($plan.Enabled -join ', '); disabled=$($plan.Disabled -join ', ')"
Write-Host "isolated app id=$appId"
try {
    $descriptorXml.Save($tempDescriptor)
    $startedAtUtc = [datetime]::UtcNow
    $process = Start-Process -FilePath (Join-Path $GameRoot 'adl64.exe') -ArgumentList '-runtime','runtimes\air\win64',(Split-Path -Leaf $tempDescriptor),'-nodebug' -WorkingDirectory $GameRoot -WindowStyle Hidden -PassThru
    for ($second = 0; $second -lt $Seconds; $second++) {
        if ($process.HasExited) { break }
        Start-Sleep -Seconds 1
    }
    $endedAtUtc = [datetime]::UtcNow
    $alive = -not $process.HasExited
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    if (Test-Path -LiteralPath $tempDescriptor) {
        Remove-Item -LiteralPath $tempDescriptor -Force
    }
}

$result = Test-SmokeEvidence $store $startedAtUtc $endedAtUtc $plan $alive
foreach ($line in $result.Observations) { Write-Host "  $line" }
if (-not $result.Passed) {
    foreach ($failure in $result.Failures) { Write-Host "  FAIL: $failure" -ForegroundColor Red }
    throw "SMOKE FAILED for $($plan.Content); evidence remains in $store"
}
Write-Host "SMOKE PASSED for $($plan.Content)" -ForegroundColor Green
