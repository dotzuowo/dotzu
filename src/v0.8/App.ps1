#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
[xml]$xaml=Get-Content (Join-Path $PSScriptRoot 'Window.xaml') -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader($xaml)))
$names=@('NavHome','NavModules','NavActivity','NavRecovery','HomePage','ModulesPage','ActivityPage','RecoveryPage','Profile','ProfileDescription','HardwareText','SystemText','Optimize','Preview','Restore','OptPrivacy','OptCaptures','OptMouse','OptPower','OptCleanup','OptApps','OptRuntimes','OptRepair','LogBox','RunTitle','RunDetail','Elapsed','Progress','OpenReport','OpenSession','OpenData','OptStartup','ChooseSettings','PlanSummary','ExportProfile','ImportProfile','StopRun','HistoryList','RefreshHistory','OpenHistory','NavMaintenance','MaintenancePage','OptDeepInventory','LongTasksNotice','RefreshHardware','ShortcutSettings','StageList')
$ui=@{};foreach($name in $names){$ui[$name]=$window.FindName($name)}
$base=$PSScriptRoot
$root=Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03'
$script:worker=$null;$script:session=$null;$script:started=$null;$script:operation=$null
$script:excluded=@();$script:stopRequested=$false;$script:updatingProfile=$false
$catalog=@(Get-Content (Join-Path $base 'Catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
. (Join-Path $base 'ExtraFunctions.ps1')
$script:excluded=@($catalog | Where-Object {-not $_.Default} | ForEach-Object {$_.Name})
$ui.ChooseSettings.Content='Explorar '+$catalog.Count+' ajustes de WinBoost'
$preferencesPath=Join-Path $root 'preferences-v05.json'
$script:uiMutex=New-Object Threading.Mutex($false,('Local\WinBoostUI-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$script:uiHeld=$false
try{$script:uiHeld=$script:uiMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$script:uiHeld=$true}
if(-not $script:uiHeld){[void][Windows.MessageBox]::Show('WinBoost ya esta abierto para este usuario.','WinBoost');$script:uiMutex.Dispose();return}
function Page($name){
 foreach($n in @('Home','Modules','Maintenance','Activity','Recovery')){
  $ui[$n+'Page'].Visibility=if($n -eq $name){'Visible'}else{'Collapsed'}
  $ui['Nav'+$n].Background=[Windows.Media.BrushConverter]::new().ConvertFromString($(if($n -eq $name){'#163A60'}else{'#1B2A40'}))
 }
}
$ui.NavHome.Add_Click({Page 'Home'});$ui.NavModules.Add_Click({Page 'Modules'})
$ui.NavActivity.Add_Click({Page 'Activity'});$ui.NavRecovery.Add_Click({Page 'Recovery';Refresh-History})
$ui.NavMaintenance.Add_Click({Page 'Maintenance'})
function Busy($busy){
 foreach($n in @('Optimize','Preview','Restore','Profile','OptPrivacy','OptCaptures','OptMouse','OptPower','OptCleanup','OptApps','OptRuntimes','OptRepair','OptStartup','ChooseSettings','ExportProfile','ImportProfile','OptDeepInventory','ShortcutSettings','RefreshHardware')){$ui[$n].IsEnabled=-not $busy}
}
function Set-Profile {
 $index=$ui.Profile.SelectedIndex
 if($index -eq 3){return}
 $script:updatingProfile=$true
 $values=@{Privacy=$true;Captures=$false;Mouse=$false;Power=$false;Cleanup=$false;Apps=$false;Runtimes=$false;Repair=$false;Startup=$false;DeepInventory=$false}
 if($index -eq 1){$values.Captures=$true;$values.Power=$true}
 if($index -eq 2){$values.Privacy=$false;$values.Cleanup=$true;$values.DeepInventory=$true}
 $script:excluded=@($catalog | Where-Object {-not $_.Default} | ForEach-Object {$_.Name})
 foreach($k in $values.Keys){$ui['Opt'+$k].IsChecked=$values[$k]}
 $ui.ProfileDescription.Text=switch($index){
  0 {'Preferencias de Windows con respaldo. Sin instalaciones, reparacion ni exploracion de temporales.'}
  1 {'Preferencias + desactivar capturas Xbox y activar Alto rendimiento si esta disponible y conectado. Puede aumentar consumo y temperatura.'}
  2 {'Limpieza de temporales antiguos y diagnostico ampliado. Puedes agregar instalacion de runtimes o reparacion desde Mantenimiento.'}
 }
 $script:updatingProfile=$false
 Update-Summary
}
$ui.Profile.Add_SelectionChanged({Set-Profile})
function Start-Run($action){
 try{
  if($null -ne $script:worker -and -not $script:worker.HasExited){return}
  $id=[guid]::NewGuid().ToString()
  $script:session=Join-Path $root $id
  New-Item -ItemType Directory -Path $script:session -Force | Out-Null
  $config=[ordered]@{}
  foreach($name in @('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair','Startup','DeepInventory')){$config[$name]=[bool]$ui['Opt'+$name].IsChecked}
  $config['SelectedSettings']=@($catalog | Where-Object {$_.Name -notin $script:excluded} | ForEach-Object {$_.Name})
  Save-ProfileFile $preferencesPath ([pscustomobject]$config)
  $request=Join-Path $script:session 'request.json'
  $config | ConvertTo-Json | Set-Content -LiteralPath $request -Encoding UTF8
  $argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $base 'Engine.ps1')+'"'),'-Action',$action,'-SessionId',$id,'-RequestFile',('"'+$request+'"'))
  $script:worker=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argsList -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $script:session 'stdout.log') -RedirectStandardError (Join-Path $script:session 'stderr.log')
  $script:started=Get-Date;$script:operation=$action;$script:stopRequested=$false
  $script:lastStatusWrite=[datetime]::MinValue;$script:lastLogWrite=[datetime]::MinValue;$script:lastStepsWrite=[datetime]::MinValue
  $ui.StageList.ItemsSource=$null;$ui.RunTitle.Foreground=[Windows.Media.Brushes]::White
  $ui.StopRun.IsEnabled=($action -ne 'Restore')
  $ui.LogBox.Clear();$ui.Progress.Value=0;$ui.RunTitle.Text='Preparando ejecucion'
  $ui.RunDetail.Text='Las tareas se ejecutan en secuencia. Windows puede pedir permisos para instalar o reparar.'
  Busy $true;Page 'Activity';$timer.Start()
 }catch{Busy $false;[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
}
$ui.Optimize.Add_Click({Start-Run 'Apply'})
$ui.Preview.Add_Click({Start-Run 'Preview'})
$ui.Restore.Add_Click({Start-Run 'Restore'})
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(650)
$timer.Add_Tick({
 try{
  $ui.Elapsed.Text=([TimeSpan]((Get-Date)-$script:started)).ToString('hh\:mm\:ss')
  $file=Join-Path $script:session 'status.json'
  if(Test-Path -LiteralPath $file){
   $write=[IO.File]::GetLastWriteTimeUtc($file)
   if($write -ne $script:lastStatusWrite){
   $s=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
   $script:lastStatusWrite=$write
   $ui.Progress.Value=[double]$s.Percent;$ui.RunTitle.Text=$s.Message
   $ui.RunDetail.Text=if($script:stopRequested){'Detencion solicitada: finalizando tarea actual, despues se recuperaran las preferencias.'}else{'Avisos: '+$s.Warnings+' | Los resultados se guardan en el informe.'}
   }
  }
  $log=Join-Path $script:session 'activity.log'
  if(Test-Path -LiteralPath $log){
   $write=[IO.File]::GetLastWriteTimeUtc($log)
   if($write -ne $script:lastLogWrite){$ui.LogBox.Text=(Get-Content -LiteralPath $log -Tail 120 -Encoding UTF8) -join "`r`n";$ui.LogBox.ScrollToEnd();$script:lastLogWrite=$write}
  }
  $stepFile=Join-Path $script:session 'steps.json'
  if(Test-Path -LiteralPath $stepFile){
   $write=[IO.File]::GetLastWriteTimeUtc($stepFile)
   if($write -ne $script:lastStepsWrite){
    $entries=@(Get-Content -LiteralPath $stepFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    $ui.StageList.ItemsSource=@($entries | ForEach-Object {
     $word=switch($_.State){Completed{'Listo'};Warning{'Aviso'};Failed{'Error'};Cancelled{'Detenido'};default{'En curso'}}
     [pscustomobject]@{Label=$word+' / '+$_.Name+' / '+$_.Seconds+' s'}
    })
    $script:lastStepsWrite=$write
   }
  }
  if($script:worker.HasExited){
   $timer.Stop();Busy $false;$ui.StopRun.IsEnabled=$false;Refresh-History
   $phase=if(Test-Path -LiteralPath $file){(Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).Phase}else{'Failed'}
   $brush=New-Object Windows.Media.BrushConverter
   switch($phase){
    'Completed'{$ui.RunTitle.Foreground=$brush.ConvertFromString('#7BD9AE')}
    'CompletedWithWarnings'{$ui.RunTitle.Text='Finalizado con avisos; revisa el informe';$ui.RunTitle.Foreground=$brush.ConvertFromString('#E6BC75')}
    'Cancelled'{$ui.RunTitle.Text='Detenido; revisa la recuperacion en el informe';$ui.RunTitle.Foreground=$brush.ConvertFromString('#E6BC75')}
    default{$ui.RunTitle.Foreground=$brush.ConvertFromString('#FF9595')}
   }
   $ui.RunDetail.Text=if($script:operation -eq 'Preview'){'Analisis sin cambios. Abre el informe, preview.json y plan.json.'}else{'Consulta el informe para ver tareas, resultados y recuperacion. Cierra sesion para refrescar preferencias.'}
   if($script:worker.ExitCode -eq 1){
    $err=Join-Path $script:session 'stderr.log'
    if(Test-Path -LiteralPath $err){$ui.LogBox.AppendText("`r`n"+(Get-Content -LiteralPath $err -Raw))}
   }
  }
 }catch{
  # El archivo de estado puede estar siendo reemplazado; reintentar en el siguiente tick.
  if($null -ne $script:worker -and $script:worker.HasExited){$timer.Stop();Busy $false;$ui.RunTitle.Text='Proceso finalizado; consulta los archivos de sesion.'}
 }
})
$ui.OpenReport.Add_Click({try{
 if(-not $script:session){throw 'Primero ejecuta una optimizacion.'}
 $report=Join-Path $script:session 'report.html'
 if(Test-Path -LiteralPath $report){Start-Process $report}else{throw 'Esta operacion no genero informe HTML. Abre sus archivos de sesion para consultar JSON y registro.'}
}catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}})
$ui.OpenSession.Add_Click({try{if($script:session){Start-Process explorer.exe -ArgumentList ('"'+$script:session+'"')}}catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}})
$ui.OpenData.Add_Click({try{New-Item -ItemType Directory -Path $root -Force | Out-Null;Start-Process explorer.exe -ArgumentList ('"'+$root+'"')}catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}})
$window.Add_Closing({param($sender,$eventArgs)
 if($null -ne $script:worker -and -not $script:worker.HasExited){$eventArgs.Cancel=$true;[void][Windows.MessageBox]::Show('Hay una operacion en curso. Espera a que termine antes de cerrar.','WinBoost')}
})
$hardwareShell=$null;$hardwareHandle=$null;$hardwareDisposed=$false
$hardwareTimer=New-Object Windows.Threading.DispatcherTimer
$hardwareTimer.Interval=[TimeSpan]::FromMilliseconds(300)
$hardwareTimer.Add_Tick({
 if($null -ne $hardwareHandle -and $hardwareHandle.IsCompleted){
  $hardwareTimer.Stop();$ui.RefreshHardware.IsEnabled=$true
  try{$r=@($hardwareShell.EndInvoke($hardwareHandle));if($r.Count){$ui.HardwareText.Text=$r[-1].Hardware;$ui.SystemText.Text=$r[-1].System}}finally{$hardwareShell.Dispose();$script:hardwareDisposed=$true}
 }
})
$ui.RefreshHardware.Add_Click({
 if($null -ne $hardwareHandle -and -not $hardwareHandle.IsCompleted){return}
 $script:hardwareDisposed=$false;$script:hardwareShell=[PowerShell]::Create()
 [void]$hardwareShell.AddScript({
  try{
   $gpu=(Get-CimInstance Win32_VideoController -OperationTimeoutSec 5 | Select-Object -ExpandProperty Name) -join ', '
   $ram=[math]::Round((Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 5).TotalPhysicalMemory/1073741824)
   [pscustomobject]@{Hardware=$gpu;System="$ram GB RAM / Windows x64"}
  }catch{[pscustomobject]@{Hardware='No se pudo consultar GPU/RAM';System='Revisa Actividad o ejecuta Diagnostico.'}}
 })
 $script:hardwareHandle=$hardwareShell.BeginInvoke();$ui.RefreshHardware.IsEnabled=$false;$hardwareTimer.Start()
})
$window.Add_ContentRendered({
 try{
  $cpu=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('HARDWARE\DESCRIPTION\System\CentralProcessor\0')
  try{$ui.HardwareText.Text=([string]$cpu.GetValue('ProcessorNameString')).Trim()}finally{if($null -ne $cpu){$cpu.Dispose()}}
  $os=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion')
  try{$ui.SystemText.Text='Windows / Build '+$os.GetValue('CurrentBuildNumber')+' / '+$env:NUMBER_OF_PROCESSORS+' procesadores logicos'}finally{if($null -ne $os){$os.Dispose()}}
 }catch{$ui.HardwareText.Text=$env:PROCESSOR_IDENTIFIER;$ui.SystemText.Text='Identificacion completa disponible al consultar GPU / RAM.'}
})
function Get-UiConfig {
 $config=[ordered]@{}
 foreach($name in @('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair','Startup','DeepInventory')){$config[$name]=[bool]$ui['Opt'+$name].IsChecked}
 $config['SelectedSettings']=@($catalog | Where-Object {$_.Name -notin $script:excluded} | ForEach-Object {$_.Name})
 return [pscustomobject]$config
}
function Update-Summary {
 $c=Get-UiConfig
 $modules=@('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair','Startup','DeepInventory' | Where-Object {$c.$_}).Count
 $groups=@();if($c.Privacy){$groups+=@('Privacy','Suggestions','Interface')};if($c.Captures){$groups+='Captures'};if($c.Mouse){$groups+='Mouse'}
 $count=@($catalog | Where-Object {$_.Module -in $groups -and $_.Name -in $c.SelectedSettings}).Count
 $ui.PlanSummary.Text="$modules modulos / $count preferencias. Estado ligero e informe incluidos."
 $long=($c.Runtimes -or $c.Repair -or $c.DeepInventory)
 $ui.LongTasksNotice.Visibility=if($long){'Visible'}else{'Collapsed'}
 $ui.Optimize.Content=if($long){'Ejecutar seleccion  →'}else{'Aplicar optimizacion  →'}
}
function Save-ProfileFile($path,$value){
 $dir=Split-Path $path -Parent
 New-Item -ItemType Directory -Path $dir -Force | Out-Null
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($tmp,($value | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
  if([IO.File]::Exists($path)){[IO.File]::Replace($tmp,$path,[NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
 }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
}
function Apply-UiConfig($value){
 $c=Validate-Config $value
 $script:updatingProfile=$true
 try{
  foreach($name in @('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair','Startup','DeepInventory')){$ui['Opt'+$name].IsChecked=$c.$name}
  $script:excluded=@($catalog | Where-Object {$_.Name -notin $c.SelectedSettings} | ForEach-Object {$_.Name})
  $ui.Profile.SelectedIndex=3
  $ui.ProfileDescription.Text='Perfil personalizado. Revisa los modulos y las preferencias individuales antes de ejecutar.'
 }finally{$script:updatingProfile=$false}
 Update-Summary
}
function Refresh-History {
 $ui.HistoryList.Items.Clear()
 if(-not (Test-Path -LiteralPath $root)){return}
 foreach($dir in @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object CreationTime -Descending | Select-Object -First 50)){
  try{
   $statusFile=Join-Path $dir.FullName 'status.json'
   if(-not (Test-Path -LiteralPath $statusFile)){continue}
   $s=Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
   $jfile=Join-Path $dir.FullName 'backup.json'
   $state=if(Test-Path -LiteralPath $jfile){(Get-Content -LiteralPath $jfile -Raw -Encoding UTF8 | ConvertFrom-Json).Status}else{$s.Phase}
   $display=$dir.CreationTime.ToString('dd/MM/yyyy HH:mm')+' / '+$state+' / '+$dir.Name.Substring(0,[math]::Min(8,$dir.Name.Length))
   [void]$ui.HistoryList.Items.Add([pscustomobject]@{Title=$display;Path=$dir.FullName})
  }catch{continue}
 }
}
$ui.RefreshHistory.Add_Click({Refresh-History})
$ui.OpenHistory.Add_Click({
 try{
  $selected=$ui.HistoryList.SelectedItem
  if($null -ne $selected){Start-Process explorer.exe -ArgumentList ('"'+$selected.Path+'"')}
 }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
})
$ui.StopRun.Add_Click({
 try{
  if($script:session -and $null -ne $script:worker -and -not $script:worker.HasExited){
   [IO.File]::WriteAllText((Join-Path $script:session 'cancel.request'),'Stop')
   $script:stopRequested=$true;$ui.StopRun.IsEnabled=$false
   $ui.RunDetail.Text='Detencion solicitada. No se interrumpe una instalacion o reparacion a la fuerza.'
  }
 }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
})
$ui.ExportProfile.Add_Click({
 try{
  $d=New-Object Microsoft.Win32.SaveFileDialog;$d.Filter='Perfil WinBoost (*.json)|*.json';$d.FileName='WinBoost_Perfil.json'
  if($d.ShowDialog($window)){
   Save-ProfileFile $d.FileName (Get-UiConfig)
   $ui.RunDetail.Text='Perfil exportado. Puedes importarlo en otra instalacion de WinBoost 0.8.'
  }
 }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
})
$ui.ImportProfile.Add_Click({
 try{
  $d=New-Object Microsoft.Win32.OpenFileDialog;$d.Filter='Perfil WinBoost (*.json)|*.json'
  if($d.ShowDialog($window)){
   Apply-UiConfig (Get-Content -LiteralPath $d.FileName -Raw -Encoding UTF8 | ConvertFrom-Json)
   Save-ProfileFile $preferencesPath (Get-UiConfig)
  }
 }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
})
. (Join-Path $base 'Settings.ps1')
function Open-Settings {
 try{
  $selection=Show-SettingsDialog $window $catalog $script:excluded
  if($null -ne $selection){
   $script:excluded=$selection.Excluded;$ui.Profile.SelectedIndex=3
   $ui.ProfileDescription.Text='Seleccion individual personalizada. Solo se aplican los modulos activos.'
   Update-Summary
  }
 }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
}
$ui.ChooseSettings.Add_Click({Open-Settings})
$ui.ShortcutSettings.Add_Click({Open-Settings})
foreach($name in @('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair','Startup','DeepInventory')){
 $onChange={
  if(-not $script:updatingProfile){
   $ui.Profile.SelectedIndex=3;$ui.ProfileDescription.Text='Perfil personalizado. Se ejecutaran los modulos y las preferencias que elegiste.'
   Update-Summary
  }
 }
 $ui['Opt'+$name].Add_Checked($onChange);$ui['Opt'+$name].Add_Unchecked($onChange)
}
Set-Profile
if(Test-Path -LiteralPath $preferencesPath){
 try{Apply-UiConfig (Get-Content -LiteralPath $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json)}catch{$ui.RunDetail.Text='El perfil guardado no se pudo cargar. Se utiliza Rapido.'}
}
try{[void]$window.ShowDialog()}
finally{
 $timer.Stop();$hardwareTimer.Stop()
 if($null -ne $hardwareShell -and -not $hardwareDisposed){
  if($null -ne $hardwareHandle -and -not $hardwareHandle.IsCompleted){[void]$hardwareShell.BeginStop($null,$null)}else{$hardwareShell.Dispose()}
 }
 if($script:uiHeld){$script:uiMutex.ReleaseMutex()};$script:uiMutex.Dispose()
}

