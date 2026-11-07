$ErrorActionPreference='Stop'
$folder=Join-Path $env:LOCALAPPDATA ('WinBoost\Inventario-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
Get-WindowsOptionalFeature -Online | Select-Object FeatureName,State | Export-Csv (Join-Path $folder 'caracteristicas.csv') -NoTypeInformation -Encoding UTF8
Get-WindowsCapability -Online | Select-Object Name,State | Export-Csv (Join-Path $folder 'capacidades.csv') -NoTypeInformation -Encoding UTF8
Get-AppxPackage | Select-Object Name,PackageFullName,NonRemovable,IsFramework | Export-Csv (Join-Path $folder 'aplicaciones.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('Inventario guardado: '+$folder) -ForegroundColor Cyan
Start-Process explorer.exe -ArgumentList ('"'+$folder+'"')
