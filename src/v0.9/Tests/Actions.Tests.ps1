$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'ActionsCore.ps1')
$catalog=WB-ReadCatalog
function Assert($ok,$message){if(-not $ok){throw $message}}
Assert ($catalog.Count -eq 121) '121 familias esperadas'
Assert (@($catalog | Where-Object {$_.Type -ne 'Settings'}).Count -eq 89) '89 acciones automaticas'
Assert (@($catalog | Where-Object {$_.Type -eq 'Settings'}).Count -eq 32) '32 flujos asistidos'
$store=@{}
function WB-Current($a){if($store.ContainsKey($a.Id)){return $store[$a.Id]};return $null}
function WB-SetState($a,$value){$store[$a.Id]=$value}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('wb-actions-'+[guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
$path=Join-Path $tmp 'backup.json'
$count=0
foreach($a in @($catalog | Where-Object {$_.Reversible})){
 foreach($choice in $a.Choices){
  $before=switch($a.Type){'Registry'{[pscustomobject]@{Exists=$true;Kind='String';Value='original'}};'Power'{'381b4222-f694-41f0-9685-ff5bb260df2e'};'Defender'{2};'Service'{[pscustomobject]@{StartType='Manual';Running=$false}}}
  $store=@{};$store[$a.Id]=$before
  $journal=[pscustomobject]@{Status='Pending';Entries=@()}
  $item=[pscustomobject]@{Definition=$a;Choice=$choice;Argument=''}
  [void](WB-ApplyReversible $item $journal $path)
  $n=$journal.Entries.Count
  [void](WB-ApplyReversible $item $journal $path)
  Assert ($n -eq $journal.Entries.Count) 'Reaplicar duplica diario'
  $conflicts=WB-Restore $journal $path $catalog
  Assert ($conflicts -eq 0 -and (WB-Same (WB-Current $a) $before)) ('Restauracion incorrecta: '+$a.Id)
  $count++
 }
}
Write-Output ('PASS: '+$count+' variantes reversibles, idempotencia y restauracion exacta')
$a=$catalog | Where-Object Id -eq 'AdvertisingID';$choice=$a.Choices[0]
$before=[pscustomobject]@{Exists=$false;Kind=$null;Value=$null};$store=@{};$store[$a.Id]=$before
$item=[pscustomobject]@{Definition=$a;Choice=$choice;Argument=''};$journal=[pscustomobject]@{Status='Pending';Entries=@()}
[void](WB-ApplyReversible $item $journal $path)
$foreign=[pscustomobject]@{Exists=$true;Kind='DWord';Value=123};$store[$a.Id]=$foreign
Assert ((WB-Restore $journal $path $catalog) -eq 1) 'Debe detectar conflicto'
Assert (WB-Same $store[$a.Id] $foreign) 'No sobrescribir cambio externo'
Write-Output 'PASS: conserva cambios externos'
$store[$a.Id]=$before;$journal=[pscustomobject]@{Status='Pending';Entries=@()}
function WB-SetState($a,$value){$disk=WB-ReadJournal $path;Assert ($disk.Entries.Count -eq 1) 'Debe guardar antes de escribir';$store[$a.Id]=$value;throw 'fallo despues de escribir'}
$failed=$false
try{[void](WB-ApplyReversible $item $journal $path)}catch{$failed=$true}
Assert $failed 'Debe propagarse el fallo'
function WB-SetState($a,$value){$store[$a.Id]=$value}
Assert ((WB-Restore (WB-ReadJournal $path) $path $catalog) -eq 0) 'Recuperacion tras fallo parcial'
Assert (WB-Same $store[$a.Id] $before) 'Recuperar valor ausente'
Write-Output 'PASS: diario previo a mutacion y recuperacion parcial'
foreach($bad in @(
 [pscustomobject]@{Schema=1;Actions=@([pscustomobject]@{Id='unknown';Choice='Enable'})},
 [pscustomobject]@{Schema=1;Actions=@([pscustomobject]@{Id='AdvertisingID';Choice='unknown'})},
 [pscustomobject]@{Schema=1;Actions=@([pscustomobject]@{Id='WindowsFeatures';Choice='Activar';Argument='*'})},
 [pscustomobject]@{Schema=1;Actions=@([pscustomobject]@{Id='WindowsFeatures';Choice='Activar';Argument='NetFx3; calc.exe'})},
 [pscustomobject]@{Schema=1;Actions=@([pscustomobject]@{Id='WindowsFeatures';Choice='Activar'})},
 [pscustomobject]@{Schema=1;Actions=@([pscustomobject]@{Id='AdvertisingID';Choice='Activar'},[pscustomobject]@{Id='AdvertisingID';Choice='Desactivar'})}
)){
 $rejected=$false;try{[void](WB-ValidatePlan $bad $catalog)}catch{$rejected=$true};Assert $rejected 'Plan invalido aceptado'
}
Write-Output 'PASS: rechazo de acciones/opciones invalidas, duplicados, comodines e inyeccion'
# Todos los destinos de acciones asistidas deben provenir del catalogo cerrado.
foreach($a in $catalog | Where-Object Type -eq Settings){Assert ($a.Choices[0].Value -match '^(ms-settings:|windowsdefender:|eventvwr\.msc$|devmgmt\.msc$|taskschd\.msc$|explorer\.exe$)') 'Destino asistido no admitido'}
Write-Output 'PASS: destinos asistidos cerrados, separados de ajustes automaticos'
Remove-Item -LiteralPath $tmp -Recurse -Force
