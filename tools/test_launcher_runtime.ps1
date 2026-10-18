[CmdletBinding()]
param([ValidateRange(15,90)][int]$Seconds = 35,
      [ValidateSet('ModLoaderMod','TDFCMod','none')][string[]]$Cases = @('ModLoaderMod','TDFCMod','none'))
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$game = Split-Path -Parent (Split-Path -Parent $project)
$run = Join-Path $project ('build\out\launcher-runtime\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$runtime = Join-Path $run 'game 中文 & spaces'
$launcher = Join-Path $project 'build\out\launcher\RemainsModLauncher.exe'
. (Join-Path $PSScriptRoot 'smoke_assertions.ps1')
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$guardPaths = @((Join-Path $game 'pfe.swf'), (Join-Path $game 'mods\loader-manifest.txt'), (Join-Path $project 'release\ModLoaderMod.swf'), (Join-Path $project 'supported-mods.txt'))
$before = @{}; foreach ($path in $guardPaths) { $before[$path] = (Get-FileHash -LiteralPath $path).Hash }
# Test process uses its own executable, descriptor, manifest, packages and AIR storage.
Copy-Item -LiteralPath (Join-Path $game 'adl64.exe') -Destination $runtime
Copy-Item -LiteralPath (Join-Path $game 'runtimes') -Destination $runtime -Recurse
Get-ChildItem -LiteralPath $game -File | Where-Object { $_.Name -eq 'pfe.swf' -or $_.Name -match '^(sound|sprite|texture).*\.swf$' -or $_.Extension -eq '.xml' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtime }
Copy-Item -LiteralPath (Join-Path $game 'Rooms') -Destination $runtime -Recurse
foreach ($mod in @('ModLoader','TDFC')) {
    $dest = Join-Path $runtime "mods\$mod\release"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $game "mods\$mod\release") -File | Where-Object { $_.Name -eq ($mod + 'Mod.swf') -or $_.Extension -eq '.txt' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dest }
}
Copy-Item -LiteralPath (Join-Path $project 'supported-mods.txt') -Destination (Join-Path $runtime 'mods\ModLoader\supported-mods.txt')
$results = @()
foreach ($selection in $Cases) {
    $id = 'pfe-launcher-' + [guid]::NewGuid().ToString('N')
    $descriptor = Join-Path $runtime 'application.xml'
    [IO.File]::WriteAllText($descriptor, @"
<application xmlns="http://ns.adobe.com/air/application/30.0">
<id>$id</id><versionNumber>1.0</versionNumber><filename>LauncherTest</filename>
<initialWindow><content>pfe.swf</content><visible>false</visible><width>1100</width><height>700</height><renderMode>direct</renderMode></initialWindow>
</application>
"@, [Text.UTF8Encoding]::new($false))
    $store = Join-Path $env:APPDATA "$id\Local Store"
    [string[]]$selectionArgs = if ($selection -eq 'none') { @('--none') } else { @('--only',$selection) }
    $started = [datetime]::UtcNow
    $testProcesses = @()
    try {
        & $launcher --root $runtime --no-ui @selectionArgs --launch | Tee-Object -FilePath (Join-Path $run ($selection+'-launch.txt'))
        if ($LASTEXITCODE -ne 0) { throw "Launch failed: $selection" }
        $testProcesses = @(Get-Process -Name adl64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $runtime 'adl64.exe') })
        if ($testProcesses.Count -ne 1) { throw 'Expected exactly one owned test process' }
        # A second launch must fail without changing the manifest or stopping the first process.
        $manifest = Join-Path $runtime 'mods\loader-manifest.txt'
        $manifestHash = (Get-FileHash -LiteralPath $manifest).Hash
        $duplicate = Start-Process -FilePath $launcher -ArgumentList @('--root',('"'+$runtime+'"'),'--no-ui','--none','--launch') -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $run ($selection+'-duplicate.txt'))
        if ($duplicate.ExitCode -eq 0 -or (Get-FileHash -LiteralPath $manifest).Hash -ne $manifestHash) { throw 'Duplicate launch changed selection or succeeded' }
        for ($i = 0; $i -lt $Seconds; $i++) { if ($testProcesses[0].HasExited) { break }; Start-Sleep -Seconds 1 }
        $ended = [datetime]::UtcNow
        $plan = Get-ManifestPlan $manifest 'pfe.swf'
        $evidence = Test-SmokeEvidence $store $started $ended $plan (-not $testProcesses[0].HasExited)
        $record = @{selection=$selection;appId=$id;expected=$plan.Enabled;passed=$evidence.Passed;failures=$evidence.Failures;observations=$evidence.Observations;duplicateBlocked=$true}
        $results += $record
        $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run ($selection+'-result.json')) -Encoding utf8
        if (-not $evidence.Passed) { throw ($evidence.Failures -join '; ') }
        Write-Host "PASS runtime selection=$selection; disabled entries not requested; duplicate launch blocked"
    } finally {
        foreach ($proc in $testProcesses) { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } }
    }
}
foreach ($path in $guardPaths) { if ((Get-FileHash -LiteralPath $path).Hash -ne $before[$path]) { throw "Protected input changed: $path" } }
@{passed=$true;cases=$results;protectedInputs=$before} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding utf8
Write-Host "PASS runtime tests; evidence=$run"
