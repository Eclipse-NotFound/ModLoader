param([switch]$Prepared,[switch]$PrepareOnly,[switch]$Installed)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Invoke-AirTest.ps1')
$taskGameRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$taskSdk='D:/RemainsMod/mods/Sandevistan/build/tools/flexsdk'
$taskJava='D:/Program Files/Adobe Animate 2024/jre/bin/java.exe'
$taskBuild=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../build/localization'))
$taskRuntime=Join-Path $taskBuild 'runtime'
$taskRunId='pfe-modsettings-languages-'+[guid]::NewGuid().ToString('N')
$taskOut=Join-Path $taskBuild ('runs/'+$taskRunId)
$taskStorage=Join-Path $env:APPDATA ($taskRunId+'/Local Store')
New-Item -ItemType Directory -Force -Path $taskRuntime,$taskOut | Out-Null
$env:AIR_HOME=$taskSdk
if(!$Prepared){
 Push-Location (Join-Path $PSScriptRoot '../../build')
 try {
 & $taskJava '-Dfile.encoding=UTF-8' -jar "$taskSdk/lib/compc.jar" "+flexlib=$taskSdk/frameworks" '+configname=air' "-source-path=$PSScriptRoot/stubs" '-include-classes=MainFE' "-output=$taskBuild/HostStub.swc"
 if($LASTEXITCODE -ne 0){throw 'Probe host declarations failed'}
 & $taskJava '-Dfile.encoding=UTF-8' -jar 'D:/Program Files/Adobe Animate 2024/Common/Configuration/ActionScript 3.0/bin/mxmlc.jar' '-library-path+=D:/Program Files/Adobe Animate 2024/Common/Configuration/ActionScript 3.0/FP11.1/playerglobal.swc' "-load-config=$PSScriptRoot/../../build/flex-config.xml" '-target-player=11.1' '-debug=true' "-source-path=$PSScriptRoot" "-external-library-path+=$taskBuild/HostStub.swc" "-output=$taskBuild/LocaleProbe.swf" "$PSScriptRoot/LocaleProbe.as"
 if($LASTEXITCODE -ne 0){throw 'Probe compile failed'}
 } finally {Pop-Location}
}
$taskCandidates=[ordered]@{
 ModLoader=@('ModLoaderMod','mods/ModLoader/build/out/ModLoaderMod.swf')
 'MoreSkills&Weapons'=@('MoreSkillsWeaponsMod','mods/MoreSkills&Weapons/build/out/localization/MoreSkillsWeaponsMod.swf')
 Sandevistan=@('SandevistanMod','D:/RemainsMod/mods/Sandevistan/build/out/SandevistanMod.swf')
 RealisticVision=@('RealisticVisionMod','mods/RealisticVision/build/RealisticVisionMod_test.swf')
 Rconnect=@('RConnectMod','mods/RConnect/build/localization/RConnectMod.swf')
 RandomRooms=@('RandomRoomsMod','mods/RandomRooms/build/RandomRooms-localization.swf')
 TDFC=@('TDFCMod','mods/TDFC/build/out/TDFCMod.swf')
 RModifier=@('LootEditorMod','mods/RModifier/build/out/localization/LootEditorMod.swf')
 LocaleProbe=@('LocaleProbe',"$taskBuild/LocaleProbe.swf")
}
$taskHashes=[ordered]@{}
$taskManifest=@()
foreach($taskMod in $taskCandidates.Keys){
 $taskEntry=$taskCandidates[$taskMod][0];$taskInput=$taskCandidates[$taskMod][1]
 if($Installed -and $taskMod -ne 'LocaleProbe'){$taskInput='mods/'+$taskMod+'/release/'+$taskEntry+'.swf'}
 if(![IO.Path]::IsPathRooted($taskInput)){$taskInput=Join-Path $taskGameRoot $taskInput}
 $taskDest=Join-Path $taskRuntime ('mods/'+$taskMod+'/release')
 New-Item -ItemType Directory -Force -Path $taskDest | Out-Null
 Copy-Item -LiteralPath $taskInput -Destination (Join-Path $taskDest ($taskEntry+'.swf'))
 $taskHashes[$taskMod]=@{input=$taskInput;sha256=(Get-FileHash -LiteralPath $taskInput).Hash}
 $taskManifest+=($taskMod+'|'+$taskEntry+'|1|0|0')
 $taskRelease=Join-Path $taskGameRoot ('mods/'+$taskMod+'/release')
 if(Test-Path -LiteralPath $taskRelease){Get-ChildItem -LiteralPath $taskRelease -File -Filter '*.txt' | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $taskDest}}
}
Get-ChildItem -LiteralPath $taskGameRoot -File | Where-Object {$_.Name -eq 'pfe.swf' -or $_.Name -match '^(sound|sprite|texture).*\.swf$' -or $_.Extension -eq '.xml'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $taskRuntime}
if(!(Test-Path -LiteralPath (Join-Path $taskRuntime 'Rooms'))){Copy-Item -LiteralPath (Join-Path $taskGameRoot 'Rooms') -Destination $taskRuntime -Recurse}
[IO.File]::WriteAllLines((Join-Path $taskRuntime 'mods/loader-manifest.txt'),$taskManifest,[Text.UTF8Encoding]::new($false))
$taskDescriptor=Join-Path $taskRuntime 'app_localization_test.xml'
$taskXml=@"
<application xmlns="http://ns.adobe.com/air/application/30.0">
<id>$taskRunId</id><versionNumber>1.0</versionNumber><filename>ModLocalizationTest</filename>
<initialWindow><content>pfe.swf</content><visible>false</visible><width>1100</width><height>700</height><renderMode>direct</renderMode></initialWindow>
</application>
"@
[IO.File]::WriteAllText($taskDescriptor,$taskXml,[Text.UTF8Encoding]::new($false))
$taskHashes.game=@{input='pfe.swf';sha256=(Get-FileHash -LiteralPath (Join-Path $taskRuntime 'pfe.swf')).Hash}
@{appId=$taskRunId;storage=$taskStorage;candidates=$taskHashes} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskOut 'inputs.json') -Encoding utf8
Set-Content -LiteralPath (Join-Path $taskBuild 'last-run.txt') -Value $taskOut -Encoding utf8
if($PrepareOnly){return}
$taskProc=$null
try{
 $taskProc=Invoke-AirTest -Executable (Join-Path $taskGameRoot 'adl64.exe') -Arguments @('-runtime',(Join-Path $taskGameRoot 'runtimes/air/win64'),$taskDescriptor) -WorkingDirectory $taskRuntime -EvidenceDirectory $taskOut -TimeoutSeconds 360
 Set-Content -LiteralPath (Join-Path $taskOut 'process-id.txt') -Value $taskProc.pid
 Copy-Item (Join-Path $taskOut 'adl-output.log') (Join-Path $taskOut 'stdout.log')
 Copy-Item (Join-Path $taskOut 'adl-error.log') (Join-Path $taskOut 'stderr.log')
 if($taskProc.timedOut){throw 'Localization probe timeout'}
 $taskResult=Join-Path $taskStorage 'results.txt'
 if(!(Test-Path -LiteralPath $taskResult)){throw ('No probe result. ADL exit '+$taskProc.ExitCode)}
 Get-Content -LiteralPath $taskResult -Tail 5
 if((Get-Content -LiteralPath $taskResult -Tail 1) -notmatch '^PASS \d+ checks$'){throw 'Localization assertions failed'}
} finally {
 if(Test-Path -LiteralPath $taskStorage){Get-ChildItem -LiteralPath $taskStorage -File | Where-Object {$_.Extension -in @('.png','.json','.txt','.log')} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $taskOut}}
 Write-Output ('Evidence: '+$taskOut)
}
