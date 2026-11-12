"""Entry integration with mocked Windows host, elevation and child process.
No Windows changes. Run with WINBOOST_TEST_PWSH set to pwsh/powershell."""
from pathlib import Path
import tempfile, subprocess, os, json, shutil
BASE=Path(__file__).resolve().parent.parent
PS=os.environ.get('WINBOOST_TEST_PWSH') or shutil.which('pwsh') or shutil.which('powershell')
assert PS, 'PowerShell required'
src=(BASE/'WinBoost.ps1').read_text(encoding='utf-8-sig')
src=src.replace("[Security.Principal.WindowsIdentity]::GetCurrent().User.Value","'S-TEST'")
src=src.replace("$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())","$principal=$null")
src=src.replace("$admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)","$admin=($env:WB_ADMIN -eq '1')")
src=src.replace("$PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'","($env:WB_REHOST -eq '1')")
src=src.replace("$build=[int](Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion').CurrentBuildNumber","$build=26100")
mock=r"""
function Start-Process {
 param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru,$Verb,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError)
 @{File=$FilePath;Args=$ArgumentList;Verb=$Verb} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $env:LOCALAPPDATA 'spawn.json')
 $p=[pscustomobject]@{HasExited=$true;ExitCode=2}
 $p | Add-Member ScriptMethod WaitForExit {}
 return $p
}
"""
src=src.replace("try {",mock+"\ntry {",1)
with tempfile.TemporaryDirectory(prefix='wb-entry-') as folder:
 root=Path(folder);app=root/"app with ' apostrophe";shutil.copytree(BASE,app)
 (app/'WinBoost.ps1').write_text(src,encoding='utf-8-sig')
 def run(name,args,admin='1',rehost='0'):
  data=root/name;data.mkdir()
  env=dict(os.environ,OS='Windows_NT',SystemRoot=str(root),LOCALAPPDATA=str(data),
           PROCESSOR_ARCHITECTURE='AMD64',WB_ADMIN=admin,WB_REHOST=rehost)
  r=subprocess.run([PS,'-NoProfile','-File',str(app/'WinBoost.ps1')]+args,env=env,capture_output=True,text=True)
  spawn=json.loads((data/'spawn.json').read_text(encoding='utf-8-sig')) if (data/'spawn.json').exists() else None
  return r,data,spawn
 for profile in ['Rapido','Gaming','Mantenimiento']:
  r,data,spawn=run(profile,['-Mode','Preview','-Profile',profile])
  assert r.returncode==2,(r.stdout,r.stderr)
  cfg=json.loads(next(data.rglob('request.json')).read_text(encoding='utf-8-sig'))
  assert cfg['Power']==(profile=='Gaming')
  assert cfg['Cleanup']==(profile=='Mantenimiento')
  assert not cfg['Apps'] and not cfg['Runtimes'] and not cfg['Repair']
  assert spawn['Args'][spawn['Args'].index('-Action')+1]=='Preview'
 print('PASS: 3 perfiles, plan enviado al motor y codigo de salida preservado')
 import base64
 for mode in ['GUI','Restore','Apply']:
  args=['-Mode',mode]+(['-RestoreSessionId','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'] if mode=='Restore' else [])+(['-Profile','Gaming'] if mode=='Apply' else [])
  r,data,spawn=run('relay'+mode,args,admin='0')
  assert r.returncode==2 and spawn['Verb']=='RunAs',(r.stdout,r.stderr)
  command=base64.b64decode(spawn['Args'][-1]).decode('utf-16-le')
  assert "app with '' apostrophe" in command and "-ExpectedSid 'S-TEST'" in command
  assert ('-Profile' in command)==(mode=='Apply')
  assert ('-RestoreSessionId aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' in command)==(mode=='Restore')
 print('PASS: elevacion, rutas con espacios/apostrofes y argumentos GUI/Restore/Apply')
 r,data,spawn=run('identity',['-Mode','Apply','-ExpectedSid','OTHER'])
 assert r.returncode==1 and spawn is None
 print('PASS: identidad diferente bloqueada antes de iniciar motor')
 bad=app/'bad.json';bad.write_text('{"Privacy":"true"}')
 r,data,spawn=run('bad',['-Mode','Apply','-PresetPath',str(bad)])
 assert r.returncode==1 and spawn is None
 print('PASS: perfil invalido bloqueado antes de iniciar motor')
 r,data,spawn=run('restore',['-Mode','Restore','-RestoreSessionId','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'])
 assert r.returncode==2 and not list(data.rglob('request.json'))
 assert spawn['Args'][spawn['Args'].index('-RestoreSessionId')+1]=='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
 print('PASS: restauracion sin perfil ni solicitud de ajustes')

# Advanced runner forwards restore without an empty PlanFile argument.
with tempfile.TemporaryDirectory(prefix='wb-actions-entry-') as folder:
 root=Path(folder);app=root/"app with ' apostrophe";shutil.copytree(BASE,app)
 (app/'WinBoost.ps1').write_text(src,encoding='utf-8-sig')
 native=root/'System32'/'WindowsPowerShell'/'v1.0'/'powershell.exe';native.parent.mkdir(parents=True)
 native.write_text('#!/usr/bin/env python3\nimport os,json,sys\nfrom pathlib import Path\nPath(os.environ["LOCALAPPDATA"],"native.json").write_text(json.dumps(sys.argv[1:]))\nsys.exit(2)\n');native.chmod(0o755)
 data=root/'data';data.mkdir()
 env=dict(os.environ,OS='Windows_NT',SystemRoot=str(root),LOCALAPPDATA=str(data),PROCESSOR_ARCHITECTURE='AMD64',WB_ADMIN='1',WB_REHOST='0')
 for mode in ['ActionsRestore','ActionsPreview','ActionsApply']:
  args=[PS,'-NoProfile','-File',str(app/'WinBoost.ps1'),'-Mode',mode]
  plan=root/"plan with ' quote.json";plan.write_text('{"Schema":1,"Actions":[]}')
  if mode=='ActionsRestore':args+=['-RestoreSessionId','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa']
  if mode!='ActionsRestore':args+=['-PresetPath',str(plan)]
  r=subprocess.run(args,env=env,capture_output=True,text=True)
  assert r.returncode==2,(mode,r.stderr,r.stdout)
  forwarded=json.loads((data/'native.json').read_text())
  assert forwarded[forwarded.index('-Mode')+1]==mode.replace('Actions','')
  if mode=='ActionsRestore':
   assert '-PlanFile' not in forwarded
   assert forwarded[forwarded.index('-RestoreSessionId')+1]=='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  else:assert forwarded[forwarded.index('-PlanFile')+1]==str(plan)
 print('PASS: advanced modes, exact paths and restore without empty argument')
