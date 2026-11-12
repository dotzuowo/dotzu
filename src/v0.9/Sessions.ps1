# Shared read-only session discovery. No recursive traversal or deletion.
function Read-WBSessionJournal([string]$Path){
 $errors=@()
 foreach($candidate in @($Path,($Path+'.previous'),($Path+'.bak'))){
  if(-not [IO.File]::Exists($candidate)){continue}
  try{
   $j=Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json
   foreach($name in @('Schema','Sid','Computer','Status','Date')){
    if($null -eq $j.PSObject.Properties[$name]){throw ('Missing journal field: '+$name)}
   }
   if($j.Schema -notin @(3,4)){throw 'Unsupported journal schema.'}
   [void][datetime]::Parse([string]$j.Date,[Globalization.CultureInfo]::InvariantCulture)
   return [pscustomobject]@{Journal=$j;Recovered=($candidate -ne $Path);Source=$candidate}
  }catch{$errors+=($candidate+': '+$_.Exception.Message)}
 }
 throw ('Unreadable journal: '+$Path+' / '+($errors -join ' / '))
}
function Get-WBSessionHistory([string]$Root,[string]$Sid,[string]$Computer){
 $locations=@([pscustomobject]@{Path=$Root;Engine='Base';Schema=3},[pscustomobject]@{Path=(Join-Path $Root 'Advanced');Engine='Advanced';Schema=4})
 foreach($location in $locations){
  if(-not [IO.Directory]::Exists($location.Path)){continue}
  foreach($dir in @(Get-ChildItem -LiteralPath $location.Path -Directory)){
   $id=[guid]::Empty
   if(-not [guid]::TryParseExact($dir.Name,'D',[ref]$id) -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
   $path=Join-Path $dir.FullName 'backup.json'
   if(-not ([IO.File]::Exists($path) -or [IO.File]::Exists($path+'.previous') -or [IO.File]::Exists($path+'.bak'))){
    $summaryPath=Join-Path $dir.FullName 'summary.json'
    if([IO.File]::Exists($summaryPath)){
     try{
      $summary=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
      [pscustomobject]@{SessionId=$dir.Name;Engine=$location.Engine;Path=$dir.FullName;BackupPath=$path;HasBackup=$false;Date=$dir.CreationTime;Status=[string]$summary.Status;Journal=$null;Recovered=$false;Error=''}
     }catch{Write-Verbose ('Unreadable session summary: '+$summaryPath)}
    }
    continue
   }
   try{
    $read=Read-WBSessionJournal $path;$j=$read.Journal
    if($j.Schema -ne $location.Schema){throw 'Journal schema does not match session engine.'}
    if(($Sid -and $j.Sid -ne $Sid) -or ($Computer -and $j.Computer -ne $Computer)){continue}
    [pscustomobject]@{SessionId=$dir.Name;Engine=$location.Engine;Path=$dir.FullName;BackupPath=$path;HasBackup=$true;Date=[datetime]$j.Date;Status=[string]$j.Status;Journal=$j;Recovered=$read.Recovered;Error=''}
   }catch{
    [pscustomobject]@{SessionId=$dir.Name;Engine=$location.Engine;Path=$dir.FullName;BackupPath=$path;HasBackup=$true;Date=$dir.CreationTime;Status='Unreadable';Journal=$null;Recovered=$false;Error=$_.Exception.Message}
   }
  }
 }
}
function Get-WBRestoreSession([object[]]$Sessions,[string]$RestoreSessionId,[string]$Engine){
 if($RestoreSessionId){
  $id=[guid]::Empty
  if(-not [guid]::TryParseExact($RestoreSessionId,'D',[ref]$id)){throw 'Identificador de restauracion invalido.'}
  $match=@($Sessions | Where-Object {$_.SessionId -eq $RestoreSessionId -and $_.Engine -eq $Engine -and $_.HasBackup})
  if($match.Count -ne 1){throw 'Sesion de restauracion no encontrada para este usuario y equipo.'}
  if($match[0].Error){throw $match[0].Error}
  return $match[0]
 }
 return $Sessions | Where-Object {$_.Engine -eq $Engine -and $_.HasBackup -and -not $_.Error -and $_.Status -ne 'Restored'} | Sort-Object Date -Descending | Select-Object -First 1
}
