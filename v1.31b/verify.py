#!/usr/bin/env python3
"""Compare each compiled .TPU's code against the original segment, byte for byte.

    python v1.31b/build.py && python v1.31b/verify.py

WHY THIS EXISTS.  Matching the original's code SIZE is a weak check -- two
different routines can be the same length.  The target is a byte-exact
rebuild, so the honest question is whether the bytes agree, and that is
answerable: the .TPU carries the unit's compiled code verbatim.

THE ONE ALLOWED DIFFERENCE IS A PENDING FIXUP.  A .TPU is not linked yet, so
every reference the linker still has to resolve -- far calls into other units,
offsets of DGROUP variables -- is left as ZERO where the original binary has
the resolved value.  So the rule is:

    a differing byte is acceptable ONLY where the .TPU byte is 0x00.

That is strict enough to be worth something.  A real codegen difference --
a different instruction, a different operand, a different branch -- would have
to coincidentally emit zero to slip through, and a wrong branch direction or a
swapped operand will not.  Anything else is reported as a MISMATCH and the
transcription is wrong.

FINDING THE CODE IN THE .TPU.  Rather than parse a format that varies between
Turbo Pascal releases, the original segment is slid over the whole .TPU and
the best-scoring position wins.  Small files, and it cannot be fooled: if the
unit does not contain the code, no position scores well.
"""

import struct
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
# tp6_dialect is the kit's now (#50): TP6 has no `far` directive on a unit's
# exported routines at all, which is a fact about a compiler rather than about
# this target. build.py is archived; this is the same function.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] /
                       "kit" / "tools"))
from pascal.build import tp6_dialect   # noqa: E402  -- see the stale check
from omf import code_and_fixups        # noqa: E402  -- see obj_mask below
import refpath

ROOT = pathlib.Path(__file__).resolve().parents[1]
IMAGE = refpath.ORIG
BUILD = ROOT / "build"

# unit -> (segment, code bytes in the original)
#
# The sizes are the original's, read off the segment map in docs/04-units.md.
# Where a segment is padded up to a paragraph the figure is the code only, so
# a unit may legitimately compile SHORTER; only the overlap is compared.
UNITS = {
    "ASCIIZ":   (0x1642, 144),
    "VTNOTES":  (0x1650, 149),   # 160 in the segment map; the last 11 are padding
    "FILTERS":  (0x1544, 144),
    "VTCTRL":   (0x14B7, 25),
    "VTDOSRSZ": (0x188F, 29),
    "VTDOSMEM": (0x1880, 237),
    "FILEUTIL": (0x116A, 59),
    "VTSHELL":  (0x1931, 138),   # 141 in the segment map; the last 3 are padding
    # 12ba, IN PROGRESS. 5968 is the whole segment; the unit covers the top of
    # it and is reported PARTIAL until it reaches the end.
    "PLAYMOD":  (0x12BA, 5968),
    # 142f, IN PROGRESS. Six routines transcribed from the top; everything from
    # 0184 down is a stub, so the prefix stops there and that IS the measure while
    # the unit is built strictly top-down. 2176 is the whole segment.
    "MODCOMMA": (0x142F, 2176),
    # 11bb, IN PROGRESS. 4080 is the whole segment; 0000..001f is a set constant
    # and the first routine is at 0020.
    "VTCFG":    (0x11BB, 4080),
    # 17cf, IN PROGRESS. 2832 is the whole segment.
    "HEAPS":    (0x17CF, 2832),
    # 109c, IN PROGRESS. 3296 is the whole segment.
    "VTCMD":    (0x109C, 3296),
    "SONGELEM": (0x165A, 3216),
    "MODLOADE": (0x154D, 3920),
    # 19a0. 1905 in the segment map; the code ends at 076a with Sb16StartSample's
    # RETF 4 and the last 7 bytes are padding.
    "SOUNDBLA": (0x19A0, 1898),
    "DEVSB":    (0x193A, 1617),
    # 14b9, IN PROGRESS. 2224 is the whole segment. All sixteen routines are
    # named and in place, but only eight have real bodies; the rest are
    # placeholders holding their position, so the prefix stops at the first
    # near-call displacement that depends on one of them. Read it per block.
    "SONGUNIT": (0x14B9, 2224),
    "CMDLINE":  (0x116E, 1232),
    "HARDWARE": (0x1B24, 765),
    # 2752 in the segment map; the code ends `C9 CA 02 00` (LEAVE / RETF 2) at
    # 0ab4 and the last 11 bytes are padding. This read 2739 and cut the RETF's
    # own operand in half, which showed up as a phantom 62-byte tail region --
    # difflib had nothing to align our real tail against, so it swept up the
    # typed constants the .TPU stores after the code.
    "GUS":      (0x1723, 2741),
    "DEVGUS":   (0x1084, 376),   # 384 in the segment map; the last 8 are padding
    "VTSILENC": (0x1065, 489),   # 491 in the segment map; the last 2 are padding
    "UNKLOADE": (0x164B, 77),
    "VTRESID":  (0x1B54, 432),
    # 1a17, the player core -- complete. Its remaining differences are all
    # pending fixups plus 27 bytes that cannot match from the source; see the
    # header of SOUNDDEV.PAS. NOTE the region list overstates it badly, because
    # the gain ladder's pointer tables are sixteen consecutive DW OFFSETs and an
    # unresolved table is a 32-byte run of zeros, well past MAX_FIXUP. Judge
    # this unit by whether the differing bytes are ZERO, not by the run length.
    "SOUNDDEV": (0x1A17, 4303),
}


