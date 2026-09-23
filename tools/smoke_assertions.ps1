# Pure evidence checks shared by the launcher and the offline regression tests.
function Get-ManifestPlan([string]$manifestPath, [string]$contentPath) {
    $content = $contentPath.Replace('\', '/')
    $column = switch ($content) {
        'pfe.swf' { 2; break }
        'DLC/pfe.swf' { 3; break }
        'DLC/pfeUI.swf' { 4; break }
        default { throw "unsupported descriptor content: $contentPath" }
    }
    $enabled = [System.Collections.Generic.List[string]]::new()
    $disabled = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    $lineNo = 0
    foreach ($rawLine in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
        $lineNo++
        $line = $rawLine.Trim().Trim([char]0xFEFF)
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        $parts = @($line.Split('|') | ForEach-Object { $_.Trim() })
        if ($parts.Count -ne 5) { throw "manifest line $lineNo needs 5 columns" }
        if ($parts[0] -notmatch '^[A-Za-z0-9_.&-]+$' -or $parts[0].Contains('..') -or
            $parts[1] -notmatch '^[A-Za-z_$][A-Za-z0-9_$]*$') {
            throw "manifest line $lineNo has invalid directory or entry"
        }
        foreach ($flag in $parts[2..4]) {
            if ($flag -notin @('0','1')) { throw "manifest line $lineNo has invalid switch" }
        }
        if ($seen.ContainsKey($parts[1])) { throw "manifest duplicate entry: $($parts[1])" }
        $seen[$parts[1]] = $true
        if ($parts[$column] -eq '1') { $enabled.Add($parts[1]) }
        else { $disabled.Add($parts[1]) }
    }
    if ($seen.Count -eq 0) { throw 'manifest has no entries' }
    return [pscustomobject]@{ Content = $content; Column = $column;
                              Enabled = @($enabled.ToArray()); Disabled = @($disabled.ToArray()) }
}

function Test-SmokeEvidence([string]$store, [datetime]$startedAtUtc, [datetime]$endedAtUtc,
                            $plan, [bool]$alive) {
    $failures = [System.Collections.Generic.List[string]]::new()
    $observations = [System.Collections.Generic.List[string]]::new()
    if (-not $alive) { $failures.Add('game process exited before observation window ended') }
    $statusFiles = @(Get-ChildItem -LiteralPath (Join-Path $store '#SharedObjects') -Recurse -Filter 'ModLoader.sol' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTimeUtc -ge $startedAtUtc } |
                    Sort-Object LastWriteTimeUtc -Descending)
    if ($statusFiles.Count -ne 1) {
        $failures.Add("expected one current ModLoader.sol, found $($statusFiles.Count)")
    } else {
        $sol = $statusFiles[0]
        $observations.Add("status file: $($sol.FullName)")
        try {
            $blob = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($sol.FullName))
            $runIds = @([regex]::Matches($blob, 'run_\d{13}_\d+') |
                        ForEach-Object { $_.Value } | Select-Object -Unique)
            if ($runIds.Count -ne 1) {
                $failures.Add("expected one fresh run id in status file, found $($runIds.Count)")
            } else {
                $runTimeMs = [long]([regex]::Match($runIds[0], 'run_(\d{13})_').Groups[1].Value)
                $startMs = ([DateTimeOffset]$startedAtUtc).ToUnixTimeMilliseconds()
                $endMs = ([DateTimeOffset]$endedAtUtc).ToUnixTimeMilliseconds()
                if ($runTimeMs -lt $startMs -or $runTimeMs -gt $endMs) {
                    $failures.Add("status run id is outside this launch: $($runIds[0])")
                }
            }
            foreach ($key in @('boot_start', 'boot')) {
                if ($blob -notmatch ($key + '(?![A-Za-z0-9_])')) {
                    $failures.Add("missing current status key: $key")
                }
            }
            foreach ($entry in $plan.Enabled) {
                foreach ($prefix in @('requested_', 'ok_')) {
                    $key = $prefix + $entry
                    if ($blob -notmatch ([regex]::Escape($key) + '(?![A-Za-z0-9_])')) {
                        $failures.Add("missing current status key: $key")
                    }
                }
            }
            foreach ($entry in $plan.Disabled) {
                foreach ($prefix in @('requested_', 'ok_')) {
                    $key = $prefix + $entry
                    if ($blob -match ([regex]::Escape($key) + '(?![A-Za-z0-9_])')) {
                        $failures.Add("disabled mod has status key: $key")
                    }
                }
            }
            $errors = @([regex]::Matches($blob, 'err_[A-Za-z0-9_]+') |
                        ForEach-Object { $_.Value } | Select-Object -Unique)
            foreach ($errorKey in $errors) { $failures.Add("loader error status: $errorKey") }
        } catch {
            $failures.Add("cannot inspect ModLoader.sol: $_")
        }
    }

    $logs = @{
        'SandevistanMod' = 'sandy_modlog.txt'
        'RConnectMod' = 'RConnect.log'
        'RealisticVisionMod' = 'RVision.log'
        'RandomRoomsMod' = 'RandomRooms_diag.log'
        'ModSettingsMod' = 'ModSettings.log'
        'ModLoaderMod' = 'ModSettings.log'
        'TDFCMod' = 'tdfc.log'
    }
    foreach ($entry in $plan.Enabled) {
        if (-not $logs.ContainsKey($entry)) {
            $observations.Add("$entry : status-only (no own file log)")
            continue
        }
        $path = Join-Path $store $logs[$entry]
        $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($null -eq $file -or $file.LastWriteTimeUtc -lt $startedAtUtc) {
            $failures.Add("enabled mod log not fresh: $entry ($path)")
        } else {
            $observations.Add("$entry : fresh log at $($file.LastWriteTimeUtc.ToString('o'))")
        }
    }
    foreach ($entry in $plan.Disabled) {
        if (-not $logs.ContainsKey($entry)) { continue }
        # The current runtime inherits the legacy settings log. Disabled-entry
        # requested/ok keys above still detect a second host independently.
        $sharedWithEnabled = @($plan.Enabled | Where-Object { $logs.ContainsKey($_) -and $logs[$_] -eq $logs[$entry] })
        if ($sharedWithEnabled.Count -gt 0) { continue }
        $path = Join-Path $store $logs[$entry]
        $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($null -ne $file -and $file.LastWriteTimeUtc -ge $startedAtUtc) {
            $failures.Add("disabled mod log refreshed: $entry ($path)")
        }
    }
    return [pscustomobject]@{ Passed = ($failures.Count -eq 0);
                              Failures = @($failures.ToArray()); Observations = @($observations.ToArray()) }
}
