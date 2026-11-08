#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('Apply','Restore','Preview')][string]$Action='Preview',
 [string]$RequestFile,
 [Parameter(Mandatory=$true)][string]$SessionId
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$parsedId=[guid]::Empty
if(-not [guid]::TryParseExact($SessionId,'D',[ref]$parsedId)){throw 'Identificador invalido.'}
$root=Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03'
$run=Join-Path $root $SessionId
New-Item -ItemType Directory -Path $run -Force | Out-Null
$logPath=Join-Path $run 'activity.log'
$statusPath=Join-Path $run 'status.json'
$journalPath=Join-Path $run 'backup.json'
[object[]]$catalog=Get-Content (Join-Path $PSScriptRoot 'Catalog.json') -Raw | ConvertFrom-Json
$script:warnings=0;$script:step=0;$script:total=1;$script:freed=0L
$script:journalWrites=0;$script:startedAt=[Diagnostics.Stopwatch]::StartNew();$script:inventoryCache=$null;
$script:steps=@();$script:journal=$null;$script:rollback='No solicitado';$script:cancelPath=Join-Path $run 'cancel.request'
function Save-Json($value,$file){
 if([IO.Path]::GetFileName($file) -eq 'backup.json'){$script:journalWrites++}
 $text=ConvertTo-Json -InputObject $value -Depth 20
 $tmp=$file+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($text)
 try{
  $stream=New-Object IO.FileStream($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  # Reemplazo en el mismo volumen; conservar la version previa del diario.
  if([IO.File]::Exists($file)){
   $previous=if([IO.Path]::GetFileName($file) -eq 'backup.json'){$file+'.previous'}else{[NullString]::Value}
   for($attempt=0;$attempt -lt 6;$attempt++){
    try{[IO.File]::Replace($tmp,$file,$previous);break}
    catch [IO.IOException]{if($attempt -eq 5){throw};Start-Sleep -Milliseconds (20*($attempt+1))}
   }
  }else{[IO.File]::Move($tmp,$file)}
 }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
}
function Read-Journal($file){
 try{return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)}
 catch{
  if(Test-Path -LiteralPath ($file+'.previous')){
   Log ('Diario principal ilegible; recuperando copia anterior: '+$file) 'WARNING'
   $script:warnings++
   return (Get-Content -LiteralPath ($file+'.previous') -Raw -Encoding UTF8 | ConvertFrom-Json)
  }
  throw
 }
}
function Check-Cancellation {
 if(Test-Path -LiteralPath $script:cancelPath){throw [OperationCanceledException]::new('Detencion solicitada. No se iniciaran mas tareas.')}
}

function Log($message,$level='INFO'){
 $line='[{0}] {1} {2}' -f (Get-Date -Format 'HH:mm:ss'),$level,$message
 Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Status($phase,$message,$percent){Save-Json ([ordered]@{Phase=$phase;Message=$message;Percent=$percent;Warnings=$script:warnings;Updated=(Get-Date).ToString('o')}) $statusPath}
function Stage($name,[scriptblock]$body,[bool]$critical=$false){
 Check-Cancellation
 $entry=[pscustomobject]@{Name=$name;State='Running';Started=(Get-Date).ToString('o');Seconds=0;Detail=''}
 $script:steps+=$entry
 Status 'Running' $name ([int](100*$script:step/$script:total));Log $name
 $watch=[Diagnostics.Stopwatch]::StartNew()
 try{& $body;$entry.State='Completed'}
 catch [OperationCanceledException]{$entry.State='Cancelled';$entry.Detail=$_.Exception.Message;throw}
 catch{$entry.State=if($critical){'Failed'}else{'Warning'};$entry.Detail=$_.Exception.Message;$script:warnings++;Log $_.Exception.Message 'WARNING';if($critical){throw}}
 finally{
  $entry.Seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)
  Save-Json $script:steps (Join-Path $run 'steps.json');$script:step++
 }
}