def original(seg, n):
    d = IMAGE.read_bytes()
    base = struct.unpack_from("<H", d, 8)[0] * 16
    o = base + seg * 16 - 0x10000
    return d[o:o + n]


def score(orig, tpu, at):
    """Exact matches, real differences, pending fixups, first real difference."""
    same = bad = fix = 0
    first = -1
    for k in range(len(orig)):
        if tpu[at + k] == orig[k]:
            same += 1
        elif tpu[at + k] == 0:
            fix += 1
        else:
            bad += 1
            if first < 0:
                first = k
    return same, bad, fix, first


# The longest thing a linker fixup can zero out is a far pointer: four bytes.
# Anything longer is not a pending reference, it is a region the compiler did
# not fill because the code is simply different -- or padding past the end of
# the unit. Without this cap a long run of zeros in the .TPU swallows the real
# divergence and the unit reports far better agreement than it has.
MAX_FIXUP = 4

# How much of a segment has to be present at a candidate position for it to be
# worth considering. Enough that a run of coincidence cannot win, small enough
# that a partially transcribed unit is still measurable.
MIN_OVERLAP = 64


def prefix(orig, tpu, at, mask=frozenset()):
    """Bytes agreeing from the start, allowing runs of at most MAX_FIXUP zeros.

    `mask` holds positions an assembled module recorded as relocations; those
    are allowed to differ whatever their value, because the assembler left an
    addend there rather than a zero. See obj_mask.
    """
    k = run = 0
    while k < len(orig):
        if tpu[at + k] == orig[k]:
            run = 0
        elif at + k in mask:
            run = 0                     # a recorded relocation, not a difference
        elif tpu[at + k] == 0:
            run += 1
            if run > MAX_FIXUP:
                return k - run + 1      # rewind to where the run began
        else:
            break
        k += 1
    return k


