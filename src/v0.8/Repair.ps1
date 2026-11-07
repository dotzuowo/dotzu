#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$LogFile)
$ErrorActionPreference='Stop'
$code=1;$transcribing=$false
try{
 Start-Transcript -LiteralPath $LogFile -Force | Out-Null;$transcribing=$true
 & dism.exe /Online /Cleanup-Image /RestoreHealth
 $dismCode=$LASTEXITCODE
 if($dismCode -eq 3010){Write-Host 'DISM requiere reinicio. No se ejecuta SFC hasta reiniciar.';$code=3010}
 elseif($dismCode -ne 0){Write-Host "DISM: error $dismCode. Se omite SFC.";$code=1}
 else{
  & sfc.exe /scannow
  $sfcCode=$LASTEXITCODE
  Write-Host "SFC: codigo $sfcCode. Revisa el texto del diagnostico y CBS.log."
  $code=if($sfcCode -eq 0){0}else{1}
 }
}catch{Write-Error $_ -ErrorAction Continue;$code=1}
finally{if($transcribing){Stop-Transcript | Out-Null}}
exit $code
