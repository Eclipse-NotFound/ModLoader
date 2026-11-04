# Synchronous owned AIR launch. The Python helper owns the child and its desktop.
function Invoke-AirTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Executable,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
        [double]$TimeoutSeconds = 120,
        [string]$UntilFile = '',
        [double]$GraceSeconds = 2
    )
    $candidates = @($env:REMAINS_DEBUG_PYTHON)
    $command = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates += $command.Source }
    $candidates += Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $python = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and $_ -notlike '*WindowsApps*' } | Select-Object -First 1
    if (!$python) { throw 'Python 3.10+ required; set REMAINS_DEBUG_PYTHON.' }
    $receipt = Join-Path $EvidenceDirectory 'air-process.json'
    if (Test-Path -LiteralPath $receipt) { throw "Preserve existing evidence: $receipt" }
    $invokeArgs = @('-B', '-X', 'utf8', (Join-Path $PSScriptRoot 'air_test_process.py'),
        '--cwd', $WorkingDirectory, '--timeout', [string]$TimeoutSeconds,
        '--stdout', (Join-Path $EvidenceDirectory 'adl-output.log'),
        '--stderr', (Join-Path $EvidenceDirectory 'adl-error.log'), '--receipt', $receipt)
    if ($UntilFile) { $invokeArgs += @('--until-file', $UntilFile, '--grace', [string]$GraceSeconds) }
    $invokeArgs += @('--', $Executable) + $Arguments
    # Forward the actual AIR PID immediately so existing outer registries can own it.
    & $python @invokeArgs | ForEach-Object { Write-Host $_ }
    $helperExit = $LASTEXITCODE
    if (!(Test-Path -LiteralPath $receipt)) { throw "Private AIR launch failed (exit $helperExit); no receipt." }
    $result = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($result.error -or !$result.closed) { throw "Private AIR launch failed: $($result.error)" }
    return $result
}
