"""Compare our DEMOVT code segment against the original's, and classify the differences.

`verify.py` does not list a PROGRAM -- it compares a `.TPU`'s CODE against a segment, and
segment `1000` has no `.TPU`. So the program was the one segment with no measure at all
until the whole thing linked. This is that measure.

THREE CLASSES OF DIFFERENCE, AND ONLY THE THIRD IS A DEFECT:

  * a SEGMENT word that is 7 paragraphs low. Our `DEMOVT` is still longer than the
    original's, so every segment above it sits 7 paragraphs further on. Cosmetic until
    the size is right, and self-correcting when it is.
  * a DGROUP offset in the VARIABLE region -- above about $0c70. `dgroup.py` proves the
    initialised half is exact and says NOTHING about the uninitialised half, because a
    plain `var` is reserved space the linker never writes. Those addresses will move.
  * anything else: a real difference in the code.

The tool aligns forwards and backwards, which is what makes it useful while a size is
still wrong: the prefix says where the first divergence is and the suffix says how much
of the tail is already right, so the missing bytes are bracketed rather than hunted.
"""
import re
import struct
import sys
import pathlib
import refpath

ROOT = pathlib.Path(__file__).resolve().parents[1]
ORIG_LEN = 1616          # 1065 - 1000, in bytes: the segment's whole extent
VARBASE = 0x0c70         # the initialised/uninitialised DGROUP boundary


def images():
    o = refpath.read()
    oh = struct.unpack_from('<H', o, 8)[0] * 16
    u = (ROOT / 'build/VTMAIN.EXE').read_bytes()
    uh = struct.unpack_from('<H', u, 8)[0] * 16
    mp = (ROOT / 'build' / 'VTMAIN.MAP').read_text(encoding='ascii', errors='replace')
    m = re.search(r'^\s*([0-9A-F]+)H\s+([0-9A-F]+)H\s+([0-9A-F]+)H\s+DEMOVT\s+CODE',
                  mp, re.M)
    n = int(m.group(3), 16)
    return o[oh:oh + ORIG_LEN], u[uh:uh + n]


# The program's routines, from the header of VTMAIN.PAS. A block ENDS where the next
# one's literals begin, not at its prologue -- the trap this project records twice.
BLOCKS = [
    (0x0000, 'the four banner constants'),
    (0x00f8, 'ShowBanner'),
    (0x016b, 'TimerChain'),
    (0x0171, 'PollDriver'),
    (0x01a5, 'TimerHandler'),
    (0x01bd, 'HookTimer'),
    (0x020a, 'UnhookTimer'),
    (0x024c, 'Dispatch'),
    (0x02b5, 'PlayModule'),
    (0x0405, 'the usage text'),
    (0x04b3, 'the init chain'),
    (0x04e0, 'the body'),
]


def blocks(O, U, window=200):
    """Per routine: search for the shift that aligns it, then count REAL differences.

    A whole-segment prefix is useless while a size is wrong -- the first byte that
    disagrees is a jump displacement or an address, and everything past it reads as
    broken. Per block, with the shift SEARCHED rather than assumed, each routine says
    whether it is right on its own. Same instrument as `blocks.py` and the four
    `block*.py` scripts, pointed at the program.
    """
    print("%-28s %-13s %6s  %s" % ("routine", "orig", "shift", "real differences"))
    print("-" * 78)
    bad = 0
    for (a, name), (b, _) in zip(BLOCKS, BLOCKS[1:] + [(len(O), '')]):
        seg = O[a:b]
        best, bestn = None, None
        for s in range(-window, window + 1):
            if a + s < 0 or a + s + len(seg) > len(U):
                continue
            n = real_diffs(seg, U[a + s:a + s + len(seg)])
            if bestn is None or n < bestn:
                best, bestn = s, n
        note = 'exact' if bestn == 0 else '** %d **' % bestn
        if bestn:
            bad += 1
        print("%-28s %04x..%04x %+6d  %s" % (name, a, b - 1, best, note))
    print("-" * 78)
    print("%d of %d block(s) exact" % (len(BLOCKS) - bad, len(BLOCKS)))


def real_diffs(a, b):
    """Differences that are not one of the two known fixup classes."""
    n = 0
    i = 0
    while i < len(a):
        if a[i] == b[i]:
            i += 1
            continue
        if a[i] - b[i] == -7:            # a segment word, 7 paragraphs low
            i += 1
            continue
        if i and struct.unpack_from('<H', a, i - 1)[0] >= VARBASE              and struct.unpack_from('<H', b, i - 1)[0] >= VARBASE:
            i += 1                        # a var-region DGROUP offset
            continue
        n += 1
        i += 1
    return n


def main():
    O, U = images()
    print("DEMOVT   ours %d bytes, the segment is %d -- %+d"
          % (len(U), ORIG_LEN, len(U) - ORIG_LEN))

    pre = 0
    while pre < min(len(O), len(U)) and O[pre] == U[pre]:
        pre += 1
    suf = 0
    while suf < min(len(O), len(U)) - pre and O[-1 - suf] == U[-1 - suf]:
        suf += 1
    print("agrees for the first %d byte(s) and the last %d" % (pre, suf))
    print("so everything in question lies in orig %04x..%04x / ours %04x..%04x"
          % (pre, len(O) - suf - 1, pre, len(U) - suf - 1))
    print()

    # the first divergence, with enough context to read the instruction
    a = max(0, pre - 8)
    print("FIRST DIVERGENCE at %04x" % pre)
    for k in range(a, min(pre + 40, len(O)), 16):
        print("  %04x  orig %s" % (k, ' '.join('%02x' % x for x in O[k:k + 16])))
        print("  %04x  ours %s" % (k, ' '.join('%02x' % x for x in U[k:k + 16])))

    print()
    blocks(O, U)

    if '-a' not in sys.argv:
        print("\n(-a to classify every difference in the common prefix region)")
        return

    # classify differences while the two are still in step
    print("\nDIFFERENCES, classified -- only 'CODE' is a defect:")
    i, shown = 0, 0
    n = min(len(O), len(U))
    while i < n - 1 and shown < 60:
        if O[i] == U[i]:
            i += 1
            continue
        wo = struct.unpack_from('<H', O, i - 1)[0] if i else 0
        wu = struct.unpack_from('<H', U, i - 1)[0] if i else 0
        if O[i] - U[i] == -7:
            kind = 'segment word, 7 paragraphs low'
        elif wo >= VARBASE and wu >= VARBASE:
            kind = 'DGROUP var-region offset (%04x -> %04x)' % (wo, wu)
        else:
            kind = '** CODE **'
        print("  %04x  orig %02x  ours %02x   %s" % (i, O[i], U[i], kind))
        shown += 1
        i += 1


if __name__ == '__main__':
    main()
