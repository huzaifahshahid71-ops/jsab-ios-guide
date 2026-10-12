"""Experimental system-heap C++ operators for a temporary ARM64 Unity copy.

Changes eight matched function entries, not DRM or game logic. The throwing new
operators become malloc-style on OOM; this is a compatibility test, not a fully
conforming replacement C++ runtime. Never run against the original game.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

p = argparse.ArgumentParser()
p.add_argument('binary', type=Path)
args = p.parse_args()
path = args.binary.resolve()
if not str(path).startswith('/private/tmp/'):
    p.error('Only temporary staging copies are supported')
data = bytearray(path.read_bytes())
magic, cpu, subtype, kind, commands = struct.unpack_from('<5I', data)
assert magic == 0xfeedfacf and cpu == 0x100000c, 'Expected thin ARM64 Mach-O'
segments, stub_ranges = [], []
position = 32
for _ in range(commands):
    command, length = struct.unpack_from('<II', data, position)
    assert length >= 8 and position + length <= len(data)
    if command == 0x19:
        vm, size, offset, file_size = struct.unpack_from('<4Q', data, position + 24)
        segments.append((vm, size, offset, file_size))
        count = struct.unpack_from('<I', data, position + 64)[0]
        for i in range(count):
            section = position + 72 + 80 * i
            address, section_size = struct.unpack_from('<QQ', data, section + 32)
            flags = struct.unpack_from('<I', data, section + 64)[0]
            if flags & 0xff == 8:
                stub_ranges.append((address, address + section_size))
    position += length

def file_offset(address):
    for vm, size, offset, file_size in segments:
        if vm <= address < vm + file_size:
            return offset + address - vm
    raise ValueError('Address outside file-backed segments')

exports = subprocess.check_output(['xcrun', 'dyld_info', '-exports', str(path)], text=True)
exports = {name: int(address, 16) for address, name in
           re.findall(r'(0x[0-9a-fA-F]+)\s+(__Z\S+)', exports)}
indirect = subprocess.check_output(['xcrun', 'otool', '-Iv', str(path)], text=True)
stubs = {}
for address, name in re.findall(r'(0x[0-9a-fA-F]+)\s+\d+\s+(_malloc|_free)\s*$', indirect, re.M):
    address = int(address, 16)
    if any(start <= address < end for start, end in stub_ranges):
        assert name not in stubs, 'Ambiguous allocator stub'
        stubs[name] = address
assert set(stubs) == {'_malloc', '_free'}
names = ('__Znwm', '__Znam', '__ZnwmRKSt9nothrow_t', '__ZnamRKSt9nothrow_t',
         '__ZdlPv', '__ZdaPv', '__ZdlPvRKSt9nothrow_t', '__ZdaPvRKSt9nothrow_t')
changes = []
before = hashlib.sha256(data).hexdigest()
for name in names:
    address = exports[name]
    offset = file_offset(address)
    # Guard the exact engine entry sequence observed in this build.
    assert data[offset:offset+16].hex() == 'f44fbea9fd7b01a9fd430091f30300aa', name
    target = stubs['_malloc' if name.startswith('__Zn') else '_free']
    delta = target - address
    assert delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27)
    instruction = 0x14000000 | ((delta // 4) & 0x3ffffff)
    immediate = instruction & 0x3ffffff
    if immediate & (1 << 25): immediate -= 1 << 26
    assert address + immediate * 4 == target
    changes.append(dict(symbol=name, address=address, target=target,
                        original=data[offset:offset+4].hex(), replacement=hex(instruction)))
    struct.pack_into('<I', data, offset, instruction)
assert len(changes) == 8
path.write_bytes(data)
report = dict(before=before, after=hashlib.sha256(data).hexdigest(), changes=changes)
path.with_suffix('.allocator-patch.json').write_text(json.dumps(report, indent=2))
print('Verified and patched eight paired C++ allocator entries in staging copy')
