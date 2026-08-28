#!/usr/bin/env python3
"""How much of each 1.31 segment does the 1.39b RELEASE's compiled code reproduce?

    python v1.31b/relbuild.py          first -- compiles the release into build/vt
    python v1.31b/relmatch.py          then this

BOTH RUN. This was unrunnable for a while and this docstring said so at length;
`relbuild.py` beside this file closed that on 28 Aug 2026 and the two were measured
together the same day -- 3 programs, 21,266 lines, 49 `.TPU`, and the corroboration
below. **The 1.31 build DELETES build/vt** -- the kit's `build.py` wipes its staging
directory and that wipe takes subdirectories too -- so run `relbuild.py` AFTER it.

WHAT THE FIRST RUN SAID, and it is worth recording because it is INDEPENDENT
CORROBORATION of pairings this project had already made by hand. Every segment's
top-ranked release unit is the one this tree had independently named it:
`12ba`/PLAYMOD, `1a17`/SOUNDDEV, `11bb`/VTCFG, `165a`/SONGELEM, `14b9`/SONGUNIT,
`142f`/MODCOMMANDS, `116e`/CMDLINE, `1b24`/HARDWARE at 83.7%, `1642`/ASCIIZ at
100.0%. Nothing was overturned.

Four segments rank against a release unit under a DIFFERENT NAME, and those are
version renames rather than disagreements: `1b54` -> VTSPECIA (we call it VTRESID),
`1650` -> SONGUTIL (VTNOTES), `1880` -> UMBUNIT (VTDOSMEM), `1065` -> DEVGUS at only
5.8% (VTSILENC). `1000` ranks against VTSTRCON at 13.9%, which means nothing:
`1000` is the PROGRAM and the release's program is VT.PAS, a different program.
`14b7` and `188f` score nothing above 5% -- both are 32 bytes, too small to window.

And the caution below held exactly: `154d` scores 55.4% against MODLOADE and its
bodies still do not transfer.

WHY THIS EXISTS. Every pairing in this project was found by hand: a role match, a
shared string, a record offset. Then `11bb` went in essentially VERBATIM from
`VTCFG.PAS` -- twenty routines, three measured adjustments -- and `17cf` started the
same way. If a release source can be that close, the release's COMPILED CODE can be
diffed against the original directly, and that measurement ranks every remaining
segment at once instead of one discovery at a time.

The release tree builds (`vtbuild.py`, 21,266 lines, no errors) and leaves 49 `.TPU`
files in `build/vt`. This compares each of them against each 1.31 segment.

WHAT IT MEASURES, and the second number is the one to read:

  prefix   `verify.py`'s own measure -- locate the segment's opening in the .TPU and
           report how far it agrees. Strict, and it only works when the unit's FIRST
           routine is the segment's first routine. A dash means the openings differ,
           which is common and is NOT evidence of a bad pairing.
  windows  the fraction of the segment covered by 16-byte windows that appear
           somewhere in the .TPU. Robust to routines being reordered, added or
           removed between versions, which is what actually differs.

BOTH USE verify.py's ZERO RULE: a .TPU byte of 0 matches anything, because that is
how Turbo Pascal leaves an unresolved reference. Without it every window straddling
a fixup would fail and the numbers would be meaningless -- most windows contain at
least one address.

READ IT AS A RANKING, NOT A VERDICT. A high score means "start from this source and
measure"; it does not mean the bodies are identical, and it cannot distinguish "1.39b
changed this routine" from "this is a different unit that happens to share idioms".
`154d` scores respectably against `MODLOADE` and its bodies still do not transfer,
because 1.31 has free functions where 1.39b has methods -- same shape, different code.
"""

import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
# verify.py is archived (#50). Its three functions this used map onto the kit:
# original() is a segment read, locate() is align.anchor_first and prefix() is
# align.walk under the pending rule -- the same substitution #33 measured row
# for row against every unit.
#
# EXERCISED 28 Aug 2026, at last. `relbuild.py` builds the release now, this script
# ran end to end against its 49 .TPU files, and it reproduced by measurement every
# pairing the project had made by hand. So the repoint onto the kit's align module
# -- original() is a segment read, locate() is align.anchor_first and prefix() is
# align.walk under the pending rule -- is VERIFIED, not merely argued for.
#
# It was unverified from #50 until then, and this comment used to blame the release
# tree being "held out of source control". That was wrong: the release SOURCES are
# tracked under `v1.39b/`. What was missing was the BUILDER.
sys.path.insert(0, str(HERE.parent / "kit" / "tools"))
from substrate import align                    # noqa: E402
import struct                                  # noqa: E402


