#!/usr/bin/env python3
"""How much of each 1.31 segment does the 1.39b RELEASE's compiled code reproduce?

    python tools/dosbox/vtbuild.py     first -- compiles the release into build/vt
    python v1.31b/relmatch.py          then this

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
import verify as V                             # noqa: E402

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
        print("no .TPU in build/vt -- run tools/dosbox/vtbuild.py first")
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