function Read-Reg($path,$name){
 $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
 try{
  $exists=($null -ne $k -and $k.GetValueNames() -contains $name)
  $value=$null;$kind=$null
  if($exists){
   $kind=$k.GetValueKind($name).ToString()
   if($kind -notin @('DWord','String','ExpandString')){throw "Tipo inesperado: $name ($kind)"}
   $value=$k.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  }
  return [pscustomobject]@{Exists=$exists;Kind=$kind;Value=$value}
 }finally{if($null -ne $k){$k.Dispose()}}
}
function Write-Reg($path,$name,$value,$kind){
 $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
 try{
  $v=$value
  if($kind -eq 'DWord'){$v=[int]$value}else{$v=[string]$value}
  $key.SetValue($name,$v,[Microsoft.Win32.RegistryValueKind]::$kind)
 }finally{$key.Dispose()}
}
function Remove-Reg($path,$name){
 $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path,$true)
 try{if($null -ne $key){$key.DeleteValue($name,$false)}}finally{if($null -ne $key){$key.Dispose()}}
}
function Same-State($a,$b){return ($a.Exists -eq $b.Exists -and ((-not $a.Exists) -or ($a.Kind -eq $b.Kind -and [string]$a.Value -ceq [string]$b.Value)))}
function Native($exe,[string[]]$arguments){
 $out=& $exe @arguments 2>&1 | Out-String
 $code=$LASTEXITCODE
 if($out){Add-Content -LiteralPath $logPath -Value $out -Encoding UTF8}
 if($code -ne 0){throw "$exe devolvio $code"}
 return $out
}
function Power-Guid {
 $s=Native 'powercfg.exe' @('/getactivescheme')
 $match=[regex]::Match($s,'[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}')
 if(-not $match.Success){throw 'No se pudo identificar el plan de energia.'}
 return $match.Value.ToLowerInvariant()
}
function Inventory($file){
 $result=[ordered]@{Date=(Get-Date).ToString('o');Build=$script:build;Mode='Light';Errors=@()}
 $result.CPU=$env:PROCESSOR_IDENTIFIER
 $result.LogicalProcessors=$env:NUMBER_OF_PROCESSORS
 $result.Disks=@([IO.DriveInfo]::GetDrives() | Where-Object {$_.DriveType -eq 'Fixed' -and $_.IsReady} | ForEach-Object {
  [pscustomobject]@{DeviceID=$_.Name;Size=$_.TotalSize;FreeSpace=$_.AvailableFreeSpace}
 })
 if($cfg.DeepInventory){
  $result.Mode='Detailed'
  if($null -eq $script:inventoryCache){
   $cache=[ordered]@{}
   foreach($name in @('CPU','GPU','Memory','Startup','Network','DNS','Power')){
    Check-Cancellation
    try{
     $cache[$name]=switch($name){
      CPU {@(Get-CimInstance Win32_Processor -OperationTimeoutSec 5 | Select-Object Name)}
      GPU {@(Get-CimInstance Win32_VideoController -OperationTimeoutSec 5 | Select-Object -Property @('Name','DriverVersion'))}
      Memory {@(Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 5 | Select-Object TotalPhysicalMemory)}
      Startup {@(Get-CimInstance Win32_StartupCommand -OperationTimeoutSec 5 | Select-Object -Property @('Name','Command','Location'))}
      Network {@(Get-NetAdapter | Select-Object -Property @('Name','Status','LinkSpeed'))}
      DNS {@(Get-DnsClientServerAddress | Select-Object -Property @('InterfaceAlias','AddressFamily','ServerAddresses'))}
      Power {Power-Guid}
     }
    }catch [OperationCanceledException]{throw}
    catch{$result.Errors+="$name : $($_.Exception.Message)";$script:warnings++;Log "Inventario $name : $($_.Exception.Message)" 'WARNING'}
   }
   $script:inventoryCache=$cache
   $result.SnapshotNote='Hardware, inicio y red consultados al comenzar el diagnostico ampliado.'
  }else{$result.SnapshotNote='Hardware, inicio y red reutilizados del primer inventario; no son una segunda medicion.'}
  foreach($name in $script:inventoryCache.Keys){$result[$name]=$script:inventoryCache[$name]}
  $result.Processes=@(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 -Property @('ProcessName','Id','WorkingSet64'))
 }
 Save-Json $result $file
 return $result
}