class V:
    """The three calls this file made into verify.py, on the kit's engine."""

    import refpath as _rp
    IMAGE = _rp.ORIG                           # as verify.py had it

    @staticmethod
    def original(seg, n):
        d = V.IMAGE.read_bytes()
        base = struct.unpack_from("<H", d, 8)[0] * 16
        return d[base + seg * 16 - 0x10000:][:n]

    @staticmethod
    def locate(orig, tpu):
        at, got = align.anchor_first(orig, tpu, align.pending)
        return (at, got) if at >= 0 else (at, None)

    @staticmethod
    def prefix(orig, tpu, at, mask=frozenset()):
        pre, _, _ = align.walk(orig, tpu[at:at + len(orig)],
                               align.pending, None, False)
        return pre

ROOT = HERE.parent
VT = ROOT / "build" / "vt"

WIN = 8             # window size for the coverage measure
STEP = 4            # and how far to slide it


def windows_covered(orig, tpu):
    """Fraction of the segment covered by WIN-byte runs that appear in the .TPU.

    EXACT MATCHES ONLY, and that is a deliberate retreat. The first version allowed a
    zero byte in the .TPU to match anything, the way `verify.py` does for a pending
    fixup -- and every segment scored 100% against every unit, because a .TPU is full
    of long runs of zeros and a run of zeros matches anything. That is the identical
    mistake `verify.py`'s own header records twice, made again within an hour of
    reading the warning. **A zero rule needs a cap on the zeros every time it is
    used.**

    Capping the wildcards fixed the scores and made it far too slow -- the search
    stops being a `bytes.find` and becomes a Python loop over every position. So the
    wildcards are gone instead and the window is short: eight bytes usually fits
    between two fixups, `find` runs at C speed, and what is lost is only ABSOLUTE
    coverage. Every pair is under-reported the same way, so the RANKING -- which is
    all this tool is for -- survives.
    """
    hits = total = 0
    for i in range(0, len(orig) - WIN, STEP):
        total += 1
        if tpu.find(orig[i:i + WIN]) >= 0:
            hits += 1
    return hits, total


def main():
    # every segment with code, from the map
    import re
    txt = (ROOT / "v1.31b/docs/00-map.md").read_text(encoding="utf-8",
                                                     errors="replace")
    seg = {int(m.group(1), 16): int(m.group(2))
           for m in re.finditer(r"^\| `([0-9a-f]{4})` \| (\d+) \|", txt, re.M)}
    for dead in (0x1891, 0x1b6f, 0x1ba1, 0x1caa):
        seg.pop(dead, None)

    tpus = sorted(VT.glob("*.TPU")) + sorted((VT / "LIB").glob("*.TPU"))
    if not tpus:
        print("no .TPU in build/vt -- run python v1.31b/relbuild.py first.")
        print("(the kit's build.py wipes build/, subdirectories included, so a")
        print(" 1.31 build since the last relbuild.py is enough to explain this)")
        return 1
    blobs = {f: f.read_bytes() for f in tpus}

    only = [a.lower() for a in sys.argv[1:]]
    print("%-6s %-6s  %-14s %-9s %s" % ("seg", "bytes", "release unit",
                                        "prefix", "windows"))
    print("-" * 62)
    for sg in sorted(seg, key=lambda k: -seg[k]):
        if only and ("%04x" % sg) not in only:
            continue
        orig = V.original(sg, seg[sg])
        scored = []
        for f, blob in blobs.items():
            hits, total = windows_covered(orig, blob)
            if not total:
                continue
            pct = 100.0 * hits / total
            if pct < 5:
                continue
            at, got = V.locate(orig, blob)
            pre = V.prefix(orig, blob, at) if got is not None else None
            scored.append((pct, pre or 0, f.name, pre))
        scored.sort(reverse=True)
        if not scored:
            print("%-6s %-6d  -- nothing scores above 5%%" % ("%04x" % sg, seg[sg]))
            continue
        for i, (pct, _, name, pre) in enumerate(scored[:3]):
            print("%-6s %-6s  %-14s %-9s %5.1f%%"
                  % ("%04x" % sg if i == 0 else "", seg[sg] if i == 0 else "",
                     name, ("+%04x" % pre) if pre else "-", pct))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
