# Offline regression checks; no game process and no game SWF writes.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'patch_game_swfs.ps1') -FunctionsOnly
. (Join-Path $PSScriptRoot 'smoke_assertions.ps1')

function Expect([bool]$condition, [string]$message) {
    if (-not $condition) { throw "TEST FAILED: $message" }
}
function Expect-Throw([scriptblock]$action, [string]$message) {
    $threw = $false
    try { & $action | Out-Null } catch { $threw = $true }
    Expect $threw $message
}

$legacySource = @'
package
{
   import flash.net.URLRequest;
   import flash.ui.ContextMenu;
   import flash.utils.getQualifiedClassName;
   public class MainFE
   {
      internal var mainMenu:MainMenu;
      internal function onEnterFrameLoader(param1:Event) : *
      {
         this.mainMenu = new MainMenu(this);
            this.loadModSettingsMod();
            this.loadSandevistanMod();
            this.loadRConnectMod();
            this.loadRVisionMod();
            this.loadMSWMod();
            this.loadTDFCMod();
            this.loadRandomRoomsMod();
      }
   }
}
'@
$converted = Transform-MainFe $legacySource 'pfe.swf'
Expect ($converted.RemovedCalls -eq 7) 'all seven legacy calls removed'
Expect (-not $converted.AlreadyPatched) 'legacy source must be changed'
Expect ((Transform-MainFe $converted.Text 'pfe.swf').AlreadyPatched) 'v2 rerun must verify and skip'
$oddIndent = $legacySource.Replace('            this.loadSandevistanMod();','         this.loadSandevistanMod();')
Expect ((Transform-MainFe $oddIndent 'pfe.swf').RemovedCalls -eq 7) 'indentation change still removed'
$partial = $legacySource.Replace('            this.loadSandevistanMod();','')
Expect-Throw { Transform-MainFe $partial 'pfe.swf' } 'partial old call set must fail'
$brokenV2 = $legacySource.Replace('      internal var mainMenu:MainMenu;',
    '      internal var mainMenu:MainMenu;' + [Environment]::NewLine + '      internal var modLoaderStatusReady:Boolean;')
Expect-Throw { Transform-MainFe $brokenV2 'pfe.swf' } 'marker alone must not skip validation'

$manifest = Join-Path $GameRoot 'mods\loader-manifest.txt'
Assert-Manifest $manifest
$plan = Get-ManifestPlan $manifest 'DLC/pfeUI.swf'
Expect ($plan.Enabled.Count -eq 2 -and $plan.Disabled -contains 'ModSettingsMod') '1.04 matrix'
Expect-Throw { Get-ManifestPlan $manifest 'unknown.swf' } 'unknown descriptor content'

$testDir = Join-Path $WorkDir ('test-loader-' + [guid]::NewGuid().ToString('N'))
$workFull = [IO.Path]::GetFullPath($WorkDir).TrimEnd([IO.Path]::DirectorySeparatorChar)
$testFull = [IO.Path]::GetFullPath($testDir)
Expect ($testFull.StartsWith($workFull + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) 'test directory must stay inside work'
New-Item -ItemType Directory -Force -Path (Join-Path $testDir '#SharedObjects') | Out-Null
try {
    $started = [datetime]::UtcNow.AddSeconds(-10)
    $ended = [datetime]::UtcNow.AddSeconds(2)
    $runMs = ([DateTimeOffset][datetime]::UtcNow.AddSeconds(-5)).ToUnixTimeMilliseconds()
    $runId = 'run_' + $runMs + '_123'
    $solPath = Join-Path (Join-Path $testDir '#SharedObjects') 'ModLoader.sol'
    $goodStatus = "session $runId boot_start boot requested_SandevistanMod ok_SandevistanMod requested_RConnectMod ok_RConnectMod"
    [IO.File]::WriteAllText($solPath,$goodStatus)
    [IO.File]::SetLastWriteTimeUtc($solPath,[datetime]::UtcNow)
    foreach ($name in @('sandy_modlog.txt','RConnect.log')) {
        $logPath = Join-Path $testDir $name
        [IO.File]::WriteAllText($logPath,'fresh init')
        [IO.File]::SetLastWriteTimeUtc($logPath,[datetime]::UtcNow)
    }
    Expect (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed 'fresh evidence passes'
    Remove-Item -LiteralPath $solPath
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed) 'missing status fails'
    [IO.File]::WriteAllText($solPath,$goodStatus)
    [IO.File]::SetLastWriteTimeUtc($solPath,[datetime]::UtcNow)
    [IO.File]::WriteAllText($solPath,$goodStatus.Replace(' requested_SandevistanMod',' X1requested_SandevistanMod'))
    Expect (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed 'adjacent binary key still found'
    [IO.File]::WriteAllText($solPath,$goodStatus)
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $false).Passed) 'early exit fails'
    [IO.File]::WriteAllText($solPath,($goodStatus + '1err_RConnectMod'))
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed) 'error key fails'
    [IO.File]::WriteAllText($solPath,($goodStatus + ' requested_ModSettingsMod'))
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed) 'disabled mod request fails'
    [IO.File]::WriteAllText($solPath,($goodStatus + ' run_1111111111111_9'))
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed) 'stale run id fails'
    [IO.File]::WriteAllText($solPath,$goodStatus)
    [IO.File]::SetLastWriteTimeUtc((Join-Path $testDir 'RConnect.log'),$started.AddSeconds(-1))
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed) 'stale enabled log fails'
    [IO.File]::SetLastWriteTimeUtc((Join-Path $testDir 'RConnect.log'),[datetime]::UtcNow)
    [IO.File]::WriteAllText((Join-Path $testDir 'ModSettings.log'),'unexpected init')
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $plan $true).Passed) 'fresh disabled log fails'
    $mergedPlan=[pscustomobject]@{Enabled=@('ModLoaderMod');Disabled=@('ModSettingsMod')}
    $mergedStatus="session $runId boot_start boot requested_ModLoaderMod ok_ModLoaderMod"
    [IO.File]::WriteAllText($solPath,$mergedStatus)
    Expect (Test-SmokeEvidence $testDir $started $ended $mergedPlan $true).Passed 'new host owns inherited log without reviving disabled old host'
    [IO.File]::WriteAllText($solPath,($mergedStatus+' requested_ModSettingsMod ok_ModSettingsMod'))
    Expect (-not (Test-SmokeEvidence $testDir $started $ended $mergedPlan $true).Passed) 'shared log never hides duplicate host loading'
    $badManifest = Join-Path $testDir 'bad-manifest.txt'
    [IO.File]::WriteAllText($badManifest,'Bad|BadMod|1|0')
    Expect-Throw { Assert-Manifest $badManifest } 'patch rejects malformed manifest'
    Expect-Throw { Get-ManifestPlan $badManifest 'pfe.swf' } 'smoke rejects malformed manifest'
    $originalGameRoot = $GameRoot
    try {
        $GameRoot = $testFull
        Expect-Throw { Patch-One 'pfe.swf' } 'missing target fails before export'
    } finally { $GameRoot = $originalGameRoot }
} finally {
    Remove-Item -LiteralPath $testFull -Recurse -Force
}
Write-Host 'offline loader checks passed'