def locate(orig, tpu):
    """Best position, ANCHORED ON THE PROCEDURE PROLOGUE.

    Two earlier versions of this got it wrong and both failures are worth
    keeping in mind:

    * Ranking by "fewest real differences" scores a run of zero bytes as a
      perfect match, because against zeros every difference looks like a
      pending fixup. Two units passed that should not have.
    * Ranking by "most exact matches" is not fooled that way, but it drifts
      when the unit and the segment are different lengths: it slides to
      whatever alignment happens to share the most bytes, which can be
      nowhere near the start, and then reports a first-divergence offset that
      means nothing.

    So anchor instead: find the positions where the opening bytes agree, and
    among those take the one that agrees FURTHEST from the start. That is
    alignment-independent and it makes the reported divergence the real one.
    """
    # Candidates are positions whose FIRST byte matches exactly. That single
    # constraint is what keeps the search out of the .TPU's symbol table and
    # off its runs of zeros -- both of which previously scored well enough to
    # be chosen, and one of which reported a match sitting in the middle of
    # the string "MixRate".
    #
    # A PARTIAL UNIT COMPILES MUCH SHORTER THAN ITS SEGMENT, and this used to
    # require the whole segment to fit inside the .TPU from the candidate
    # position onwards. SOUNDDEV is 1.6KB of a 4303-byte segment, so every
    # candidate was rejected and the unit reported "NOT LOCATED -- first
    # instruction differs" when its opening 27 bytes were in fact perfect.
    #
    # So require MIN_OVERLAP bytes, or the whole segment if it is smaller than
    # that. Both halves of that `min` are load-bearing:
    #
    #   * without the MIN_OVERLAP cap, a partial unit has no valid candidate at
    #     all and reports NOT LOCATED however good its opening is;
    #   * without the len(orig) floor, a segment SHORTER than MIN_OVERLAP gets a
    #     HARDER test than before -- which took VTDOSRSZ, all 29 bytes of it,
    #     from 93% to NOT LOCATED.
    #
    # Trying the strict rule first and falling back only when it yields nothing
    # does not work either: for a partial unit the strict rule yields plenty of
    # candidates, just no good ones, so the fallback never fires.
    #
    # Relaxing the requirement cannot mislocate a complete unit, because the
    # winner is still whichever position agrees FURTHEST. A 64-byte coincidence
    # near the end of a .TPU does not outrank a real match of hundreds.
    need = min(MIN_OVERLAP, len(orig))
    cands, i = [], tpu.find(orig[:1])
    while i >= 0:
        if len(tpu) - i >= need:
            cands.append(i)
        i = tpu.find(orig[:1], i + 1)

    best, at = None, -1
    for i in cands:
        # Compare only what is actually there. For a complete unit this is the
        # whole segment; for a partial one it is however much has been written.
        head = orig[:min(len(orig), len(tpu) - i)]
        same, bad, fix, first = score(head, tpu, i)
        pre = prefix(head, tpu, i)
        if best is None or pre > best[0]:
            best, at = (pre, same, bad, fix, first), i

    # Too short to be the routine: the unit's first instruction differs, so
    # there is nothing to align against and no offset worth reporting.
    if best is None or best[0] < 4:
        return -1, None
    return at, best


def detail(name, seg, n, orig, tpu, at, pre):
    """Dump the bytes either side of the divergence, original against ours."""
    lo = max(0, pre - 24)
    hi = min(n, pre + 40)
    print("\n=== %s  seg %04x  diverges at +%04x of %04x" % (name, seg, pre, n))
    for base in range(lo, hi, 16):
        o = orig[base:base + 16]
        t = tpu[at + base:at + base + 16]
        mark = "".join(
            "  " if base + k >= len(orig) else
            ".." if o[k] == t[k] else
            "--" if t[k] == 0 else "^^"
            for k in range(len(o)))
        flag = "  <<<" if base <= pre < base + 16 else ""
        print("  +%04x  orig %s%s" % (base, o.hex(), flag))
        print("         tp7  %s" % t.hex())
        print("              %s" % mark)
    print("  legend: .. same   -- pending fixup (tp7 zero)   ^^ REAL difference")


def obj_mask(unit, ours):
    """Byte positions inside `ours` that an assembled module left as relocations.

    A .TPU leaves an unresolved reference as ZERO, which is what every other
    check here relies on. An assembled module does not: TASM resolves what it
    can and leaves an ADDEND -- `DW OFFSET @@G1Table` becomes the offset from
    the module's own start, `Volumes[2]` becomes the displacement 2 -- so
    against a linked binary those bytes differ by exactly the base the linker
    would have added. There is no way to tell that from the bytes, and guessing
    would excuse real differences, so it is read from the .OBJ instead.

    Returns an empty set when the unit links no module, which leaves every other
    unit measured exactly as before.
    """
    obj = BUILD / (unit + ".OBJ")
    if not obj.exists():
        return set()
    code, fixups = code_and_fixups(obj)
    # Turbo Pascal appends object-module code AFTER all of the unit's own code,
    # so the module sits at the end -- but find it rather than assume it, by its
    # opening bytes, which are code and not a fixup.
    at = ours.find(code[:24])
    if at < 0:
        return set()
    return {at + f for f in fixups}


