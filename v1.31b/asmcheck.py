#!/usr/bin/env python3
"""Measure a {$L} object module STRICTLY, against the .OBJ's own relocations.

    python v1.31b/asmcheck.py            check every configured module
    python v1.31b/asmcheck.py PLAYMOD    just one

WHY THIS EXISTS, AND WHY blocks.py AND verify.py ARE BOTH TOO KIND HERE.

Both of those excuse a byte when OUR side is ZERO, which is exactly right for a
.TPU -- Turbo Pascal emits an unresolved reference as zeros and records a fixup
beside it. An ASSEMBLED module does not work that way. TASM writes the value it
knows, which is the offset RELATIVE TO THE MODULE, and leaves the linker to add
the module's base. So every code self-reference in an object module differs from
the original by exactly the base, in bytes that are NOT zero, and the zero rule
either flags them as real differences or -- worse -- excuses the ones whose high
byte happens to be zero while flagging the rest.

`12ba`'s module shows both halves of that: of its 18 relocation fields, the nine
in DumpRaw have a zero high byte and so read as ONE difference each, and the nine
in EmptyRaw have a high byte of 01 and read as TWO. Twenty-seven "differences"
for thirty-six relocation bytes, and not one of them is a defect.

This script asks the only question that settles it:

  1. does every CODE self-reference hold exactly OURS + THE MODULE BASE?
  2. does every differing byte in the module lie INSIDE a relocation field?

Both yes means the module is byte-exact as far as the bytes can say. What is left
over is the DGROUP references, which no .TPU comparison can settle either way --
they are risk 1, and this tool prints the symbol offsets they imply so that they
can at least be read off and checked by hand. That is STRICTER than the heuristic, not
looser -- it will not excuse a wrong byte just because it is zero, and it will
not accept a relocation whose addend is not the one the linker will resolve.

The docs record that `SOUNDDEV.ASM`'s first honest measurement needed `omf.py`
for the same reason; this is that measurement made repeatable.
"""

import re
import subprocess
import sys
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import verify as V                             # noqa: E402

ROOT = HERE.parent

# unit -> (segment, segment size, where the module lands, first byte past the
#          module). The tail beyond `end` is linker padding and is checked to be
#          zero rather than compared.
MODULES = {
    "PLAYMOD":  (0x12BA, 5968, 0x148F, 0x1746),
    "SOUNDDEV": (0x1A17, 4303, 0x0746, 0x10C4),
}


def fixups(obj):
    """{module offset: length} from the .OBJ's own FIXUPP records."""
    out = subprocess.run([sys.executable, str(HERE / "omf.py"), str(obj), "-v"],
                         capture_output=True, text=True,
                       encoding="utf-8", cwd=str(ROOT)).stdout
    return {int(m.group(1), 16): int(m.group(2))
            for m in re.finditer(r"^\s*\+([0-9a-f]{4})\s+(\d+) byte", out, re.M)}


def check(unit, seg, size, base, end):
    orig = V.original(seg, size)
    tpu = (V.BUILD / (unit + ".TPU")).read_bytes()
    at, got = V.locate(orig, tpu)
    if got is None:
        print("  %-9s .TPU does not contain the segment -- run build.py" % unit)
        return False
    ours = tpu[at:at + len(orig) + 256]

    obj = V.BUILD / (unit + ".OBJ")
    if not obj.exists():
        print("  %-9s no %s -- run build.py" % (unit, obj.name))
        return False

    fields = fixups(obj)
    covered = {base + off + i for off, ln in fields.items() for i in range(ln)}

    # Each relocation field must fall into exactly one of two cases.
    #
    #   self   a CODE self-reference. TASM wrote the offset relative to the
    #          module, so the original must hold exactly that plus the base, and
    #          the arithmetic is checked -- no zero rule involved.
    #   pending  an EXTERNAL or DGROUP symbol our side left as zero. The byte
    #          comparison can say nothing about these; the original holds the
    #          variable's DGROUP offset and where we put that variable is risk 1,
    #          not something a .TPU records. Counted and reported, never excused
    #          as agreement.
    #   sym+add  the same, but with a non-zero ADDEND -- `OFFSET Something + n`.
    #          Our side holds n alone, so the implied symbol is `orig - ours`, and
    #          those are grouped and printed. They cannot be verified from the
    #          bytes either, but they are checkable BY HAND against the declared
    #          variables, and a single symbol serving several fields shows up as
    #          one repeated offset. SOUNDDEV has seven such fields and all seven
    #          imply the same symbol.
    #
    # Anything that is none of the three is unexplained and fails.
    self_refs = pending = 0
    implied = {}
    bad_val = []
    for off in sorted(fields):
        a = base + off
        o = orig[a] | (orig[a + 1] << 8)
        u = ours[a] | (ours[a + 1] << 8)
        if o == (u + base) & 0xFFFF:
            self_refs += 1
        elif u == 0:
            pending += 1
        elif u < 0x100:                         # small enough to be an addend
            implied.setdefault((o - u) & 0xFFFF, []).append(a)
        else:
            bad_val.append((a, o, u))

    stray = [a for a in range(base, end)
             if orig[a] != ours[a] and a not in covered]

    pad = orig[end:size]
    pad_ok = not pad or set(pad) == {0}

    ok = not bad_val and not stray and pad_ok
    print("  %-9s %04x  module %04x..%04x  %3d field(s): %3d self-ref, %3d pending,"
          " %2d symbol+addend  %s"
          % (unit, seg, base, end - 1, len(fields), self_refs, pending,
             sum(len(v) for v in implied.values()), "OK" if ok else "FAILED"))
    for sym in sorted(implied):
        print("      implies a DGROUP symbol at %04x, used by %d field(s): %s"
              % (sym, len(implied[sym]),
                 " ".join("%04x" % a for a in implied[sym])))

    for a, o, u in bad_val:
        print("      %04x  UNEXPLAINED: orig %04x, ours %04x -- neither ours+base"
              " (%04x) nor a zero our side left pending"
              % (a, o, u, (u + base) & 0xFFFF))
    for a in stray:
        print("      %04x  orig %02x  ours %02x  -- OUTSIDE any relocation"
              % (a, orig[a], ours[a]))
    if not pad_ok:
        print("      %04x..%04x  tail is not all zero" % (end, size - 1))
    elif pad:
        print("      %04x..%04x  %d byte(s) of linker padding, all zero"
              % (end, size - 1, len(pad)))
    return ok


def main():
    only = [a.upper() for a in sys.argv[1:]]
    bad = 0
    for unit, spec in MODULES.items():
        if only and unit not in only:
            continue
        if not check(unit, *spec):
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
