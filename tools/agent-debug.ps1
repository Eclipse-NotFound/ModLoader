# Pass arguments unchanged to the stdlib-only debugger. PythonPath can also be set in REMAINS_DEBUG_PYTHON.
$ErrorActionPreference = 'Stop'
$candidates = @($env:REMAINS_DEBUG_PYTHON)
$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($python) { $candidates += $python.Source }
$candidates += Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$selected = $null
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate) -and $candidate -notlike '*WindowsApps*') { $selected = $candidate; break }
}
if (!$selected) { throw 'Python 3.10+ required. Set REMAINS_DEBUG_PYTHON to the python.exe path.' }
& $selected (Join-Path $PSScriptRoot 'mod_debugger.py') @args
exit $LASTEXITCODE
