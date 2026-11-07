# Funciones auxiliares del motor; no ejecutan cambios al importarlas.
function Validate-Config($value){
 if($null -eq $value.PSObject.Properties['DeepInventory']){$value | Add-Member NoteProperty DeepInventory $false}
 if($value.DeepInventory -isnot [bool]){throw 'Opcion invalida: DeepInventory'}
 foreach($key in @('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair')){
  if($null -eq $value.PSObject.Properties[$key] -or $value.$key -isnot [bool]){throw "Opcion invalida: $key"}
 }
 if($null -eq $value.PSObject.Properties['Startup']){$value | Add-Member NoteProperty Startup $false}
 if($value.Startup -isnot [bool]){throw 'Opcion invalida: Startup'}
 if($null -eq $value.PSObject.Properties['SelectedSettings']){$value | Add-Member NoteProperty SelectedSettings @($catalog | Where-Object {$_.Default} | ForEach-Object {$_.Name})}
 if($value.SelectedSettings -is [string]){throw 'SelectedSettings debe ser una lista.'}
 foreach($name in @($value.SelectedSettings)){
  if($name -isnot [string] -or @($catalog | Where-Object {$_.Name -ceq $name}).Count -ne 1){throw "Ajuste desconocido: $name"}
 }
 if(@($value.SelectedSettings | Select-Object -Unique).Count -ne @($value.SelectedSettings).Count){throw 'Hay ajustes duplicados.'}
 return $value
}
function Preflight {
 if($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess){throw 'Requiere Windows y PowerShell de 64 bits.'}
 $script:build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
 if($script:build -lt 22000){throw 'Requiere Windows 11.'}
 if($env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'Esta version solo admite Windows x64.'}
 $pending=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
 if($pending){$script:warnings++;Log 'Windows indica un reinicio pendiente. Las tareas pueden requerir revision despues de reiniciar.' 'WARNING'}
 Save-Json ([ordered]@{Build=$script:build;PowerShell=$PSVersionTable.PSVersion.ToString();PendingReboot=$pending;Architecture=$env:PROCESSOR_ARCHITECTURE}) (Join-Path $run 'preflight.json')
}
function Check-IncompleteSession($sid){
 foreach($file in @(Get-ChildItem -LiteralPath $root -Filter backup.json -Recurse)){
  if($file.FullName -eq $journalPath){continue}
  $j=Read-Journal $file.FullName
  if($j.Sid -eq $sid -and $j.Computer -eq $env:COMPUTERNAME -and $j.Status -eq 'Pending'){
   throw 'Hay una ejecucion anterior incompleta. Usa Recuperacion antes de comenzar otra.'
  }
 }
}
function Write-Report($phase,$message){
 $changed=if($null -ne $script:journal){@($script:journal.Registry | Where-Object {$_.State -eq 'Applied'}).Count}else{0}
 $removed=if($null -ne $script:journal){@($script:journal.Apps | Where-Object {$_.State -eq 'Removed'}).Count}else{0}
 $summary=[ordered]@{
  Version='0.9.0';Session=$SessionId;Operation=$Action;Status=$phase;Message=$message
  PreferencesApplied=$changed;TempBytesDeleted=$script:freed;AppsRemoved=$removed
  EngineSeconds=[math]::Round($script:startedAt.Elapsed.TotalSeconds,3);JournalWrites=$script:journalWrites;Warnings=$script:warnings;Rollback=$script:rollback;Steps=$script:steps
  NeedSignOut=($null -ne $script:journal -and $script:journal.Registry.Count -gt 0)
  Reversible='Preferencias, inicio de apps y plan de energia'
  NotReversible='Temporales, desinstalacion de apps, runtimes y reparacion'
 }
 Save-Json $summary (Join-Path $run 'summary.json')
 $enc={param($x) [Net.WebUtility]::HtmlEncode([string]$x)}
 $rows=foreach($e in $script:steps){'<tr><td>'+(& $enc $e.Name)+'</td><td>'+(& $enc $e.State)+'</td><td>'+(& $enc $e.Seconds)+' s</td><td>'+(& $enc $e.Detail)+'</td></tr>'}
 $changes=@()
 if($null -ne $script:journal){
  $changes=foreach($e in $script:journal.Registry){
   '<tr><td>'+(& $enc $e.Name)+'</td><td>'+(& $enc ($e.Before | ConvertTo-Json -Compress))+'</td><td>'+(& $enc ($e.After | ConvertTo-Json -Compress))+'</td><td>'+(& $enc $e.State)+'</td></tr>'
  }
 }
 $html=@'
<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WinBoost / Informe</title>
<style>body{margin:0;background:#0b111b;color:#dce9fa;font:15px Segoe UI,Arial,sans-serif}main{max-width:1100px;margin:48px auto;padding:24px}h1{font-size:36px;color:#75bdff}h2{margin-top:36px}p{line-height:1.6;color:#a9bfd9}table{width:100%;border-collapse:collapse;background:#132033}th,td{text-align:left;padding:12px;border-bottom:1px solid #2a3a51;overflow-wrap:anywhere}th{color:#8ac8ff}.cards{display:flex;gap:16px;flex-wrap:wrap}.card{background:#132033;border:1px solid #2a3a51;border-radius:12px;padding:20px;flex:1;min-width:150px}.number{font-size:28px;color:#76c5ff}small{color:#93a9c4}@media print{body{background:white;color:black}p,small{color:#333}table,.card{background:#f3f5f7}th,td{color:black}}</style><main><small>WINBOOST OPTIMIZER / 0.9</small><h1>Informe de ejecucion</h1>
'@
 $html+='<p><b>'+(& $enc $phase)+'</b> / '+(& $enc $message)+'</p><div class="cards">'
 $html+='<div class="card"><div class="number">'+$changed+'</div>Preferencias aplicadas</div>'
 $html+='<div class="card"><div class="number">'+([math]::Round($script:freed/1048576,1))+' MB</div>Temporales eliminados</div>'
 $html+='<div class="card"><div class="number">'+$removed+'</div>Apps desinstaladas</div>'
 $html+='<div class="card"><div class="number">'+$script:warnings+'</div>Avisos</div></div>'
 $html+='<h2>Secuencia ejecutada</h2><table><tr><th>Tarea</th><th>Resultado</th><th>Duracion</th><th>Detalle</th></tr>'+($rows -join '')+'</table>'
 $html+='<h2>Diario de preferencias</h2><table><tr><th>Valor</th><th>Original</th><th>Objetivo</th><th>Estado</th></tr>'+($changes -join '')+'</table>'
 $previewFile=Join-Path $run 'preview.json'
 if(Test-Path -LiteralPath $previewFile){
  $preview=@(Get-Content -LiteralPath $previewFile -Raw -Encoding UTF8 | ConvertFrom-Json)
  $html+='<h2>Vista previa: no aplicada</h2><table><tr><th>Ajuste</th><th>Actual</th><th>Objetivo</th></tr>'
  foreach($e in $preview){$html+='<tr><td>'+(& $enc $e.Ajuste)+'</td><td>'+(& $enc ($e.Antes | ConvertTo-Json -Compress))+'</td><td>'+(& $enc $e.Despues)+'</td></tr>'}
  $html+='</table>'
 }
 if(Test-Path -LiteralPath (Join-Path $run 'plan.json')){
  $plan=Get-Content -LiteralPath (Join-Path $run 'plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $html+='<h2>Modulos solicitados</h2><p>'+(& $enc (($plan.PSObject.Properties | Where-Object {$_.Value -eq $true} | ForEach-Object {$_.Name}) -join ', '))+'</p>'
 }
 $html+='<p>Reversion automatica: '+(& $enc $script:rollback)+'. Los estados JSON antes/despues y el registro estan en esta carpeta. El diagnostico ampliado reutiliza datos estaticos del primer inventario. Los resultados no son benchmarks de FPS, ping o temperatura.</p>'
 $html+='<p>Restaurar cubre preferencias, inicio y energia. No recupera temporales borrados, datos de apps, runtimes ni reparaciones. Algunas preferencias pueden ser ignoradas por Windows segun su version o politicas.</p></main></html>'
 [IO.File]::WriteAllText((Join-Path $run 'report.html'),$html,(New-Object Text.UTF8Encoding($false)))
}
