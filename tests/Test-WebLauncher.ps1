# Check the same text path used by iwr | iex. Never launch the Windows worker.
param([string]$File, [string]$Url)
$ErrorActionPreference='Stop'
if(-not $File -and -not $Url){throw 'Specify File or Url'}
$oldLocal=$env:LOCALAPPDATA;$oldOS=$env:OS;$oldSystem=$env:SystemRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('wb-web-test-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($temp)
try{
 $env:LOCALAPPDATA=$temp;$env:OS='Windows_NT';$env:SystemRoot=$temp
 $script:called=$false
 function Start-Process($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru){
  $cmd=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
  if($cmd -notmatch "^& '(.+WinBoost\.ps1)' -Mode GUI; exit " -or -not [IO.File]::Exists($Matches[1])){throw 'GUI dispatch did not target the extracted file'}
  $script:called=$true;return [pscustomobject]@{ExitCode=0}
 }
 if($Url){iwr $Url -UseBasicParsing | iex}else{
  $bytes=[IO.File]::ReadAllBytes($File)
  if($bytes[0] -ne 35 -or @($bytes | Where-Object {$_ -gt 127}).Count){throw 'Web launcher must be ASCII without BOM'}
  [Text.Encoding]::UTF8.GetString($bytes) | iex
 }
 if(-not $script:called){throw 'GUI dispatch did not run'}
 'PASS: web launcher extracted files and requested GUI; Windows worker was mocked.'
}finally{$env:LOCALAPPDATA=$oldLocal;$env:OS=$oldOS;$env:SystemRoot=$oldSystem;Remove-Item -LiteralPath $temp -Recurse -Force}
