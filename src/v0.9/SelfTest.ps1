#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$results=New-Object 'Collections.Generic.List[string]'
$failed=$false
function Check($name,[scriptblock]$body){
 try{& $body;$results.Add('PASS / '+$name);Write-Host ('PASS / '+$name) -ForegroundColor Green}
 catch{$script:failed=$true;$results.Add('FAIL / '+$name+' / '+$_.Exception.Message);Write-Host ($results[$results.Count-1]) -ForegroundColor Red}
}
Check 'Windows 11 x64 y PowerShell compatible' {
 if($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'Se necesita Windows x64 y PowerShell de 64 bits.'}
 $build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
 if($build -lt 22000){throw 'Se necesita Windows 11.'}
}
Check 'Sintaxis de scripts con el PowerShell de este equipo' {
 foreach($file in @(Get-ChildItem $root -Filter '*.ps1' -Recurse)){
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
 }
}
Check 'Carga de las ventanas WPF' {
 Add-Type -AssemblyName PresentationFramework
 foreach($name in @('Window.xaml','Settings.xaml','ActionsWindow.xaml')){
  [xml]$xml=Get-Content (Join-Path $root $name) -Raw -Encoding UTF8
  $window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader($xml)))
  $window.Close()
 }
}
Check 'Catalogo de preferencias' {
 [object[]]$items=Get-Content (Join-Path $root 'Catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($items.Count -ne 44 -or @($items.Name | Select-Object -Unique).Count -ne 44){throw 'Catalogo incompleto o duplicado.'}
 foreach($item in $items){if($item.Kind -notin @('DWord','String') -or $item.Path -notmatch '^(Software|System|Control Panel)\\'){throw 'Entrada invalida.'}}
}
Check 'Contrato del motor con registro simulado' {& (Join-Path $root 'Tests\Engine.Tests.ps1')}
$out=Join-Path $env:LOCALAPPDATA 'WinBoost\OptimizerV03'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$file=Join-Path $out 'selftest.txt'
$results | Set-Content -LiteralPath $file -Encoding UTF8
Write-Host "`nInforme: $file"
Write-Host 'Este diagnostico no prueba limpieza real, WinGet, DISM/SFC ni permisos de cada operacion.'
if($failed){exit 1}
