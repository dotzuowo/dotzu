#requires -Version 5.1
$ErrorActionPreference='Stop'
try{& (Join-Path $PSScriptRoot 'App.ps1')}
catch{
 $root=Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03'
 New-Item -ItemType Directory -Path $root -Force -ErrorAction SilentlyContinue | Out-Null
 $file=Join-Path $root 'startup-error.txt'
 $_ | Out-String | Set-Content -LiteralPath $file -Encoding UTF8
 try{Add-Type -AssemblyName PresentationFramework;[void][Windows.MessageBox]::Show("No se pudo abrir WinBoost.`n$($_.Exception.Message)`nDetalle: $file",'WinBoost - inicio')}
 catch{Write-Host "No se pudo abrir WinBoost. Consulta $file"}
 exit 1
}
