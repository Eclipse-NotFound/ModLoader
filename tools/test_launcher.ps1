[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$game = Split-Path -Parent (Split-Path -Parent $project)
$out = Join-Path $project ('build\out\launcher-tests\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$fixture = Join-Path $out 'fixture 中文 & spaces'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$compiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$exe = Join-Path $out 'LauncherTests.exe'
$sources = @((Join-Path $project 'src\ModScanner.cs'), (Join-Path $project 'src\ModLauncher.cs'), (Join-Path $project 'build\tests\LauncherTests.cs'))
$manifest = Join-Path $project 'src\launcher.manifest'
& $compiler /nologo /target:exe /main:LauncherTests /warnaserror+ /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll "/win32manifest:$manifest" "/out:$exe" @sources
if ($LASTEXITCODE -ne 0) { throw 'Launcher tests compilation failed' }
& $exe $fixture $out $game | Tee-Object -FilePath (Join-Path $out 'results.txt')
if ($LASTEXITCODE -ne 0) { throw "Launcher tests failed: $out" }
Write-Host "Evidence: $out"
