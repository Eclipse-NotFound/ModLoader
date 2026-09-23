$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$source = Join-Path $project 'src\ModScanner.cs'
$output = Join-Path $project 'RemainsModScanner.exe'
$compilers = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$compiler = $compilers | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) { throw '没有找到 Windows .NET Framework C# 编译器。' }
& $compiler /nologo /target:winexe /optimize+ /warnaserror+ /r:System.Windows.Forms.dll /out:$output $source
if ($LASTEXITCODE -ne 0) { throw "扫描器编译失败（退出码 $LASTEXITCODE）。" }
Write-Host "已生成 $output"