def regions(orig, tpu, at, mask=frozenset()):
    """Every place the two disagree, not just the first.

    A single two-byte codegen difference early in a unit displaces everything
    after it, so a first-divergence report says nothing about the remaining
    2,600 bytes. Aligning with difflib recovers the structure: the matching
    runs come back as blocks and the gaps between them are the real work
    list. A gap of 1-4 bytes where OUR side is zero is a pending fixup, not a
    defect.

    THE WINDOW OVER-READS BY 64 BYTES on purpose, so a unit that compiles
    LONGER than the original still has something to align against. The cost is
    that whatever slack is left over always turns up as a final gap with
    nothing on the original side -- and because the .TPU stores its typed
    constants straight after the code, that gap fills with table data and reads
    like a 62-byte divergence. It is not one, so a trailing gap the original
    side does not reach into is dropped. A unit whose code really is longer
    still shows it: the excess appears as gaps INSIDE the aligned region.
    """
    import difflib
    win = tpu[at:at + len(orig) + 64]
    sm = difflib.SequenceMatcher(None, orig, win, autojunk=False)
    out, oi, ti = [], 0, 0
    for a, b, n in sm.get_matching_blocks():
        if a > oi or b > ti:
            ours = win[ti:b]
            # A gap is pending fixups if OUR side is all zero and either it is
            # short enough to be one reference (four bytes, a far pointer) or it
            # lines up EXACTLY with the same number of original bytes.
            #
            # That second clause is what a table of unresolved offsets looks
            # like: the gain ladder at 1a17:083e is sixteen consecutive
            # DW OFFSET entries, so an unlinked table is a 32-byte run of zeros
            # against 32 bytes of real addresses. The four-byte cap alone
            # reported all of it as real, and the docs carried "132 differences
            # in the ladder" for several sessions on that basis. They were all
            # zero.
            #
            # The cap still matters for the case it was added for -- a unit that
            # simply STOPS, leaving zeros against the original's remaining code.
            # There the lengths do not match, because difflib pairs the original's
            # bytes against nothing.
            allzero = len(ours) > 0 and all(c == 0 for c in ours)
            # ...or the gap is entirely inside relocation fields the assembler
            # recorded. Same rule, better evidence: the .OBJ says which bytes
            # are pending instead of the value 0 standing in for it.
            relocated = (len(ours) == a - oi and len(ours) > 0
                         and all(ti + k in mask for k in range(len(ours))))
            fixup = relocated or (allzero and
                                  (len(ours) <= MAX_FIXUP or len(ours) == a - oi))
            trailing = oi >= len(orig)
            if not fixup and not trailing:
                out.append((oi, a - oi, b - ti))
        oi, ti = a + n, b + n
    return out


