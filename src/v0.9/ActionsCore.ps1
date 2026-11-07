# WinBoost: funciones importables, sin cambios al cargar el archivo.
function WB-ReadCatalog {
 return @(Get-Content (Join-Path $PSScriptRoot 'Actions.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function WB-ValidatePlan($plan,$catalog){
 if($null -eq $plan -or $null -eq $plan.PSObject.Properties['Schema'] -or $plan.Schema -ne 1){throw 'Formato de plan no valido.'}
 if($null -eq $plan.PSObject.Properties['Actions'] -or $plan.Actions -is [string]){throw 'Falta la lista de acciones.'}
 $seen=@{};$result=@()
 foreach($row in @($plan.Actions)){
  if($null -eq $row.PSObject.Properties['Id'] -or $null -eq $row.PSObject.Properties['Choice']){throw 'Accion incompleta.'}
  $matches=@($catalog | Where-Object {$_.Id -ceq $row.Id})
  if($matches.Count -ne 1 -or $seen.ContainsKey([string]$row.Id)){throw 'Accion desconocida o duplicada.'}
  $a=$matches[0];$seen[$a.Id]=$true
  $choices=@($a.Choices | Where-Object {$_.Label -ceq $row.Choice})
  if($choices.Count -ne 1){throw ('Opcion desconocida: '+$a.Label)}
  $arg=if($null -ne $row.PSObject.Properties['Argument']){[string]$row.Argument}else{''}
  if($a.Argument -and [string]::IsNullOrWhiteSpace($arg)){throw ('Indica el argumento de '+$a.Label)}
  if($arg.Length -gt 2048 -or $arg -match '[\r\n\x00]'){throw 'Argumento no valido.'}
  if($a.Type -in @('Feature','Capability','Appx') -and $arg -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._~+-]{0,199}$'){throw 'Usa un nombre exacto del inventario, sin comodines.'}
  if($a.Type -eq 'ImportAssociations'){
   if(-not [IO.Path]::IsPathRooted($arg) -or [IO.Path]::GetExtension($arg) -ne '.xml' -or $arg.Contains('"')){throw 'Indica una ruta absoluta a un XML.'}
  }
  $result+= [pscustomobject]@{Definition=$a;Choice=$choices[0];Argument=$arg}
 }
 return $result
}
function WB-Save($value,$path){
 $text=ConvertTo-Json -InputObject $value -Depth 30
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($tmp,$text,(New-Object Text.UTF8Encoding($false)))
  if([IO.File]::Exists($path)){[IO.File]::Replace($tmp,$path,$path+'.bak')}else{[IO.File]::Move($tmp,$path)}
 }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function WB-ReadJournal($path){
 try{return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json}
 catch{return Get-Content -LiteralPath ($path+'.bak') -Raw -Encoding UTF8 | ConvertFrom-Json}
}
function WB-RegistryRoot($hive){
 if($hive -eq 'HKCU'){return [Microsoft.Win32.Registry]::CurrentUser}
 if($hive -eq 'HKLM'){return [Microsoft.Win32.Registry]::LocalMachine}
 throw 'Colmena no admitida.'
}
function WB-RegRead($a){
 $key=(WB-RegistryRoot $a.Hive).OpenSubKey($a.Path)
 try{
  if($null -eq $key -or $key.GetValueNames() -notcontains $a.Name){return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}}
  $kind=$key.GetValueKind($a.Name).ToString()
  if($kind -notin @('DWord','String','ExpandString')){throw ('Tipo de Registro no admitido: '+$kind)}
  return [pscustomobject]@{Exists=$true;Kind=$kind;Value=$key.GetValue($a.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
 }finally{if($null -ne $key){$key.Dispose()}}
}
function WB-RegWrite($a,$state){
 if(-not $state.Exists){
  $key=(WB-RegistryRoot $a.Hive).OpenSubKey($a.Path,$true)
  try{if($null -ne $key){$key.DeleteValue($a.Name,$false)}}finally{if($null -ne $key){$key.Dispose()}}
  return
 }
 if($state.Kind -notin @('DWord','String','ExpandString')){throw 'Tipo de respaldo no admitido.'}
 $key=(WB-RegistryRoot $a.Hive).CreateSubKey($a.Path)
 try{
  $v=if($state.Kind -eq 'DWord'){[int]$state.Value}else{[string]$state.Value}
  $key.SetValue($a.Name,$v,[Microsoft.Win32.RegistryValueKind]::$($state.Kind))
 }finally{$key.Dispose()}
}
function WB-Same($a,$b){
 return (($a | ConvertTo-Json -Depth 10 -Compress) -ceq ($b | ConvertTo-Json -Depth 10 -Compress))
}
function WB-Native($exe,[string[]]$arguments){
 $result=& $exe @arguments 2>&1 | Out-String
 $code=$LASTEXITCODE
 if($code -notin @(0,3010)){throw ($exe+' devolvio '+$code+': '+$result)}
 return [pscustomobject]@{ExitCode=$code;Output=$result;RestartRequired=($code -eq 3010)}
}
function WB-PowerState {
 $output=(WB-Native 'powercfg.exe' @('/getactivescheme')).Output
 $m=[regex]::Match($output,'[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}')
 if(-not $m.Success){throw 'No se pudo leer el plan de energia.'}
 return $m.Value.ToLowerInvariant()
}
function WB-Current($a){
 switch($a.Type){
  'Registry' {return WB-RegRead $a}
  'Defender' {return [int](Get-MpPreference -ErrorAction Stop).($a.Property)}
  'Power' {return WB-PowerState}
  'Service' {
   $s=Get-Service -Name $a.Service -ErrorAction Stop
   if([string]$s.Status -notin @('Running','Stopped')){throw 'El servicio esta en transicion o pausado.'}
   return [pscustomobject]@{StartType=[string]$s.StartType;Running=($s.Status -eq 'Running')}
  }
  default {return $null}
 }
}
function WB-Target($a,$choice){
 switch($a.Type){
  'Registry' {return [pscustomobject]@{Exists=($null -ne $choice.Value);Kind=$(if($null -ne $choice.Value){$a.Kind}else{$null});Value=$choice.Value}}
  'Defender' {return [int]$choice.Value}
  'Power' {return [string]$choice.Value}
  'Service' {return [pscustomobject]@{StartType=[string]$choice.Value;Running=($choice.Value -ne 'Disabled')}}
  default {return $null}
 }
}
function WB-SetState($a,$state){
 switch($a.Type){
  'Registry' {WB-RegWrite $a $state}
  'Defender' {
   if([int]$state -notin @(0,1,2,6)){throw 'Estado Defender no valido.'}
   $params=@{ErrorAction='Stop'};$params[$a.Property]=[int]$state
   Set-MpPreference @params
  }
  'Power' {
   if([string]$state -notmatch '^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$'){throw 'Plan de energia no valido.'}
   [void](WB-Native 'powercfg.exe' @('/setactive',[string]$state))
  }
  'Service' {
   if($state.StartType -notin @('Automatic','Manual','Disabled') -or $state.Running -isnot [bool]){throw 'Estado de servicio no valido.'}
   if(-not $state.Running){Stop-Service -Name $a.Service -ErrorAction Stop}
   Set-Service -Name $a.Service -StartupType $state.StartType -ErrorAction Stop
   if($state.Running){Start-Service -Name $a.Service -ErrorAction Stop}
   (Get-Service -Name $a.Service).WaitForStatus($(if($state.Running){'Running'}else{'Stopped'}),[TimeSpan]::FromSeconds(15))
  }
  default {throw 'Accion sin restauracion automatica.'}
 }
}
function WB-CheckSupport($a,$argument,$build){
 if($build -lt $a.MinBuild){throw ('Requiere compilacion '+$a.MinBuild+' o posterior.')}
 switch($a.Type){
  'Defender' {Get-Command Set-MpPreference -ErrorAction Stop | Out-Null;Get-MpComputerStatus -ErrorAction Stop | Out-Null}
  'Feature' {Get-WindowsOptionalFeature -Online -FeatureName $argument -ErrorAction Stop | Out-Null}
  'Sandbox' {Get-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -ErrorAction Stop | Out-Null}
  'Capability' {
   $match=@(Get-WindowsCapability -Online -Name $argument -ErrorAction Stop | Where-Object {$_.Name -ceq $argument})
   if($match.Count -ne 1){throw 'Capacidad no encontrada.'}
  }
  'Appx' {
   $match=@(Get-AppxPackage -Name $argument -ErrorAction Stop | Where-Object {$_.Name -ceq $argument})
   if($match.Count -ne 1 -or $match[0].NonRemovable -or $match[0].IsFramework -or $match[0].IsResourcePackage){throw 'App inexistente, ambigua, protegida o dependencia.'}
  }
  'Winget' {Get-Command winget.exe -ErrorAction Stop | Out-Null}
  'WSL' {Get-Command wsl.exe -ErrorAction Stop | Out-Null}
  'ImportAssociations' {
   if(-not (Test-Path -LiteralPath $argument -PathType Leaf)){throw 'XML inexistente.'}
   if((Get-Item -LiteralPath $argument).Length -gt 5MB){throw 'XML demasiado grande.'}
   $settings=New-Object Xml.XmlReaderSettings;$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
   $reader=[Xml.XmlReader]::Create($argument,$settings)
   try{$doc=New-Object Xml.XmlDocument;$doc.XmlResolver=$null;$doc.Load($reader);if($doc.DocumentElement.Name -ne 'DefaultAssociations'){throw 'XML no es de asociaciones.'}}finally{$reader.Dispose()}
  }
  'Service' {Get-Service -Name $a.Service -ErrorAction Stop | Out-Null}
 }
}
function WB-InvokeNative($item,$session){
 $a=$item.Definition;$v=$item.Choice.Value;$arg=$item.Argument
 switch($a.Type){
  'RestorePoint' {Checkpoint-Computer -Description ('WinBoost '+(Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop;return 'Solicitud de punto de restauracion completada; comprobar en Proteccion del sistema.'}
  'Hibernation' {return WB-Native 'powercfg.exe' @('/hibernate',[string]$v)}
  'ReservedStorage' {return Set-WindowsReservedStorageState -State $v -Online -ErrorAction Stop}
  'Feature' {
   if($v -eq 'Enable'){return Enable-WindowsOptionalFeature -Online -FeatureName $arg -All -NoRestart -ErrorAction Stop}
   return Disable-WindowsOptionalFeature -Online -FeatureName $arg -NoRestart -ErrorAction Stop
  }
  'Sandbox' {
   if($v -eq 'Enable'){return Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -All -NoRestart -ErrorAction Stop}
   return Disable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -NoRestart -ErrorAction Stop
  }
  'Capability' {
   if($v -eq 'Install'){return Add-WindowsCapability -Online -Name $arg -ErrorAction Stop}
   return Remove-WindowsCapability -Online -Name $arg -ErrorAction Stop
  }
  'WSL' {return WB-Native 'wsl.exe' @('--install','--no-launch')}
  'Winget' {return WB-Native 'winget.exe' @('install','--id',[string]$v,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')}
  'Appx' {
   $p=@(Get-AppxPackage -Name $arg -ErrorAction Stop | Where-Object {$_.Name -ceq $arg})
   if($p.Count -ne 1 -or $p[0].NonRemovable -or $p[0].IsFramework -or $p[0].IsResourcePackage){throw 'Paquete no permitido.'}
   Remove-AppxPackage -Package $p[0].PackageFullName -ErrorAction Stop
   if(@(Get-AppxPackage -Name $arg | Where-Object {$_.Name -ceq $arg}).Count){throw 'La app sigue instalada.'}
   return 'Paquete eliminado para el usuario actual; no se restauran sus datos.'
  }
  'ExportAssociations' {return WB-Native 'dism.exe' @('/Online',('/Export-DefaultAppAssociations:'+(Join-Path $session 'associations.xml')))}
  'ImportAssociations' {return WB-Native 'dism.exe' @('/Online',('/Import-DefaultAppAssociations:'+$arg))}
  'MicrosoftUpdate' {
   $manager=New-Object -ComObject Microsoft.Update.ServiceManager
   $id='7971f918-a847-4430-9279-4a52d1efe18d'
   $exists=@($manager.Services | Where-Object {$_.ServiceID -eq $id}).Count -gt 0
   if($v -eq 'Enable' -and -not $exists){[void]$manager.AddService2($id,7,'')}
   if($v -eq 'Disable' -and $exists){$manager.RemoveService($id)}
   $after=@($manager.Services | Where-Object {$_.ServiceID -eq $id}).Count -gt 0
   if($after -ne ($v -eq 'Enable')){throw 'No se verifico Microsoft Update.'}
   return 'Registro de Microsoft Update verificado.'
  }
  'GPUpdate' {return WB-Native 'gpupdate.exe' @('/force','/wait:60')}
  'LogInfo' {return [pscustomobject]@{Computer=$env:COMPUTERNAME;PowerShell=$PSVersionTable.PSVersion.ToString();Time=(Get-Date).ToString('o')}}
  'Settings' {
   # Destino proviene exclusivamente del catalogo local; nunca del argumento del plan.
   Start-Process -FilePath ([string]$v) -ErrorAction Stop | Out-Null
   return 'Controles abiertos. Cambio pendiente de realizar y verificar por el usuario.'
  }
  default {throw ('Tipo no implementado: '+$a.Type)}
 }
}
function WB-ApplyReversible($item,$journal,$path){
 $a=$item.Definition;$before=WB-Current $a;$after=WB-Target $a $item.Choice
 if(WB-Same $before $after){return 'AlreadyConfigured'}
 $entry=[pscustomobject]@{Id=$a.Id;Choice=$item.Choice.Label;Before=$before;After=$after;State='Planned'}
 $journal.Entries+= $entry;WB-Save $journal $path
 if(-not (WB-Same (WB-Current $a) $before)){$entry.State='NotApplied';WB-Save $journal $path;throw 'Cambio simultaneo detectado; no se aplico esta accion.'}
 WB-SetState $a $after
 if(-not (WB-Same (WB-Current $a) $after)){throw 'No se verifico el estado solicitado.'}
 $entry.State='Applied';WB-Save $journal $path
 return $(if($a.Type -eq 'Registry'){'RegistryVerified'}else{'StateVerified'})
}
function WB-Restore($journal,$path,$catalog){
 $conflicts=0;$entries=@($journal.Entries);[array]::Reverse($entries)
 foreach($e in $entries){
  if($e.State -in @('Restored','NotApplied')){continue}
  try{
   $found=@($catalog | Where-Object {$_.Id -ceq $e.Id -and $_.Reversible})
   if($found.Count -ne 1){throw 'Accion de respaldo no permitida.'}
   $a=$found[0];$choice=@($a.Choices | Where-Object {$_.Label -ceq $e.Choice})
   if($choice.Count -ne 1 -or -not (WB-Same (WB-Target $a $choice[0]) $e.After)){throw 'Destino de respaldo alterado.'}
   $current=WB-Current $a
   if(-not (WB-Same $current $e.Before)){
    if(-not (WB-Same $current $e.After)){throw 'Estado cambiado externamente o escritura parcial; revisar manualmente.'}
    WB-SetState $a $e.Before
    if(-not (WB-Same (WB-Current $a) $e.Before)){throw 'Restauracion no verificada.'}
   }
   $e.State='Restored';WB-Save $journal $path
  }catch{$conflicts++;Write-Warning ($e.Id+': '+$_.Exception.Message)}
 }
 $journal.Status=if($conflicts){'RestoreConflicts'}else{'Restored'}
 WB-Save $journal $path
 return $conflicts
}
