"""census.py -- the four cheap measurements, in one command.

    python v1.31b/census.py 165a

WHY THIS EXISTS. Four scans settled almost everything structural in `17cf` and `116e`,
and all four are greps rather than disassembly:

  FAR RETURNS      a routine census, and the stack-cleanup count is a SIGNATURE. `RETF 4`
                   is Self alone, `RETF 8` is Self plus one pointer-sized parameter,
                   `RETF 12` is Self plus two. Reading them is far cheaper than finding
                   the entry points and much harder to get wrong.
  PRINTABLE STRINGS  their ABSENCE is evidence. `17cf`'s missing `WriteLn` was found this
                   way: no strings in 2,832 bytes means no text was ever written.
  FAR CALLS OUT    which other segments this one leans on, with a count each. A routine
                   the release calls three times and this segment calls once is a
                   routine 1.31 does not have.
  VIRTUAL SITES    `CALLF [DI+nn]` and `[BX+nn]`, in address order, which is how the VMT
                   layout gets read off the code. `116e`'s extra virtual method was found
                   because four sites landed on +$14 where the release's declaration order
                   puts +$10.

**A MISSING CALL PROVES A MISSING ROUTINE FAR MORE CHEAPLY THAN SEARCHING FOR THE
ROUTINE.** That is the whole thesis of this file.
"""

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "work" / "unpack" / "NEUROSIS_008_unpacked.exe"

# Segment extents, from Ghidra's own block list. Keep in step with verify.py's UNITS.
SEGS = {
    0x1000: 1621, 0x1065: 489, 0x1084: 376, 0x109c: 3296, 0x116a: 59,
    0x116e: 1232, 0x11bb: 4080, 0x12ba: 5968, 0x142f: 2176, 0x14b7: 25,
    0x14b9: 2224, 0x1544: 144, 0x154d: 3920, 0x1642: 144, 0x164b: 77,
    0x1650: 149, 0x165a: 3216, 0x1723: 2741, 0x17cf: 2832, 0x1880: 237,
    0x188f: 29, 0x1931: 138, 0x193a: 1617, 0x19a0: 1905, 0x1a17: 4303,
    0x1b24: 765, 0x1b54: 432,
}


def load(seg, size=None):
    blob = EXE.read_bytes()
    base = struct.unpack_from("<H", blob, 8)[0] * 16
    if size is None:
        size = SEGS[seg]
    off = base + (seg - 0x1000) * 16
    return blob[off:off + size]


def returns(d):
    """Far returns, in address order. `c9`/`5d` is LEAVE or POP BP first."""
    out = []
    for m in re.finditer(rb"[\xc9\x5d](\xca|\xcb)", d):
        i = m.start()
        if d[i + 1] == 0xCA:
            out.append((i, struct.unpack_from("<H", d, i + 2)[0]))
        else:
            out.append((i, None))
    return out


def strings(d, minlen=4):
    out = []
    for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, d):
        out.append((m.start(), m.group().decode("latin-1")))
    return out


def farcalls(d):
    """`9a` lo hi seg seg -- direct far calls, grouped by target with a count.

    The target segment is a FIXUP, so in the unpacked image it is already relocated and
    absolute; report it as-is and compare against the map."""
    hits = {}
    for m in re.finditer(rb"\x9a", d):
        i = m.start()
        if i + 5 > len(d):
            continue
        ofs, tseg = struct.unpack_from("<HH", d, i + 1)
        hits.setdefault((tseg, ofs), []).append(i)
    return hits


# 16-BIT MODRM rm VALUES ARE NOT THE REGISTER NUMBERS, and getting that wrong made this
# scan report zero sites in a segment with eight of them. `FF /3` is CALLF m16:16, so the
# reg field is 011 and the byte is 0x58 + rm: 100 = [SI], 101 = [DI], 110 = [BP],
# 111 = [BX]. **`ff 5f` is [BX], not [DI]** -- the natural guess from the 32-bit encoding,
# and wrong. `26 8b 3d ff 5d 14` is what a virtual call actually looks like.
RM16 = {0x04: "SI", 0x05: "DI", 0x06: "BP", 0x07: "BX"}


def virtuals(d):
    """Virtual method calls. Turbo Pascal emits `26 8b 3d` -- `MOV DI,ES:[DI]`, fetching
    the VMT pointer from the object's offset 0 -- then `CALLF [DI+slot]`, with the VMT in
    DGROUP so the call itself needs no segment prefix. Only the CALLF is matched here, and
    **the displacement IS the VMT slot.**"""
    out = []
    for m in re.finditer(rb"\xff([\x5c-\x5f])", d):
        i = m.start()
        out.append((i, RM16[d[i + 1] & 7], d[i + 2]))
    for m in re.finditer(rb"\xff([\x9c-\x9f])", d):
        i = m.start()
        out.append((i, RM16[d[i + 1] & 7], struct.unpack_from("<H", d, i + 2)[0]))
    return sorted(out)


def main():
    seg = int(sys.argv[1], 16)
    size = SEGS[seg]
    d = load(seg, size)
    print("== %04x  %d bytes" % (seg, size))

    r = returns(d)
    print("\n-- FAR RETURNS (%d)  -- the routine census; the count is a signature" % len(r))
    for i, n in r:
        print("     %04x  RETF %s" % (i, "" if n is None else n))
    from collections import Counter
    print("     counts: %s" % dict(Counter(n for _, n in r)))

    s = strings(d)
    print("\n-- PRINTABLE STRINGS (%d)  -- an absence is evidence" % len(s))
    for i, t in s[:40]:
        print("     %04x  %r" % (i, t))

    f = farcalls(d)
    print("\n-- FAR CALLS OUT (%d distinct targets)" % len(f))
    for (tseg, ofs), sites in sorted(f.items(), key=lambda kv: -len(kv[1])):
        print("     %04x:%04x  x%-3d  from %s" % (
            tseg, ofs, len(sites), " ".join("%04x" % a for a in sites[:8])))

    v = virtuals(d)
    print("\n-- VIRTUAL CALL SITES (%d), in address order -- this is the VMT layout" % len(v))
    for i, reg, n in v:
        print("     %04x  CALLF [%s+%02x]" % (i, reg, n))
    slots = Counter("[%s+%02x]" % (reg, n) for _, reg, n in v)
    print("     slots: %s" % dict(sorted(slots.items())))


if __name__ == "__main__":
    main()
