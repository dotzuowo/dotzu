"""Worker orchestration with simulated OS adapters, no Windows mutations."""
import os,json,subprocess,tempfile,shutil,uuid
from pathlib import Path
BASE=Path(__file__).resolve().parent.parent
PS=os.environ['WINBOOST_TEST_PWSH']
src=(BASE/'ActionsEngine.ps1').read_text(encoding='utf-8-sig')
src=src.replace("[Security.Principal.WindowsIdentity]::GetCurrent().User.Value","'TEST-SID'")
src=src.replace("$build=[int](Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion').CurrentBuildNumber","$build=26100")
src=src.replace('$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())','$principal=$null')
src=src.replace('$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)','$true')
mock=r'''
$script:mockPath=Join-Path $env:LOCALAPPDATA 'store.json'
$script:store=@{}
if(Test-Path $script:mockPath){$o=Get-Content $script:mockPath -Raw | ConvertFrom-Json;foreach($p in $o.PSObject.Properties){$script:store[$p.Name]=$p.Value}}
function WB-CheckSupport($a,$arg,$build){if($env:WB_UNSUPPORTED -eq $a.Id){throw 'Unsupported mock'}}
function WB-Current($a){
 if($script:store.ContainsKey($a.Id)){return $script:store[$a.Id]}
 return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
}
function WB-SetState($a,$state){
 $script:store[$a.Id]=$state;WB-Save $script:store $script:mockPath
 if($env:WB_CRASH -eq '1'){[Environment]::Exit(99)}
 if($env:WB_CANCEL -eq '1'){[IO.File]::WriteAllText((Join-Path $session 'cancel.request'),'stop')}
}
function WB-InvokeNative($item,$session){
 if($env:WB_FAIL -eq '1'){throw 'Native failure'}
 [IO.File]::WriteAllText((Join-Path $session 'native.called'),$item.Definition.Id)
 if($env:WB_RESTART -eq 'Native'){return [pscustomobject]@{ExitCode=3010;RestartRequired=$true}}
 if($env:WB_RESTART -eq 'Feature'){return [pscustomobject]@{RestartNeeded='Yes'}}
 return 'Mock native result'
}
'''
src=src.replace(". (Join-Path $PSScriptRoot 'ActionsCore.ps1')",". (Join-Path $PSScriptRoot 'ActionsCore.ps1')\n"+mock)
with tempfile.TemporaryDirectory(prefix='wb-action-pipeline-') as tmp:
 root=Path(tmp);app=root/'app';shutil.copytree(BASE,app);(app/'ActionsEngine.ps1').write_text(src,encoding='utf-8-sig')
 def run(folder,mode,actions,restore_id=None,**extra):
  data=root/folder;data.mkdir(exist_ok=True)
  sid=str(uuid.uuid4());plan=data/'request.json';plan.write_text(json.dumps({'Schema':1,'Actions':actions}))
  env=dict(os.environ,OS='Windows_NT',PROCESSOR_ARCHITECTURE='AMD64',COMPUTERNAME='TEST-PC',LOCALAPPDATA=str(data),**extra)
  command=[PS,'-NoProfile','-File',str(app/'ActionsEngine.ps1'),'-Mode',mode,'-SessionId',sid,'-PlanFile',str(plan)]
  if restore_id:command+=['-RestoreSessionId',restore_id]
  r=subprocess.run(command,env=env,capture_output=True,text=True)
  session=data/'WinBoost'/'OptimizerV03'/'Advanced'/sid
  summary=json.loads((session/'summary.json').read_text()) if (session/'summary.json').exists() else None
  return r,summary,session,data
 actions=[{'Id':'AdvertisingID','Choice':'Desactivar'},{'Id':'TailoredExperiences','Choice':'Desactivar'}]
 r,s,p,d=run('preview','Preview',actions);assert r.returncode==0,(r.stderr,s);assert s['Status']=='Preview';assert not (d/'store.json').exists()
 print('PASS: preview without mutations')
 r,s,p,d=run('apply','Apply',actions);assert r.returncode==0,(r.stderr,s);assert all(x['Status']=='RegistryVerified' for x in s['Results'])
 r,s,p,d=run('apply','Restore',[]);assert r.returncode==0,(r.stderr,s);store=json.loads((d/'store.json').read_text());assert all(not x['Exists'] for x in store.values())
 print('PASS: full worker apply and restore')
 r,s,p,d=run('unsupported','Apply',actions,WB_UNSUPPORTED='TailoredExperiences');assert r.returncode!=0;assert not (d/'store.json').exists()
 print('PASS: unsupported plan blocks before mutation')
 r,s,p,d=run('failed','Apply',actions+[{'Id':'Hibernation','Choice':'Desactivar'}],WB_FAIL='1');assert r.returncode!=0;assert all(not x['Exists'] for x in json.loads((d/'store.json').read_text()).values());assert s['ManualReview']==['Hibernation']
 print('PASS: native failure rollback and manual review record')
 r,s,p,d=run('cancel','Apply',actions,WB_CANCEL='1');assert r.returncode==3 and s['ExitCode']==3 and s['Status']=='Cancelled';assert all(not x['Exists'] for x in json.loads((d/'store.json').read_text()).values())
 print('PASS: cooperative stop and rollback')
 r,s,p,d=run('assisted','Apply',[{'Id':'DNSoverHTTPS','Choice':'Abrir controles de Windows'}]);assert r.returncode==0;assert s['Results'][0]['Status']=='OpenedForManualAction'
 print('PASS: assisted action never reported as applied')
 r,s,p,d=run('crash','Apply',actions,WB_CRASH='1');assert r.returncode==99
 r,s,p,d=run('crash','Apply',actions);assert r.returncode!=0;assert 'incompleta' in s['Message']
 r,s,p,d=run('crash','Restore',[]);assert r.returncode==0;assert all(not x['Exists'] for x in json.loads((d/'store.json').read_text()).values())
 print('PASS: abrupt crash, block next apply, restore persisted journal')

 for result_type in ['Native','Feature']:
  r,s,p,d=run('restart'+result_type,'Apply',[{'Id':'Hibernation','Choice':'Desactivar'}],WB_RESTART=result_type)
  assert r.returncode==0 and s['RestartRequired'] and s['Results'][0]['RestartRequired'],(r.stderr,s)
  assert 'Reinicio requerido' in (p/'report.html').read_text()
 print('PASS: native 3010 and feature restart signals reach summary and HTML')
 r,s,first,d=run('specific','Apply',actions[:1]);assert r.returncode==0
 r,s,second,d=run('specific','Apply',actions[1:]);assert r.returncode==0
 r,s,p,d=run('specific','Restore',[],restore_id=first.name)
 assert r.returncode==0 and s['RestoredSession']==first.name,(r.stderr,s)
 current=json.loads((d/'store.json').read_text())
 assert not current['AdvertisingID']['Exists'] and current['TailoredExperiences']['Exists']
 r,s,p,d=run('specific','Restore',[],restore_id='../../outside')
 assert r.returncode==1 and current==json.loads((d/'store.json').read_text())
 print('PASS: restore chosen session without touching newer independent changes; reject invalid ID')
 # Keep one damaged journal, recover a healthy session, and block fresh apply.
 (first/'backup.json').write_text('{broken');(first/'backup.json.bak').unlink(missing_ok=True)
 r,s,p,d=run('specific','Restore',[],restore_id=second.name)
 assert r.returncode==2 and s['RestoredSession']==second.name and s['Warnings']==1,(r.stderr,s)
 r,s,p,d=run('specific','Apply',actions)
 assert r.returncode==1 and 'ilegible' in s['Message']
 assert (first/'backup.json').read_text()=='{broken'
 print('PASS: corrupt backup is visible, unrelated restore works with warning, apply fails closed')
 # Missing/corrupt primary with a valid .bak can be explicitly recovered.
 r,s,crashed,d=run('fallback','Apply',actions,WB_CRASH='1');assert r.returncode==99
 import shutil
 shutil.copyfile(crashed/'backup.json',crashed/'backup.json.bak')
 (crashed/'backup.json').unlink()
 r,s,p,d=run('fallback','Restore',[],restore_id=crashed.name)
 assert r.returncode==2 and s['Status']=='Restored' and not any(v['Exists'] for v in json.loads((d/'store.json').read_text()).values()),(r.stderr,s)
 print('PASS: recover interrupted action session from backup when primary is missing')
