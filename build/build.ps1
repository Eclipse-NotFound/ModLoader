param([string]$AnimateRoot = 'D:\Program Files\Adobe Animate 2024')
$ErrorActionPreference = 'Stop'
$javaPath = Join-Path $AnimateRoot 'jre\bin\java.exe'
$compilerPath = Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\bin\mxmlc.jar'
$playerGlobal = Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\FP11.1\playerglobal.swc'
foreach ($toolPath in @($javaPath,$compilerPath,$playerGlobal)) {
    if (-not (Test-Path -LiteralPath $toolPath)) { throw "Missing build dependency: $toolPath" }
}
New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'out') | Out-Null
Push-Location $PSScriptRoot
try {
    & $javaPath '-Dfile.encoding=UTF-8' -jar $compilerPath "-library-path+=$playerGlobal" '-target-player=11.1' '-source-path+=../src/runtime' '-source-path+=../src/settings' '-output=out/ModLoaderMod.swf' '../src/runtime/ModLoaderMod.as'
    if ($LASTEXITCODE -ne 0) { throw 'ModLoader runtime compilation failed' }
    Get-FileHash -LiteralPath 'out/ModLoaderMod.swf'
}
finally { Pop-Location }
