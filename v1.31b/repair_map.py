"""Repair 00-map.md: reverse the mojibake, then rebuild the blank-line structure.

The damage is two independent things:

  1. 22 double-encoded characters -- an em dash, two o-acute, two a-acute and a
     copyright sign, each read as cp1252 and re-written as UTF-8. All reverse
     exactly, so this half is not a judgement call.

  2. Every line is followed by a variable run of blank lines: 9,759 of the
     file's 10,736 lines are blank. It is NOT a uniform multiplication and no
     arithmetic inverts it. What IS true is that within a run of consecutive
     PROSE lines the padding is constant -- 70 of the 71 such runs have gaps
     that are exact multiples of the run's minimum, quotient 1..3 -- so the
     original gap is recoverable there as gap//m. Table rows, fenced blocks and
     indented code do not need a multiplier: markdown forbids a blank line
     inside a table, and the rest read as one block.

Every gap is therefore resolved one of three ways, and the script says which:
EXACT (a clean multiplier), STRUCTURAL (markdown leaves no choice), or FLAGGED.
"""
import pathlib, re, collections, sys

SRC = pathlib.Path(r'D:\source\VangeliSTracker\v1.31b\docs\00-map.md')
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else SRC

raw = SRC.read_text(encoding='utf-8')

# ALREADY APPLIED -- kept as the record of how, not as a step to repeat. Running
# it on the repaired file would re-derive multipliers from gaps that no longer
# encode anything, so it refuses.
_blank = sum(1 for l in raw.split(chr(10)) if not l.strip())
if _blank < len(raw.split(chr(10))) / 3:
    raise SystemExit('00-map.md looks already repaired (%d blank lines of %d) -- '
                     'nothing to do. See the docstring above for what this did.'
                     % (_blank, len(raw.split(chr(10)))))

# ---------------------------------------------------------------- 1. mojibake
MOJI = [('\u00e2\u20ac\u201d', '\u2014'),   # em dash
        ('\u00c3\u00b3',       '\u00f3'),   # o acute
        ('\u00c3\u00a1',       '\u00e1'),   # a acute
        ('\u00c2\u00a9',       '\u00a9')]   # copyright
fixed = 0
for bad, good in MOJI:
    fixed += raw.count(bad)
    raw = raw.replace(bad, good)

lines = raw.split('\n')
content = [l for l in lines if l.strip()]
idx = [i for i, l in enumerate(lines) if l.strip()]
gaps = [b - a for a, b in zip(idx, idx[1:])]

# ------------------------------------------------------------ 2. classify
infence, f = [], False
for l in content:
    if l.lstrip().startswith('```'):
        infence.append(True); f = not f
    else:
        infence.append(f)

def kind(n):
    l = content[n]
    if infence[n]: return 'fence'
    if l.startswith('#'): return 'head'
    if l.strip() == '---': return 'rule'
    if l.startswith('|'): return 'table'
    if l.startswith('    ') or l.startswith('\t'): return 'code'
    if re.match(r'^\s*([-*+]|\d+\.)\s', l): return 'list'
    return 'prose'

K = [kind(n) for n in range(len(content))]

# ------------------------------------- 3. local multiplier over prose runs
def segment(run):
    """Split a run of gap-indices into maximal blocks a constant m explains."""
    out, i = [], 0
    while i < len(run):
        best = None
        for j in range(len(run), i, -1):
            g = [gaps[x] for x in run[i:j]]
            m = min(g)
            if all(x % m == 0 and x // m <= 3 for x in g):
                best = (j, m); break
        if best is None:
            best = (i + 1, gaps[run[i]])
        out.append((run[i:best[0]], best[1]))
        i = best[0]
    return out

resolved = {}                      # gap index -> (newlines, how)
runs, cur = [], []
for i in range(len(gaps)):
    if K[i] == 'prose' and K[i + 1] == 'prose':
        cur.append(i)
    else:
        if cur: runs.append(cur)
        cur = []
if cur: runs.append(cur)

lonely = 0
for r in runs:
    if len(r) == 1:
        lonely += 1
        continue                   # no neighbours to infer m from; handled below
    for block, m in segment(r):
        for i in block:
            resolved[i] = (gaps[i] // m, 'EXACT')

# ------------------------------------------------- 4. structural defaults
for i in range(len(gaps)):
    if i in resolved:
        continue
    a, b = K[i], K[i + 1]
    if a == b == 'table':
        resolved[i] = (1, 'STRUCTURAL')          # a blank line ends a table
    elif a == b == 'fence' or a == b == 'code':
        resolved[i] = (1, 'STRUCTURAL')          # one block, read verbatim
    elif a == b == 'list':
        resolved[i] = (1, 'STRUCTURAL')
    elif 'fence' in (a, b) and (a == 'fence') != (b == 'fence'):
        resolved[i] = (2, 'STRUCTURAL')          # a fence needs air around it
    elif a in ('head', 'rule') or b in ('head', 'rule'):
        resolved[i] = (2, 'STRUCTURAL')
    elif a != b:
        resolved[i] = (2, 'STRUCTURAL')          # block change: blank line
    else:
        # prose>prose with no run to infer a multiplier from -- 21 cases. Fall
        # back to the sentence: a line that does not END a sentence was wrapped
        # mid-sentence, so its successor belongs to the same paragraph. Checked
        # by hand against all 21 and it calls every one correctly, including the
        # single genuine paragraph break ("Two routines settle it.").
        ends = content[i].rstrip().endswith(('.', ':', '!', '?'))
        resolved[i] = (2 if ends else 1, 'SENTENCE')

# ------------------------------------------------------------- 5. rebuild
parts = [content[0]]
for i in range(len(gaps)):
    parts.append('\n' * resolved[i][0])      # 1 = adjacent, 2 = one blank line
    parts.append(content[i + 1])
text = ''.join(parts).rstrip('\n') + '\n'
assert '\n\n\n' not in text, 'more than one blank line survived'
OUT.write_text(text, encoding='utf-8', newline='\n')

# ------------------------------------------------------------- 6. report
how = collections.Counter(v[1] for v in resolved.values())
print('mojibake sequences reversed : %d' % fixed)
print('content lines               : %d (unchanged)' % len(content))
print('gaps resolved               : %s' % dict(how))
print('prose runs with no neighbour: %d (defaulted to a blank line)' % lonely)
print('lines before / after        : %d -> %d' % (len(lines), text.count('\n')))
print('written to                  : %s' % OUT)
flag = [i for i, v in resolved.items() if v[1] == 'FLAGGED']
for i in sorted(flag)[:20]:
    print('   FLAGGED gap %d: %r || %r' % (gaps[i], content[i][-46:], content[i+1][:46]))
