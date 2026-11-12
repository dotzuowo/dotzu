$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Sessions.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('wb-sessions-'+[guid]::NewGuid())
function New-Journal($engine,$date,$sid='TEST-SID'){
 $id=[guid]::NewGuid().ToString()
 $parent=if($engine -eq 'Advanced'){Join-Path $root 'Advanced'}else{$root}
 $dir=Join-Path $parent $id;[void][IO.Directory]::CreateDirectory($dir)
 $j=[pscustomobject]@{Schema=$(if($engine -eq 'Advanced'){4}else{3});Sid=$sid;Computer='TEST-PC';Status='Pending';Date=$date;Entries=@();Registry=@();Power=$null}
 $file=Join-Path $dir 'backup.json'
 [IO.File]::WriteAllText($file,($j | ConvertTo-Json -Depth 8))
 return [pscustomobject]@{Id=$id;File=$file;Journal=$j}
}
try{
 $base=New-Journal 'Base' '2026-11-01T10:00:00Z'
 $first=New-Journal 'Advanced' '2026-11-02T10:00:00Z'
 $latest=New-Journal 'Advanced' '2026-11-03T10:00:00Z'
 $foreign=New-Journal 'Advanced' '2026-11-04T10:00:00Z' 'OTHER-SID'
 $history=@(Get-WBSessionHistory $root 'TEST-SID' 'TEST-PC')
 Assert ($history.Count -eq 3) 'History must include both engines and exclude another identity'
 Assert ((Get-WBRestoreSession $history '' 'Advanced').SessionId -eq $latest.Id) 'Default restore must choose latest advanced session'
 Assert ((Get-WBRestoreSession $history $first.Id 'Advanced').SessionId -eq $first.Id) 'Explicit restore must choose requested session'
 Assert ((Get-WBRestoreSession $history '' 'Base').SessionId -eq $base.Id) 'Base and advanced sessions must stay separate'
 foreach($bad in @('../outside',$foreign.Id,$base.Id)){
  $caught=$false;try{Get-WBRestoreSession $history $bad 'Advanced' | Out-Null}catch{$caught=$true}
  Assert $caught 'Reject invalid, foreign and wrong-engine restore IDs'
 }
 Copy-Item -LiteralPath $first.File -Destination ($first.File+'.bak')
 [IO.File]::WriteAllText($first.File,'{broken')
 $history=@(Get-WBSessionHistory $root 'TEST-SID' 'TEST-PC')
 Assert ((Get-WBRestoreSession $history $first.Id 'Advanced').Recovered) 'Recover valid previous journal'
 Remove-Item -LiteralPath $first.File
 Assert ((Get-WBRestoreSession @(Get-WBSessionHistory $root 'TEST-SID' 'TEST-PC') $first.Id 'Advanced').Recovered) 'Discover backup even when primary is missing'
 Remove-Item -LiteralPath ($first.File+'.bak')
 [IO.File]::WriteAllText($first.File,'{broken')
 $history=@(Get-WBSessionHistory $root 'TEST-SID' 'TEST-PC')
 Assert (@($history | Where-Object Status -eq Unreadable).Count -eq 1) 'Corrupt session must remain visible'
 Assert ((Get-WBRestoreSession $history '' 'Advanced').SessionId -eq $latest.Id) 'Unrelated corruption must not prevent recovery'
 $caught=$false;try{Get-WBRestoreSession $history $first.Id 'Advanced' | Out-Null}catch{$caught=$true}
 Assert $caught 'Do not restore unreadable session'
 $preview=Join-Path $root ([guid]::NewGuid().ToString());[void][IO.Directory]::CreateDirectory($preview)
 [IO.File]::WriteAllText((Join-Path $preview 'summary.json'),'{"Status":"Completed"}')
 $history=@(Get-WBSessionHistory $root 'TEST-SID' 'TEST-PC')
 Assert (@($history | Where-Object {-not $_.HasBackup}).Count -eq 1) 'Preserve preview sessions in history'
 Assert ([IO.File]::ReadAllText($first.File) -eq '{broken') 'Discovery must never rewrite damaged journals'
 'PASS: mixed history, exact restore ID, identity, corruption and backup recovery'
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
