$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$base=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'Engine.ps1'),[ref]$tokens,[ref]$errors)
foreach($fn in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
 $source=$fn.Extent.Text.Replace('[Security.Principal.WindowsIdentity]::GetCurrent().User.Value',"'TEST-SID'")
 . ([scriptblock]::Create($source))
}
[object[]]$catalog=Get-Content (Join-Path $base 'Catalog.json') -Raw | ConvertFrom-Json
. (Join-Path $base 'ExtraFunctions.ps1')
$cfg=Validate-Config ([pscustomobject]@{Privacy=$true;Captures=$false;Mouse=$false;Power=$false;Cleanup=$false;Apps=$false;Runtimes=$false;Repair=$false})
$script:store=@{}
function Key($path,$name){return $path+'|'+$name}
function Read-Reg($path,$name){
 $k=Key $path $name
 if($script:store.ContainsKey($k)){return $script:store[$k]}
 return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
}
function Write-Reg($path,$name,$value,$kind){$script:store[(Key $path $name)]=[pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}}
function Remove-Reg($path,$name){$script:store.Remove((Key $path $name))}
function Log($message,$level='INFO'){}
function Assert($ok,$message){if(-not $ok){throw $message}}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('winboost-tests-'+[guid]::NewGuid())
$env:COMPUTERNAME='TEST-PC'
$script:warnings=0
function New-TestSession {
 $script:root=Join-Path $testRoot ([guid]::NewGuid().ToString());$script:run=Join-Path $script:root 'session'
 New-Item -ItemType Directory $script:run -Force | Out-Null
 $script:journalPath=Join-Path $script:run 'backup.json'
 $script:cancelPath=Join-Path $script:run 'cancel.request'
 $script:journalWrites=0;$script:startedAt=[Diagnostics.Stopwatch]::StartNew()
 $script:journal=[pscustomobject]@{Schema=3;Computer='TEST-PC';Sid='TEST-SID';Date=(Get-Date).ToString('o');Status='Pending';Registry=@();Power=$null;Apps=@()}
}
# Existentes, ausentes y tipos distintos deben volver a su estado exacto.
New-TestSession
$first=$catalog[0];Write-Reg $first.Path $first.Name 'original' 'String'
Registry-Apply
Assert ($script:journal.Registry.Count -eq 21) 'Debe registrar 21 preferencias base'
Registry-Apply
Assert ($script:journal.Registry.Count -eq 21) 'Reaplicar no debe duplicar entradas'
Restore-Latest
Assert ((Read-Reg $first.Path $first.Name).Value -eq 'original') 'Debe restaurar tipo/valor anterior'
Assert ($script:store.Count -eq 1) 'Debe eliminar valores originalmente ausentes'
Write-Output 'PASS: aplicar, idempotencia y restauracion de valores presentes/ausentes'
# Un cambio externo no se sobreescribe.
$script:store=@{};New-TestSession;Registry-Apply
Write-Reg $first.Path $first.Name 1234 'DWord'
Restore-Latest
Assert ((Read-Reg $first.Path $first.Name).Value -eq 1234) 'No debe sobrescribir cambio externo'
Assert ($script:journal.Status -eq 'RestoreConflicts') 'Debe marcar conflicto'
Write-Output 'PASS: conflictos externos preservados'
# Fallo durante escritura: entrada planeada guardada antes de mutacion.
$script:store=@{};New-TestSession
$script:count=0
function Write-Reg($path,$name,$value,$kind){
 $script:count++
 if($script:count -eq 3){throw 'fallo simulado'}
 $script:store[(Key $path $name)]=[pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}
}
try{Registry-Apply;throw 'No hubo fallo'}catch{Assert ($_.Exception.Message -eq 'fallo simulado') 'Fallo inesperado'}
$disk=Get-Content $script:journalPath -Raw | ConvertFrom-Json
Assert ($disk.Registry.Count -ge 3) 'Debe conservar originales y la intencion previa al fallo'
function Write-Reg($path,$name,$value,$kind){$script:store[(Key $path $name)]=[pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}}
Restore-Latest
Assert ($script:store.Count -eq 0) 'Debe restaurar aplicacion parcial'
Write-Output 'PASS: recuperacion tras fallo parcial'
# Respaldo manipulado no puede imponer un destino fuera del catalogo.
$script:store=@{};New-TestSession;Registry-Apply
$script:journal.Registry[0].After.Value=999
Save-Json $script:journal $script:journalPath
Restore-Latest
Assert ($script:journal.Status -eq 'RestoreConflicts') 'Debe rechazar destino ajeno al catalogo'
Write-Output 'PASS: validacion de catalogo en restauracion'
# La version anterior sobrevive a una escritura atomica y puede leerse tras corrupcion.
New-TestSession
Save-Json ([pscustomobject]@{Number=1}) $script:journalPath
Save-Json ([pscustomobject]@{Number=2}) $script:journalPath
Assert ((Read-Journal $script:journalPath).Number -eq 2) 'Debe leer ultima version'
[IO.File]::WriteAllText($script:journalPath,'{corrupto')
Assert ((Read-Journal $script:journalPath).Number -eq 1) 'Debe recuperar version anterior'
Write-Output 'PASS: escritura atomica y recuperacion del diario anterior'
# Cancelacion cooperativa.
[IO.File]::WriteAllText($script:cancelPath,'Stop')
$caught=$false
try{Check-Cancellation}catch [OperationCanceledException]{$caught=$true}
Assert $caught 'Debe reconocer peticion de detener'
Write-Output 'PASS: senal de cancelacion cooperativa'
# Validacion de perfiles importados.
$bad=[pscustomobject]@{Privacy=$true;Captures=$false;Mouse=$false;Power=$false;Cleanup=$false;Apps=$false;Runtimes=$false;Repair=$false;SelectedSettings=@('NoExiste')}
$caught=$false
try{[void](Validate-Config $bad)}catch{$caught=$true}
Assert $caught 'Debe rechazar ajustes desconocidos'
Write-Output 'PASS: rechazo de perfiles invalidos'
# Inicio: conservar comando y tipo ExpandString sin expandir variables.
$script:store=@{};New-TestSession
$startup='Software\Microsoft\Windows\CurrentVersion\Run'
Write-Reg $startup 'Discord' '%LOCALAPPDATA%\Discord\Update.exe --processStart Discord.exe' 'ExpandString'
Apply-Startup
Assert (-not (Read-Reg $startup 'Discord').Exists) 'Debe quitar entrada opcional de inicio'
Restore-Latest
Assert ((Read-Reg $startup 'Discord').Kind -eq 'ExpandString') 'Debe restaurar tipo expandible'
Assert ((Read-Reg $startup 'Discord').Value.StartsWith('%LOCALAPPDATA%')) 'No debe expandir comando original'
Write-Output 'PASS: restauracion exacta de inicio automatico'
# Diario agrupado: todos los originales quedan guardados con menos escrituras.
$script:store=@{};New-TestSession
Registry-Apply
Assert ($script:journalWrites -le 5) 'La ruta base no debe volver a guardar dos veces por valor'
Assert ((Read-Journal $script:journalPath).Registry.Count -eq 21) 'El diario debe contener todos los originales'
Write-Output ('PASS: diario agrupado / '+$script:journalWrites+' escrituras para 21 preferencias')
# El inventario ligero no debe abrir CIM ni modulos de red.
New-TestSession;$script:build=26100;$script:inventoryCache=$null
$cfg.DeepInventory=$false
function Get-CimInstance {throw 'CIM prohibido en inventario ligero'}
function Get-NetAdapter {throw 'Red prohibida en inventario ligero'}
$light=Inventory (Join-Path $script:run 'light.json')
Assert ($light.Mode -eq 'Light' -and $light.Errors.Count -eq 0) 'El inventario ligero no debe llamar adaptadores pesados'
Write-Output 'PASS: inventario ligero sin CIM ni red'
# Concurrencia entre lectura y escritura: no revertir cambios que no hicimos.
$script:store=@{};New-TestSession;$script:reads=0
function Read-Reg($path,$name){
 $script:reads++
 $key=Key $path $name
 if($script:reads -eq (@(Selected-Catalog).Count+1)){$script:store[$key]=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0}}
 if($script:store.ContainsKey($key)){return $script:store[$key]}
 return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
}
$caught=$false
try{Registry-Apply}catch{$caught=$true}
Assert $caught 'Debe detenerse ante un cambio simultaneo'
Assert ($script:journal.Registry[0].State -eq 'NotApplied') 'Debe marcar operacion que no se ejecuto'
Restore-Latest
Assert ($script:store.Count -eq 1) 'No debe deshacer una escritura ajena'
Write-Output 'PASS: concurrencia antes de escribir preservada durante recuperacion'
# Un informe no debe ejecutar HTML procedente de nombres/valores.
New-TestSession
$script:steps=@([pscustomobject]@{Name='<script>alert(1)</script>';State='Completed';Seconds=0;Detail='<img src=x onerror=alert(1)>'})
$script:freed=0L;$script:rollback='No solicitado';$SessionId='test';$Action='Apply'
Write-Report 'Completed' '<script>untrusted</script>'
$html=Get-Content (Join-Path $script:run 'report.html') -Raw
Assert (-not $html.Contains('<script>')) 'No debe insertar etiquetas de script'
Assert ($html.Contains('&lt;script&gt;')) 'Debe conservar texto escapado en el informe'
Write-Output 'PASS: informe HTML conserva datos como texto'
# Perfil Rapido: no habilitar mantenimiento largo de forma implicita.
$tokens=$null;$errors=$null
$appAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'App.ps1'),[ref]$tokens,[ref]$errors)
$profileFn=$appAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-Profile'},$false)
. ([scriptblock]::Create($profileFn.Extent.Text))
$ui=@{Profile=[pscustomobject]@{SelectedIndex=0};ProfileDescription=[pscustomobject]@{Text=''}}
foreach($name in @('Privacy','Captures','Mouse','Power','Cleanup','Apps','Runtimes','Repair','Startup','DeepInventory')){$ui['Opt'+$name]=[pscustomobject]@{IsChecked=$false}}
function Update-Summary {}
Set-Profile
Assert ($ui.OptPrivacy.IsChecked -and -not $ui.OptCleanup.IsChecked -and -not $ui.OptRepair.IsChecked -and -not $ui.OptRuntimes.IsChecked -and -not $ui.OptDeepInventory.IsChecked) 'Rapido debe omitir tareas largas'
$ui.Profile.SelectedIndex=2;Set-Profile
Assert ($ui.OptCleanup.IsChecked -and $ui.OptDeepInventory.IsChecked -and -not $ui.OptRepair.IsChecked -and -not $ui.OptRuntimes.IsChecked) 'Mantenimiento no debe forzar instalaciones o reparacion'
Write-Output 'PASS: perfiles separan optimizacion de tareas largas'

# Catalogo ampliado: las opciones nuevas no entran en el perfil base.
Assert (@($cfg.SelectedSettings).Count -eq 26) 'El perfil base no debe activar opciones nuevas'
function Read-Reg($path,$name){
 $k=Key $path $name
 if($script:store.ContainsKey($k)){return $script:store[$k]}
 return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
}
$cfg.Captures=$true;$cfg.Mouse=$true
$cfg.SelectedSettings=@($catalog.Name)
$script:store=@{};New-TestSession
Registry-Apply
Assert ($script:journal.Registry.Count -eq 45) 'Deben aplicar las 45 preferencias seleccionadas'
Registry-Apply
Assert ($script:journal.Registry.Count -eq 45) 'No duplicar al reaplicar el catalogo ampliado'
Restore-Latest
Assert ($script:store.Count -eq 0) 'Restaurar las 45 preferencias a su ausencia original'
Write-Output 'PASS: 19 opciones nuevas optativas, 45 preferencias idempotentes y reversibles'
Remove-Item -LiteralPath $testRoot -Recurse -Force

