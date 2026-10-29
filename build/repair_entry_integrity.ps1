param([ValidateSet('Original','ModTools')][string]$Scope='Original')
$ErrorActionPreference = 'Stop'
$gameRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$evidence = Join-Path $PSScriptRoot 'out/startup-repair-20261029'
$discovery = Get-Content -LiteralPath (Join-Path $evidence 'bundle-discovery.json') -Raw | ConvertFrom-Json
$candidate = Get-Content -LiteralPath (Join-Path $evidence 'medium-host-check/label-check.json') -Raw | ConvertFrom-Json
$prefix = if ($Scope -eq 'Original') { 'entry-label' } else { 'mod-entry-label' }
$receipt = Join-Path $evidence ($prefix + '-repair.json')
if (Test-Path -LiteralPath $receipt) { throw 'Receipt already exists; do not repeat this repair.' }
$entries = if ($Scope -eq 'Original') {
    @(@{Name='Remains.exe';Hash=$discovery.sha256},@{Name='adl64.exe';Hash=$candidate.beforeHash})
} else {
    @(@{Name='mods/ModLoader/RemainsModLauncher.exe';Hash='C05B4C231A97EBD740DCE64D642F994EDBFFBC14B74723AB40A1F27FA45F9590'},
      @{Name='mods/ModLoader/RemainsModScanner.exe';Hash='8FA1839893B85085B788B65CCF1884495A4CAB7BFC473E20FED80E894C0D33C1'})
}
$rows = @()
foreach ($entry in $entries) {
    $target = Join-Path $gameRoot $entry.Name
    if ((Get-FileHash -LiteralPath $target).Hash -ne $entry.Hash) { throw "Changed executable: $target" }
    $rows += [pscustomobject]@{Path=$target;SHA256=$entry.Hash;BeforeAccess=(Get-Acl -LiteralPath $target).Sddl;BeforeLabel=(& icacls.exe $target | Out-String);AfterLabel=$null;AfterAccess=$null;HashUnchanged=$false;Applied=$false}
}
$rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence ($prefix + '-before.json')) -Encoding utf8
try {
    foreach ($row in $rows) {
        & icacls.exe $row.Path /setintegritylevel M | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Cannot set ordinary integrity: $($row.Path)" }
        $row.Applied=$true
        $row.AfterLabel=(& icacls.exe $row.Path | Out-String)
        $row.AfterAccess=(Get-Acl -LiteralPath $row.Path).Sddl
        $row.HashUnchanged=((Get-FileHash -LiteralPath $row.Path).Hash -eq $row.SHA256)
        if (-not $row.HashUnchanged -or $row.BeforeAccess -ne $row.AfterAccess) { throw 'Content or discretionary permissions changed unexpectedly.' }
    }
} finally {
    [pscustomobject]@{Time=(Get-Date -Format o);Scope=$Scope;Constraint='Only mandatory integrity labels of exact entry executables; no directory/DACL/content change';Files=$rows} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receipt -Encoding utf8
}
$rows | Select-Object Path,Applied,HashUnchanged | ConvertTo-Json -Compress