function Get-TempCandidates {
 $temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
 $profile=[IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')+'\'
 if(-not $temp.StartsWith($profile,[StringComparison]::OrdinalIgnoreCase)){throw 'TEMP fuera del perfil: limpieza omitida.'}
 # Rechazar enlaces en cualquiera de los ancestros hasta la raiz del volumen.
 $node=Get-Item -LiteralPath $temp -Force
 while($null -ne $node){
  if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'TEMP usa un enlace: limpieza omitida.'}
  $node=$node.Parent
 }
 $queue=New-Object 'Collections.Generic.Queue[string]'
 $queue.Enqueue($temp)
 $result=New-Object 'Collections.Generic.List[object]'
 $cutoff=(Get-Date).AddDays(-7);$examined=0;$directories=0;$bytes=0L
 while($queue.Count -gt 0 -and $examined -lt 10000 -and $directories -lt 1000){
  $dir=$queue.Dequeue();$directories++
  foreach($f in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)){
   if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
   if($f.PSIsContainer){if($queue.Count -lt 1000){$queue.Enqueue($f.FullName)};continue}
   $examined++
   if($f.LastWriteTime -lt $cutoff -and $f.LastAccessTime -lt $cutoff -and $bytes+$f.Length -le 1073741824){
    $result.Add([pscustomobject]@{Path=$f.FullName;Length=$f.Length;LastWriteTimeUtc=$f.LastWriteTimeUtc.ToString('o')});$bytes+=$f.Length
   }
   if($examined -ge 10000){break}
  }
 }
 return $result.ToArray()
}
function Selected-Catalog {
 $groups=@()
 if($cfg.Privacy){$groups+=@('Privacy','Suggestions','Interface')}
 if($cfg.Captures){$groups+='Captures'}
 if($cfg.Mouse){$groups+='Mouse'}
 $selected=@($catalog | Where-Object {$_.Module -in $groups -and $_.Name -in $cfg.SelectedSettings})
 if($cfg.GameExecutable){
  $selected+=[pscustomobject]@{Path='Software\Microsoft\DirectX\UserGpuPreferences';Name=$cfg.GameExecutable;Label='GPU de alto rendimiento / '+[IO.Path]::GetFileName($cfg.GameExecutable);Kind='String';Value=$null;Module='GameGpu'}
 }
 return $selected
}
function Apply-RegistryEntry($path,$name,$after,$label){
 Check-Cancellation
 $old=Read-Reg $path $name
 if(Same-State $old $after){Log "Ya configurado: $label";return}
 $entry=[pscustomobject]@{Path=$path;Name=$name;Before=$old;After=$after;State='Planned'}
 $script:journal.Registry+=$entry
 Save-Json $script:journal $journalPath
 if(-not (Same-State (Read-Reg $path $name) $old)){$entry.State='NotApplied';Save-Json $script:journal $journalPath;throw "Cambio simultaneo detectado: $label"}
 if($after.Exists){Write-Reg $path $name $after.Value $after.Kind}else{Remove-Reg $path $name}
 if(-not (Same-State (Read-Reg $path $name) $after)){throw "No se verifico: $label"}
 $entry.State='Applied';Save-Json $script:journal $journalPath
 Log "Aplicado: $label"
}
function Registry-Apply {
 $script:alreadyConfigured=@()
 $batch=@()
 # Primero persistir TODOS los originales. Planned tambien se puede recuperar
 # despues de una interrupcion, comparando contra el valor original y objetivo.
 foreach($c in @(Selected-Catalog)){
  Check-Cancellation
  $old=Read-Reg $c.Path $c.Name
  $target=if($c.Module -eq 'GameGpu'){Get-GameGpuTarget $old}else{$c.Value}
  $after=[pscustomobject]@{Exists=$true;Kind=$c.Kind;Value=$target}
  if(Same-State $old $after){$script:alreadyConfigured+=$c.Label;Log "Ya configurado: $($c.Label)";continue}
  $batch+=[pscustomobject]@{Path=$c.Path;Name=$c.Name;Before=$old;After=$after;State='Planned'}
 }
 if($batch.Count -eq 0){Log 'La seleccion ya esta configurada.';return}
 $script:journal.Registry+=$batch
 Save-Json $script:journal $journalPath
 $count=0
 foreach($entry in $batch){
  Check-Cancellation
  if(-not (Same-State (Read-Reg $entry.Path $entry.Name) $entry.Before)){
   $entry.State='NotApplied';Save-Json $script:journal $journalPath
   throw "Cambio simultaneo detectado: $($entry.Name)"
  }
  Write-Reg $entry.Path $entry.Name $entry.After.Value $entry.After.Kind
  if(-not (Same-State (Read-Reg $entry.Path $entry.Name) $entry.After)){throw "No se verifico: $($entry.Name)"}
  $entry.State='Applied';$count++
  Log "Aplicado: $($entry.Name)"
  if($count % 8 -eq 0){Save-Json $script:journal $journalPath}
 }
 Save-Json $script:journal $journalPath
}

