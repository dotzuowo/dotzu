function Show-WinBoostActions($owner){
 . (Join-Path $PSScriptRoot 'ActionsCore.ps1')
 [xml]$xaml=Get-Content (Join-Path $PSScriptRoot 'ActionsWindow.xaml') -Raw -Encoding UTF8
 $dialog=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader($xaml)))
 if($owner.Resources.Contains('WinBoostOriginalLogo')){
  $dialog.Resources['WinBoostOriginalLogo']=$owner.Resources['WinBoostOriginalLogo']
 }
 $dialog.Owner=$owner
 $desktop=[Windows.SystemParameters]::WorkArea
 $dialog.MinWidth=[math]::Min($dialog.MinWidth,$desktop.Width)
 $dialog.MinHeight=[math]::Min($dialog.MinHeight,$desktop.Height)
 $dialog.Width=[math]::Min($dialog.Width,$desktop.Width)
 $dialog.Height=[math]::Min($dialog.Height,$desktop.Height)
 $validatePlan=${function:WB-ValidatePlan};$saveJson=${function:WB-Save}
 $basePath=$PSScriptRoot
 $cat=WB-ReadCatalog;$controls=@{}
 foreach($name in @('ActionGrid','ActionSearch','ActionCategory','ActionDetail','ActionStatus','ActionProgress','ActionPreview','ActionApply','ActionRestore','ActionExport','ActionImport','ActionReport','ActionStop','ActionReset','ActionInventory')){$controls[$name]=$dialog.FindName($name)}
 $rows=New-Object 'Collections.ObjectModel.ObservableCollection[object]'
 foreach($a in $cat){$rows.Add([pscustomobject]@{Id=$a.Id;Label=$a.Label;Category=$a.Category;Choice='Sin cambios';Choices=@('Sin cambios')+@($a.Choices.Label);Argument='';Description=$a.Description;ArgumentHint=$a.Argument;Route=$(if($a.Type -eq 'Settings'){'Asistido'}elseif($a.Reversible){'Con respaldo'}else{'Manual para revertir'})})}
 $controls.ActionGrid.ItemsSource=$rows
 $controls.ActionCategory.ItemsSource=@('Todas')+@($rows.Category | Sort-Object -Unique);$controls.ActionCategory.SelectedIndex=0
 $view=[Windows.Data.CollectionViewSource]::GetDefaultView($rows)
 $filter={
  $text=$controls.ActionSearch.Text;$category=[string]$controls.ActionCategory.SelectedItem
  $predicate={param($r) ($category -eq 'Todas' -or $r.Category -eq $category) -and ($r.Label+' '+$r.Id+' '+$r.Description).IndexOf($text,[StringComparison]::OrdinalIgnoreCase) -ge 0}.GetNewClosure()
  $view.Filter=[Predicate[object]]$predicate;$view.Refresh()
 }.GetNewClosure()
 $controls.ActionSearch.Add_TextChanged($filter);$controls.ActionCategory.Add_SelectionChanged($filter)
 $controls.ActionGrid.Add_SelectionChanged({$r=$controls.ActionGrid.SelectedItem;if($null -ne $r){$controls.ActionDetail.Text=$r.Description+"`n"+$(if($r.ArgumentHint){'Argumento: '+$r.ArgumentHint}else{'No necesita argumento.'})}})
 $state=[pscustomobject]@{Worker=$null;Session=$null}
 $busy={param($yes) foreach($name in @('ActionGrid','ActionPreview','ActionApply','ActionRestore','ActionExport','ActionImport','ActionReset','ActionInventory')){$controls[$name].IsEnabled=-not $yes};$controls.ActionStop.IsEnabled=$yes}.GetNewClosure()
 $makePlan={
  [void]$controls.ActionGrid.CommitEdit();[void]$controls.ActionGrid.CommitEdit()
  return [pscustomobject]@{Schema=1;Actions=@($rows | Where-Object {$_.Choice -ne 'Sin cambios'} | ForEach-Object {[pscustomobject]@{Id=$_.Id;Choice=$_.Choice;Argument=$_.Argument}})}
 }.GetNewClosure()
 $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(600)
 $start={param($mode)
  try{
   if($null -ne $state.Worker -and -not $state.Worker.HasExited){return}
   $plan=& $makePlan
   if($mode -ne 'Restore'){$validated=@(& $validatePlan $plan $cat);if(-not $validated.Count){throw 'Elige al menos una opcion distinta de Sin cambios.'}}
   $id=[guid]::NewGuid().ToString();$state.Session=Join-Path (Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03\Advanced') $id
   New-Item -ItemType Directory -Path $state.Session -Force | Out-Null
   $request=Join-Path $state.Session 'request.json';& $saveJson $plan $request
   $engine=Join-Path $basePath 'ActionsEngine.ps1'
   $cmd='& '+("'"+$engine.Replace("'","''")+"'")+' -Mode '+$mode+' -SessionId '+$id+' -PlanFile '+("'"+$request.Replace("'","''")+"'")+'; exit $LASTEXITCODE'
   $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
   $state.Worker=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state.Session 'stdout.log') -RedirectStandardError (Join-Path $state.Session 'stderr.log')
   & $busy $true;$controls.ActionStatus.Text='Preparando el plan...';$timer.Start()
  }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
 }.GetNewClosure()
 $timer.Add_Tick({
  try{
   $p=Join-Path $state.Session 'status.json'
   if(Test-Path -LiteralPath $p){try{$s=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json;$controls.ActionStatus.Text=$s.Message;$controls.ActionProgress.Value=$s.Percent}catch{}}
   if($state.Worker.HasExited){
    $timer.Stop();$state.Worker.WaitForExit();& $busy $false
    $summary=Join-Path $state.Session 'summary.json'
    if(Test-Path -LiteralPath $summary){$s=Get-Content $summary -Raw -Encoding UTF8 | ConvertFrom-Json;$controls.ActionStatus.Text=$s.Status+': '+$s.Message}else{$controls.ActionStatus.Text='No se genero informe. Revisa '+$state.Session}
   }
  }catch{$timer.Stop();& $busy $false;$controls.ActionStatus.Text=$_.Exception.Message}
 })
 $controls.ActionPreview.Add_Click({& $start 'Preview'})
 $controls.ActionApply.Add_Click({& $start 'Apply'})
 $controls.ActionRestore.Add_Click({& $start 'Restore'})
 $controls.ActionReset.Add_Click({foreach($r in $rows){$r.Choice='Sin cambios';$r.Argument=''};$controls.ActionGrid.Items.Refresh()})
 $controls.ActionStop.Add_Click({if($state.Session){[IO.File]::WriteAllText((Join-Path $state.Session 'cancel.request'),'Stop');$controls.ActionStatus.Text='Se detendra al terminar la accion en curso.'}})
 $controls.ActionReport.Add_Click({if($state.Session){$p=Join-Path $state.Session 'report.html';if(Test-Path $p){Start-Process -FilePath $p}}})
 $controls.ActionExport.Add_Click({
  try{$plan=& $makePlan;[void](& $validatePlan $plan $cat);$save=New-Object Microsoft.Win32.SaveFileDialog;$save.Filter='Plan WinBoost (*.json)|*.json';$save.FileName='WinBoost-Acciones.json';if($save.ShowDialog() -eq $true){& $saveJson $plan $save.FileName}}catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
 })
 $controls.ActionImport.Add_Click({
  try{
   $open=New-Object Microsoft.Win32.OpenFileDialog;$open.Filter='Plan WinBoost (*.json)|*.json'
   if($open.ShowDialog() -eq $true){
    $plan=Get-Content -LiteralPath $open.FileName -Raw -Encoding UTF8 | ConvertFrom-Json;[void](& $validatePlan $plan $cat)
    foreach($r in $rows){$r.Choice='Sin cambios';$r.Argument=''}
    foreach($selected in $plan.Actions){$r=$rows | Where-Object {$_.Id -ceq $selected.Id};$r.Choice=$selected.Choice;$r.Argument=if($selected.PSObject.Properties['Argument']){$selected.Argument}else{''}}
    $controls.ActionGrid.Items.Refresh()
   }
  }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'WinBoost')}
 })
 $controls.ActionInventory.Add_Click({
  # Abrir una consola independiente mantiene la interfaz receptiva durante DISM.
  $scriptFile=Join-Path $basePath 'ActionsInventory.ps1'
  $cmd='& '+("'"+$scriptFile.Replace("'","''")+"'")
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)
 })
 $dialog.Add_Closing({param($sender,$e) if($null -ne $state.Worker -and -not $state.Worker.HasExited){$e.Cancel=$true;[void][Windows.MessageBox]::Show('Espera a que termine o solicita Detener.','WinBoost')}})
 try{[void]$dialog.ShowDialog()}finally{$timer.Stop();if($null -ne $state.Worker){$state.Worker.Dispose()}}
}
