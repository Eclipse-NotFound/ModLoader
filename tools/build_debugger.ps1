[CmdletBinding()]
param([string]$AnimateRoot = 'D:\Program Files\Adobe Animate 2024', [switch]$WithFixture)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$java = Join-Path $AnimateRoot 'jre\bin\java.exe'
$compiler = Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\bin\mxmlc.jar'
$global = Join-Path $AnimateRoot 'Common\Configuration\ActionScript 3.0\FP11.1\playerglobal.swc'
foreach ($path in @($java,$compiler,$global)) { if (!(Test-Path -LiteralPath $path)) { throw "Missing dependency: $path" } }
$out = Join-Path $project 'build\out\debugger-tools'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location (Join-Path $project 'build')
try {
    & $java '-Dfile.encoding=UTF-8' -jar $compiler "-library-path+=$global" '-target-player=11.1' '-debug=false' '-optimize=true' '-source-path+=../src/debugger' "-output=$out/AgentDebugProbeMod.swf" '../src/debugger/AgentDebugProbeMod.as'
    if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed' }
    if ($WithFixture) {
        $fixture = Join-Path $out 'DebugFault/release'
        New-Item -ItemType Directory -Force -Path $fixture | Out-Null
        & $java '-Dfile.encoding=UTF-8' -jar $compiler "-library-path+=$global" '-target-player=11.1' '-debug=false' '-optimize=true' "-output=$fixture/DebugFaultMod.swf" 'tests/DebugFaultMod.as'
        if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
    }
    Get-FileHash -LiteralPath (Join-Path $out 'AgentDebugProbeMod.swf')
} finally { Pop-Location }
