"""Rebuild/check the self-contained launcher without executing application code."""
import argparse
import base64
import hashlib
import io
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'src' / 'v0.9'


def package_bytes():
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(SOURCE.rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts or path.suffix == '.pyc':
                continue
            info = zipfile.ZipInfo(path.relative_to(SOURCE).as_posix(), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes(), compresslevel=9)
    return stream.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    launcher = (ROOT / 'WinBoost.ps1').read_text(encoding='ascii')
    if args.check:
        match = re.search(r"\$package='([^']+)'", launcher)
        assert match, 'Missing embedded package'
        blob = base64.b64decode(match[1], validate=True)
        digest = hashlib.sha256(blob).hexdigest()
        assert f"if($actual -ne '{digest}')" in launcher, 'Package checksum mismatch'
        with zipfile.ZipFile(io.BytesIO(blob)) as archive:
            expected = {path.relative_to(SOURCE).as_posix(): path.read_bytes() for path in SOURCE.rglob('*') if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc'}
            assert len(archive.namelist()) == len(set(archive.namelist())), 'Duplicate package entries'
            assert set(archive.namelist()) == set(expected), 'Package file list differs from source'
            for name, content in expected.items():
                assert archive.read(name) == content, f'Stale packaged source: {name}'
        assert (ROOT / 'WinBoost.ps1').read_bytes() == (ROOT / 'install.ps1').read_bytes(), 'Launcher copies differ'
        print('PASS: embedded sources, checksum and launcher copies')
        return
    blob = package_bytes()
    digest = hashlib.sha256(blob).hexdigest()
    launcher, count = re.subn(r"\$package='[^']*'", lambda _: "$package='" + base64.b64encode(blob).decode('ascii') + "'", launcher)
    assert count == 1, 'Expected exactly one embedded package'
    launcher, count = re.subn(r"if\(\$actual -ne '[a-f0-9]{64}'\)", "if($actual -ne '" + digest + "')", launcher)
    assert count == 1, 'Expected exactly one package checksum'
    expected = launcher.encode('ascii')
    for name in ('WinBoost.ps1', 'install.ps1'):
        path = ROOT / name
        if args.check:
            assert path.read_bytes() == expected, f'{name} is stale; run python tools/build_package.py'
        else:
            path.write_bytes(expected)
    print(('PASS: package matches sources' if args.check else 'Built both launchers') + ' / SHA256 ' + digest)


if __name__ == '__main__':
    main()
