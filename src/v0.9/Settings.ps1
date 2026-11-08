function Show-SettingsDialog($owner,$catalog,$excluded){
 [xml]$xml=Get-Content (Join-Path $PSScriptRoot 'Settings.xaml') -Raw -Encoding UTF8
 $dialog=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader($xml)))
 if($owner.Resources.Contains('WinBoostOriginalLogo')){
  $dialog.Resources['WinBoostOriginalLogo']=$owner.Resources['WinBoostOriginalLogo']
 }
 $dialog.Owner=$owner
 $desktop=[Windows.SystemParameters]::WorkArea
 $dialog.MinWidth=[math]::Min($dialog.MinWidth,$desktop.Width)
 $dialog.MinHeight=[math]::Min($dialog.MinHeight,$desktop.Height)
 $dialog.Width=[math]::Min($dialog.Width,$desktop.Width)
 $dialog.Height=[math]::Min($dialog.Height,$desktop.Height)
 $rows=New-Object 'Collections.ObjectModel.ObservableCollection[object]'
 foreach($item in $catalog){
  $current='Sin configurar';$key=$null
  try{
   $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($item.Path)
   if($null -ne $key -and $key.GetValueNames() -contains $item.Name){$current=[string]$key.GetValue($item.Name)}
  }catch{$current='No disponible'}finally{if($null -ne $key){$key.Dispose()}}
  $module=switch($item.Module){'Captures'{'Juegos y capturas'};'Mouse'{'Puntero'};default{'Privacidad e interfaz'}}
  $rows.Add([pscustomobject]@{Enabled=($item.Name -notin $excluded);Module=$module;Category=$item.Category;Label=$item.Label;Name=$item.Name;Current=$current;Target=[string]$item.Value;Default=$item.Default;Description=$item.Description;Path=('HKCU\'+$item.Path)})
 }
 $grid=$dialog.FindName('SettingsGrid');$grid.ItemsSource=$rows
 $search=$dialog.FindName('SearchSettings');$category=$dialog.FindName('CategoryFilter')
 $category.ItemsSource=@('Todas')+@($rows.Category | Sort-Object -Unique);$category.SelectedIndex=0
 $view=[Windows.Data.CollectionViewSource]::GetDefaultView($rows)
 $refresh={
  $text=$search.Text;$selected=[string]$category.SelectedItem
  $filter={param($row) ($selected -eq 'Todas' -or $row.Category -eq $selected) -and ($row.Label+' '+$row.Name+' '+$row.Description+' '+$row.Module).IndexOf($text,[StringComparison]::OrdinalIgnoreCase) -ge 0}.GetNewClosure()
  $view.Filter=[Predicate[object]]$filter;$view.Refresh()
  $dialog.FindName('CountSettings').Text=([string]@($view).Count)+' visibles / '+$rows.Count+' disponibles'
 }.GetNewClosure()
 $search.Add_TextChanged($refresh);$category.Add_SelectionChanged($refresh)
 $grid.Add_SelectionChanged({
  $row=$grid.SelectedItem
  if($null -ne $row){$dialog.FindName('DetailText').Text=$row.Description+"`nModulo necesario: "+$row.Module+" | Actual: "+$row.Current+' | Objetivo: '+$row.Target+"`n"+$row.Path+'\'+$row.Name}
 })
 $dialog.FindName('SelectVisible').Add_Click({
  [void]$grid.CommitEdit();foreach($row in @($view)){$row.Enabled=$true};$grid.Items.Refresh()
 })
 $dialog.FindName('ClearVisible').Add_Click({
  [void]$grid.CommitEdit();foreach($row in @($view)){$row.Enabled=$false};$grid.Items.Refresh()
 })
 $dialog.FindName('DefaultSettings').Add_Click({
  [void]$grid.CommitEdit();foreach($row in $rows){$row.Enabled=$row.Default};$grid.Items.Refresh()
 })
 $dialog.FindName('SaveSettings').Add_Click({[void]$grid.CommitEdit();[void]$grid.CommitEdit();$dialog.DialogResult=$true})
 $dialog.FindName('CancelSettings').Add_Click({$dialog.DialogResult=$false})
 & $refresh
 if($dialog.ShowDialog() -eq $true){return [pscustomobject]@{Excluded=@($rows | Where-Object {-not $_.Enabled} | ForEach-Object {$_.Name})}}
 return $null
}
