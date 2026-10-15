param([ValidateSet('Install','Verify','Rollback')][string]$Action='Install', [string]$TestDirectory='')
$ErrorActionPreference='Stop'
$modRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot=[IO.Path]::GetFullPath((Join-Path $modRoot '..\..'))
$target=Join-Path $modRoot 'release\ModLoaderMod.swf'
$candidate=Join-Path $PSScriptRoot 'out\ModLoaderMod.swf'
$out=Join-Path $PSScriptRoot 'out\keybind-installation'
$receiptPath=Join-Path $out 'deployment.json'
$expectedOld='2D01241A89FB25D608AC5138254E14DC3E5FB46E7120319A0D5922E4CF9816FD'
$expectedNew='BD71B6F31774B97841D4C158451DA0353B53BC46AC72F8E2A7FE2C3F3F4908B1'
function Fingerprint([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function SaveReceipt($r){$r | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8}
if($Action -eq 'Install'){
    if(Test-Path -LiteralPath $receiptPath){throw 'Installation receipt already exists; inspect it before proceeding'}
    if((Fingerprint $target) -ne $expectedOld -or (Fingerprint $candidate) -ne $expectedNew){throw 'Production or candidate changed; coordinate before installation'}
    [xml]$descriptor=Get-Content -LiteralPath (Join-Path $gameRoot 'application.xml') -Raw
    if([string]$descriptor.application.initialWindow.content -ne 'pfe.swf'){throw 'Unexpected active game host'}
    if((Fingerprint (Join-Path $gameRoot 'pfe.swf')) -ne '9987C696BEBBEB0626D8F73DA775CF867B2CED4FF626137FD9F161264270F938'){throw 'Game host changed; verify its loader first'}
    $protected=@{}
    foreach($rel in @('pfe.swf','DLC\pfe.swf','DLC\pfeUI.swf','application.xml','mods\loader-manifest.txt','mods\ModLoader\supported-mods.txt')){$protected[$rel]=Fingerprint (Join-Path $gameRoot $rel)}
    # FA has separate, explicit deployment authorization in its own chat.
    # It is observed but not included in this transaction's unchanged set.
    Get-ChildItem -LiteralPath (Join-Path $gameRoot 'mods') -Directory | Where-Object {$_.Name -notin @('ModLoader','FirearmAttachments')} | ForEach-Object {
        $release=Join-Path $_.FullName 'release'
        if(Test-Path -LiteralPath $release){Get-ChildItem -LiteralPath $release -File | Where-Object {$_.Extension -in @('.swf','.txt','.json')} | ForEach-Object {$protected[$_.FullName.Substring($gameRoot.Length+1)]=Fingerprint $_.FullName}}
    }
    $backup=Join-Path $PSScriptRoot ('backups\before-keybinds-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    if(Test-Path -LiteralPath $backup){throw 'Backup directory already exists'}
    New-Item -ItemType Directory -Path $backup,$out | Out-Null
    $old=Join-Path $backup 'ModLoaderMod.swf'
    Copy-Item -LiteralPath $target -Destination $old
    if((Fingerprint $old) -ne $expectedOld){throw 'Backup fingerprint mismatch'}
    $receipt=@{status='backed-up';authorizationThread='01a13b7b-fe67-7a00-a10f-dd2df045fad9';authorizationMessages=@('01a13fb7-9a82-7421-9c1f-831774bfc1a6','01a13fb9-429b-7421-96c5-4080ba0a2efc');authorizedScope='ModLoader dependency for FA shortcuts only';target=$target;candidate=$candidate;backup=$old;before=$expectedOld;after=$expectedNew;protected=$protected;installedAt=$null}
    SaveReceipt $receipt
    $temporary=$target+'.keybind-'+[guid]::NewGuid().ToString('N')+'.tmp'
    Copy-Item -LiteralPath $candidate -Destination $temporary
    if((Fingerprint $temporary) -ne $expectedNew){throw 'Temporary candidate fingerprint mismatch'}
    Move-Item -LiteralPath $temporary -Destination $target -Force
    if((Fingerprint $target) -ne $expectedNew){throw 'Installed fingerprint mismatch'}
    foreach($rel in $protected.Keys){if((Fingerprint (Join-Path $gameRoot $rel)) -ne $protected[$rel]){throw ('Unrelated input changed: '+$rel)}}
    $receipt.status='installed-pending-verification';$receipt.installedAt=(Get-Date -Format o);SaveReceipt $receipt
    Write-Output ('Installed ModLoader 2.4.0, SHA256 '+$expectedNew+'; backup '+$old)
}else{
    $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if((Fingerprint $target) -ne $expectedNew){throw 'Installed target changed; do not overwrite another deployment'}
    if($Action -eq 'Rollback'){
        if((Fingerprint $receipt.backup) -ne $expectedOld){throw 'Backup changed'}
        Copy-Item -LiteralPath $receipt.backup -Destination $target
        if((Fingerprint $target) -ne $expectedOld){throw 'Rollback fingerprint mismatch'}
        $receipt.status='rolled-back';SaveReceipt $receipt
    }else{
        if(!$TestDirectory){throw 'Verify requires the completed isolated test directory'}
        $run=Get-Content -LiteralPath (Join-Path $TestDirectory 'run.json') -Raw | ConvertFrom-Json
        if(!$run.installedHost -or $run.hashes.ModLoader -ne $expectedNew){throw 'Test did not use this installed host'}
        foreach($phase in @('first','reload')){
            $result=Get-Content -LiteralPath (Join-Path $TestDirectory ($phase+'-results.txt'))
            if($result[-1] -notmatch '^PASS \d+ assertions$' -or ($result -match '^FAIL ').Count){throw 'Installed-host test failed'}
        }
        foreach($property in $receipt.protected.PSObject.Properties){if((Fingerprint (Join-Path $gameRoot $property.Name)) -ne $property.Value){throw ('Protected file changed: '+$property.Name)}}
        $receipt.status='installed-and-verified'
        $receipt | Add-Member -NotePropertyName verification -NotePropertyValue ([IO.Path]::GetFullPath($TestDirectory)) -Force
        SaveReceipt $receipt
        Write-Output ('Verified installed ModLoader '+$expectedNew)
    }
}
