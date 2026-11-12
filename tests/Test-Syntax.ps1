# Parse only: never dot-source production scripts or change Windows settings.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$files=@(Get-ChildItem (Join-Path $repo 'src/v0.9') -Filter *.ps1 -Recurse)+@(Get-ChildItem $PSScriptRoot -Filter *.ps1)+@(Get-Item (Join-Path $repo 'WinBoost.ps1'),(Join-Path $repo 'install.ps1'))
foreach($file in $files){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($file.FullName+': '+($errors.Message -join '; '))}
}
foreach($file in Get-ChildItem (Join-Path $repo 'src/v0.9') -Filter *.xaml){[xml](Get-Content $file.FullName -Raw -Encoding UTF8) | Out-Null}
'PASS: PowerShell syntax and XAML XML'
