param([string]$GameRoot = '', [switch]$Restore, [string]$Backup = '')
$ErrorActionPreference = 'Stop'
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Child([string]$Root, [string]$Relative) {
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe relative path' }
    return $path
}
if ($Restore) {
    if (-not $Backup) { $Backup = Read-Host 'Backup folder (contains receipt.json)' }
    $receipt = Get-Content -LiteralPath (Join-Path $Backup 'receipt.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $GameRoot = $receipt.gameRoot
    foreach ($item in $receipt.items) {
        $target = Child $GameRoot $item.path
        if (-not (Test-Path -LiteralPath $target) -or (Hash $target) -ne $item.installedHash) {
            throw "File changed after installation; restore stopped: $($item.path)"
        }
        if ($item.existed -and (Hash (Child $Backup $item.path)) -ne $item.beforeHash) { throw 'Backup checksum mismatch' }
    }
    foreach ($item in $receipt.items) {
        $target = Child $GameRoot $item.path
        if ($item.existed) { Copy-Item -LiteralPath (Child $Backup $item.path) -Destination $target -Force }
        else { Remove-Item -LiteralPath $target }
    }
    Write-Host 'Restored. Restart the game. Backup and player saves were preserved.'
    exit 0
}
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'FILES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($item in $manifest.files) {
    if ((Hash (Child (Join-Path $PSScriptRoot 'payload') $item.path)) -ne $item.sha256) { throw "Package checksum mismatch: $($item.path)" }
}
if (-not $GameRoot) { $GameRoot = Read-Host 'Remains folder (contains pfe.swf)' }
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$hostPath = Child $GameRoot 'pfe.swf'
if ($manifest.acceptedHostHashes -notcontains (Hash $hostPath)) { throw 'Unsupported game build. No files changed. This collection requires a known Remains 1.02 build.' }
[xml]$descriptor = Get-Content -LiteralPath (Child $GameRoot 'application.xml') -Raw
$content = $descriptor.SelectSingleNode('/*[local-name()="application"]/*[local-name()="initialWindow"]/*[local-name()="content"]').InnerText
if ($content -ne 'pfe.swf') { throw 'application.xml must use pfe.swf (1.02). No files changed.' }
$Backup = Child $GameRoot ('.modpack-backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $Backup | Out-Null
$actions = @()
foreach ($item in $manifest.files) {
    $target = Child $GameRoot $item.path
    $existed = Test-Path -LiteralPath $target
    if ($existed -and ($item.preserveExisting -or (Hash $target) -eq $item.sha256)) { continue }
    $beforeHash = $null
    if ($existed) {
        $beforeHash = Hash $target
        $saved = Child $Backup $item.path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
        Copy-Item -LiteralPath $target -Destination $saved
        if ((Hash $saved) -ne $beforeHash) { throw 'Backup copy failed verification' }
    }
    $actions += [pscustomobject]@{path=$item.path;existed=$existed;beforeHash=$beforeHash;installedHash=$item.sha256}
}
$receipt = [pscustomobject]@{gameRoot=$GameRoot;package=$manifest.name;items=$actions;status='prepared'}
$receiptPath = Join-Path $Backup 'receipt.json'
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
$written = @()
try {
    foreach ($item in $actions) {
        $target = Child $GameRoot $item.path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        $written += $item
        Copy-Item -LiteralPath (Child (Join-Path $PSScriptRoot 'payload') $item.path) -Destination $target -Force
        if ((Hash $target) -ne $item.installedHash) { throw "Installed checksum mismatch: $($item.path)" }
    }
    $receipt.status = 'installed'
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
} catch {
    foreach ($item in $written) {
        $target = Child $GameRoot $item.path
        if ($item.existed) { Copy-Item -LiteralPath (Child $Backup $item.path) -Destination $target -Force }
        elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
    }
    $receipt.status = 'rolled-back-after-error'
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    throw
}
Write-Host ('Installed ' + $actions.Count + ' files. Existing configuration was preserved.')
Write-Host ('Backup: ' + $Backup)
Write-Host 'Restart normally. Do not run old per-mod installers. RModifier and legacy ModSettings are disabled in this collection.'
