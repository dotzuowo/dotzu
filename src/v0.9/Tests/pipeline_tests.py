"""Pruebas de desarrollo: Python 3 + PowerShell. Sustituye adaptadores de Windows;
no ejecuta registro real, limpieza, instaladores ni reparaciones."""
from pathlib import Path
import tempfile, json, subprocess, os, uuid, shutil, sys

BASE=Path(__file__).resolve().parent.parent
PWSH=os.environ.get('WINBOOST_TEST_PWSH') or shutil.which('pwsh') or shutil.which('powershell')
if not PWSH: raise SystemExit('Falta PowerShell. Define WINBOOST_TEST_PWSH.')
MOCK=r'''
$script:mockPath=Join-Path $env:WB_TEST_WORLD 'store.json'
$script:mockStore=@{};$script:writeCount=0
if(Test-Path -LiteralPath $script:mockPath){
 $v=Get-Content -LiteralPath $script:mockPath -Raw | ConvertFrom-Json
 foreach($p in $v.PSObject.Properties){$script:mockStore[$p.Name]=$p.Value}
}
function Preflight {
 $script:build=26100
 if($env:WB_TEST_FAIL_PREFLIGHT -eq '1'){throw 'preflight simulado'}
 Save-Json @{Build=$script:build;Mock=$true} (Join-Path $run 'preflight.json')
}
function Read-Reg($path,$name){
 $key=$path+'|'+$name
 if($script:mockStore.ContainsKey($key)){return $script:mockStore[$key]}
 return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
}
function Write-Reg($path,$name,$value,$kind){
 $script:writeCount++
 if($env:WB_TEST_FAIL_WRITE -and $script:writeCount -eq [int]$env:WB_TEST_FAIL_WRITE){throw 'fallo de registro simulado'}
 $script:mockStore[$path+'|'+$name]=[pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}
 Save-Json $script:mockStore $script:mockPath
 if($env:WB_TEST_CRASH_WRITE -and $script:writeCount -eq [int]$env:WB_TEST_CRASH_WRITE){[Environment]::Exit(99)}
 if($env:WB_TEST_CANCEL_WRITE -and $script:writeCount -eq [int]$env:WB_TEST_CANCEL_WRITE){[IO.File]::WriteAllText($script:cancelPath,'Stop')}
}
function Remove-Reg($path,$name){$script:mockStore.Remove($path+'|'+$name);Save-Json $script:mockStore $script:mockPath}
function Inventory($file){$v=@{Mock=$true;Disks=@();Errors=@()};Save-Json $v $file;return $v}
function Apply-Power {Log 'MOCK energia'}
function Clean-Temp {
 $script:freed=4096;Log 'MOCK limpieza'
 if($env:WB_TEST_CANCEL_CLEANUP -eq '1'){[IO.File]::WriteAllText($script:cancelPath,'Stop');Check-Cancellation}
}
function Remove-OptionalApps {Log 'MOCK apps'}
function Install-Runtimes {if($env:WB_TEST_RUNTIME_ERROR -eq '1'){throw 'WinGet sin red simulado'};Log 'MOCK runtimes'}
function Repair-Windows {if($env:WB_TEST_UAC_CANCEL -eq '1'){throw 'UAC cancelado simulado'};Log 'MOCK reparar'}
'''
DEFAULT=dict(Privacy=True,Captures=False,Mouse=False,Power=False,Cleanup=False,Apps=False,Runtimes=False,Repair=False,Startup=False)

