# Integration check on a disposable hosted Windows runner only.
param([Parameter(Mandatory=$true)][string]$Source)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){throw 'Requires a disposable GitHub-hosted runner.'}
$root=Join-Path $env:RUNNER_TEMP ('wb-game-'+[guid]::NewGuid())
New-Item -Type Directory $root | Out-Null
$env:LOCALAPPDATA=$root
$game=Join-Path $root "test game '1'.exe"
[IO.File]::WriteAllBytes($game,[byte[]]@())
$cfg=Get-Content (Join-Path $Source 'Presets/Gaming.json') -Raw | ConvertFrom-Json
if($cfg.Privacy -or -not $cfg.Captures -or -not $cfg.Power){throw 'Gaming profile flags incorrect'}
# Power schemes depend on hardware and AC; exercise only game preferences on this VM.
$cfg.Power=$false
$cfg | Add-Member NoteProperty GameExecutable $game
$request=Join-Path $root 'request.json'
$cfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $request -Encoding UTF8
$catalog=Get-Content (Join-Path $Source 'Catalog.json') -Raw | ConvertFrom-Json
$items=@($catalog | Where-Object {$_.Name -in $cfg.SelectedSettings})
if($items.Count -ne 4){throw 'Unexpected Gaming catalog'}
function Run-Engine($action){
 $id=[guid]::NewGuid().ToString()
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Source 'Engine.ps1') -Action $action -SessionId $id -RequestFile $request | Out-Host
 if($LASTEXITCODE -notin @(0,2)){throw "$action failed with $LASTEXITCODE"}
 $dir=Join-Path (Join-Path $root 'WinBoost\OptimizerV03') $id
 return Get-Content (Join-Path $dir 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}
$gpu=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\DirectX\UserGpuPreferences')
$original='OtherOption=on;GpuPreference=1;Extra=keep;'
$gpu.SetValue($game,$original)
try{
 foreach($item in $items){
  $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($item.Path)
  try{$key.SetValue($item.Name,[int](1-$item.Value),[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$key.Dispose()}
 }
 $preview=Run-Engine 'Preview'
 if($gpu.GetValue($game) -cne $original){throw 'Preview modified GPU preferences'}
 $first=Run-Engine 'Apply'
 if($first.PreferencesApplied -ne 5 -or $gpu.GetValue($game) -cne 'OtherOption=on;GpuPreference=2;Extra=keep;'){throw 'Apply did not preserve unrelated preferences'}
 $second=Run-Engine 'Apply'
 if($second.PreferencesApplied -ne 0 -or @($second.AlreadyConfigured).Count -ne 5){throw 'Repeated apply should report five matches'}
 $null=Run-Engine 'Restore'
 $null=Run-Engine 'Restore'
 if($gpu.GetValue($game) -cne $original){throw 'Restore did not recover original GPU string'}
 foreach($item in $items){
  $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($item.Path)
  try{if($key.GetValue($item.Name) -ne (1-$item.Value)){throw "Failed to restore $($item.Name)"}}finally{$key.Dispose()}
 }
 Write-Output 'PASS: Windows PowerShell desktop preview, five verified changes, idempotence and restoration.'
}finally{$gpu.DeleteValue($game,$false);$gpu.Dispose()}
