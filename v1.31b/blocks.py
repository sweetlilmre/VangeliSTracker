#!/usr/bin/env python3
"""Verify 12ba block by block, which is the only honest measure mid-routine.

    python v1.31b/blocks.py
    python v1.31b/asmcheck.py PLAYMOD    <- and this one for the last three blocks

WHY THIS EXISTS. `verify.py`'s prefix stops at the first byte that differs, and
inside a routine that is only PARTLY transcribed the first difference is always
the same thing: a jump displacement that cannot be right until the rest of the
routine exists. The prefix therefore freezes at the routine's start and says
nothing about the 400 bytes after it that ARE right.

So each finished block is compared at its own position, searching for the shift
that minimises real differences -- never a single global shift, which the docs
record as a mistake that once reported 73 mismatches where there were none. A
byte counts as a difference only when OUR side is non-zero, the same rule
verify.py uses.

READ IT AS A CHECKLIST. **12ba IS FINISHED.** All 5,958 bytes of code are
transcribed and every one of them is accounted for; the ten bytes at 1746..174f
are linker padding, which is why the total stops at 5,958 rather than 5,968.

EVERY PASCAL LINE READS 0. THE LAST THREE LINES DO NOT, AND THAT IS CORRECT --
USE asmcheck.py FOR THOSE. The three `asm` blocks are the `{$L}` object module,
and this script's zero rule is the wrong instrument for them:

    148f..1554  asm DumpRaw            9    all inside relocations
    1555..15ff  asm EmptyRaw          18    all inside relocations
    1600..1745  asm DumpInstrument     0

TASM does not leave an unresolved reference as zeros the way Turbo Pascal does --
it writes the offset RELATIVE TO THE MODULE and lets the linker add the base. So
every code self-reference differs from the original by exactly 148f, in bytes that
are not zero. The nine fields in DumpRaw have a zero high byte and read as one
difference each; the nine in EmptyRaw have a high byte of 01 and read as two.
Twenty-seven "differences" for thirty-six relocation bytes, and not one is a
defect. `python v1.31b/asmcheck.py PLAYMOD` checks the arithmetic field by field
against the .OBJ's own FIXUPP records and reports 18 of 18 self-references OK.

So: any non-zero on a PASCAL line is a real defect. The three asm lines are read
through asmcheck.py instead, and 27 is their expected value.

HOW PLAYSTART'S FIVE DIFFERENCES CLOSED, because the way they closed is the
lesson. They were listed here as self-closing -- four bytes of prologue that
would come right when the routine reached its locals, and one jump displacement
that depended on code not yet written -- and both explanations were wrong. The
routine had been given a second parameter it does not have: 12ba:132c is
`RETF 4`, four bytes, which is the `var Song` reference alone, and every frame
reference in the routine was two bytes off because of it. The prologue was not
waiting for locals; it was reading `Song` at [BP+8] instead of [BP+6].

SO "IT WILL CLOSE ITSELF" IS A PREDICTION AND WAS MARKED AS ONE. It was believed
for several sessions. The general rule it came from is still right -- a frame
larger than the locals explain is a compiler temporary or a `with` slot, which
is exactly what PlayStart's [BP-8] turned out to be -- but a routine's PARAMETER
list is settled by its `RETF`, in one instruction, and that check is free.
"""

import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import verify as V                            # noqa: E402

SEG, SIZE = 0x12BA, 5968

# Every block finished so far, in address order. A block is added here only once
# its bytes have been checked; the last entry is where the work stopped.
BLOCKS = [
    ("0000..0006  NullProcedure", 0x0000, 0x0007),
    ("0007..0186  UnCanal", 0x0007, 0x0187),
    ("0187..0201  AdvanceEventRow", 0x0187, 0x0202),
    ("0202..0274  SetEvent", 0x0202, 0x0275),
    ("0275..02e9  PostEvent", 0x0275, 0x02ea),
    ("02ea..03cb  FlushEventRow", 0x02ea, 0x03cc),
    ("03cc..0663  SetGusVoiceCtl", 0x03cc, 0x0664),
    ("0664..0692  MyMove", 0x0664, 0x0693),
    ("0693..0b28  NextPattern", 0x0693, 0x0b29),
    ("0b29..0c4d  MixTick", 0x0b29, 0x0c4e),
    ("0c4e..1007  SeqTick", 0x0c4e, 0x1008),
    ("1008..1048  ProcessTickEntry", 0x1008, 0x1049),
    ("1049..105c  IdleGiver", 0x1049, 0x105d),
    ("105d..10a0  BufferGiver", 0x105d, 0x10a1),
    ("10a1..10d6  PlayStart: copy", 0x10a1, 0x10d7),
    ("10d7..10f8  PlayStart: pos", 0x10d7, 0x10f9),
    ("10f9..116e  PlayStart: range", 0x10f9, 0x116f),
    ("116f..11d5  PlayStart: prime", 0x116f, 0x11d6),
    ("11d6..1223  PlayStart: chans", 0x11d6, 0x1224),
    ("1224..129e  PlayStart: buffers", 0x1224, 0x129f),
    ("129f..132e  PlayStart: go", 0x129f, 0x132f),
    ("132f..1365  ChangeSamplingRate: ask", 0x132f, 0x1366),
    ("1366..13d6  ChangeSamplingRate: apply", 0x1366, 0x13d7),
    ("13d7..141d  PlayStop", 0x13d7, 0x141e),
    ("141e..148e  initialisation", 0x141e, 0x148f),
    # ---- the {$L} object module. 1746..174f is linker padding, not code.
    ("148f..1554  asm DumpRaw", 0x148f, 0x1555),
    ("1555..15ff  asm EmptyRaw", 0x1555, 0x1600),
    ("1600..1745  asm DumpInstrument", 0x1600, 0x1746),
]


def main():
    orig = V.original(SEG, SIZE)
    tpu = (V.BUILD / "PLAYMOD.TPU").read_bytes()
    at, got = V.locate(orig, tpu)
    if got is None:
        print("PLAYMOD.TPU does not contain the segment -- run build.py")
        return 1
    ours = tpu[at:at + len(orig) + 256]

    total = bad = 0
    for name, lo, hi in BLOCKS:
        block = orig[lo:hi]
        best = None
        for shift in range(-64, 64):
            seg = ours[lo + shift:lo + shift + len(block)]
            if len(seg) != len(block):
                continue
            d = sum(1 for a, b in zip(block, seg) if a != b and b != 0)
            if best is None or d < best[1]:
                best = (shift, d)
        shift, diffs = best
        total += len(block)
        bad += diffs
        print("  %-28s %4d bytes  shift %+3d  real diffs %d"
              % (name, len(block), shift, diffs))
    print("  %-28s %4d bytes                real diffs %d"
          % ("TOTAL", total, bad))
    print()
    print("  %d of %d bytes of segment %04x transcribed (%d%%)"
          % (total, SIZE, SEG, 100 * total // SIZE))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