with tempfile.TemporaryDirectory(prefix='winboost-pipeline-') as folder:
    temp=Path(folder); app=temp/'app'; app.mkdir()
    for name in ['Catalog.json','ExtraFunctions.ps1']:
        shutil.copy(BASE/name, app/name)
    source=(BASE/'Engine.ps1').read_text(encoding='utf-8-sig')
    source=source.replace('[Security.Principal.WindowsIdentity]::GetCurrent().User.Value',"'TEST-SID'")
    marker='$mutex=$null;$held=$false;'
    assert source.count(marker)==1
    source=source.replace(marker,MOCK+'\n'+marker)
    (app/'Engine.ps1').write_text(source,encoding='utf-8-sig')
    def execute(world, action='Apply', config=None, **flags):
        world.mkdir(exist_ok=True)
        sid=str(uuid.uuid4()); request=world/(sid+'.json')
        request.write_text(json.dumps(DEFAULT if config is None else config),encoding='utf-8')
        env=os.environ.copy();env.update(LOCALAPPDATA=str(world),COMPUTERNAME='TEST-PC',WB_TEST_WORLD=str(world))
        env.update({key:str(value) for key,value in flags.items()})
        result=subprocess.run([PWSH,'-NoProfile','-File',str(app/'Engine.ps1'),'-Action',action,'-SessionId',sid,'-RequestFile',str(request)],env=env,capture_output=True,text=True,timeout=40)
        matches=list(world.rglob('status.json'))
        run=next((p.parent for p in matches if p.parent.name==sid),None)
        assert run is not None, result.stderr
        summary=json.loads((run/'summary.json').read_text(encoding='utf-8-sig')) if (run/'summary.json').exists() else None
        status=json.loads((run/'status.json').read_text(encoding='utf-8-sig'))
        return result,status,summary,run
    def world(name):return temp/name
    def check(ok,message,result=None):
        if not ok: raise AssertionError(message+(('\n'+result.stdout+'\n'+result.stderr) if result else ''))
    def store(w):return json.loads((w/'store.json').read_text(encoding='utf-8-sig')) if (w/'store.json').exists() else {}

    w=world('preview');r,s,summary,run=execute(w,action='Preview')
    check(r.returncode==0 and s['Phase']=='Completed' and not store(w),'Preview no debe modificar registro',r)
    check(len(json.loads((run/'preview.json').read_text()))==21,'Plan base debe incluir 21 preferencias')
    print('PASS: pipeline Preview sin cambios y con plan exacto')

    w=world('normal');r,s,summary,run=execute(w)
    check(r.returncode==0 and len(store(w))==21 and summary['PreferencesApplied']==21,'Apply base',r)
    r,s,summary,_=execute(w)
    check(r.returncode==0 and summary['PreferencesApplied']==0,'Apply idempotente',r)
    r,s,summary,_=execute(w,action='Restore')
    check(r.returncode==0 and len(store(w))==21,'Restaurar sesion vacia primero',r)
    r,s,summary,_=execute(w,action='Restore')
    check(r.returncode==0 and not store(w),'Restaurar valores de sesion original',r)
    print('PASS: pipeline Apply, repeticion y restauracion por orden')

    w=world('failed');r,s,summary,run=execute(w,WB_TEST_FAIL_WRITE=3)
    check(r.returncode==1 and s['Phase']=='Failed' and not store(w),'Fallo critico debe revertir cambios parciales',r)
    check('restauradas' in summary['Rollback'],'Informe debe identificar recuperacion')
    print('PASS: fallo critico con reversion automatica')

    w=world('cancel');r,s,summary,run=execute(w,WB_TEST_CANCEL_WRITE=2)
    check(r.returncode==3 and s['Phase']=='Cancelled' and not store(w),'Cancelacion debe revertir preferencias',r)
    print('PASS: cancelacion cooperativa con reversion')

    w=world('cleanup');c=dict(DEFAULT,Cleanup=True)
    r,s,summary,run=execute(w,config=c,WB_TEST_CANCEL_CLEANUP=1)
    check(r.returncode==3 and not store(w) and summary['TempBytesDeleted']==4096,'No debe afirmar que revierte limpieza',r)
    print('PASS: cancelacion conserva informe de tareas irreversibles')

    w=world('warnings');c=dict(DEFAULT,Runtimes=True,Repair=True)
    r,s,summary,run=execute(w,config=c,WB_TEST_RUNTIME_ERROR=1,WB_TEST_UAC_CANCEL=1)
    check(r.returncode==2 and s['Phase']=='CompletedWithWarnings' and summary['Warnings']==2,'Avisos no deben ser exito silencioso',r)
    check((run/'after.json').exists(),'Debe continuar hasta informe posterior')
    print('PASS: fallos de red/UAC simulados con avisos y continuacion')

    w=world('badconfig');c=dict(DEFAULT,Privacy='true')
    r,s,summary,run=execute(w,config=c)
    check(r.returncode==1 and not store(w) and not (run/'backup.json').exists(),'Perfil invalido debe rechazarse antes de modificar',r)
    print('PASS: validacion antes de crear transaccion')

    w=world('subset');catalog=json.loads((BASE/'Catalog.json').read_text());names=[catalog[0]['Name']]
    r,s,summary,run=execute(w,config=dict(DEFAULT,SelectedSettings=names))
    check(r.returncode==0 and len(store(w))==1,'Seleccion individual debe respetarse',r)
    print('PASS: seleccion individual aplicada por el pipeline')

    w=world('preflight');r,s,summary,run=execute(w,WB_TEST_FAIL_PREFLIGHT=1)
    check(r.returncode==1 and s['Phase']=='Failed' and not store(w),'Preflight debe impedir cambios',r)
    print('PASS: preflight bloquea cambios ante incompatibilidad simulada')

    # Interrupcion forzada anterior: restaurar antes de otra aplicacion.
    w=world('pending');r,s,summary,run=execute(w)
    jpath=run/'backup.json';j=json.loads(jpath.read_text());j['Status']='Pending';jpath.write_text(json.dumps(j))
    r,s,summary,newrun=execute(w)
    check(r.returncode==1 and not (newrun/'backup.json').exists() and len(store(w))==21,'Debe bloquear sesion nueva con transaccion incompleta',r)
    print('PASS: bloqueo de ejecucion sobre una sesion incompleta')
    w=world('hard-crash');r,s,summary,run=execute(w,WB_TEST_CRASH_WRITE=9)
    check(r.returncode==99 and len(store(w))==9 and summary is None,'Interrupcion abrupta debe dejar diario pendiente',r)
    r,s,summary,_=execute(w)
    check(r.returncode==1 and len(store(w))==9,'Debe bloquear otra aplicacion tras interrupcion',r)
    r,s,summary,_=execute(w,action='Restore')
    check(r.returncode==0 and not store(w),'Diario agrupado debe recuperar cambios incluso sin finally',r)
    print('PASS: interrupcion abrupta entre avances y recuperacion posterior')
    print('11 escenarios del pipeline verificados con adaptadores simulados.')
