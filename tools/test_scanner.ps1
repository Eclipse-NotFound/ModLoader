$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$scanner = Join-Path $project 'RemainsModScanner.exe'
if (-not (Test-Path -LiteralPath $scanner)) { throw '请先运行 tools/build_scanner.ps1。' }

function Expect([bool]$condition, [string]$message) {
    if (-not $condition) { throw "扫描器测试失败：$message" }
}
function Add-FakeSwf([string]$gameRoot, [string]$directory, [string]$entry, [bool]$valid) {
    $release = Join-Path (Join-Path (Join-Path $gameRoot 'mods') $directory) 'release'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    $path = Join-Path $release ($entry + '.swf')
    if ($valid) { [IO.File]::WriteAllBytes($path,[byte[]](70,87,83,9,8,0,0,0)) }
    else { [IO.File]::WriteAllText($path,'not a swf') }
}
function Run-Scanner([string]$gameRoot, [string[]]$extraArgs) {
    & $scanner --no-ui --root $gameRoot @extraArgs 2>$null | Out-Null
    return $LASTEXITCODE
}

$work = Join-Path $project 'work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$root = Join-Path $work ('scanner-test-' + [guid]::NewGuid().ToString('N'))
$workFull = [IO.Path]::GetFullPath($work).TrimEnd([IO.Path]::DirectorySeparatorChar)
$rootFull = [IO.Path]::GetFullPath($root)
Expect ($rootFull.StartsWith($workFull + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) '测试目录必须位于 ModLoader/work 内'

try {
    $testScanner = Join-Path $root 'mods\ModLoader'
    New-Item -ItemType Directory -Force -Path $testScanner | Out-Null
    Copy-Item -LiteralPath (Join-Path $project 'supported-mods.txt') -Destination $testScanner
    $manifest = Join-Path $root 'mods\loader-manifest.txt'
    Add-FakeSwf $root 'ModSettings' 'ModSettingsMod' $true
    Add-FakeSwf $root 'ModLoader' 'ModLoaderMod' $true
    Add-FakeSwf $root 'FreshMod' 'FreshMod' $true
    Add-FakeSwf $root 'FreshMod' 'FreshMod.before-old' $true
    Add-FakeSwf $root 'BrokenMod' 'BrokenMod' $false
    Expect ((Run-Scanner $root @('--dry-run')) -eq 0) '预览应成功'
    Expect (-not (Test-Path -LiteralPath $manifest)) '预览不能写入名单'

    Expect ((Run-Scanner $root @()) -eq 0) '首次扫描应成功'
    $lines = Get-Content -LiteralPath $manifest -Encoding UTF8
    Expect ($lines -contains 'ModLoader|ModLoaderMod|1|0|0') '内置设置只启用1.02'
    Expect ($lines -contains 'ModSettings|ModSettingsMod|0|0|0') '旧设置包仍在也不得再次启用'
    Expect ($lines -contains 'Sandevistan|SandevistanMod|0|0|0') '缺少正式包时应关闭全部版本'
    Expect ($lines -contains 'FreshMod|FreshMod|1|1|1') '新模组应启用全部版本'
    Expect (-not ($lines -match 'BrokenMod|before-old')) '坏包与备份包不能加入'
    $hash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    $backupDir = Join-Path $testScanner 'work\manifest-backups'
    Expect ((Run-Scanner $root @()) -eq 0) '重复扫描应成功'
    Expect ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -eq $hash) '重复扫描不能改变名单'
    Expect (-not (Test-Path -LiteralPath $backupDir)) '名单不变时不能产生备份'

    Add-FakeSwf $root 'Sandevistan' 'SandevistanMod' $true
    Expect ((Run-Scanner $root @()) -eq 0) '增加已登记模组后扫描应成功'
    $lines = Get-Content -LiteralPath $manifest -Encoding UTF8
    Expect ($lines -contains 'Sandevistan|SandevistanMod|1|1|1') '新放回的正式包应恢复已知兼容范围'
    Expect ((Get-ChildItem -LiteralPath $backupDir -File).Count -eq 1) '变更时应保留旧名单备份'

    $before = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    Set-Content -LiteralPath (Join-Path $testScanner 'supported-mods.txt') -Value 'Bad|BadMod|1|1' -Encoding UTF8
    Expect ((Run-Scanner $root @()) -ne 0) '目录格式错误应失败'
    Expect ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -eq $before) '失败不能破坏原名单'
    $rollbackCatalog = @(Get-Content -LiteralPath (Join-Path $project 'supported-mods.txt') | ForEach-Object {
        $_ -replace '^ModLoader\|ModLoaderMod\|1\|0\|0$', 'ModLoader|ModLoaderMod|0|0|0' -replace '^ModSettings\|ModSettingsMod\|0\|0\|0$', 'ModSettings|ModSettingsMod|1|0|0'
    })
    [IO.File]::WriteAllLines((Join-Path $testScanner 'supported-mods.txt'), $rollbackCatalog, [Text.UTF8Encoding]::new($false))
    Expect ((Run-Scanner $root @()) -eq 0) '保留新包时可切回旧设置宿主'
    Expect ((Run-Scanner $root @()) -eq 0) '回滚后重复扫描成功'
    $lines = Get-Content -LiteralPath $manifest
    Expect ($lines -contains 'ModLoader|ModLoaderMod|0|0|0') '回滚后新包仍在也不得自动复活'
    Expect ($lines -contains 'ModSettings|ModSettingsMod|1|0|0') '回滚后只启用原1.02设置入口'
    Copy-Item -LiteralPath (Join-Path $project 'supported-mods.txt') -Destination $testScanner -Force
    Remove-Item -LiteralPath (Join-Path $root 'mods\ModSettings\release\ModSettingsMod.swf')
    Expect ((Run-Scanner $root @()) -eq 0) '旧包缺席时仍能扫描'
    Expect ((Get-Content -LiteralPath $manifest) -contains 'ModLoader|ModLoaderMod|1|0|0') '新宿主不依赖旧包'
    Remove-Item -LiteralPath (Join-Path $root 'mods\ModLoader\release\ModLoaderMod.swf')
    Add-FakeSwf $root 'ModSettings' 'ModSettingsMod' $true
    Expect ((Run-Scanner $root @()) -eq 0) '新包缺席时正常生成降级名单'
    $lines = Get-Content -LiteralPath $manifest
    Expect ($lines -contains 'ModLoader|ModLoaderMod|0|0|0') '新包缺席则禁用新入口'
    Expect ($lines -contains 'ModSettings|ModSettingsMod|0|0|0') '新包缺席不得悄悄复活旧宿主'
    Expect ($lines -contains 'Sandevistan|SandevistanMod|1|1|1') '宿主缺席不影响其他已知模组'
} finally {
    if (Test-Path -LiteralPath $rootFull) { Remove-Item -LiteralPath $rootFull -Recurse -Force }
}
Write-Host '扫描器隔离测试通过'
$global:LASTEXITCODE = 0
