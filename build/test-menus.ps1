param([ValidateSet('all','without-msw')][string]$Scenario='all',
    [string]$AnimateRoot='D:\Program Files\Adobe Animate 2024',
    [switch]$InstalledHost, [switch]$SmokeOnly,
    [string]$MigrateFrom='',
    [ValidateSet('MenuProbe','GroupProbe')][string]$Probe='MenuProbe',
    [string]$MSWSwf='', [string]$HostSwf='',
    [ValidatePattern('^[a-z0-9-]*$')][string]$RunLabel='')
$ErrorActionPreference='Stop'
$label=if($RunLabel){$RunLabel}else{$Scenario}
$probeOutput='out/'+$Probe+'-'+$label+'.swf'
Push-Location $PSScriptRoot
try {
    & (Join-Path $AnimateRoot 'jre\bin\java.exe') '-Dfile.encoding=UTF-8' -jar (Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\bin\mxmlc.jar') ("-library-path+="+(Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\FP11.1\playerglobal.swc')) '-target-player=11.1' '-debug=true' '-source-path+=tests' ('-output='+$probeOutput) ('tests/'+$Probe+'.as')
    if($LASTEXITCODE -ne 0){throw 'Menu probe compilation failed'}
} finally {Pop-Location}
$gameRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$runtime=Join-Path $PSScriptRoot ('test-runtime\menus-'+$label)
$out=Join-Path $PSScriptRoot ('out\menus\'+$label)
New-Item -ItemType Directory -Force $runtime,$out | Out-Null
$mapping=@{ModLoader='ModLoaderMod.swf';ModSettings='ModSettingsMod.swf';'MoreSkills&Weapons'='MoreSkillsWeaponsMod.swf';Sandevistan='SandevistanMod.swf';RealisticVision='RealisticVisionMod.swf';TDFC='TDFCMod.swf';RConnect='RConnectMod.swf';RandomRooms='RandomRoomsMod.swf'}
$candidates=@{}
if(!$InstalledHost){$candidates.ModLoader=Join-Path $PSScriptRoot 'out\ModLoaderMod.swf'}
if($MSWSwf){$candidates['MoreSkills&Weapons']=(Resolve-Path -LiteralPath $MSWSwf).Path}
if($HostSwf){$candidates.ModLoader=(Resolve-Path -LiteralPath $HostSwf).Path}
if($MigrateFrom){
    if($SmokeOnly -or $Scenario -ne 'all'){throw 'MigrateFrom requires full all scenario'}
    $candidates.ModSettings=(Resolve-Path -LiteralPath $MigrateFrom).Path
}
$hashes=@{}
foreach($mod in $mapping.Keys){
    $dest=Join-Path $runtime ('mods\'+$mod+'\release')
    $release=Join-Path $gameRoot ('mods\'+$mod+'\release')
    New-Item -ItemType Directory -Force $dest | Out-Null
    if(Test-Path -LiteralPath $release){Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Name -eq $mapping[$mod] -or $_.Extension -in @('.txt','.mp3') } | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $dest}}
    if($candidates.ContainsKey($mod)){Copy-Item -LiteralPath $candidates[$mod] -Destination (Join-Path $dest $mapping[$mod])}
    $swf=Join-Path $dest $mapping[$mod]
    if(Test-Path -LiteralPath $swf){$hashes[$mod]=(Get-FileHash -LiteralPath $swf).Hash}
}
Get-ChildItem -LiteralPath $gameRoot -File | Where-Object { $_.Name -eq 'pfe.swf' -or $_.Name -match '^(sound|sprite|texture).*\.swf$' -or $_.Extension -eq '.xml' } | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $runtime}
if(!(Test-Path -LiteralPath (Join-Path $runtime 'Rooms'))){Copy-Item -LiteralPath (Join-Path $gameRoot 'Rooms') -Destination $runtime -Recurse}
# The installed generic loader reads the private manifest; the game SWF stays byte-identical.
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\supported-mods.txt') -Destination (Join-Path $runtime 'mods\ModLoader\supported-mods.txt')
& (Join-Path $PSScriptRoot '..\RemainsModScanner.exe') --no-ui --root $runtime | Out-Null
if($LASTEXITCODE -ne 0){throw 'Private manifest scan failed'}
$manifest=Get-Content -LiteralPath (Join-Path $runtime 'mods\loader-manifest.txt')
if($Scenario -eq 'without-msw'){$manifest=@($manifest | Where-Object {$_ -notmatch '^MoreSkills&Weapons\|'})}
$manifest+= "$Probe|$Probe|1|0|0"
[IO.File]::WriteAllLines((Join-Path $runtime 'mods\loader-manifest.txt'),$manifest,[Text.UTF8Encoding]::new($false))
$probeDir=Join-Path $runtime ('mods\'+$Probe+'\release')
New-Item -ItemType Directory -Force $probeDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $probeOutput) -Destination (Join-Path $probeDir ($Probe+'.swf'))
$hashes.pfe=(Get-FileHash -LiteralPath (Join-Path $runtime 'pfe.swf')).Hash
$hashes.probe=(Get-FileHash -LiteralPath (Join-Path $probeDir ($Probe+'.swf'))).Hash
$testId='pfe-modsettings-menus-'+[guid]::NewGuid().ToString('N')
$descriptor=Join-Path $runtime 'app_modsettings_test.xml'
@"
<application xmlns="http://ns.adobe.com/air/application/30.0">
<id>$testId</id><versionNumber>1.0</versionNumber><filename>SettingsMenusTest</filename>
<initialWindow><content>pfe.swf</content><visible>false</visible><width>1100</width><height>700</height><renderMode>direct</renderMode></initialWindow>
</application>
"@ | Set-Content -LiteralPath $descriptor -Encoding utf8
$storage=Join-Path $env:APPDATA "$testId\Local Store"
@{scenario=$Scenario;appId=$testId;storage=$storage;hashes=$hashes;installedClients=$true;installedHost=[bool]$InstalledHost;migration=[bool]$MigrateFrom} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'run.json') -Encoding utf8
$runs=if($SmokeOnly){@('smoke')}elseif($Scenario -eq 'without-msw'){@('first','reload')}else{@('first','reload','final')}
try {
    foreach($run in $runs){
        $legacy=$MigrateFrom -and $run -eq 'first'
        $activeManifest=if($legacy){@($manifest | ForEach-Object {$_ -replace '^ModLoader\|ModLoaderMod\|1\|0\|0$','ModLoader|ModLoaderMod|0|0|0' -replace '^ModSettings\|ModSettingsMod\|0\|0\|0$','ModSettings|ModSettingsMod|1|0|0'})}else{$manifest}
        [IO.File]::WriteAllLines((Join-Path $runtime 'mods\loader-manifest.txt'),$activeManifest,[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $runtime 'host-kind.txt'),$(if($legacy){'legacy'}else{'ModLoader'}))
        [IO.File]::WriteAllText((Join-Path $runtime 'scenario.txt'),$Scenario+':'+$run)
        $proc=Start-Process -FilePath (Join-Path $gameRoot 'adl64.exe') -ArgumentList @('-runtime',('"'+(Join-Path $gameRoot 'runtimes\air\win64')+'"'),('"'+$descriptor+'"')) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $out ($run+'-stdout.log')) -RedirectStandardError (Join-Path $out ($run+'-stderr.log')) -PassThru
        for($i=0;$i -lt 12;$i++){
            if($proc.WaitForExit(10000)){break}
            if(Test-Path -LiteralPath (Join-Path $storage 'heartbeat.txt')){Get-Content -LiteralPath (Join-Path $storage 'heartbeat.txt') -TotalCount 1}
        }
        if(!$proc.HasExited){throw "Menu test timeout: $run"}
        $statusFiles=@(Get-ChildItem -LiteralPath (Join-Path $storage '#SharedObjects') -Filter 'ModLoader.sol' -Recurse -File)
        if($statusFiles.Count -ne 1){throw 'Missing unique loader status'}
        $status=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($statusFiles[0].FullName))
        $active=if($legacy){'ModSettingsMod'}else{'ModLoaderMod'}
        $disabled=if($legacy){'ModLoaderMod'}else{'ModSettingsMod'}
        if($status -notmatch ('ok_'+$active+'(?![A-Za-z0-9_])') -or $status -match ('(requested_|ok_)'+$disabled+'(?![A-Za-z0-9_])') -or $status -match 'err_'){throw 'Host loading/duplicate-host status failed'}
        Copy-Item -LiteralPath $statusFiles[0].FullName -Destination (Join-Path $out ($run+'-ModLoader.sol'))
        $lines=Get-Content -LiteralPath (Join-Path $storage ($run+'-results.txt'))
        $lines | Select-Object -Last 12
        if($lines[-1] -notmatch '^PASS \d+ assertions$'){throw "Menu assertions failed: $run"}
    }
} finally {
    if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id}
    if(Test-Path -LiteralPath $storage){Get-ChildItem -LiteralPath $storage -File | Where-Object { $_.Extension -in @('.png','.log','.txt') } | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $out}}
    if(Test-Path -LiteralPath $descriptor){Remove-Item -LiteralPath $descriptor}
}
