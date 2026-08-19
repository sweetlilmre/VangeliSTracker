"""Compare EVERY linked code segment against the original's, and read the DGROUP
VARIABLE layout out of the differences.

WHY THIS EXISTS. `verify.py` compares a `.TPU`'s CODE against a segment, and inside a
`.TPU` every DGROUP reference is an unresolved fixup -- zeros -- which the tool
deliberately excuses. That is what made the whole variable half of DGROUP invisible:
`dgroup.py` measures the INITIALISED half by reading it straight out of the image, and a
plain `var` is reserved space the linker never writes, so nothing in the EXE records
where one went.

**BUT THE CODE RECORDS IT.** In the LINKED image every one of those fixups is resolved to
a real address, so a variable in the wrong place shows up as a wrong operand in every
instruction that touches it. This tool is that measurement: same code, resolved
addresses, both sides.

It only became possible once the segment ORDER and every segment SIZE matched, because
until then the segments did not line up to compare and every address was off anyway.

READING THE OUTPUT. A difference is one of:

  * a DGROUP VARIABLE address, above $0c70 on both sides -- the thing being measured.
    The pair `(orig, ours)` is printed, and a group of them sharing one delta is one
    unit's block in the wrong place.
  * a DGROUP CONSTANT address, below $0c70 -- should never happen now, `dgroup.py`
    reports that half exact. If one appears, something regressed.
  * anything else: a real code difference.

    python v1.31b/linkcmp.py            the summary
    python v1.31b/linkcmp.py -v         every differing operand
    python v1.31b/linkcmp.py VTCFG      one unit
"""
import re
import struct
import sys
import pathlib
from collections import Counter
import refpath

ROOT = pathlib.Path(__file__).resolve().parents[1]
VARBASE = 0x0c70          # the initialised/uninitialised DGROUP boundary
DATALEN = 0x4690          # the ORIGINAL's DGROUP size: SS 0x1113 - DS 0x0caa
MAXDELTA = 8192           # a plausible misplacement; beyond this it is not an address

# unit name in our map -> (segment, extent in bytes). The extent is the NEXT segment's
# address minus this one, so it includes whatever padding the segment carries.
ORIG = [
    (0x1000, 'DEMOVT'), (0x1065, 'VTSILENC'), (0x1084, 'DEVGUS'), (0x109c, 'VTCMD'),
    (0x116a, 'FILEUTIL'), (0x116e, 'CMDLINE'), (0x11bb, 'VTCFG'), (0x12ba, 'PLAYMOD'),
    (0x142f, 'MODCOMMANDS'), (0x14b7, 'VTCTRL'), (0x14b9, 'SONGUNIT'), (0x1544, 'FILTERS'),
    (0x154d, 'MODLOADER'), (0x1642, 'ASCIIZ'), (0x164b, 'UNKLOADER'), (0x1650, 'VTNOTES'),
    (0x165a, 'SONGELEMENTS'), (0x1723, 'GUS'), (0x17cf, 'HEAPS'), (0x1880, 'VTDOSMEM'),
    (0x188f, 'VTDOSRSZ'), (0x1891, 'OBJECTS'), (0x1931, 'VTSHELL'), (0x193a, 'DEVSB'),
    (0x19a0, 'SOUNDBLASTER'), (0x1a17, 'SOUNDDEVICES'), (0x1b24, 'HARDWARE'),
    (0x1b54, 'VTRESID'), (0x1b6f, 'DOS'), (0x1ba1, 'SYSTEM'), (0x1caa, None),
]
RTL = {'OBJECTS', 'DOS', 'SYSTEM'}


def load():
    o = refpath.read()
    oh = struct.unpack_from('<H', o, 8)[0] * 16
    u = (ROOT / 'build/VTMAIN.EXE').read_bytes()
    uh = struct.unpack_from('<H', u, 8)[0] * 16
    ours = {}
    for line in (ROOT / 'build' / 'VTMAIN.MAP').read_text(encoding='ascii', errors='replace').splitlines():
        m = re.match(r'\s*([0-9A-F]+)H\s+[0-9A-F]+H\s+([0-9A-F]+)H\s+(\S+)\s+CODE\s*$', line)
        if m:
            ours[m.group(3)] = (uh + int(m.group(1), 16), int(m.group(2), 16))
    return o, oh, u, ours


def operand(A, B, i):
    """The 16-bit operand containing byte i, if both sides hold a DGROUP-looking word."""
    for s in (i - 1, i):
        if s < 0 or s + 2 > len(A) or s + 2 > len(B):
            continue
        a, b = struct.unpack_from('<H', A, s)[0], struct.unpack_from('<H', B, s)[0]
        if (VARBASE <= a < DATALEN and VARBASE <= b < DATALEN
                and abs(a - b) <= MAXDELTA):
            return s, a, b
    return None


def main():
    only = [a.upper() for a in sys.argv[1:] if not a.startswith('-')]
    verbose = '-v' in sys.argv
    o, oh, u, ours = load()

    print("%-14s %6s  %s" % ("unit", "diffs", "verdict"))
    print("-" * 76)
    allpairs = Counter()
    clean = 0
    for (seg, name), (nxt, _) in zip(ORIG, ORIG[1:]):
        if name is None or name in RTL or name not in ours:
            continue
        if only and name not in only:
            continue
        n = (nxt - seg) * 16
        A = o[oh + (seg - 0x1000) * 16: oh + (seg - 0x1000) * 16 + n]
        start, length = ours[name]
        B = u[start:start + length]
        m = min(len(A), len(B))
        diffs = [i for i in range(m) if A[i] != B[i]]

        pairs, code, const = [], 0, 0
        seen = set()
        for i in diffs:
            if i in seen:
                continue
            r = operand(A, B, i)
            if r:
                s, a, b = r
                seen.update((s, s + 1))
                pairs.append((a, b))
            else:
                r2 = None
                for s2 in (i - 1, i):
                    if s2 < 0 or s2 + 2 > m:
                        continue
                    a, b = struct.unpack_from('<H', A, s2)[0], struct.unpack_from('<H', B, s2)[0]
                    if 0 < a < VARBASE and 0 < b < VARBASE and a != b:
                        r2 = (a, b)
                if r2:
                    const += 1
                else:
                    code += 1
        for p in pairs:
            allpairs[p[1] - p[0]] += 1
        if not diffs:
            clean += 1
            print("%-14s %6d  exact" % (name, 0))
            continue
        c = Counter(b - a for a, b in pairs)
        dom = ('  delta %+d x%d' % c.most_common(1)[0]) if c else ''
        bits = ['%d var-address operand(s)%s' % (len(pairs), dom)]
        if const:
            bits.append('%d CONSTANT-region (REGRESSION)' % const)
        if code:
            bits.append('** %d code **' % code)
        print("%-14s %6d  %s" % (name, len(diffs), ', '.join(bits)))
        if verbose:
            for d, k in c.most_common():
                addrs = sorted(a for a, b in pairs if b - a == d)
                print("        %+7d  x%-3d  orig %s" % (d, k, ' '.join(
                    '$%04x' % a for a in addrs[:12]) + (' ...' if len(addrs) > 12 else '')))

    print("-" * 76)
    print("%d unit(s) byte-identical in the linked image" % clean)
    if allpairs:
        print()
        print("THE DELTAS, most operands first -- each is a run of the VARIABLE region")
        print("in the wrong place, and the count is how many instructions say so:")
        for d, c in allpairs.most_common(20):
            print("   %+7d   %3d operand(s)" % (d, c))


if __name__ == '__main__':
    main()
