#!/usr/bin/env python3
"""Check Git's publication set; do not read ignored private build inputs."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
result = subprocess.run(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=root, check=True, capture_output=True)
paths = sorted(set(result.stdout.decode().split('\0')) - {''})
allowed = {'.md', '.py', '.sh', '.m', '.h', '.c', '.plist'}
magic = (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\x7fELF', b'PK\x03\x04', b'\x1f\x8b', b'MZ')
errors = []
for name in paths:
    p = root / name
    if p.is_symlink():
        errors.append(f'{name}: symlink not allowed'); continue
    if p.suffix not in allowed and p.name not in ('LICENSE', '.gitignore'):
        errors.append(f'{name}: unexpected file type')
    if p.stat().st_size > 2_000_000:
        errors.append(f'{name}: unexpectedly large source file')
    d = p.read_bytes()
    if d.startswith(magic) or b'\0' in d:
        errors.append(f'{name}: binary/archive data')
    text = d.decode('utf-8', 'replace')
    patterns = [r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', r'gh[pousr]_[A-Za-z0-9]{20,}', r'github_pat_[A-Za-z0-9_]{20,}', r'\b00008\d{3}-[A-Fa-f0-9]{16}\b', r'/Users/' + 'mac' + 'book', r'com\.' + 'huzaifah' + 'shahid']
    if any(re.search(pattern, text) for pattern in patterns):
        errors.append(f'{name}: private identifier/path or credential pattern')
if errors:
    print('\n'.join(errors), file=sys.stderr); sys.exit(1)
print(f'Checked {len(paths)} publication files: source/documentation only; no matching private identifiers or binary inputs.')
