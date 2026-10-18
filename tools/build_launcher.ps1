[CmdletBinding()]
param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project 'build\out\launcher' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$compiler = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) { throw '没有找到 Windows .NET Framework C# 编译器。' }
$sources = @((Join-Path $project 'src\ModScanner.cs'), (Join-Path $project 'src\ModLauncher.cs'))
$manifest = Join-Path $project 'src\launcher.manifest'
$launcher = Join-Path $OutputDirectory 'RemainsModLauncher.exe'
$scanner = Join-Path $OutputDirectory 'RemainsModScanner.exe'
& $compiler /nologo /target:winexe /main:ModLauncher /optimize+ /warnaserror+ /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll "/win32manifest:$manifest" "/out:$launcher" @sources
if ($LASTEXITCODE -ne 0) { throw '启动器编译失败。' }
& $compiler /nologo /target:winexe /main:ModScanner /optimize+ /warnaserror+ /r:System.Windows.Forms.dll "/out:$scanner" $sources[0]
if ($LASTEXITCODE -ne 0) { throw '扫描器编译失败。' }
Write-Host "启动器和兼容扫描器已生成：$OutputDirectory"
