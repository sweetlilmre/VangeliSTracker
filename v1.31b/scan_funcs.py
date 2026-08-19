"""Enumerate likely procedure entry points in the unpacked DemoVT image.

Borland Pascal 6 emits one of two prologues for a framed routine:

    55 89 E5              PUSH BP / MOV BP,SP        no locals
    C8 nn nn 00           ENTER nn,0                 with locals

and ends on RETF (CB), RETF imm16 (CA nn nn), RET (C3) or RET imm16 (C2 nn nn),
usually preceded by LEAVE (C9) or POP BP (5D).

Scanning for those beats guessing an offset: several segments do not begin on
an instruction boundary, so disassembling from :0000 desyncs.
"""
import pathlib, struct, re, sys
import refpath

IMG = refpath.ORIG
BASE = 0x1000

SEGS = [
 (0x1000,0x0655),(0x1065,0x01f0),(0x1084,0x0180),(0x109c,0x0ce0),(0x116a,0x0040),
 (0x116e,0x04d0),(0x11bb,0x0ff0),(0x12ba,0x1750),(0x142f,0x0880),(0x14b7,0x0020),
 (0x14b9,0x08b0),(0x1544,0x0090),(0x154d,0x0f50),(0x1642,0x0090),(0x164b,0x0050),
 (0x1650,0x00a0),(0x165a,0x0c90),(0x1723,0x0ac0),(0x17cf,0x0b10),(0x1880,0x00f0),
 (0x188f,0x0020),(0x1891,0x0a00),(0x1931,0x009e),(0x193a,0x0660),(0x19a0,0x0771),
 (0x1a17,0x10d0),(0x1b24,0x0300),(0x1b54,0x01b0),(0x1b6f,0x0320),(0x1ba1,0x1090),
 (0x1caa,0x0c70),
]

d = IMG.read_bytes()
hs = struct.unpack_from('<H', d, 8)[0]*16
img = d[hs:]

def scan(seg, size):
    base = seg*16 - (BASE*16 - 0x0000) + 0x10000 - 0x10000
    base = seg*16 - 0x10000
    out = []
    i = 0
    while i < size - 3:
        b = img[base+i:base+i+4]
        if b[:3] == b'\x55\x89\xe5':
            out.append((i, 'PUSH BP'))
            i += 3; continue
        if b[0] == 0xC8 and b[3] == 0x00:
            out.append((i, 'ENTER $%03x' % struct.unpack_from('<H', b, 1)[0]))
            i += 4; continue
        i += 1
    return out

want = sys.argv[1:] if len(sys.argv) > 1 else None
total = 0
for seg, size in SEGS:
    if want and ('%04x' % seg) not in want: continue
    f = scan(seg, size)
    total += len(f)
    print("== %04x  (%d bytes)  %d entry points" % (seg, size, len(f)))
    if want:
        for off, kind in f:
            print("     %04x:%04x  %s" % (seg, off, kind))
if not want:
    print("\ntotal entry points found:", total)
