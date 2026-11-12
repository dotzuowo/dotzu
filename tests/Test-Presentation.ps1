# Run with Windows PowerShell 5.1 -STA on Windows. Only exercise presentation controls.
[CmdletBinding()]
param([string]$Source,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$Source=(Resolve-Path $Source).Path
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$env:WB_UI_OUTPUT=(Resolve-Path $OutputDirectory).Path
$env:LOCALAPPDATA=Join-Path ([IO.Path]::GetTempPath()) ('WinBoost-UI-'+[guid]::NewGuid())
$probe=@'
$window.Add_ContentRendered({
 try {
  $logo=$window.Resources['WinBoostOriginalLogo']
  if($null -eq $logo -or $logo.PixelWidth -ne 384 -or $logo.PixelHeight -ne 384){throw 'El logo oficial no se cargo desde el paquete.'}
  $ui.NavModules.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  if($ui.ModulesPage.Visibility -ne 'Visible'){throw 'Navigation failed'}
  # Seed only temporary JSON journals; verify mixed history and exact worker routing.
  $testRoot=Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03'
  $restoreId=[guid]::NewGuid().ToString()
  $journalDir=Join-Path (Join-Path $testRoot 'Advanced') $restoreId
  [void][IO.Directory]::CreateDirectory($journalDir)
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  [IO.File]::WriteAllText((Join-Path $journalDir 'backup.json'),([pscustomobject]@{Schema=4;Sid=$sid;Computer=$env:COMPUTERNAME;Date=(Get-Date).ToString('o');Status='Pending';Entries=@()} | ConvertTo-Json))
  $ui.NavRecovery.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  $item=@($ui.HistoryList.Items | Where-Object {$_.SessionId -eq $restoreId})
  if($item.Count -ne 1 -or $item[0].Engine -ne 'Advanced'){throw 'Advanced history entry missing'}
  $ui.HistoryList.SelectedItem=$item[0]
  function script:Start-Run($action,[string]$restoreId='',[bool]$advanced=$false){$script:capturedRestore=[pscustomobject]@{Action=$action;Id=$restoreId;Advanced=$advanced}}
  $ui.RestoreHistory.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  if($script:capturedRestore.Action -ne 'Restore' -or $script:capturedRestore.Id -ne $restoreId -or -not $script:capturedRestore.Advanced){throw 'Selected advanced restore did not route to exact session'}
  $ui.NavHome.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  $window.Width=1320;$window.Height=850
  $ui.Profile.SelectedIndex=1
  if([int]$ui.SettingCount.Text -lt 1 -or $ui.PageTitle.Text -ne 'Panel de control'){throw "Profile counters: settings=$($ui.SettingCount.Text) modules=$($ui.ModuleCount.Text) section=$($ui.PageTitle.Text) catalog=$($catalog.Count) privacy=$($ui.OptPrivacy.IsChecked)"}
  $window.UpdateLayout()
  Save-WindowImage $window 'WinBoost-escritorio'
  $window.Width=900
  $window.UpdateLayout()
  if($window.FindName('Rail').Width -gt 70){throw 'Compact navigation failed'}
  Save-WindowImage $window 'WinBoost-compacto'
  [IO.File]::WriteAllText((Join-Path $env:WB_UI_OUTPUT 'verified.txt'),'Navigation, counters and desktop layout verified.')
 }catch{
  [IO.File]::WriteAllText((Join-Path $env:WB_UI_OUTPUT 'failure.txt'),($_ | Out-String))
 }finally{$window.Close()}
})
'@
function Save-WindowImage($win,$name){
 $content=$win.Content
 $w=[int][math]::Ceiling($content.ActualWidth)
 $h=[int][math]::Ceiling($content.ActualHeight)
 $image=[Windows.Media.Imaging.RenderTargetBitmap]::new($w,$h,96,96,[Windows.Media.PixelFormats]::Pbgra32)
 $image.Render($content)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
 $f=[IO.File]::Create((Join-Path $env:WB_UI_OUTPUT ($name+'.png')))
 try{$encoder.Save($f)}finally{$f.Dispose()}
}
$app=Get-Content -LiteralPath (Join-Path $Source 'App.ps1') -Raw -Encoding UTF8
$hook='try{[void]$window.ShowDialog()}'
if(-not $app.Contains($hook)){throw 'Startup hook missing'}
$harness=Join-Path $Source ('ViewProbe-'+[guid]::NewGuid()+'.ps1')
try{
 [IO.File]::WriteAllText($harness,$app.Replace($hook,$probe+[Environment]::NewLine+$hook),[Text.Encoding]::UTF8)
 & $harness
 if(Test-Path (Join-Path $env:WB_UI_OUTPUT 'failure.txt')){throw (Get-Content (Join-Path $env:WB_UI_OUTPUT 'failure.txt') -Raw)}
 if(-not (Test-Path (Join-Path $env:WB_UI_OUTPUT 'verified.txt'))){throw 'Presentation check did not finish'}
 foreach($file in 'ActionsWindow.xaml','Settings.xaml'){
  [xml]$xml=Get-Content (Join-Path $Source $file) -Raw -Encoding UTF8
  $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml))
  $dialog.Show();$dialog.UpdateLayout();$dialog.Close()
 }
}finally{
 Remove-Item -LiteralPath $harness -Force -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
}
