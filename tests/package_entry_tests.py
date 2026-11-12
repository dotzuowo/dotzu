"""Package dispatch only. Mock every child process; never run the embedded worker."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PS = os.environ.get('WINBOOST_TEST_PWSH') or shutil.which('pwsh')
assert PS, 'PowerShell required'
source = (ROOT / 'WinBoost.ps1').read_text(encoding='ascii')
mock = '''
function Start-Process {
 param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru)
 $cmd=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
 if($env:WB_RESTORE_ID -and -not $cmd.Contains('-RestoreSessionId '+$env:WB_RESTORE_ID)){throw 'Restore ID missing from package dispatch'}
 return [pscustomobject]@{ExitCode=[int]$env:WB_CHILD_EXIT}
}
'''
source = source.replace("$ErrorActionPreference='Stop'", "$ErrorActionPreference='Stop'\n" + mock, 1)
with tempfile.TemporaryDirectory(prefix='wb-package-entry-') as folder:
    root = Path(folder)
    launcher = root / 'WinBoost.ps1'
    launcher.write_text(source, encoding='ascii')
    for code in (0, 1, 2, 3):
        for mode in ('file', 'expression'):
            data = root / f'{mode}-{code}'
            data.mkdir()
            env = dict(os.environ, LOCALAPPDATA=str(data), OS='Windows_NT', SystemRoot=str(root), WB_CHILD_EXIT=str(code))
            if mode == 'file':
                restore_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                env['WB_RESTORE_ID'] = restore_id
                args = ['-File', str(launcher), '-Mode', 'ActionsRestore', '-RestoreSessionId', restore_id]
            else:
                # A real file caller detects regressions where iex exits its hosting script.
                harness = root / 'harness.ps1'
                literal = str(launcher).replace("'", "''")
                harness.write_text(f"$text=Get-Content -LiteralPath '{literal}' -Raw\n$text | Invoke-Expression\nif($LASTEXITCODE -ne {code}){{throw 'Lost exit code'}}\nWrite-Output 'HOST_CONTINUES'\n", encoding='utf-8')
                args = ['-File', str(harness)]
            result = subprocess.run([PS, '-NoProfile'] + args, env=env, capture_output=True, text=True, timeout=30)
            assert result.returncode == (code if mode == 'file' else 0), (mode, code, result.stdout, result.stderr)
            if mode == 'expression':
                assert 'HOST_CONTINUES' in result.stdout, (code, result.stdout, result.stderr)
print('PASS: package preserves 0/1/2/3 in file mode and LASTEXITCODE without closing expression host')
