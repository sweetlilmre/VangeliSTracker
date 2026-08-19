"""Compare build/VTMAIN.MAP's segment lengths against the original's, ON THE SAME FOOTING.

THE FOOTING IS THE POINT. Three numbers get confused here and mixing any two of them
manufactures a gap that is not there:

  * `verify.py`'s size  -- the CODE bytes in a .TPU. Excludes the padding a segment
    carries, so it reads SHORT of the segment by up to 15.
  * our map's `Length`  -- the linked segment's exact code length. Also excludes
    padding: the linker pads by starting the NEXT segment on a paragraph.
  * the original's size -- read off the segment ADDRESSES, so it is always the code
    length rounded UP to a paragraph.

So the honest comparison rounds OUR length up to a paragraph too, which is what the
original's addresses already did. Doing it any other way puts every unit in the program
15 bytes "short" and buries the four that really are.

A surviving gap is a WORK LIST rather than a defect: Turbo Pascal smart-links per
routine, so each gap names a reference our program does not yet make and the linker
found it for free.
"""
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

# The original's link order, read off the segment addresses -- see CONTINUATION.md.
# Each segment's length is the NEXT one's address minus its own, so the list has to
# be complete and in order, and the last entry needs the end of the image.
ORIG = [
    (0x1000, 'DEMOVT'),        (0x1065, 'VTSILENC'),
    (0x1084, 'DEVGUS'),        (0x109c, 'VTCMD'),
    (0x116a, 'FILEUTIL'),      (0x116e, 'CMDLINE'),
    (0x11bb, 'VTCFG'),         (0x12ba, 'PLAYMOD'),
    (0x142f, 'MODCOMMANDS'),   (0x14b7, 'VTCTRL'),
    (0x14b9, 'SONGUNIT'),      (0x1544, 'FILTERS'),
    (0x154d, 'MODLOADER'),     (0x1642, 'ASCIIZ'),
    (0x164b, 'UNKLOADER'),     (0x1650, 'VTNOTES'),
    (0x165a, 'SONGELEMENTS'),  (0x1723, 'GUS'),
    (0x17cf, 'HEAPS'),         (0x1880, 'VTDOSMEM'),
    (0x188f, 'VTDOSRSZ'),      (0x1891, 'OBJECTS'),
    (0x193a, 'DEVSB'),         (0x19a0, 'SOUNDBLASTER'),
    (0x1a17, 'SOUNDDEVICES'),  (0x1b24, 'HARDWARE'),
    (0x1b54, 'VTRESID'),       (0x1b6f, 'DOS'),
    (0x1ba1, 'SYSTEM'),        (0x1caa, None),   # 1caa is data; it ends SYSTEM
]

# Not reconstructed, and not in scope: Borland's RTL. Reported, never chased.
RTL = {'OBJECTS', 'DOS', 'SYSTEM'}


def orig_lengths():
    out = {}
    for (seg, name), (nxt, _) in zip(ORIG, ORIG[1:]):
        if name:
            out[name] = (nxt - seg) * 16
    return out


def map_lengths(path):
    out = {}
    for line in path.read_text(encoding='ascii', errors='replace').splitlines():
        m = re.match(r'\s*([0-9A-F]+)H\s+([0-9A-F]+)H\s+([0-9A-F]+)H\s+(\S+)\s+CODE\s*$',
                     line)
        if m:
            out[m.group(4)] = int(m.group(3), 16)
    return out


def main():
    mp = ROOT / 'build' / 'VTMAIN.MAP'
    if not mp.exists():
        raise SystemExit("no build/VTMAIN.MAP -- run: python v1.31b/build.py --sw=/GS")
    ours, orig = map_lengths(mp), orig_lengths()

    rows = []
    for _, name in ORIG:
        if not name:
            continue
        o = orig[name]
        n = ours.get(name)
        if n is None:
            rows.append((o, name, None, o, 'ABSENT -- nothing references this unit'))
            continue
        # round ours up to a paragraph, which is what the original's addresses did
        padded = (n + 15) & ~15
        gap = o - padded
        if gap > 0:
            note = 'short -- %d byte(s) of routines nothing references' % gap
        elif gap < 0:
            note = 'LONGER than the original by %d -- see the CMDLINE note' % -gap
        else:
            note = 'exact'
        if name in RTL:
            note += '   (RTL, out of scope)'
        rows.append((gap, name, n, o, note))

    print("%-14s %8s %8s %8s  %s" % ("unit", "ours", "padded", "original", "verdict"))
    print("-" * 88)
    # largest gap first: that is the work list's own order
    for gap, name, n, o, note in sorted(rows, key=lambda r: -abs(r[0])):
        print("%-14s %8s %8s %8d  %s" % (
            name, '--' if n is None else n,
            '--' if n is None else (n + 15) & ~15, o, note))

    live = [r for r in rows if r[0] and r[1] not in RTL]
    print("-" * 88)
    print("%d unit(s) exact; %d with a live gap, %d byte(s) in total" % (
        len(rows) - len([r for r in rows if r[0]]),
        len(live), sum(abs(r[0]) for r in live)))


if __name__ == '__main__':
    main()