def main(argv):
    want_detail = "-d" in argv or "--detail" in argv
    want_all = "-a" in argv or "--all" in argv
    argv = [a for a in argv if not a.startswith("-")]
    only = [a.upper() for a in argv]
    if not IMAGE.exists():
        print("no unpacked image at %s" % IMAGE)
        return 1

    rows, exact, ok, failed, missing = [], 0, 0, 0, 0
    for name in sorted(UNITS):
        if only and name not in only:
            continue
        seg, n = UNITS[name]
        tpu_path = BUILD / (name + ".TPU")
        if not tpu_path.exists():
            rows.append((name, seg, n, None, None, "no .TPU -- run build.py"))
            missing += 1
            continue
        # A stale .TPU is worse than no .TPU: it reports on code that is no
        # longer the source, and build.py refuses to run at all when the lint
        # fails, so one bad comment leaves the whole tree stale. That has
        # already produced one wrong conclusion here.
        #
        # Compare CONTENT, not timestamps. build.py stages a copy of each
        # source beside the .TPU, and DOSBox writes DOS timestamps that do not
        # reliably compare against the host's -- an mtime check reported a
        # freshly built unit as stale.
        src = ROOT / "v1.31b" / "src" / (name + ".PAS")
        staged = BUILD / (name + ".PAS")
        if src.exists() and staged.exists():
            a = src.read_text(encoding="utf-8", errors="replace")
            a = a.encode("cp437", errors="replace").decode("cp437")
            # A TP6 build stages a REWRITTEN copy -- the interface's `far`
            # directives become an {$F+} region, because TP6 has no directive
            # for them (see build.tp6_dialect). Accept that form too, or every
            # TP6 build reports the whole tree stale; anything else still does.
            if staged.read_text(encoding="cp437", errors="replace") not in (
                    a, tp6_dialect(a)):
                rows.append((name, seg, n, None, None,
                             "STALE -- source changed since the build; rebuild"))
                missing += 1
                continue
        orig = original(seg, n)
        tpu = tpu_path.read_bytes()
        at, got = locate(orig, tpu)
        if got is None:
            rows.append((name, seg, n, None, None,
                         "NOT LOCATED -- first instruction differs"))
            failed += 1
            continue
        # A PARTIAL UNIT IS MEASURED OVER WHAT IT HAS. Comparing our 1.6KB
        # against 1a17's 4303 says nothing about the 2.7KB not written yet, and
        # counting those as divergent would bury the part that IS done. So the
        # comparison is clipped and the shortfall reported separately -- an
        # honest "agrees for as far as it goes, and it does not go all the way".
        full = len(orig)
        orig = orig[:min(full, len(tpu) - at)]
        short = full - len(orig)
        pre, same, bad, fix, first = got
        # A unit that links an object module needs its relocations read from the
        # .OBJ before any of the figures above mean anything: TASM leaves an
        # addend where the compiler leaves a zero. Re-measure with that mask.
        mask = obj_mask(name, tpu)
        if mask:
            pre2 = prefix(orig, tpu, at, mask)
            reloc = sum(1 for m in mask if at <= m < at + len(orig)
                        and tpu[m] != orig[m - at])
            if pre2 > pre:
                pre = pre2
                fix += reloc
        if short and pre >= len(orig):
            note = "PARTIAL: %04x of %04x transcribed, all of it %s" % (
                len(orig), full,
                "identical" if fix == 0 else "identical bar %d fixup(s)" % fix)
            ok += 1
            rows.append((name, seg, n, at, bad, note))
            continue
        if pre >= len(orig):
            # Agrees the whole way. Distinguish a literal match from one that
            # still has linker fixups outstanding.
            if fix == 0:
                note, exact = "IDENTICAL", exact + 1
            else:
                note = "identical, %d pending fixup%s" % (fix, "" if fix == 1 else "s")
                ok += 1
        else:
            note = "agrees to +%04x of %04x  (%d%%)" % (pre, len(orig),
                                                        100 * pre // len(orig))
            failed += 1
            if want_detail:
                detail(name, seg, n, orig, tpu, at, pre)
            if want_all:
                # Everything before `pre` is already proven identical by the
                # prefix scan; difflib produces alignment noise around the
                # fixup zeros there, so drop it rather than report it.
                rs = [r for r in regions(orig, tpu, at, mask) if r[0] >= pre]
                print("")
                print("=== %s  %d divergent region(s)" % (name, len(rs)))
                for off, olen, tlen in rs[:40]:
                    print("  at +%04x  original %3d byte(s)  ours %3d" % (off, olen, tlen))
                if len(rs) > 40:
                    print("  ... and %d more" % (len(rs) - 40))
        rows.append((name, seg, n, at, bad, note))

    w = max(len(r[0]) for r in rows) if rows else 8
    print("%-*s  %-6s %6s  %s" % (w, "unit", "seg", "bytes", "result"))
    print("-" * (w + 40))
    for name, seg, n, at, bad, note in rows:
        print("%-*s  %04x   %6d  %s" % (w, name, seg, n, note))
    print("-" * (w + 40))
    print("%d byte-identical, %d identical but for fixups, %d mismatched, %d missing"
          % (exact, ok, failed, missing))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
