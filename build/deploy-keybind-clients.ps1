param([ValidateSet('Install','Verify','Rollback')][string]$Action='Install', [string]$TestDirectory='')
$ErrorActionPreference='Stop'
$gameRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$planPath=Join-Path $PSScriptRoot 'keybind-client-deployment.json'
$receiptPath=Join-Path $PSScriptRoot 'out\keybind-client-installation\deployment.json'
function Fingerprint([string]$path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
function SaveReceipt($value){$value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8}
function RestoreClients($receipt){
    foreach($entry in $receipt.clients){
        $current=Fingerprint $entry.target
        if($current -eq $entry.before){continue}
        if($current -ne $entry.after){throw ('Refuse to overwrite a later deployment: '+$entry.mod)}
        if((Fingerprint $entry.backup) -ne $entry.before){throw ('Backup changed: '+$entry.mod)}
        Copy-Item -LiteralPath $entry.backup -Destination $entry.target
        if((Fingerprint $entry.target) -ne $entry.before){throw ('Rollback failed: '+$entry.mod)}
    }
}
if($Action -eq 'Install'){
    if(Test-Path -LiteralPath $receiptPath){throw 'A client installation receipt already exists; inspect it first'}
    $plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $allowed=@('MoreSkills&Weapons','Sandevistan','RealisticVision','RConnect','RandomRooms','LightAndDarkness')
    if($plan.clients.Count -ne 6 -or @($plan.clients.mod | Sort-Object -Unique).Count -ne 6){throw 'Expected six distinct authorized clients'}
    foreach($entry in $plan.clients){
        if($entry.mod -notin $allowed){throw 'Unauthorized client in plan'}
        $entry | Add-Member -NotePropertyName target -NotePropertyValue (Join-Path $gameRoot ('mods\'+$entry.mod+'\release\'+$entry.file))
        $entry | Add-Member -NotePropertyName source -NotePropertyValue (Join-Path $gameRoot $entry.candidate)
        $expectedTarget=Join-Path $gameRoot ('mods\'+$entry.mod+'\release\'+$entry.file)
        if([IO.Path]::GetFullPath($entry.target) -ne $expectedTarget){throw 'Target escapes its authorized release directory'}
        if((Fingerprint $entry.target) -ne $entry.before -or (Fingerprint $entry.source) -ne $entry.after){throw ('Production or candidate changed: '+$entry.mod)}
    }
    $protected=@{}
    foreach($rel in @('pfe.swf','DLC\pfe.swf','DLC\pfeUI.swf','application.xml','mods\loader-manifest.txt','mods\ModLoader\supported-mods.txt','mods\ModLoader\release\ModLoaderMod.swf','mods\FirearmAttachments\release\FirearmAttachmentsMod.swf')){$protected[$rel]=Fingerprint (Join-Path $gameRoot $rel)}
    if($protected['mods\ModLoader\release\ModLoaderMod.swf'] -ne 'BD71B6F31774B97841D4C158451DA0353B53BC46AC72F8E2A7FE2C3F3F4908B1'){throw 'Public dependency changed'}
    if($protected['mods\FirearmAttachments\release\FirearmAttachmentsMod.swf'] -ne 'B3304596EB7E08796F9DE2CF02E1E7CCCFF10E188D26FEDFA960AA6370D2A4B9'){throw 'FA deployment changed'}
    Get-ChildItem -LiteralPath (Join-Path $gameRoot 'mods') -Directory | ForEach-Object {
        $folder=$_;$release=Join-Path $folder.FullName 'release'
        if(Test-Path -LiteralPath $release){Get-ChildItem -LiteralPath $release -File | Where-Object {$_.Extension -in @('.txt','.json') -or $_.Extension -eq '.swf' -and $folder.Name -notin $allowed} | ForEach-Object {$protected[$_.FullName.Substring($gameRoot.Length+1)]=Fingerprint $_.FullName}}
    }
    $backupRoot=Join-Path $PSScriptRoot ('backups\before-keybind-clients-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    if(Test-Path -LiteralPath $backupRoot){throw 'Backup directory already exists'}
    New-Item -ItemType Directory -Path $backupRoot,(Split-Path -Parent $receiptPath) | Out-Null
    foreach($entry in $plan.clients){
        $folder=Join-Path $backupRoot $entry.mod;New-Item -ItemType Directory -Path $folder | Out-Null
        $entry | Add-Member -NotePropertyName backup -NotePropertyValue (Join-Path $folder $entry.file)
        Copy-Item -LiteralPath $entry.target -Destination $entry.backup
        if((Fingerprint $entry.backup) -ne $entry.before){throw ('Backup mismatch: '+$entry.mod)}
    }
    $receipt=@{status='backed-up';authorization='User in thread 01a13f40-6ca2-7872-9f9a-c1e453e80745 explicitly selected installation of all six remaining clients, 2026-10-15';clients=$plan.clients;protected=$protected;installedAt=$null}
    SaveReceipt $receipt
    try{
        foreach($entry in $plan.clients){
            if((Fingerprint $entry.target) -ne $entry.before){throw ('Production changed during backup: '+$entry.mod)}
            $temporary=$entry.target+'.keybind-'+[guid]::NewGuid().ToString('N')+'.tmp'
            Copy-Item -LiteralPath $entry.source -Destination $temporary
            if((Fingerprint $temporary) -ne $entry.after){throw ('Copy mismatch: '+$entry.mod)}
            Move-Item -LiteralPath $temporary -Destination $entry.target -Force
            if((Fingerprint $entry.target) -ne $entry.after){throw ('Installed mismatch: '+$entry.mod)}
        }
        foreach($rel in $protected.Keys){if((Fingerprint (Join-Path $gameRoot $rel)) -ne $protected[$rel]){throw ('Protected input changed: '+$rel)}}
        $receipt.status='installed-pending-verification';$receipt.installedAt=(Get-Date -Format o);SaveReceipt $receipt
        Write-Output ('Installed six clients; backups: '+$backupRoot)
    }catch{
        RestoreClients $receipt
        $receipt.status='rolled-back-on-error';SaveReceipt $receipt
        throw
    }
}else{
    $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if($Action -eq 'Rollback'){
        RestoreClients $receipt;$receipt.status='rolled-back';SaveReceipt $receipt
    }else{
        if(!$TestDirectory){throw 'Verify requires the completed installed-client test directory'}
        $run=Get-Content -LiteralPath (Join-Path $TestDirectory 'run.json') -Raw | ConvertFrom-Json
        if(!$run.installedHost -or !$run.installedClients){throw 'Verification must use installed host and clients'}
        foreach($entry in $receipt.clients){if((Fingerprint $entry.target) -ne $entry.after -or $run.hashes.($entry.mod) -ne $entry.after){throw ('Installed/tested bytes differ: '+$entry.mod)}}
        foreach($phase in @('first','reload')){
            $lines=Get-Content -LiteralPath (Join-Path $TestDirectory ($phase+'-results.txt'))
            if($lines[-1] -notmatch '^PASS \d+ assertions$' -or ($lines -match '^FAIL ').Count){throw 'Installed-client verification failed'}
        }
        foreach($property in $receipt.protected.PSObject.Properties){if((Fingerprint (Join-Path $gameRoot $property.Name)) -ne $property.Value){throw ('Protected input changed: '+$property.Name)}}
        $receipt.status='installed-and-verified';$receipt | Add-Member -NotePropertyName verification -NotePropertyValue ([IO.Path]::GetFullPath($TestDirectory)) -Force;SaveReceipt $receipt
        Write-Output 'Verified all six installed clients and protected inputs'
    }
}
