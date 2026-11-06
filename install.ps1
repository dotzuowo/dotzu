#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('Apply','Preview','GUI','DownloadOnly')][string]$Mode='Apply',
 [ValidateSet('Rapido','Gaming','Mantenimiento')][string]$Profile='Rapido'
)
$ErrorActionPreference='Stop'
$repository='dotzuowo/dotzu'
$tag='v0.7'
$asset='WinBoost_Optimizer_v0.7.zip'
$expectedHash='e2afdaad2dfee781824c8ee4eb85e2ddb8b9d3d0de7cdbbea07cd7b7bda6ba48'
$packageRoot='WinBoost_Optimizer_v0.7'
$staging=$null
try{
 if($repository -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$'){throw 'El instalador aun no esta configurado para un repositorio. No hay una publicacion activa.'}
 if($env:OS -ne 'Windows_NT'){throw 'WinBoost requiere Windows 11 x64.'}
 $os=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
 if([int]$os.CurrentBuildNumber -lt 22000){throw 'Requiere Windows 11.'}
 if($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'AMD64'){throw 'Requiere Windows x64 (Intel o AMD).'}
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 $staging=Join-Path (Join-Path $env:LOCALAPPDATA 'WinBoost\Packages\v0.7') ([guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $staging -Force | Out-Null
 $archive=Join-Path $staging $asset
 $url='https://github.com/'+$repository+'/releases/download/'+$tag+'/'+$asset
 Write-Host 'WinBoost / 1 de 3: descargando paquete v0.7...' -ForegroundColor Cyan
 Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $archive -TimeoutSec 120
 Write-Host 'WinBoost / 2 de 3: verificando SHA-256 y contenido...' -ForegroundColor Cyan
 if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash){throw 'El paquete no coincide con la version publicada. No se ejecutara.'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($archive)
 try{
  $length=0L
  foreach($entry in $zip.Entries){
   $name=$entry.FullName.Replace('\','/')
   if(-not $name.StartsWith($packageRoot+'/',[StringComparison]::Ordinal) -or $name -match '(^|/)\.\.(/|$)|:' -or [IO.Path]::IsPathRooted($name)){throw 'El ZIP contiene una ruta no permitida.'}
   $length+=$entry.Length
   if($length -gt 52428800){throw 'El paquete excede el tamano previsto.'}
  }
 }finally{$zip.Dispose()}
 [IO.Compression.ZipFile]::ExtractToDirectory($archive,$staging)
 $app=Join-Path (Join-Path $staging $packageRoot) 'WinBoost.ps1'
 if(-not (Test-Path -LiteralPath $app -PathType Leaf)){throw 'El paquete no contiene WinBoost.ps1.'}
 Write-Host ('Archivos: '+(Split-Path $app -Parent))
 if($Mode -eq 'DownloadOnly'){Write-Host 'Descarga verificada. No se aplicaron ajustes.';return}
 Write-Host ('WinBoost / 3 de 3: iniciando '+$Mode+' / '+$Profile) -ForegroundColor Cyan
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if(-not [Environment]::Is64BitProcess){$ps=Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'}
 if($Mode -eq 'GUI'){& $ps -NoProfile -STA -ExecutionPolicy Bypass -File $app}
 else{& $ps -NoProfile -STA -ExecutionPolicy Bypass -File $app -Mode $Mode -Profile $Profile -OpenReport}
 $code=$LASTEXITCODE
 if($code -notin @(0,2)){throw "WinBoost termino con codigo $code. Revisa el informe o el mensaje de la aplicacion."}
 Write-Host 'WinBoost finalizo. Revisa el informe para conocer cambios y avisos.' -ForegroundColor Cyan
}catch{
 Write-Error ('WinBoost: '+$_.Exception.Message) -ErrorAction Continue
 throw
}
