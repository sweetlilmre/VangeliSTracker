"""Per-block verification for segment 14b9, because the prefix cannot measure it.

`verify.py`'s prefix stops at the first byte that disagrees, and while 14b9 is
half-written that byte is always the first PLACEHOLDER -- the routines after it
are correct but sit at the wrong offset, so the prefix says nothing about them.
Same reason `blocks.py` exists for 12ba; this is that instrument pointed at a
different segment.

For each named block it SEARCHES for the shift that aligns our copy with the
original -- never hardcodes one, because an edit anywhere earlier moves it --
and then compares positionally, counting a difference only where OUR byte is
non-zero. A zero on our side is a pending fixup, and note that an INTRA-UNIT
NEAR CALL is one of them: Turbo Pascal leaves a same-unit code reference as
zeros with a fixup record, so a call inside the unit is not evidence that its
target is in the right place.

    python v1.31b/block14b9.py
    python v1.31b/block14b9.py GetInstrument
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify  # noqa: E402

SEG = 0x14B9
SEGLEN = 2224
# How far either side of the nominal offset to search. It has to cover the
# ACCUMULATED shortfall of every placeholder above the block, which for a
# half-written unit is most of the segment -- 600 was too small and reported
# the last routine as five real differences when the true alignment was simply
# outside the window. A too-narrow window does not fail loudly; it reports a
# wrong shift with a plausible-looking difference count.
WINDOW = 2400

# name, start, end (exclusive), transcribed?  -- the address map from census.py
# plus the far-return list. A block is one routine, its first byte to the next
# routine's first byte.
BLOCKS = [
    ("Init",               0x0000, 0x002b, True),
    ("Done",               0x002b, 0x004f, True),
    ("Load",               0x004f, 0x0100, True),
    ("LoadFName",          0x0100, 0x02c2, True),
    ("GetInsidePath",      0x02c2, 0x02f5, True),
    ("SetInsidePath",      0x02f5, 0x0352, True),
    ("GetInstrument",      0x0352, 0x0404, True),
    ("GetTrack",           0x0404, 0x04b6, True),
    ("GetPattern",         0x04b6, 0x0575, True),
    ("GetPatternSeq",      0x0575, 0x059f, True),
    ("GetPatternSequence", 0x059f, 0x05d3, True),
    ("GetPatternTempo",    0x05d3, 0x0607, True),
    ("GetNote",            0x0607, 0x0687, True),
    ("Free",               0x0687, 0x072f, True),
    ("InitValues",         0x072f, 0x0897, True),
    ("Empty",              0x0897, 0x08b0, True),
]


def best_shift(want, tpu, nominal):
    """Search for the alignment, counting only non-zero differences as real."""
    # The window has to be clamped at BOTH ends. A block near the end of a
    # half-written unit can have its nominal offset past the .TPU entirely --
    # every routine above it is a short placeholder, so the whole tail is
    # displaced by hundreds of bytes -- and an unclamped range then searches
    # nothing and returns None. That is a property of measuring an unfinished
    # unit, not an error.
    hi = min(len(tpu) - len(want), nominal + WINDOW)
    lo = max(0, min(nominal - WINDOW, hi))
    best = None
    for pos in range(lo, hi + 1):
        real = zero = 0
        for k, b in enumerate(want):
            o = tpu[pos + k]
            if o == b:
                continue
            if o == 0:
                zero += 1
            else:
                real += 1
        cand = (real, zero, abs(pos - nominal), pos)
        if best is None or cand < best:
            best = cand
    return best          # (real, pending, drift, pos)


def main(argv):
    only = [a for a in argv[1:] if not a.startswith("-")]
    orig = verify.original(SEG, SEGLEN)
    tpu_path = verify.BUILD / "SONGUNIT.TPU"
    if not tpu_path.exists():
        print("no SONGUNIT.TPU -- run v1.31b/build.py first")
        return 1
    tpu = tpu_path.read_bytes()

    at, _ = verify.locate(orig, tpu)
    if at is None:
        print("NOT LOCATED -- the unit's first instruction differs")
        return 1

    print("segment 14b9, unit code located at .TPU offset 0x%04x" % at)
    print()
    print("block                 addr         len  shift  real  pending")
    print("-" * 62)
    done = clean = 0
    for name, lo, hi, transcribed in BLOCKS:
        if only and name.lower() not in [o.lower() for o in only]:
            continue
        want = orig[lo:hi]
        real, zero, _, pos = best_shift(want, tpu, at + lo)
        shift = pos - (at + lo)
        if not transcribed:
            note = "placeholder"
        elif real == 0:
            note = "OK"
            clean += 1
        else:
            note = "** %d real" % real
        if transcribed:
            done += 1
        print("%-20s %04x..%04x %5d  %+5d  %4d  %5d  %s"
              % (name, lo, hi, hi - lo, shift, real, zero, note))
    print("-" * 62)
    print("%d of %d transcribed blocks agree" % (clean, done))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
