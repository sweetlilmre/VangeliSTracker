"""Score every release source against every DemoVT segment by shared string literals.

Pascal puts an untyped string constant in the CODE segment (the `PUSH CS` rule), so a
segment carries its unit's literals verbatim. That makes literals a cheap, one-way
test: a high score is strong evidence of a pairing; a LOW score is no evidence at all,
because plenty of units have no literals to share.
"""
import re
import struct
import pathlib

import refpath

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
REL = ROOT / 'v1.39b'

blob = refpath.read()
base = struct.unpack_from('<H', blob, 8)[0] * 16


def seg_bytes(seg, size):
    off = base + (seg - 0x1000) * 16
    return blob[off:off + size]


# segment -> size, from the map
txt = (HERE / 'docs/00-map.md').read_text(encoding='utf-8', errors='replace')
seg = {int(m.group(1), 16): int(m.group(2))
       for m in re.finditer(r'^\| `([0-9a-f]{4})` \| (\d+) \|', txt, re.M)}

# the ten not started, plus 11bb which we have just settled, as a positive control
TARGETS = [0x11bb, 0x154d, 0x109c, 0x165a, 0x17cf, 0x14b9,
           0x19a0, 0x1000, 0x193a, 0x116e]

srcs = sorted(REL.glob('*.PAS')) + sorted((REL / 'LIB').glob('*.PAS'))

# distinctive literals per source: quoted, >=4 chars, letters present
lits = {}
for f in srcs:
    t = f.read_text(encoding='latin-1', errors='replace')
    s = set()
    for m in re.finditer(r"'([^'\n]{4,40})'", t):
        v = m.group(1)
        if re.search(r'[A-Za-z]{3}', v):
            s.add(v)
    if s:
        lits[f] = s

# a literal shared by many sources says little; weight the rare ones
from collections import Counter
freq = Counter()
for s in lits.values():
    freq.update(s)

print("%-6s %-6s  %s" % ("seg", "bytes", "best-scoring release sources (unique hits / total literals)"))
print("-" * 100)
for sg in TARGETS:
    data = seg_bytes(sg, seg[sg])
    scores = []
    for f, s in lits.items():
        hits = [v for v in s if v.encode('latin-1', 'replace') in data]
        uniq = [v for v in hits if freq[v] == 1]
        if hits:
            scores.append((len(uniq), len(hits), len(s), f))
    scores.sort(reverse=True)
    label = "%-6s %-6d" % ("%04x" % sg, seg[sg])
    if not scores:
        print(label + "  -- no literal from any release source appears here")
        continue
    for i, (uniq, hits, tot, f) in enumerate(scores[:3]):
        name = f.parent.name + '/' + f.name if f.parent.name == 'LIB' else f.name
        print("%s  %-22s %3d uniq / %3d hit of %3d" % (label if i == 0 else " " * 13,
                                                       name, uniq, hits, tot))
    print()
