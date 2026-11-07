#requires -Version 5.1
<#
.SYNOPSIS
WinBoost: interfaz WPF o ejecucion automatica desde PowerShell.
.EXAMPLE
.\WinBoost.ps1 -Mode Preview -Profile Gaming
.EXAMPLE
.\WinBoost.ps1 -Mode Apply -Profile Gaming
#>
[CmdletBinding()]
param(
 [ValidateSet('GUI','Preview','Apply','Restore','Diagnose','ActionsPreview','ActionsApply','ActionsRestore')][string]$Mode='GUI',
 [ValidateSet('Rapido','Gaming','Mantenimiento')][string]$Profile='Rapido',
 [string]$PresetPath,
 [switch]$OpenReport,
 [string]$ExpectedSid
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
try {
 if($env:OS -ne 'Windows_NT'){throw 'WinBoost requiere Windows 11 x64.'}
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($ExpectedSid -and $sid -ne $ExpectedSid){throw 'Usa la misma cuenta al elevar permisos. Se cancelo para no modificar el perfil de otro usuario.'}
 $nativePS=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if(-not [Environment]::Is64BitProcess){$nativePS=Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'}
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 $admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 $needsAdmin=$Mode -in @('GUI','Apply','Restore','ActionsPreview','ActionsApply','ActionsRestore')
 $needsHost=$PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'
 if($PresetPath){$PresetPath=(Resolve-Path -LiteralPath $PresetPath -ErrorAction Stop).ProviderPath}
 if($needsHost -or ($needsAdmin -and -not $admin)){
  # Encode trusted argument values as literals; paths with spaces/apostrophes remain data.
  $command='& '+("'"+$PSCommandPath.Replace("'","''")+"'")+' -Mode '+$Mode+' -ExpectedSid '+("'"+$sid+"'")
  if($PSBoundParameters.ContainsKey('Profile')){$command+=' -Profile '+$Profile}
  if($PresetPath){$command+=' -PresetPath '+("'"+$PresetPath.Replace("'","''")+"'")}
  if($OpenReport){$command+=' -OpenReport'}
  $command+='; exit $LASTEXITCODE'
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $launch=@{FilePath=$nativePS;ArgumentList=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded);Wait=$true;PassThru=$true}
  if($needsAdmin -and -not $admin){$launch.Verb='RunAs'}
  $child=Start-Process @launch
  exit $child.ExitCode
 }
 $build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
 if($build -lt 22000 -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'Esta version admite Windows 11 x64.'}
 if($Mode -in @('ActionsPreview','ActionsApply','ActionsRestore')){
  if($PSBoundParameters.ContainsKey('Profile')){throw 'Los modulos usan -PresetPath con un plan de acciones JSON, no -Profile.'}
  $actionMode=$Mode.Replace('Actions','')
  if($actionMode -ne 'Restore' -and -not $PresetPath){throw 'Indica -PresetPath con el plan exportado desde Modulos de Windows.'}
  if($actionMode -eq 'Restore' -and $PresetPath){throw 'ActionsRestore usa la ultima sesion de modulos; no admite un plan.'}
  $id=[guid]::NewGuid().ToString()
  $engine=Join-Path $PSScriptRoot 'ActionsEngine.ps1'
  $runnerArgs=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$engine,'-Mode',$actionMode,'-SessionId',$id)
  if($PresetPath){$runnerArgs+=@('-PlanFile',$PresetPath)}
  & $nativePS @runnerArgs
  $resultCode=$LASTEXITCODE
  $report=Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03\Advanced') $id) 'report.html'
  if($OpenReport -and (Test-Path -LiteralPath $report)){Start-Process -FilePath $report}
  exit $resultCode
 }
 if($Mode -eq 'GUI'){
  if($PresetPath -or $PSBoundParameters.ContainsKey('Profile')){throw 'Para perfiles por comando usa -Mode Preview o -Mode Apply. En GUI selecciona el perfil dentro de la ventana.'}
  & (Join-Path $PSScriptRoot 'Launch.ps1')
  exit 0
 }
 if($Mode -eq 'Diagnose'){
  & $nativePS -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SelfTest.ps1')
  exit $LASTEXITCODE
 }
 if($Mode -eq 'Restore' -and ($PresetPath -or $PSBoundParameters.ContainsKey('Profile'))){throw 'Restore usa el ultimo respaldo pendiente; no admite perfiles.'}
 $catalog=@(Get-Content (Join-Path $PSScriptRoot 'Catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
 . (Join-Path $PSScriptRoot 'ExtraFunctions.ps1')
 $cfg=$null
 if($Mode -ne 'Restore'){
  $file=if($PresetPath){$PresetPath}else{Join-Path $PSScriptRoot ('Presets\'+$Profile+'.json')}
  $cfg=Validate-Config (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)
 }
 $id=[guid]::NewGuid().ToString()
 $session=Join-Path (Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03') $id
 New-Item -ItemType Directory -Path $session -Force | Out-Null
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Engine.ps1')+'"'),'-Action',$Mode,'-SessionId',$id)
 if($null -ne $cfg){
  $request=Join-Path $session 'request.json'
  $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $request -Encoding UTF8
  $arguments+=@('-RequestFile',('"'+$request+'"'))
 }
 Write-Host "`n WINBOOST / POWERSHELL 0.9" -ForegroundColor Cyan
 Write-Host " Modo: $Mode | Perfil: $Profile"
 Write-Host " Informe y registro: $session`n"
 $worker=Start-Process -FilePath $nativePS -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $session 'stdout.log') -RedirectStandardError (Join-Path $session 'stderr.log')
 $last=''
 while(-not $worker.HasExited){
  $statusFile=Join-Path $session 'status.json'
  if(Test-Path -LiteralPath $statusFile){
   try{
    $state=Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Progress -Activity 'WinBoost' -Status $state.Message -PercentComplete ([math]::Min(100,[math]::Max(0,[int]$state.Percent)))
    if($last -ne $state.Message){Write-Host ('  '+$state.Message);$last=$state.Message}
   }catch{Write-Verbose 'Actualizacion de estado en curso.'}
  }
  Start-Sleep -Milliseconds 300
 }
 $worker.WaitForExit()
 Write-Progress -Activity 'WinBoost' -Completed
 $summary=Join-Path $session 'summary.json'
 if(Test-Path -LiteralPath $summary){
  $result=Get-Content -LiteralPath $summary -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Host ("`n"+$result.Status+' / '+$result.Message)
  Write-Host ('Preferencias: '+$result.PreferencesApplied+' | Avisos: '+$result.Warnings)
 }else{Write-Warning 'El motor no genero resumen. Revisa stderr.log en la carpeta indicada.'}
 $report=Join-Path $session 'report.html'
 if($OpenReport -and (Test-Path -LiteralPath $report)){Start-Process -FilePath $report}
 exit $worker.ExitCode
}catch{
 Write-Error $_ -ErrorAction Continue
 exit 1
}