function Apply-Startup {
 foreach($name in @('Discord','Steam','EpicGamesLauncher','Spotify')){
  $path='Software\Microsoft\Windows\CurrentVersion\Run'
  $old=Read-Reg $path $name
  if($old.Exists){Apply-RegistryEntry $path $name ([pscustomobject]@{Exists=$false;Kind=$null;Value=$null}) ('Inicio automatico: '+$name)}
 }
}

function Apply-Power {
 Add-Type -AssemblyName System.Windows.Forms
 if([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -ne 'Online'){throw 'Equipo sin alimentacion de CA: energia omitida.'}
 $guid='8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
 $all=Native 'powercfg.exe' @('/list')
 if($all -notmatch $guid){throw 'Alto rendimiento no esta disponible: se conserva el plan actual.'}
 $old=Power-Guid
 if($old -eq $guid){Log 'Alto rendimiento ya esta activo.';return}
 $script:journal.Power=[pscustomobject]@{Before=$old;After=$guid;State='Planned'}
 Save-Json $script:journal $journalPath
 [void](Native 'powercfg.exe' @('/setactive',$guid))
 if((Power-Guid) -ne $guid){throw 'No se verifico el plan de energia.'}
 $script:journal.Power.State='Applied';Save-Json $script:journal $journalPath
 Log 'Alto rendimiento activado. Puede aumentar consumo y temperatura.'
}
function Clean-Temp {
 $candidates=@(Get-TempCandidates)
 Save-Json $candidates (Join-Path $run 'temp-manifest.json')
 foreach($f in $candidates){
  Check-Cancellation
  try{
   $current=Get-Item -LiteralPath $f.Path -Force
   # Comprobar de nuevo todos los ancestros antes de borrar, sin seguir enlaces.
   $ancestor=$current.Directory
   $linked=$false
   while($null -ne $ancestor){if(($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$linked=$true;break};$ancestor=$ancestor.Parent}
   if($linked -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
   if($current.Length -ne $f.Length -or $current.LastWriteTimeUtc.ToString('o') -ne $f.LastWriteTimeUtc){continue}
   if($current.LastAccessTime -ge (Get-Date).AddDays(-7)){continue}
   Remove-Item -LiteralPath $current.FullName -Force -ErrorAction Stop
   $script:freed+=$f.Length;Log "Temporal eliminado: $($f.Path)"
  }catch{Log "Temporal conservado: $($f.Path)" 'SKIP'}
 }
 Log ('Limpieza: {0:N1} MB eliminados; no recuperables con Restaurar.' -f ($script:freed / 1048576))
}
function Remove-OptionalApps {
 # Lista cerrada. Nunca Store, Xbox, Gaming Services, WebView ni frameworks.
 $names=@('Microsoft.BingNews','Microsoft.BingWeather','Microsoft.MicrosoftSolitaireCollection','Clipchamp.Clipchamp','Microsoft.Getstarted','Microsoft.People')
 foreach($name in $names){
  Check-Cancellation
  foreach($app in @(Get-AppxPackage -Name $name)){
   $entry=[pscustomobject]@{Name=$app.Name;PackageFullName=$app.PackageFullName;State='Planned'}
   $script:journal.Apps+=$entry;Save-Json $script:journal $journalPath
   try{
    Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
    if(@(Get-AppxPackage -Name $name).Count -gt 0){throw 'El paquete sigue presente.'}
    $entry.State='Removed';Log "Desinstalado para este usuario: $name"
   }catch{$entry.State='Failed';$script:warnings++;Log "No se desinstalo $name : $($_.Exception.Message)" 'WARNING'}
   Save-Json $script:journal $journalPath
  }
 }
}
function Install-Runtimes {
 $wg=Get-Command winget.exe -ErrorAction SilentlyContinue
 if($null -eq $wg){throw 'WinGet no esta disponible; runtimes omitidos.'}
 foreach($id in @('Microsoft.VCRedist.2015+.x64','Microsoft.VCRedist.2015+.x86','Microsoft.DotNet.DesktopRuntime.8','Microsoft.DotNet.DesktopRuntime.10')){
  Check-Cancellation
  Log "Instalar o actualizar runtime: $id"
  $out=& $wg.Source install --id $id --exact --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
  $code=$LASTEXITCODE
  Add-Content -LiteralPath $logPath -Value $out -Encoding UTF8
  # 0x8A15002B = no hay actualizacion aplicable; no es un fallo de instalacion.
  if($code -ne 0 -and $code -ne -1978335189){$script:warnings++;Log "WinGet $id : codigo $code; revisa salida." 'WARNING'}
 }
}
function Repair-Windows {
 $ps="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
 $argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Repair.ps1')+'"'),'-LogFile',('"'+(Join-Path $run 'repair.log')+'"'))
 $p=Start-Process -FilePath $ps -Verb RunAs -ArgumentList $argsList -Wait -PassThru
 if($p.ExitCode -ne 0){throw "Reparacion termino con codigo $($p.ExitCode). Consulta repair.log."}
 Log 'DISM y SFC finalizaron. Consulta repair.log para el diagnostico; no es una garantia de sistema sano.'
}
function Restore-Latest([string]$BackupPath){
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $files=if($BackupPath){@(Get-Item -LiteralPath $BackupPath)}else{@(Get-ChildItem -LiteralPath $root -Filter backup.json -Recurse)}
 $target=$null
 foreach($file in $files){
  try{$j=Read-Journal $file.FullName}catch{$script:warnings++;Log ('Respaldo ilegible: '+$file.FullName) 'WARNING';continue}
  if($j.Schema -eq 3 -and $j.Sid -eq $sid -and $j.Computer -eq $env:COMPUTERNAME -and $j.Status -ne 'Restored'){
   if($null -eq $target -or [datetime]$j.Date -gt [datetime]$script:journal.Date){$target=$file;$script:journal=$j}
  }
 }
 if($null -eq $target){Log 'No hay sesiones pendientes de restauracion.';return}
 Log "Restaurando $($target.Directory.Name)"
 $conflicts=0
 $entries=@($script:journal.Registry);[array]::Reverse($entries)
 foreach($e in $entries){
  if($e.State -in @('Restored','NotApplied')){continue}
  try{
   $allowed=@($catalog | Where-Object {$_.Path -eq $e.Path -and $_.Name -eq $e.Name})
   $validSetting=($allowed.Count -eq 1 -and $e.After.Exists -and $e.After.Kind -eq $allowed[0].Kind -and [string]$e.After.Value -ceq [string]$allowed[0].Value)
   $validStartup=($e.Path -eq 'Software\Microsoft\Windows\CurrentVersion\Run' -and $e.Name -in @('Discord','Steam','EpicGamesLauncher','Spotify') -and -not $e.After.Exists)
   $validGpu=($e.Path -eq 'Software\Microsoft\DirectX\UserGpuPreferences' -and (Test-GameExecutableName $e.Name) -and $e.After.Exists -and $e.After.Kind -eq 'String' -and [string]$e.After.Value -ceq (Get-GameGpuTarget $e.Before))
   if((-not $validGpu -and -not $validSetting -and -not $validStartup) -or $e.Before.Kind -notin @($null,'DWord','String','ExpandString')){throw 'Entrada de respaldo invalida.'}
   $current=Read-Reg $e.Path $e.Name
   if(Same-State $current $e.Before){$e.State='Restored';Save-Json $script:journal $target.FullName;continue}
   if(-not (Same-State $current $e.After)){throw "Cambio externo: $($e.Name)"}
   if($e.Before.Exists){Write-Reg $e.Path $e.Name $e.Before.Value $e.Before.Kind}
   else{Remove-Reg $e.Path $e.Name}
   if(-not (Same-State (Read-Reg $e.Path $e.Name) $e.Before)){throw "No se verifico la restauracion: $($e.Name)"}
   $e.State='Restored';Save-Json $script:journal $target.FullName;Log "Restaurado: $($e.Name)"
  }catch{$conflicts++;Log $_.Exception.Message 'WARNING'}
 }
 if($null -ne $script:journal.Power -and $script:journal.Power.State -ne 'Restored'){
  try{
   $power=$script:journal.Power
   if($power.Before -notmatch '^[a-f0-9-]{36}$' -or $power.After -ne '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'){throw 'Respaldo de energia invalido.'}
   $current=Power-Guid
   if($current -ne $power.Before){
    if($current -ne $power.After){throw 'Cambio externo en el plan de energia.'}
    [void](Native 'powercfg.exe' @('/setactive',$power.Before))
    if((Power-Guid) -ne $power.Before){throw 'No se verifico restauracion de energia.'}
   }
   $power.State='Restored'
  }catch{$conflicts++;Log $_.Exception.Message 'WARNING'}
 }
 $script:journal.Status=if($conflicts -eq 0){'Restored'}else{'RestoreConflicts'}
 Save-Json $script:journal $target.FullName
 $script:warnings+=$conflicts
 Log 'Restaurar cubre preferencias y energia. No reinstala apps, runtimes ni archivos temporales.'
}
. (Join-Path $PSScriptRoot 'ExtraFunctions.ps1')
$mutex=$null;$held=$false;$exitCode=0;$phase='Failed';$message='Proceso sin finalizar'
try{
 Status 'Running' 'Comprobando equipo' 0
 Preflight
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $mutex=New-Object Threading.Mutex($false,('Local\WinBoostOptimizerV03-'+$sid))
 try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(-not $held){throw 'Otra ejecucion WinBoost esta trabajando en este usuario.'}
 if($Action -eq 'Restore'){
  $script:total=1
  Stage 'Restaurar ultima sesion pendiente' {Restore-Latest}
 }else{
  if(-not $RequestFile){throw 'Falta la seleccion de modulos.'}
  $cfg=Validate-Config (Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json)
  if($cfg.GameExecutable -and -not (Test-Path -LiteralPath $cfg.GameExecutable -PathType Leaf)){throw 'El ejecutable del juego no existe en este equipo. Selecciona su ubicación actual.'}
  if($Action -eq 'Preview'){
   $script:total=2
   Stage 'Inventario ligero del equipo' {[void](Inventory (Join-Path $run 'inventory.json'))}
   Stage 'Plan exacto de preferencias' {
    $list=@(Selected-Catalog | ForEach-Object {
     $current=Read-Reg $_.Path $_.Name
     $target=if($_.Module -eq 'GameGpu'){Get-GameGpuTarget $current}else{$_.Value}
     [pscustomobject]@{Ajuste=$_.Label;Nombre=$_.Name;Antes=$current;Despues=$target;Tipo=$_.Kind}
    })
    Save-Json $list (Join-Path $run 'preview.json')
    Save-Json $cfg (Join-Path $run 'plan.json')
    Log "Analisis sin cambios: $($list.Count) preferencias. Los modulos adicionales estan en plan.json."
   }
  }else{
   Check-IncompleteSession $sid
   $script:journal=[pscustomobject]@{Schema=3;Computer=$env:COMPUTERNAME;Sid=$sid;Date=(Get-Date).ToString('o');Status='Pending';Registry=@();Power=$null;Apps=@();Options=$cfg;Version='0.9.0'}
   Save-Json $script:journal $journalPath
   $script:total=3+@('Startup','Power','Cleanup','Apps','Runtimes','Repair' | Where-Object {$cfg.$_}).Count
   Stage 'Estado inicial' {$script:before=Inventory (Join-Path $run 'before.json')}
   Stage 'Preferencias seleccionadas, con verificacion y respaldo' {Registry-Apply} $true
   if($cfg.Startup){Stage 'Reducir inicio automatico de cuatro apps opcionales' {Apply-Startup} $true}
   if($cfg.Power){Stage 'Alto rendimiento cuando este disponible' {Apply-Power}}
   if($cfg.Cleanup){Stage 'Limpiar temporales antiguos' {Clean-Temp}}
   if($cfg.Apps){Stage 'Desinstalar apps opcionales' {Remove-OptionalApps}}
   if($cfg.Runtimes){Stage 'Instalar runtimes Microsoft' {Install-Runtimes}}
   if($cfg.Repair){Stage 'Reparar Windows con DISM y SFC' {Repair-Windows}}
   Stage 'Estado final' {$script:after=Inventory (Join-Path $run 'after.json')}
   Check-Cancellation
   $script:journal.Status=if($script:warnings){'CompletedWithWarnings'}else{'Completed'}
   Save-Json $script:journal $journalPath
  }
 }
 $phase=if($script:warnings){'CompletedWithWarnings'}else{'Completed'}
 $message=if($Action -eq 'Preview'){'Analisis terminado sin aplicar cambios.'}elseif($Action -eq 'Restore'){'Restauracion terminada. Revisa posibles conflictos.'}else{'Trabajo terminado. Revisa el informe y vuelve a iniciar sesion cuando te convenga.'}
 if($script:warnings){$exitCode=2}
}catch{
 $cancelled=$_.Exception -is [OperationCanceledException]
 $message=$_.Exception.Message
 $phase=if($cancelled){'Cancelled'}else{'Failed'}
 $exitCode=if($cancelled){3}else{1}
 Log $message $(if($cancelled){'CANCEL'}else{'ERROR'})
 if($Action -eq 'Apply' -and $held -and $null -ne $script:journal -and (Test-Path -LiteralPath $journalPath)){
  try{
   Log 'Recuperando las preferencias de esta ejecucion antes de finalizar.'
   Restore-Latest $journalPath
   $script:rollback=if($script:journal.Status -eq 'Restored'){'Preferencias y energia restauradas'}else{'Restauracion con conflictos; revisar diario'}
  }catch{$script:rollback='No se pudo completar la recuperacion: '+$_.Exception.Message;$script:warnings++;Log $script:rollback 'WARNING'}
 }
}finally{
 try{Write-Report $phase $message}catch{Log ('No se pudo crear el informe: '+$_.Exception.Message) 'ERROR';$exitCode=1;$phase='Failed';$message='No se pudo guardar el informe final. Consulta el registro.'}
 try{Status $phase $message 100;Log "Finalizado: $phase"}catch{Write-Error $_ -ErrorAction Continue;$exitCode=1}
 if($held){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
}
exit $exitCode
