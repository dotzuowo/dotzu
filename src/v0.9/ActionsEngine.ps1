#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Preview','Apply','Restore')][string]$Mode='Preview',[string]$PlanFile,[Parameter(Mandatory=$true)][string]$SessionId,[string]$RestoreSessionId)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ActionsCore.ps1')
. (Join-Path $PSScriptRoot 'Sessions.ps1')
$guid=[guid]::Empty
if(-not [guid]::TryParseExact($SessionId,'D',[ref]$guid)){throw 'Sesion no valida.'}
$root=Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03'
$actionRoot=Join-Path $root 'Advanced'
$session=Join-Path $actionRoot $SessionId
New-Item -ItemType Directory -Path $session -Force | Out-Null
$journalFile=Join-Path $session 'backup.json';$journal=$null
$results=@();$state='Failed';$message='';$code=1;$mutex=$null;$held=$false;$irreversible=@();$restartRequired=$false;$warnings=@();$restoredSession=$null
function Progress-State($text,$percent){WB-Save ([pscustomobject]@{Phase=$state;Message=$text;Percent=$percent;Warnings=$warnings.Count}) (Join-Path $session 'status.json')}
try{
 if($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'Requiere Windows 11 x64.'}
 $build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
 if($build -lt 22000){throw 'Requiere Windows 11.'}
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Inicia WinBoost con permisos de administrador.'}
 $catalog=WB-ReadCatalog
 $mutex=New-Object Threading.Mutex($false,('Local\WinBoostOptimizerV03-'+$sid))
 try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(-not $held){throw 'Otra ejecucion WinBoost esta activa.'}
 $state='Running'
 if($Mode -eq 'Restore'){
  $sessions=@(Get-WBSessionHistory $root $sid $env:COMPUTERNAME)
  foreach($s in $sessions | Where-Object {$_.Error}){$warnings+=('Respaldo ilegible conservado: '+$s.BackupPath)}
  $target=Get-WBRestoreSession $sessions $RestoreSessionId 'Advanced'
  if($null -ne $target){
   $restoredSession=$target.SessionId
   if($target.Recovered){$warnings+='Se uso la copia anterior del diario.'}
   $conflicts=WB-Restore $target.Journal $target.BackupPath $catalog
   $state=if($conflicts){'RestoreConflicts'}else{'Restored'}
   $code=if($conflicts){2}else{0};$message='Restauracion de acciones reversibles. Instalaciones, eliminaciones y tareas nativas sin respaldo requieren revision manual.'
  }else{$state='NoPendingBackup';$message='No hay acciones avanzadas pendientes de restauracion.';$code=0}
 }else{
  if($RestoreSessionId){throw 'RestoreSessionId solo se admite en Restore.'}
  if(-not $PlanFile){throw 'Falta el plan JSON.'}
  $plan=Get-Content -LiteralPath $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $items=@(WB-ValidatePlan $plan $catalog)
  if(-not $items.Count){throw 'Selecciona al menos una accion.'}
  WB-Save $plan (Join-Path $session 'plan.json')
  $i=0
  foreach($item in $items){
   Progress-State ('Comprobando: '+$item.Definition.Label) ([int](20*$i/$items.Count))
   WB-CheckSupport $item.Definition $item.Argument $build
   $results+=[pscustomobject]@{Id=$item.Definition.Id;Label=$item.Definition.Label;Choice=$item.Choice.Label;Argument=$item.Argument;Type=$item.Definition.Type;Reversible=$item.Definition.Reversible;Before=$(if($item.Definition.Reversible){WB-Current $item.Definition}else{$null});Target=(WB-Target $item.Definition $item.Choice);Status='Planned';RestartRequired=$false;Detail=$item.Definition.Description}
   $i++
  }
  if($Mode -eq 'Preview'){$state='Preview';$message='Plan comprobado sin aplicar cambios. Las acciones asistidas requieren intervencion manual.';$code=0}
  else{
   foreach($s in @(Get-WBSessionHistory $root $sid $env:COMPUTERNAME)){
    if($s.Error){throw ('Respaldo ilegible; revisa Recuperacion antes de aplicar: '+$s.BackupPath)}
    if($s.Recovered){throw ('Diario recuperado desde copia anterior; restaura la sesion antes de aplicar: '+$s.SessionId)}
    if($s.Status -eq 'Pending'){throw 'Hay una sesion incompleta. Restaura esa sesion antes de aplicar otro plan.'}
   }
   $journal=[pscustomobject]@{Schema=4;Version='0.9';Sid=$sid;Computer=$env:COMPUTERNAME;Date=(Get-Date).ToString('o');Status='Pending';Entries=@()}
   WB-Save $journal $journalFile
   for($i=0;$i -lt $items.Count;$i++){
    if(Test-Path -LiteralPath (Join-Path $session 'cancel.request')){throw [OperationCanceledException]::new('Detencion solicitada.')}
    $item=$items[$i];$row=$results[$i]
    Progress-State ('Ejecutando: '+$item.Definition.Label) (20+[int](75*$i/$items.Count))
    $row.Status='Running';WB-Save $results (Join-Path $session 'results.json')
    try{
     if($item.Definition.Reversible){$row.Status=WB-ApplyReversible $item $journal $journalFile}
     else{
      # Registrar la intencion ANTES de una operacion que puede ser irreversible.
      $irreversible+=$item.Definition.Id
      WB-Save $irreversible (Join-Path $session 'manual-review.json')
      $output=WB-InvokeNative $item $session
      foreach($part in @($output)){
       if($null -ne $part -and (($null -ne $part.PSObject.Properties['RestartRequired'] -and [string]$part.RestartRequired -in @('True','Yes')) -or ($null -ne $part.PSObject.Properties['RestartNeeded'] -and [string]$part.RestartNeeded -in @('True','Yes')))){$row.RestartRequired=$true;$restartRequired=$true}
      }
      $row.Detail=$output | ConvertTo-Json -Depth 10 -Compress
      $row.Status=if($item.Definition.Type -eq 'Settings'){'OpenedForManualAction'}else{'CommandCompleted'}
     }
    }catch{$row.Status='Failed';$row.Detail=$_.Exception.Message;throw}
    finally{WB-Save $results (Join-Path $session 'results.json')}
   }
   $journal.Status='Completed';WB-Save $journal $journalFile
   $state='Completed';$code=0;$message='Plan terminado. RegistryVerified verifica valores, no efectos visuales. OpenedForManualAction solo abre controles; CommandCompleted no es una prueba funcional.'
  }
 }
}catch{
 $message=$_.Exception.Message;$state=if($_.Exception -is [OperationCanceledException]){'Cancelled'}else{'Failed'};$code=if($state -eq 'Cancelled'){3}else{1}
 if($null -ne $journal -and $held){
  try{
   $n=WB-Restore $journal $journalFile $catalog
   foreach($entry in $journal.Entries){
    $affected=@($results | Where-Object {$_.Id -eq $entry.Id})
    foreach($row in $affected){if($entry.State -eq 'Restored'){$row.Status='RestoredAfterFailure'}elseif($entry.State -ne 'NotApplied'){$row.Status='RestoreConflict'}}
   }
   $message+=' | Recuperacion de estados reversibles: '+$n+' conflictos.'
  }
  catch{$message+=' | Recuperacion incompleta: '+$_.Exception.Message}
 }
 foreach($r in $results){if($r.Status -eq 'Planned'){$r.Status='NotRun'}}
}finally{
 try{
  if($restartRequired){$message+=' Reinicio requerido; WinBoost no reinicia automaticamente.'}
  if($warnings.Count){$message+=' Avisos: '+($warnings -join ' | ');if($code -eq 0){$code=2}}
  $summary=[pscustomobject]@{Version='0.9';Session=$SessionId;RestoredSession=$restoredSession;Status=$state;Message=$message;Mode=$Mode;ExitCode=$code;RestartRequired=$restartRequired;Warnings=$warnings.Count;WarningDetails=$warnings;Results=$results;ManualReview=$irreversible}
  WB-Save $summary (Join-Path $session 'summary.json')
  $encode={param($v) [Net.WebUtility]::HtmlEncode([string]$v)}
  $rows=foreach($r in $results){'<tr><td>'+(& $encode $r.Label)+'</td><td>'+(& $encode $r.Choice)+'</td><td>'+(& $encode $r.Status)+'</td><td>'+(& $encode $r.Detail)+'</td></tr>'}
  $html='<html lang="es"><meta charset="utf-8"><title>WinBoost / Acciones</title><style>body{font:15px Segoe UI,Arial;background:#0b111b;color:#dce9fa;padding:40px}h1{color:#79b8fb}table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:14px;border-bottom:1px solid #32445b;overflow-wrap:anywhere}p{line-height:1.6}</style><h1>WinBoost / '+(& $encode $state)+'</h1><p>'+(& $encode $message)+'</p><table><tr><th>Accion</th><th>Seleccion</th><th>Estado</th><th>Detalle</th></tr>'+($rows -join '')+'</table><p>Restaurar cubre Registro, preferencias de Defender, DiagTrack y plan de energia. No deshace instalaciones, desinstalaciones, limpiezas ni acciones manuales. Ninguna accion garantiza mejoras de FPS.</p></html>'
  [IO.File]::WriteAllText((Join-Path $session 'report.html'),$html,(New-Object Text.UTF8Encoding($false)))
  Progress-State ($state+': '+$message) 100
 }catch{Write-Error ('No se pudo guardar el informe: '+$_.Exception.Message) -ErrorAction Continue;$code=1}
 if($held){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
}
exit $code
