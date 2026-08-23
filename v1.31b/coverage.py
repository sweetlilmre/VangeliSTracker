"""Coverage of the DemoVT byte-exact pass, computed from the tree rather than recited."""
import re, subprocess, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

ROOT = pathlib.Path(__file__).resolve().parents[1]

# every segment and its size, from 00-map.md (authoritative on the layout)
txt = (ROOT / 'v1.31b/docs/00-map.md').read_text(encoding='utf-8', errors='replace')
seg = {int(m.group(1), 16): int(m.group(2))
       for m in re.finditer(r'^\| `([0-9a-f]{4})` \| (\d+) \|', txt, re.M)}

RTL = {0x1891: 'Objects', 0x1b6f: 'Dos', 0x1ba1: 'System'}   # never in scope
DATA = {0x1caa: 'constants only, no code'}

# what verify.py reports, parsed from its own output
# The per-unit table comes from the kit's instrument now (#50). This still
# parses another tool's printed output, which is fragile by nature -- the row
# shape is the contract and nothing enforces it. Moving this into the kit is
# where that gets fixed; until then the parse is unchanged and so is the answer.
out = subprocess.run([sys.executable,
                      str(ROOT / 'kit/tools/pascal/units.py'),
                      'v1.31b/units.toml'],
                     capture_output=True, text=True,
                     encoding='utf-8', cwd=str(ROOT)).stdout
done, partial = {}, {}
for line in out.splitlines():
    m = re.match(r'^(\w+)\s+([0-9a-f]{4})\s+(\d+)\s+(.*)$', line)
    if not m:
        continue
    name, s, size, res = m.group(1), int(m.group(2), 16), int(m.group(3)), m.group(4)
    if res.startswith('IDENTICAL') or res.startswith('identical'):
        done[s] = (name, size)
    else:
        p = re.search(r'agrees to \+([0-9a-f]+)', res)
        if p:
            partial[s] = (name, int(p.group(1), 16))

in_scope = {k: v for k, v in seg.items() if k not in RTL and k not in DATA}
total = sum(in_scope.values())
done_bytes = sum(sz for _, sz in done.values())
part_bytes = sum(n for _, n in partial.values())

print("IN SCOPE: %d segments, %d bytes" % (len(in_scope), total))
print("  excluded: %s (Borland RTL, %d bytes), %s (%d bytes)"
      % (', '.join('%04x' % k for k in RTL), sum(seg[k] for k in RTL),
         '1caa', seg[0x1caa]))
print()
print("COMPLETE  %2d unit(s)  %6d bytes" % (len(done), done_bytes))
print("PARTIAL   %2d unit(s)  %6d bytes" % (len(partial), part_bytes))
for s, (n, b) in sorted(partial.items()):
    print("             %-9s %04x  %d of %d (%d%%)"
          % (n, s, b, seg[s], 100 * b // seg[s]))
print()
covered = done_bytes + part_bytes
print("COVERED   %6d of %d bytes  = %.1f%%" % (covered, total, 100.0 * covered / total))
print()
untouched = {k: v for k, v in in_scope.items() if k not in done and k not in partial}

# 1000 IS THE PROGRAM, so it compiles into the .EXE rather than to a .TPU and
# verify.py -- which compares a .TPU's code against a segment -- has nothing to
# list it as. It is measured by `progcmp.py` instead, and that number is asked
# for here rather than assumed, so this total is the whole program.
PROGRAM_SEG = 0x1000
prog = untouched.pop(PROGRAM_SEG, None)
if prog is not None:
    out2 = subprocess.run([sys.executable, 'v1.31b/progcmp.py'],
                          capture_output=True, text=True,
                     encoding='utf-8', cwd=str(ROOT)).stdout
    m = re.search(r'agrees for the first (\d+) byte', out2)
    n = int(m.group(1)) if m else 0
    print("THE PROGRAM: 1000, %d bytes in the segment -- %d verified by progcmp.py"
          % (prog, n))
    print("             (its code is 1604; the rest of the segment is padding)")
    covered += n
    print()
    print("COVERED, WITH THE PROGRAM  %6d of %d bytes  = %.1f%%"
          % (covered, total, 100.0 * covered / total))
    print()
if untouched:
    print("NOT STARTED: %d segments, %d bytes" % (len(untouched), sum(untouched.values())))
    for k in sorted(untouched, key=lambda x: -untouched[x]):
        print("   %04x  %5d" % (k, untouched[k]))
else:
    print("NOT STARTED: none. Every segment is transcribed.")
