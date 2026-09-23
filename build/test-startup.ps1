param([switch]$InstalledHost,[switch]$NormalOnly,[string]$AnimateRoot='D:\Program Files\Adobe Animate 2024')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$gameRoot=[IO.Path]::GetFullPath((Join-Path $project '..\..'))
. (Join-Path $project 'tools\smoke_assertions.ps1')
Push-Location $PSScriptRoot
try {
    foreach($probe in @(@('tests/StartupProbe.as','out/StartupProbe.swf'),@('tests/failure/ModLoaderMod.as','out/FailedRuntime.swf'))){
        & (Join-Path $AnimateRoot 'jre\bin\java.exe') '-Dfile.encoding=UTF-8' -jar (Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\bin\mxmlc.jar') ("-library-path+="+(Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\FP11.1\playerglobal.swc')) '-target-player=11.1' '-debug=true' ('-output='+$probe[1]) $probe[0]
        if($LASTEXITCODE -ne 0){throw 'Startup probe compilation failed'}
    }
} finally {Pop-Location}
$runtime=Join-Path $PSScriptRoot 'test-runtime\startup'
New-Item -ItemType Directory -Force $runtime,(Join-Path $runtime 'DLC') | Out-Null
foreach($dir in @('','DLC')){
    Get-ChildItem -LiteralPath (Join-Path $gameRoot $dir) -File | Where-Object {$_.Name -in @('pfe.swf','pfeUI.swf') -or $_.Name -match '^(sound|sprite|texture).*\.swf$' -or $_.Extension -eq '.xml'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $runtime $dir)}
}
if(!(Test-Path -LiteralPath (Join-Path $runtime 'Rooms'))){Copy-Item -LiteralPath (Join-Path $gameRoot 'Rooms') -Destination $runtime -Recurse}
$mapping=@{ModLoader='ModLoaderMod.swf';ModSettings='ModSettingsMod.swf';'MoreSkills&Weapons'='MoreSkillsWeaponsMod.swf';Sandevistan='SandevistanMod.swf';RealisticVision='RealisticVisionMod.swf';TDFC='TDFCMod.swf';RConnect='RConnectMod.swf';RandomRooms='RandomRoomsMod.swf'}
foreach($mod in $mapping.Keys){
    $dest=Join-Path $runtime ('mods\'+$mod+'\release');New-Item -ItemType Directory -Force $dest | Out-Null
    $release=Join-Path $gameRoot ('mods\'+$mod+'\release')
    if(Test-Path -LiteralPath $release){Get-ChildItem -LiteralPath $release -File | Where-Object {$_.Name -eq $mapping[$mod] -or $_.Extension -in @('.txt','.mp3')} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $dest}}
}
$hostSource=if($InstalledHost){Join-Path $project 'release\ModLoaderMod.swf'}else{Join-Path $PSScriptRoot 'out\ModLoaderMod.swf'}
$hostDest=Join-Path $runtime 'mods\ModLoader\release\ModLoaderMod.swf'
Copy-Item -LiteralPath $hostSource -Destination $hostDest
Copy-Item -LiteralPath (Join-Path $project 'supported-mods.txt') -Destination (Join-Path $runtime 'mods\ModLoader\supported-mods.txt')
& (Join-Path $project 'RemainsModScanner.exe') --root $runtime --no-ui | Out-Null
if($LASTEXITCODE -ne 0){throw 'Startup manifest scan failed'}
$manifestPath=Join-Path $runtime 'mods\loader-manifest.txt'
$manifest=@(Get-Content -LiteralPath $manifestPath)+'StartupProbe|StartupProbe|1|1|1'
[IO.File]::WriteAllLines($manifestPath,$manifest,[Text.UTF8Encoding]::new($false))
$probeDir=Join-Path $runtime 'mods\StartupProbe\release';New-Item -ItemType Directory -Force $probeDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'out\StartupProbe.swf') -Destination $probeDir
$cases=@(@{label='102';content='pfe.swf';failure=''},@{label='103';content='DLC/pfe.swf';failure=''},@{label='104';content='DLC/pfeUI.swf';failure=''})
if(!$NormalOnly){$cases+=@(@{label='missing';content='pfe.swf';failure='missing'},@{label='init-failure';content='pfe.swf';failure='init'})}
foreach($case in $cases){
    Copy-Item -LiteralPath $hostSource -Destination $hostDest -Force
    if($case.failure -eq 'missing'){Remove-Item -LiteralPath $hostDest}
    if($case.failure -eq 'init'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'out\FailedRuntime.swf') -Destination $hostDest -Force}
    $plan=Get-ManifestPlan $manifestPath $case.content
    @{content=$case.content;enabled=$plan.Enabled;disabled=$plan.Disabled;failure=$case.failure} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtime 'startup-scenario.json') -Encoding utf8
    $appId='pfe-modsettings-startup-'+[guid]::NewGuid().ToString('N')
    $descriptor=Join-Path $runtime 'app_startup_test.xml'
    $label=$(if($InstalledHost){'installed-'}else{'candidate-'})+$case.label
    $out=Join-Path $PSScriptRoot ('out\startup\'+$label);New-Item -ItemType Directory -Force $out | Out-Null
    $storage=Join-Path $env:APPDATA "$appId\Local Store"
    @"
<application xmlns="http://ns.adobe.com/air/application/30.0"><id>$appId</id><versionNumber>1.0</versionNumber><filename>StartupTest</filename><initialWindow><content>$($case.content)</content><visible>false</visible><width>1100</width><height>700</height><renderMode>direct</renderMode></initialWindow></application>
"@ | Set-Content -LiteralPath $descriptor -Encoding utf8
    @{appId=$appId;storage=$storage;case=$case;hostHash=(Get-FileHash -LiteralPath $hostSource).Hash;gameHash=(Get-FileHash -LiteralPath (Join-Path $runtime $case.content)).Hash} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'run.json') -Encoding utf8
    $proc=$null
    try {
        $proc=Start-Process -FilePath (Join-Path $gameRoot 'adl64.exe') -ArgumentList @('-runtime',('"'+(Join-Path $gameRoot 'runtimes\air\win64')+'"'),('"'+$descriptor+'"')) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $out 'stdout.log') -RedirectStandardError (Join-Path $out 'stderr.log') -PassThru
        for($i=0;$i -lt 8;$i++){if($proc.WaitForExit(10000)){break}}
        if(!$proc.HasExited){throw "Startup timeout: $label"}
        $lines=Get-Content -LiteralPath (Join-Path $storage 'startup-results.txt')
        Write-Output ($label+': '+$lines[-1])
        if($proc.ExitCode -ne 0 -or $lines[-1] -notmatch '^PASS \d+ assertions$'){throw "Startup assertions failed: $label"}
    } finally {
        if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id}
        if(Test-Path -LiteralPath $storage){Get-ChildItem -LiteralPath $storage -File | Where-Object {$_.Extension -in @('.txt','.log','.json')} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $out}}
        if(Test-Path -LiteralPath $descriptor){Remove-Item -LiteralPath $descriptor}
    }
}
