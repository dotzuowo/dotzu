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
  $ui.NavModules.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  if($ui.ModulesPage.Visibility -ne 'Visible'){throw 'Navigation failed'}
  $ui.NavHome.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  $ui.Profile.SelectedIndex=1
  if([int]$ui.SettingCount.Text -lt 1 -or $ui.PageTitle.Text -ne 'Panel de control'){throw 'Profile counters failed'}
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
