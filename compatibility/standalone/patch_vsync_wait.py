"""Staged ARM64 Unity frame-wait guard for the inspected JSAB 1.6.50 engine.

The display callback writes 0x17810fc from (vSyncCount > 0). The main loop
decrements a frame counter and waits unconditionally when that counter <= 0.
Preserve that wait when VSync is enabled; skip it when disabled.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

parser = argparse.ArgumentParser()
parser.add_argument('binary', type=Path)
path = parser.parse_args().binary.resolve()
assert str(path).startswith('/private/tmp/'), 'Only staging copies supported'
data = bytearray(path.read_bytes())
assert struct.unpack_from('<II', data) == (0xfeedfacf, 0x100000c)
site, cave, resume, wait = 0xd0dac0, 0x3da0, 0xd0dac4, 0xd0db54
assert struct.unpack_from('<I', data, site)[0] == 0x540004ad
assert data[cave:cave+32] == bytes(32)
assert 32 + struct.unpack_from('<I', data, 20)[0] <= cave
# Check the exact callback instructions that establish the pacing flag.
assert struct.unpack_from('<I', data, 0xd508c4)[0] == 0x3903f148
assert struct.unpack_from('<I', data, 0xd508bc)[0] == 0xb000518a
# All addresses here are __TEXT VM addresses equal to file offsets.
assert data[40:46] == b'__TEXT'
assert struct.unpack_from('<Q', data, 32+24)[0] == 0
assert struct.unpack_from('<Q', data, 32+40)[0] == 0

def branch(source, target):
    delta = target-source
    assert delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27)
    word = 0x14000000 | ((delta//4) & 0x3ffffff)
    n = word & 0x3ffffff
    if n & (1 << 25): n -= 1 << 26
    assert source+n*4 == target
    return word

page_delta = (0x1781000 >> 12) - ((cave+8) >> 12)
adrp = 0x90000010 | ((page_delta & 3) << 29) | (((page_delta >> 2) & 0x7ffff) << 5)
code = [0x5400004d, branch(cave+4, resume), adrp,
        0x39400000 | (0xfc << 10) | (16 << 5) | 16,
        0x35000050, branch(cave+20, resume), branch(cave+24, wait)]
# Decode the new control flow for all original branch/VSync combinations.
for counter_le in (False, True):
    for vsync in (False, True):
        pc = cave
        for _ in range(8):
            if pc in (resume, wait): break
            word = code[(pc-cave)//4]
            if word == 0x5400004d: pc += 8 if counter_le else 4
            elif word == 0x35000050: pc += 8 if vsync else 4
            elif word >> 26 == 5:
                n = word & 0x3ffffff
                if n & (1 << 25): n -= 1 << 26
                pc += n*4
            else: pc += 4
        assert pc == (wait if counter_le and vsync else resume)
before = hashlib.sha256(data).hexdigest()
struct.pack_into('<I', data, site, branch(site, cave))
struct.pack_into('<7I', data, cave, *code)
path.write_bytes(data)
path.with_suffix('.vsync-patch.json').write_text(json.dumps(dict(
    before=before, after=hashlib.sha256(data).hexdigest(), site=site, cave=cave,
    resume=resume, wait=wait, words=[hex(w) for w in code]), indent=2))
print('VSync wait guard verified for all four counter/VSync states')
