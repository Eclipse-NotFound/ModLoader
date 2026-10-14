param([Parameter(Mandatory=$true)][string]$Stage,[string]$Attempt='verification')
$ErrorActionPreference='Stop'
$stageRoot=(Resolve-Path -LiteralPath $Stage).Path
if($Attempt -notmatch '^[A-Za-z0-9-]+$') {throw 'Invalid evidence name'}
$testRoot=Join-Path (Split-Path -Parent $stageRoot) $Attempt
$gameRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
New-Item -ItemType Directory -Path $testRoot | Out-Null
$installer=Join-Path $stageRoot 'Install.ps1'
$manifest=Get-Content -LiteralPath (Join-Path $stageRoot 'FILES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$checks=@()
function Check([string]$Name,[bool]$Passed) {
    $script:checks += [pscustomobject]@{name=$Name;passed=$Passed}
    if(-not $Passed) {throw ('Collection verification failed: '+$Name)}
}
# Exercise the shipped installer/restore against a disposable previous 1.02 host.
$upgradeRoot=Join-Path $testRoot 'upgrade-target'
New-Item -ItemType Directory -Path $upgradeRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $gameRoot 'pfe_before_ContinuousScene_v03_20261014-231026.swf') -Destination (Join-Path $upgradeRoot 'pfe.swf')
Copy-Item -LiteralPath (Join-Path $gameRoot 'application.xml') -Destination $upgradeRoot
$priorHash=(Get-FileHash -LiteralPath (Join-Path $upgradeRoot 'pfe.swf')).Hash
$config=Join-Path $upgradeRoot 'mods/WallBlend/release/config.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null
'{"enabled":true,"mode":"current","sentinel":"preserve-personal-settings"}' | Set-Content -LiteralPath $config -Encoding UTF8
$configHash=(Get-FileHash -LiteralPath $config).Hash
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -GameRoot $upgradeRoot
Check 'installer-exits-successfully' ($LASTEXITCODE -eq 0)
Check 'existing-config-preserved' ((Get-FileHash -LiteralPath $config).Hash -eq $configHash)
foreach($item in $manifest.files) {
    if($item.path -eq 'mods/WallBlend/release/config.json') {continue}
    Check ('installed-'+$item.path) ((Get-FileHash -LiteralPath (Join-Path $upgradeRoot $item.path)).Hash -eq $item.sha256)
}
$backup=@(Get-ChildItem -LiteralPath (Join-Path $upgradeRoot '.modpack-backups') -Directory)
Check 'one-automatic-backup' ($backup.Count -eq 1)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Restore -Backup $backup[0].FullName
Check 'restore-exits-successfully' ($LASTEXITCODE -eq 0)
Check 'previous-host-restored' ((Get-FileHash -LiteralPath (Join-Path $upgradeRoot 'pfe.swf')).Hash -eq $priorHash)
Check 'restore-preserves-config' ((Get-FileHash -LiteralPath $config).Hash -eq $configHash)
Check 'new-mod-removed-by-restore' (-not (Test-Path -LiteralPath (Join-Path $upgradeRoot 'mods/FirearmAttachments/release/FirearmAttachmentsMod.swf')))
$unsupported=Join-Path $testRoot 'unsupported-target'
New-Item -ItemType Directory -Path $unsupported | Out-Null
'unsupported' | Set-Content -LiteralPath (Join-Path $unsupported 'pfe.swf')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -GameRoot $unsupported 2>&1 | Out-File -LiteralPath (Join-Path $testRoot 'unsupported.log')
Check 'unknown-host-rejected' ($LASTEXITCODE -ne 0)
Check 'unknown-host-untouched' ((Get-Content -LiteralPath (Join-Path $unsupported 'pfe.swf') -Raw).Trim() -eq 'unsupported')
Check 'unknown-host-no-backup-or-write' (-not (Test-Path -LiteralPath (Join-Path $unsupported '.modpack-backups')))
# Launch exact package files under a new AIR identity. No test driver is loaded.
$runtime=Join-Path $testRoot 'runtime'
New-Item -ItemType Directory -Path $runtime | Out-Null
Copy-Item -LiteralPath (Join-Path $stageRoot 'payload/pfe.swf') -Destination $runtime
Copy-Item -LiteralPath (Join-Path $stageRoot 'payload/mods') -Destination $runtime -Recurse
foreach($pattern in @('texture*.swf','sprite*.swf','sound*.swf','text_*.xml','rooms.xml','lang.xml')) {
    foreach($source in Get-ChildItem -LiteralPath $gameRoot -Filter $pattern -File) {
        Copy-Item -LiteralPath $source.FullName -Destination $runtime
    }
}
foreach($folder in @('Music','Rooms')) {
    Copy-Item -LiteralPath (Join-Path $gameRoot $folder) -Destination $runtime -Recurse
}
# Test the exact distributed scanner against the isolated files, including its
# version flags and disabled legacy/RModifier entries; no live manifest is read.
& (Join-Path $runtime 'mods/ModLoader/RemainsModScanner.exe') --no-ui --root $runtime | Out-File -LiteralPath (Join-Path $testRoot 'scanner.log')
Check 'scanner-exits-successfully' ($LASTEXITCODE -eq 0)
$manifestLines=@(Get-Content -LiteralPath (Join-Path $runtime 'mods/loader-manifest.txt') | Where-Object {$_ -and -not $_.StartsWith('#')})
Check 'scanner-enables-ten-102-components' (@($manifestLines | Where-Object {$_ -match '\|1\|0\|0$'}).Count -eq 10)
Check 'scanner-does-not-enable-dlc' (@($manifestLines | Where-Object {$_ -match '\|[01]\|1\||\|[01]\|[01]\|1$'}).Count -eq 0)
Check 'scanner-disables-rmodifier' ($manifestLines -contains 'RModifier|LootEditorMod|0|0|0')
Check 'scanner-disables-old-settings' ($manifestLines -contains 'ModSettings|ModSettingsMod|0|0|0')
# Restore the unmodified, frozen manifest for the runtime smoke.
Copy-Item -LiteralPath (Join-Path $stageRoot 'payload/mods/loader-manifest.txt') -Destination (Join-Path $runtime 'mods/loader-manifest.txt') -Force
$appId='pfe-modsettings-distribution-'+(Get-Date -Format 'yyyyMMddHHmmssfff')
$descriptor=Join-Path $runtime 'application.xml'
@"
<?xml version="1.0" encoding="UTF-8"?>
<application xmlns="http://ns.adobe.com/air/application/30.0"><id>$appId</id><versionNumber>1.0</versionNumber><filename>DistributionSmoke</filename><initialWindow><content>pfe.swf</content><visible>false</visible><width>1280</width><height>800</height><renderMode>direct</renderMode></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>
"@ | Set-Content -LiteralPath $descriptor -Encoding UTF8
$process=$null
$store=Join-Path $env:APPDATA ($appId+'/Local Store')
$start=[datetime]::UtcNow
try {
    $process=Start-Process -FilePath (Join-Path $gameRoot 'adl64.exe') -ArgumentList @('-runtime',('"'+(Join-Path $gameRoot 'runtimes/air/win64')+'"'),('"'+$descriptor+'"'),('"'+$runtime+'"')) -WorkingDirectory $runtime -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'stdout.log') -RedirectStandardError (Join-Path $testRoot 'stderr.log')
    Write-Output ('Isolated distribution startup PID '+$process.Id+' / '+$appId)
    $process.WaitForExit(50000) | Out-Null
    Check 'game-alive-after-50-seconds' (-not $process.HasExited)
    $statusFiles=@(Get-ChildItem -LiteralPath (Join-Path $store '#SharedObjects') -Recurse -Filter 'ModLoader.sol' -File | Where-Object {$_.LastWriteTimeUtc -ge $start})
    Check 'exactly-one-fresh-loader-status' ($statusFiles.Count -eq 1)
    $status=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($statusFiles[0].FullName))
    $runIds=@([regex]::Matches($status,'run_\d{13}_\d+') | ForEach-Object {$_.Value} | Select-Object -Unique)
    Check 'one-fresh-loader-run-id' ($runIds.Count -eq 1)
    $runMs=[long]([regex]::Match($runIds[0],'run_(\d{13})_').Groups[1].Value)
    Check 'loader-run-id-matches-launch-time' ($runMs -ge ([DateTimeOffset]$start).ToUnixTimeMilliseconds() -and $runMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    foreach($row in Get-Content -LiteralPath (Join-Path $runtime 'mods/loader-manifest.txt')) {
        if($row.StartsWith('#') -or -not $row) {continue}
        $fields=$row.Split('|'); $entry=$fields[1]; $enabled=$fields[2] -eq '1'
        foreach($prefix in @('requested_','ok_')) {
            $present=$status -match ([regex]::Escape($prefix+$entry)+'(?![A-Za-z0-9_])')
            Check ($prefix+$entry+'-matches-enable-flag') ($present -eq $enabled)
        }
    }
    Check 'no-loader-errors' ($status -notmatch 'err_[A-Za-z0-9_]+')
    # Sandy intentionally suppresses its own log unless diaglog=1. Verify its
    # native requested/ok keys above without shipping or enabling diagnostic config.
    Check 'sandy-default-has-no-diagnostic-config' (-not (Test-Path -LiteralPath (Join-Path $runtime 'mods/Sandevistan/release/config.txt')))
    foreach($spec in @(@('ContinuousScene.log','v0.3.0 loaded','heartbeat'),@('RVision.log','init ok v0.30.4-scene','tick 181'),@('WallBlend.log','v0.4.2 loaded','heartbeat'),@('FirearmAttachments.log','v0.1.0 loaded','eight guns'),@('ModSettings.log','runtime v2.3.0 loaded','frames=600'))) {
        $log=[string](Get-Content -LiteralPath (Join-Path $store $spec[0]) -Raw)
        Check ('production-log-'+$spec[0]) ($log.Contains($spec[1]) -and $log.Contains($spec[2]) -and $log -notmatch '\bERROR\b|"failed":true')
    }
    foreach($name in @('RConnect.log','RandomRooms_diag.log','tdfc.log')) {
        $file=Get-Item -LiteralPath (Join-Path $store $name)
        Check ('fresh-log-'+$name) ($file.LastWriteTimeUtc -ge $start -and $file.Length -gt 0)
    }
    Check 'no-loot-editor-log' (-not (Test-Path -LiteralPath (Join-Path $store 'LootEditor.log')))
    $errors=[string](Get-Content -LiteralPath (Join-Path $testRoot 'stderr.log') -Raw)
    Check 'no-uncaught-air-errors' ($errors -notmatch '(TypeError|ReferenceError|VerifyError): Error #')
} finally {
    if($process -and -not $process.HasExited) {$process.Kill();$process.WaitForExit()}
    if(Test-Path -LiteralPath $store) {Copy-Item -LiteralPath $store -Destination (Join-Path $testRoot 'isolated-store') -Recurse}
    [pscustomobject]@{appId=$appId;passed=(@($checks|Where-Object {-not $_.passed}).Count -eq 0);checks=$checks;scope='Installer/restore/scan plus exact-package native startup; no full gameplay or network certification'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $testRoot 'result.json') -Encoding UTF8
}
Write-Output ('PASSED: '+$checks.Count+' checks. Evidence: '+$testRoot)
