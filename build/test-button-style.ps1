param([ValidatePattern('^[a-z0-9-]+$')][string]$RunLabel='baseline',
    [string]$AnimateRoot='D:\Program Files\Adobe Animate 2024',
    [switch]$CandidateHost)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    & (Join-Path $AnimateRoot 'jre\bin\java.exe') '-Dfile.encoding=UTF-8' -jar (Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\bin\mxmlc.jar') ("-library-path+="+(Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\FP11.1\playerglobal.swc')) '-target-player=11.1' '-debug=true' '-source-path+=tests' '-output=out/ButtonStyleProbe.swf' 'tests/ButtonStyleProbe.as'
    if($LASTEXITCODE -ne 0){throw 'Button probe compilation failed'}
} finally {Pop-Location}
$gameRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$runtime=Join-Path $PSScriptRoot 'test-runtime\button-style'
$out=Join-Path $PSScriptRoot ('out\button-style\'+$RunLabel)
New-Item -ItemType Directory -Force $runtime,$out | Out-Null
Get-ChildItem -LiteralPath $gameRoot -File | Where-Object { $_.Name -eq 'pfe.swf' -or $_.Name -match '^(sound|sprite|texture).*\.swf$' -or $_.Extension -eq '.xml' } | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $runtime}
if(!(Test-Path -LiteralPath (Join-Path $runtime 'Rooms'))){Copy-Item -LiteralPath (Join-Path $gameRoot 'Rooms') -Destination $runtime -Recurse}
$hostDir=Join-Path $runtime 'mods\ModLoader\release'
$probeDir=Join-Path $runtime 'mods\ButtonStyleProbe\release'
New-Item -ItemType Directory -Force $hostDir,$probeDir | Out-Null
$hostSource=if($CandidateHost){Join-Path $PSScriptRoot 'out\ModLoaderMod.swf'}else{Join-Path $PSScriptRoot '..\release\ModLoaderMod.swf'}
Copy-Item -LiteralPath $hostSource -Destination $hostDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'out\ButtonStyleProbe.swf') -Destination $probeDir
[IO.File]::WriteAllLines((Join-Path $runtime 'mods\loader-manifest.txt'),@('ModLoader|ModLoaderMod|1|0|0','ModSettings|ModSettingsMod|0|0|0','ButtonStyleProbe|ButtonStyleProbe|1|0|0'),[Text.UTF8Encoding]::new($false))
$testId='pfe-modsettings-button-'+[guid]::NewGuid().ToString('N')
$descriptor=Join-Path $runtime 'app_button_test.xml'
@"
<application xmlns="http://ns.adobe.com/air/application/30.0">
<id>$testId</id><versionNumber>1.0</versionNumber><filename>ButtonStyleTest</filename>
<initialWindow><content>pfe.swf</content><visible>false</visible><width>1100</width><height>700</height><renderMode>direct</renderMode></initialWindow>
</application>
"@ | Set-Content -LiteralPath $descriptor -Encoding utf8
$storage=Join-Path $env:APPDATA "$testId\Local Store"
@{appId=$testId;storage=$storage;hostHash=(Get-FileHash -LiteralPath (Join-Path $hostDir 'ModLoaderMod.swf')).Hash;pfeHash=(Get-FileHash -LiteralPath (Join-Path $runtime 'pfe.swf')).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'run.json') -Encoding utf8
try {
    $proc=Start-Process -FilePath (Join-Path $gameRoot 'adl64.exe') -ArgumentList @('-runtime',('"'+(Join-Path $gameRoot 'runtimes\air\win64')+'"'),('"'+$descriptor+'"')) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $out 'stdout.log') -RedirectStandardError (Join-Path $out 'stderr.log') -PassThru
    for($i=0;$i -lt 18;$i++) { if($proc.WaitForExit(10000)){break} }
    if(!$proc.HasExited){throw 'Button style probe timed out'}
    Get-Content -LiteralPath (Join-Path $storage 'results.txt')
    if($proc.ExitCode -ne 0){throw 'Button style or page navigation assertions failed'}
} finally {
    if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id}
    if(Test-Path -LiteralPath $storage){Get-ChildItem -LiteralPath $storage -File | Where-Object { $_.Extension -in @('.png','.log','.txt','.json') } | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $out}}
    if(Test-Path -LiteralPath $descriptor){Remove-Item -LiteralPath $descriptor}
}
