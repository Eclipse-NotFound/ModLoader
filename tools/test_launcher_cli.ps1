$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $project 'build\out\launcher\RemainsModLauncher.exe'
$scanner = Join-Path $project 'build\out\launcher\RemainsModScanner.exe'
$out = Join-Path $project ('build\out\launcher-cli\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$root = Join-Path $out '游戏 中文 & path'
$loader = Join-Path $root 'mods\ModLoader'
New-Item -ItemType Directory -Force -Path $loader | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'supported-mods.txt') -Destination $loader
foreach ($pair in @(@('ModLoader','ModLoaderMod'),@('TDFC','TDFCMod'),@('新模组','FreshMod'))) {
    $release = Join-Path $root ('mods\'+$pair[0]+'\release')
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $release ($pair[1]+'.swf')), [byte[]](70,87,83,9,8,0,0,0))
}
$script:checks = 0
function Check([bool]$ok,[string]$message) { if (-not $ok) { throw $message }; $script:checks++; Write-Host "PASS CLI $script:checks`: $message" }
function Run([string[]]$arguments,[int]$expected=0) {
    $stdout = Join-Path $out 'stdout.json'
    $stderr = Join-Path $out 'stderr.txt'
    $cmdArgs = @('--root',('"'+$root+'"'),'--version','1.02','--no-ui') + $arguments
    $p = Start-Process -FilePath $launcher -ArgumentList $cmdArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Check ($p.ExitCode -eq $expected) ('exit '+$expected+': '+($arguments -join ' '))
    if ($expected -eq 0 -and $arguments -contains '--json') { return Get-Content -LiteralPath $stdout -Raw -Encoding utf8 | ConvertFrom-Json }
}
$manifest = Join-Path $root 'mods\loader-manifest.txt'
$list = Run @('--list','--json')
Check ($list.selected.Count -eq 3) 'read-only list discovers three packages'
Check ($list.mods[-1].directory -eq '新模组') 'UTF-8 JSON survives redirect'
Check (-not (Test-Path -LiteralPath $manifest)) 'list does not save'
Run @('--only','TDFCMod')
$list = Run @('--list','--json')
Check ($list.selected.Count -eq 1 -and $list.selected[0] -eq 'TDFCMod') 'CLI selection survives process restart'
$hash = (Get-FileHash -LiteralPath $manifest).Hash
$preview = Run @('--all','--dry-run','--json')
Check ($preview.selected.Count -eq 3 -and (Get-FileHash -LiteralPath $manifest).Hash -eq $hash) 'dry run previews without saving'
Run @('--only','TDFCMod,TypoMod') 1
Run @('--all','--none') 1
Run @('--version','1.04','--enable','TDFCMod') 1
Run @('--none','--launch') 1
Run @('--none','--report',('"'+(Join-Path $out 'bad.txt')+'"')) 1
Check ((Get-FileHash -LiteralPath $manifest).Hash -eq $hash) 'failed commands leave selection intact'
& $scanner --root $root --no-ui | Out-Null
Check ($LASTEXITCODE -eq 0) 'scanner can follow launcher'
$list = Run @('--list','--json')
Check ($list.selected.Count -eq 1 -and $list.selected[0] -eq 'TDFCMod') 'scanner does not reset disabled packages'
Run @('--report',('"'+(Join-Path $out 'report.json')+'"'))
$report = Get-Content -LiteralPath (Join-Path $out 'report.json') -Raw -Encoding utf8 | ConvertFrom-Json
Check ($report.configuration.selected[0] -eq 'TDFCMod' -and $report.configuration.mods[0].sha256.Length -eq 64) 'export describes exact selected configuration and fingerprints'
Run @('--none')
$list = Run @('--list','--json')
Check ($list.selected.Count -eq 0) 'none persists across process restart'
@{passed=$true;assertions=$script:checks} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'summary.json')
Write-Host "Evidence: $out"
