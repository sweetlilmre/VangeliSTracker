#!/usr/bin/env python3
"""Emit the gain ladder of DemoVT segment 1a17 as Turbo Pascal assembler.

    python emit_gain.py > src/VTGAIN.INC

WHY THIS IS GENERATED AND NOT HAND-WRITTEN.  1a17:0746..0a80 is 315 bytes of
48 tiny near routines plus three 16-entry pointer tables plus a patch area.
Every routine is drawn from a five-instruction vocabulary and every table
entry must agree with a routine's address.  Transcribing that by hand from a
hex dump is a hundred chances to be quietly wrong, and a single wrong entry
would send the mixer into the middle of an instruction.  So the bytes are read
back out of the unpacked image and decoded here, which makes the .INC a
mechanical consequence of the binary rather than of my typing.

This is the same reasoning as tools/emit_p6text.py in the main project.

WHAT THE LADDER IS.  Each cell applies a gain to EAX using EBX as scratch,
by shifting and adding, and returns.  Cell 0 of every family is a bare RET --
unity, no adjustment.

    family 1  1a17:0746  SAR EBX,n / SUB EAX,EBX   attenuate, gain (16-k)/16
    family 2  1a17:085e  SAR EBX,n / ADD EAX,EBX   boost, gain (16+k)/16
    family 3  1a17:0976  SHL EBX,n / ADD EAX,EBX   amplify, gain bitrev4(k)+1

THE BIT-REVERSAL CANCELS.  Family 3's gains are stored in bit-reversed order
-- entry k is gain bitrev4(k)+1, not k+1 -- and SetGains looks that table up
through the permutation at 1a17:0a71.  Bit reversal is an involution, so
T3[bitrev(v)] is gain v+1: a clean integer ladder 1..16.  The cells sit in
memory in the order the shift-and-add construction emits them, which is
bit-reversed by gain; rather than reorder two hundred bytes of code, the
author permuted the index instead.  Both halves are asserted below.

The 386 instructions are emitted as an explicit 66h prefix in front of Turbo
Pascal's 16-bit mnemonic.  That is byte-identical here because none of the
five instructions involved has an immediate whose width the prefix changes --
see docs/06-transcription.md.  Turbo Pascal 7's built-in assembler is
286-only, so this is the only way to get 386 code into a .PAS file without a
separate TASM step.

The output is verified against the image byte-for-byte before it is printed;
if the reassembled bytes differ, this script fails rather than emitting
something plausible.
"""

import struct
import re
import sys
import pathlib
from fractions import Fraction

IMAGE = pathlib.Path(__file__).resolve().parent.parent / "work" / "unpack" / "NEUROSIS_008_unpacked.exe"
SEG = 0x1A17

# Where each family's cells live, and where its pointer table lives.  Read out
# of the image; see docs/04-units.md.  The tables are what SetGains (1a17:0a81)
# indexes, so these three pairs are the ground truth for the whole region.
FAMILIES = [
    ("G1", 0x0746, 0x083E, 0x083E),   # cells, ---, table   (cells run up to the table)
    ("G2", 0x085E, 0x0956, 0x0956),
    ("G3", 0x0976, 0x0A41, 0x0A41),
]

PATCH = 0x0A61          # eight words, all initially the family-1 unity cell
BITREV = 0x0A71         # sixteen bytes, the 4-bit bit-reversal permutation
END = 0x0A81


def load():
    d = IMAGE.read_bytes()
    base = struct.unpack_from("<H", d, 8)[0] * 16
    start = base + SEG * 16 - 0x10000
    return d[start:start + 0x1100]


# ---------------------------------------------------------------------------
# The five-instruction vocabulary.  Each entry maps exact bytes to the Turbo
# Pascal source that reproduces them.  Anything outside this set is a decode
# failure and stops the script -- there is no "best effort" here.
# ---------------------------------------------------------------------------
# THREE OF THE FIVE ARE EMITTED AS EXPLICIT BYTES, and the reason is measured
# rather than guessed: Turbo Pascal 7 assembles the mnemonic to a DIFFERENT
# ENCODING of the same instruction than the original's assembler chose, and
# that is invisible in the source.
#
#   written        TP7 emits    the original has
#   RET            CB  (RETF)   C3  -- a written RET inside a FAR procedure
#                               becomes a far return, and every cell ends near
#   SUB AX,BX      29 D8        2B C3  -- the other direction of the same op
#   ADD AX,BX      01 D8        03 C3  -- likewise
#
# The shift forms DO agree, so they keep their mnemonics; they are the readable
# majority and the ones worth reading. This was worth 80 bytes of the cells.
def decode(b, i):
    if b[i] == 0xC3:
        return 1, "DB 0C3h", "return -- NEAR, see the note above"
    if b[i] != 0x66:
        return None
    op = b[i + 1]
    if op == 0xC1 and b[i + 2] in (0xFB, 0xE3):
        n = b[i + 3]
        if b[i + 2] == 0xFB:
            return 4, "DB 66h; SAR BX,%d" % n, "EBX := EBX shr %d (signed)" % n
        return 4, "DB 66h; SHL BX,%d" % n, "EBX := EBX shl %d" % n
    if op == 0xD1 and b[i + 2] in (0xFB, 0xE3):
        if b[i + 2] == 0xFB:
            return 3, "DB 66h; SAR BX,1", "EBX := EBX shr 1 (signed)"
        return 3, "DB 66h; SHL BX,1", "EBX := EBX shl 1"
    if op == 0x2B and b[i + 2] == 0xC3:
        return 3, "DB 66h, 2Bh, 0C3h", "EAX := EAX - EBX"
    if op == 0x03 and b[i + 2] == 0xC3:
        return 3, "DB 66h, 03h, 0C3h", "EAX := EAX + EBX"
    return None


def gain_of(b, lo, hi):
    """Work out the cell's gain as an exact fraction, by interpreting it."""
    a, x = Fraction(1), Fraction(1)     # EAX = 1*v, EBX = 1*v
    i = lo
    while i < hi:
        got = decode(b, i)
        if got is None:
            return None
        n, src, _ = got
        if "SAR BX,1" in src:
            x /= 2
        elif "SAR BX," in src:
            x /= 2 ** int(src.split(",")[1])
        elif "SHL BX,1" in src:
            x *= 2
        elif "SHL BX," in src:
            x *= 2 ** int(src.split(",")[1])
        elif "2Bh" in src:
            a -= x
        elif "03h" in src:
            a += x
        i += n
    return a


MIXER = r'''
  { ==================================================================
    1a17:0b2a .. 1a17:0c00 -- THE TWO FILTER CHAINS AND THEIR WRAPPER.

    Still inside this procedure: these reach their gain cells through
    @@Patch above, and labels do not cross procedures.

    WHAT EACH CHAIN COMPUTES. A two-tap filter built entirely out of the
    patched gain cells -- there is no multiply anywhere in it:

        a := Gain_0(sample)      first tap, on the new sample
        b := Gain_1(a)
        c := Gain_2(previous)    second tap, on the held-over one
        d := Gain_3(c)
        result := (b + d) shr 2  then clamped to signed 16 bits

    THE PREVIOUS SAMPLE LIVES IN THE INSTRUCTION STREAM. 0b2f loads it as
    a 32-bit IMMEDIATE and 0b3a writes the new one back over those four
    bytes. So the filter state is not in DGROUP and not in a register
    across calls -- it is the constant the next call will load, which
    costs no memory reference to read. Same instinct as the shared poll's
    guard byte at CS:$104b, for speed rather than for hiding.

    THE CLAMP READS BACKWARDS. The fast path is CMP / JNB / RET: one
    comparison and a one-byte jump over the return for the overwhelmingly
    common in-range case. Only a value at or above $8000 falls through to
    the second test, which separates real overflow from a negative number
    that merely looks large unsigned.

    WHY SO MANY DB. Turbo Pascal assembles several of these mnemonics to a
    different ENCODING of the same instruction than the original's
    assembler chose -- see the note on the cells above, and note that a
    written RET here would come out CB rather than C3 because this
    procedure is far. The bytes are explicit and the mnemonic is in the
    comment. Jumps and near calls keep their labels: those displacements
    are self-relative, so they are the compiler's to compute.
    ================================================================== }

  { ---- chain A, slots 0..3 ----------------------------------------- }
@@FilterA:
    DB 66h, 98h              { 0b2a  CWDE -- sign-extend AX into EAX }
    DB 66h, 8Bh, 0C8h        { 0b2c  MOV  ECX,EAX -- keep the sample }
    DB 66h, 0BBh             { 0b2f  MOV  EBX,imm32 ... }
@@PrevA1:
    DD -1                    { 0b31  ... and the immediate IS the state }
    DB 2Eh, 0FFh, 16h        { 0b35  CALL WORD PTR CS:[@@Patch] }
    DW OFFSET @@Patch
    DB 66h, 2Eh, 0A3h        { 0b3a  MOV  CS:[@@PrevA1],EAX }
    DW OFFSET @@PrevA1
    DB 66h, 8Bh, 0D8h        { 0b3f  MOV  EBX,EAX }
    DB 2Eh, 0FFh, 16h        { 0b42  CALL WORD PTR CS:[@@Patch+2] }
    DW OFFSET @@Patch+2
    DB 66h, 91h              { 0b47  XCHG EAX,ECX }
    DB 66h, 0BBh             { 0b49  MOV  EBX,imm32 ... }
@@PrevA2:
    DD -1                    { 0b4b  ... the second tap's state }
    DB 2Eh, 0FFh, 16h        { 0b4f  CALL WORD PTR CS:[@@Patch+4] }
    DW OFFSET @@Patch+4
    DB 66h, 2Eh, 0A3h        { 0b54  MOV  CS:[@@PrevA2],EAX }
    DW OFFSET @@PrevA2
    DB 66h, 8Bh, 0D8h        { 0b59  MOV  EBX,EAX }
    DB 2Eh, 0FFh, 16h        { 0b5c  CALL WORD PTR CS:[@@Patch+6] }
    DW OFFSET @@Patch+6
    DB 66h, 03h, 0C1h        { 0b61  ADD  EAX,ECX -- the two taps }
    DB 66h, 0C1h, 0F8h, 02h  { 0b64  SAR  EAX,2 }
    DB 66h, 3Dh              { 0b68  CMP  EAX,00008000h }
    DD 8000h
    JNB     @@ClampA         { 0b6e  out of range -- go and sort it }
@@DoneA:
    DB 0C3h                  { 0b70  RET -- NEAR, the common path }
@@ClampA:
    DB 66h, 3Dh              { 0b71  CMP  EAX,FFFF8000h }
    DD 0FFFF8000h
    JNB     @@DoneA          { 0b77  negative but in range after all }
    DB 66h, 23h, 0C0h        { 0b79  AND  EAX,EAX -- test the sign }
    JS      @@LowA           { 0b7c }
    DB 66h, 0B8h             { 0b7e  MOV  EAX,00007FFFh }
    DD 7FFFh
    JMP     @@DoneA          { 0b84 }
@@LowA:
    DB 66h, 0B8h             { 0b86  MOV  EAX,FFFF8000h }
    DD 0FFFF8000h
    JMP     @@DoneA          { 0b8c }

  { ---- chain B, slots 4..7 -- the same again ----------------------- }
@@FilterB:
    DB 66h, 98h              { 0b8e  CWDE }
    DB 66h, 8Bh, 0C8h        { 0b90  MOV  ECX,EAX }
    DB 66h, 0BBh             { 0b93  MOV  EBX,imm32 ... }
@@PrevB1:
    DD -1                    { 0b95 }
    DB 2Eh, 0FFh, 16h        { 0b99  CALL WORD PTR CS:[@@Patch+8] }
    DW OFFSET @@Patch+8
    DB 66h, 2Eh, 0A3h        { 0b9e  MOV  CS:[@@PrevB1],EAX }
    DW OFFSET @@PrevB1
    DB 66h, 8Bh, 0D8h        { 0ba3  MOV  EBX,EAX }
    DB 2Eh, 0FFh, 16h        { 0ba6  CALL WORD PTR CS:[@@Patch+10] }
    DW OFFSET @@Patch+10
    DB 66h, 91h              { 0bab  XCHG EAX,ECX }
    DB 66h, 0BBh             { 0bad  MOV  EBX,imm32 ... }
@@PrevB2:
    DD -1                    { 0baf }
    DB 2Eh, 0FFh, 16h        { 0bb3  CALL WORD PTR CS:[@@Patch+12] }
    DW OFFSET @@Patch+12
    DB 66h, 2Eh, 0A3h        { 0bb8  MOV  CS:[@@PrevB2],EAX }
    DW OFFSET @@PrevB2
    DB 66h, 8Bh, 0D8h        { 0bbd  MOV  EBX,EAX }
    DB 2Eh, 0FFh, 16h        { 0bc0  CALL WORD PTR CS:[@@Patch+14] }
    DW OFFSET @@Patch+14
    DB 66h, 03h, 0C1h        { 0bc5  ADD  EAX,ECX }
    DB 66h, 0C1h, 0F8h, 02h  { 0bc8  SAR  EAX,2 }
    DB 66h, 3Dh              { 0bcc  CMP  EAX,00008000h }
    DD 8000h
    JNB     @@ClampB         { 0bd2 }
@@DoneB:
    DB 0C3h                  { 0bd4  RET -- NEAR }
@@ClampB:
    DB 66h, 3Dh              { 0bd5  CMP  EAX,FFFF8000h }
    DD 0FFFF8000h
    JNB     @@DoneB          { 0bdb }
    DB 66h, 23h, 0C0h        { 0bdd  AND  EAX,EAX }
    JS      @@LowB           { 0be0 }
    DB 66h, 0B8h             { 0be2  MOV  EAX,00007FFFh }
    DD 7FFFh
    JMP     @@DoneB          { 0be8 }
@@LowB:
    DB 66h, 0B8h             { 0bea  MOV  EAX,FFFF8000h }
    DD 0FFFF8000h
    JMP     @@DoneB          { 0bf0 }

  { 1a17:0bf2 -- run a pair through both chains.

    AX carries one sample and BX the other, in and out. All the shuffling
    is because both chains take their input in AX and return it there: BX
    is parked on the stack across the first call, then swapped in for the
    second while the first result takes its place.

    The final RET is Pascal's own epilogue rather than a written one -- an
    `assembler` procedure always gets one, so writing it would emit a
    second. That is also what puts a NEAR-looking C3 at 0c00 even though
    this procedure is far: it is the procedure's own return. }
@@FilterPair:
    DB 53h                   { 0bf2  PUSH BX -- park the second sample }
    CALL    @@FilterA        { 0bf3 }
    DB 5Bh                   { 0bf6  POP  BX }
    DB 50h                   { 0bf7  PUSH AX -- park the first result }
    DB 8Bh, 0C3h             { 0bf8  MOV  AX,BX }
    CALL    @@FilterB        { 0bfa }
    DB 8Bh, 0D8h             { 0bfd  MOV  BX,AX }
    DB 58h                   { 0bff  POP  AX }
    DB 0C3h                  { 0c00  RET -- NEAR, and explicit now that the }
                             {       downmix follows. It was the procedure's }
                             {       own epilogue while this was the last }
                             {       block, which is how the RETF-vs-RET }
                             {       problem surfaced here. }
'''


DOWNMIX_HEAD = r'''
  { ==================================================================
    1a17:0c7e -- THE 32-WAY UNROLLED DOWNMIX. Frameless; falls into the
    filter chain above by a tail JMP.

    SI walks a row of 32 channel samples, words, and the row is summed
    into two accumulators. Which accumulator a channel goes to follows
    `n mod 4`: 0 and 3 to AX, 1 and 2 to BX. That is a four-channel
    panning interleave, not an alternation -- reading it as one is the
    easy mistake.

    THREE OF THE CONFIGURATOR'S NINE PATCH SITES ARE IN HERE, and between
    them they remove every per-sample decision from the loop:

      @@UnrollEntry  0c83  the displacement of the JMP at 0c82. The
                           configurator writes (32 - Channels) * 3, which
                           skips exactly the ADDs for channels that are
                           not there. THE CHANNEL COUNT COSTS NOTHING --
                           no counter, no compare, no branch.
      @@Stride       0ce3  the immediate of ADD SI, so advancing to the
                           next row is one instruction whatever the width.
      @@FilterSwitch 0cf6  either 90h or C3h. A NOP falls through into
                           the filter chain; a RET returns instead. That
                           is how a whole filter stage is switched off
                           without a test.

    THE SATURATING ADD AT 0ce8 USES THE OVERFLOW DIRECTION. After ADD
    AX,BX, JNO takes the common path. On overflow the stored sign is the
    INVERSE of the true one, so SF set means the true result was too
    POSITIVE -- hence JS goes to 7FFFh and the fall-through to 8001h.

    Note 8001h, not 8000h. One off the true minimum, and consistently so;
    presumably to keep the range symmetric about zero.
    ================================================================== }
@@DownMix:
    DB 8Bh, 04h              { 0c7e  MOV  AX,[SI] -- channel 0 }
    DB 33h, 0DBh             { 0c80  XOR  BX,BX }
    DB 0EBh                  { 0c82  JMP  SHORT ... }
@@UnrollEntry:
    DB 0                     { 0c83  ... and the displacement is patched }
'''

DOWNMIX_TAIL = r'''    DB 81h, 0C6h             { 0ce1  ADD  SI,imm16 ... }
@@Stride:
    DW 1234h                 { 0ce3  ... the row stride, patched }
    DB 0E9h                  { 0ce5  JMP  NEAR ... }
@@MethodJmp:
    DW 0FA5Dh                { 0ce6  ... displacement patched to one of }
                             {       0, 12h, 30h or 5Ah -- the mixing }
                             {       method. The value here is the }
                             {       original's own unpatched one; it }
                             {       resolves to 0745, which is a RETF, }
                             {       so an unconfigured mixer returns. }
                             {       Emitted verbatim either way. }
    DB 03h, 0C3h             { 0ce8  ADD  AX,BX -- the two accumulators }
    JNO     @@Saturated      { 0cea  the common path }
    JS      @@TooHigh        { 0cec  sign INVERTED by the overflow }
    DB 0B8h, 01h, 80h        { 0cee  MOV  AX,8001h -- see the note }
    JMP     @@Saturated      { 0cf1 }
@@TooHigh:
    DB 0B8h, 0FFh, 7Fh       { 0cf3  MOV  AX,7FFFh }
@@Saturated:
@@FilterSwitch:
    DB 90h                   { 0cf6  NOP or C3h -- the filter switch }
    JMP     @@FilterA        { 0cf7  tail call into the filter chain }
'''


def downmix_adds():
    """The downmix's 31 ADDs -- channels 31 down to 1. It zeroes BX and loads
    channel 0 directly, where the mono loop primes both and starts at 2."""
    return add_run(31, 1, 0x0C84)


def satclamp(reg, pc):
    """The 12-byte clamp that follows every arithmetic step in the kernels.

        JNO  +0Ah        the common path -- nothing to do
        JS   +05h        SF is INVERTED by the overflow, so set means the
                         true result was too POSITIVE
        MOV  reg,8001h   too negative
        JMP  +03h
        MOV  reg,7FFFh   too positive

    The three displacements are self-relative constants and never change, so
    they are literals; there are seven of these and naming three labels apiece
    would bury the shape. 8001h rather than 8000h throughout -- see the note on
    the downmix.
    """
    mov = {"AX": "0B8h", "BX": "0BBh", "CX": "0B9h", "DX": "0BAh"}[reg]
    return [
        "    DB 71h, 0Ah              { %04x  JNO  -- in range, done }" % pc,
        "    DB 78h, 05h              { %04x  JS   -- too high, see above }" % (pc + 2),
        "    DB %s, 01h, 80h        { %04x  MOV  %s,8001h }" % (mov, pc + 4, reg),
        "    DB 0EBh, 03h             { %04x  JMP  past the other arm }" % (pc + 7),
        "    DB %s, 0FFh, 7Fh       { %04x  MOV  %s,7FFFh }" % (mov, pc + 9, reg),
    ]


METHODS_HEAD = r"""
  { ==================================================================
    1a17:0cfa, 0d18 and 0d42 -- THE OTHER THREE MIXING METHODS.

    @@MethodJmp above selects between these by displacement: 0 falls
    straight through to the mono path at 0ce8, and 12h, 30h and 5Ah land
    here. All three end at @@StereoTail, which tail-calls the filter PAIR
    rather than the single chain the mono path uses.

    Every arithmetic step is followed by the same 12-byte clamp; see
    satclamp() in emit_gain.py for what it does and why its displacements
    are literals.

    METHOD 1, 0cfa -- double each side independently. The cheapest way to
    make up the headroom the accumulators were summed with.

    METHOD 2, 0d18 -- cross-feed by an EXACT 17-BIT AVERAGE, and this is
    the piece worth stopping on:

        MOV DX,AX / ADD DX,BX / JNO +4 / RCR DX,1 / JMP +2 / SAR DX,1

    A signed 16-bit sum of two 16-bit values needs 17 bits. When it
    overflows, the seventeenth bit is in CF -- so RCR rotates it back in as
    the new top bit and the halved result is EXACT rather than clamped.
    Where there was no overflow, SAR halves and preserves the sign. Two
    instructions and a branch to get a correct average with no widening.

    METHOD 3, 0d42 -- halve both sides first, then cross-feed 1.5x of
    their sum: DX := (AX+BX); DX := DX + DX shr 1. The pre-halving is what
    buys the room for the 1.5.
    ================================================================== }
"""

METHODS_TAIL = r"""@@FilterSwitch2:
    DB 90h                   { 0d78  NOP or C3h -- the same switch as }
                             {       0cf6, written by the same store }
    JMP     @@FilterPair     { 0d79  tail call -- BOTH chains, not one }
"""


def method_lines():
    out = METHODS_HEAD.rstrip("\n").split("\n")
    # Method 1, 0cfa -- double each side.
    out.append("@@Method1:")
    out.append("    DB 03h, 0DBh             { 0cfa  ADD  BX,BX }")
    out += satclamp("BX", 0x0CFC)
    out.append("    DB 03h, 0C0h             { 0d08  ADD  AX,AX }")
    out += satclamp("AX", 0x0D0A)
    out.append("    JMP     @@FilterSwitch2  { 0d16 }")
    # Method 2, 0d18 -- exact 17-bit average, then cross-feed.
    out.append("@@Method2:")
    out.append("    DB 8Bh, 0D0h             { 0d18  MOV  DX,AX }")
    out.append("    DB 03h, 0D3h             { 0d1a  ADD  DX,BX -- 17 bits }")
    out.append("    DB 71h, 04h              { 0d1c  JNO  -- it fitted }")
    out.append("    DB 0D1h, 0DAh            { 0d1e  RCR  DX,1 -- CF is bit 16 }")
    out.append("    DB 0EBh, 02h             { 0d20  JMP }")
    out.append("    DB 0D1h, 0FAh            { 0d22  SAR  DX,1 -- signed halve }")
    out.append("    DB 03h, 0C2h             { 0d24  ADD  AX,DX }")
    out += satclamp("AX", 0x0D26)
    out.append("    DB 03h, 0DAh             { 0d32  ADD  BX,DX }")
    out += satclamp("BX", 0x0D34)
    out.append("    JMP     @@FilterSwitch2  { 0d40 }")
    # Method 3, 0d42 -- halve, then cross-feed 1.5x.
    out.append("@@Method3:")
    out.append("    DB 0D1h, 0F8h            { 0d42  SAR  AX,1 }")
    out.append("    DB 0D1h, 0FBh            { 0d44  SAR  BX,1 }")
    out.append("    DB 8Bh, 0D0h             { 0d46  MOV  DX,AX }")
    out.append("    DB 03h, 0D3h             { 0d48  ADD  DX,BX }")
    out.append("    DB 8Bh, 0CAh             { 0d4a  MOV  CX,DX -- keep the sum }")
    out.append("    DB 0D1h, 0FAh            { 0d4c  SAR  DX,1 }")
    out.append("    DB 03h, 0D1h             { 0d4e  ADD  DX,CX -- 1.5x the sum }")
    out += satclamp("DX", 0x0D50)
    out.append("    DB 03h, 0C2h             { 0d5c  ADD  AX,DX }")
    out += satclamp("AX", 0x0D5E)
    out.append("    DB 03h, 0DAh             { 0d6a  ADD  BX,DX }")
    out += satclamp("BX", 0x0D6C)
    out += METHODS_TAIL.rstrip("\n").split("\n")
    return out


def add_run(first_ch, last_ch, pc):
    """The unrolled ADDs, channel `first_ch` down to `last_ch`.

    The accumulator follows n mod 4: 0 and 3 to AX, 1 and 2 to BX. Generated
    rather than typed -- one wrong modrm byte puts the kernel into the middle
    of an instruction, and there are sixty-one of these across the two loops.
    """
    out = []
    for n in range(first_ch, last_ch - 1, -1):
        reg = "AX" if n % 4 in (0, 3) else "BX"
        modrm = "44h" if reg == "AX" else "5Ch"
        out.append("    DB 03h, %-4s %02Xh        { %04x  ADD  %s,[SI+%02xh] -- ch %d }"
                   % (modrm + ",", 2 * n, pc, reg, 2 * n, n))
        pc += 3
    return out


MONO = r"""
  { ==================================================================
    1a17:0d7c -- THE MONO OUTPUT LOOP. This is what 1a17:1087 and 1090
    install at DS:$0c00, and what actually turns mixed channels into
    bytes for the card.

    Per sample: sum the 32 channels into two accumulators, add them,
    saturate, convert to unsigned, store one byte, advance. CX is the
    sample count and LOOP drives it.

    IT IS ENTERED AT THE BOTTOM. The JMP at 0d7d goes to @@MonoPrime,
    which loads channels 0 and 1 into the two accumulators before any
    ADD runs -- so the unrolled run covers channels 31 down to 2, THIRTY
    adds rather than thirty-one. Priming instead of zeroing saves two
    instructions per sample.

    TWO MORE PATCH SITES, AND THE SECOND IS THE NICE ONE:

      @@Stride2   0ddb  the row stride, as in the downmix.
      @@MonoLoop  0dee  THE DISPLACEMENT OF THE LOOP INSTRUCTION. The
                        configurator writes 3 * (32 - Channels) - 70h, so
                        the backward jump lands partway INTO the unrolled
                        run and the absent channels are never touched.
                        The loop's own branch target is the channel count.

    THE OUTPUT CONVERSION IS ONE INSTRUCTION. `XOR AH,80h` flips the sign
    bit of the high byte, which turns a signed 16-bit sample into the
    unsigned 8-bit one a DAC wants -- taking the high byte IS the
    downshift, so there is no shift at all. Then MOV ES:[DI],AH.
    ================================================================== }
@@MonoMix:
    DB 41h                   { 0d7c  INC  CX -- LOOP counts down }
    JMP     @@MonoPrime      { 0d7d  enter at the bottom, see above }
"""

MONO_TAIL = r"""    DB 81h, 0C6h             { 0dd9  ADD  SI,imm16 ... }
@@Stride2:
    DW 1234h                 { 0ddb  ... the row stride, patched }
    DB 03h, 0C3h             { 0ddd  ADD  AX,BX }
    JO      @@MonoClamp      { 0ddf }
@@MonoStore:
    DB 80h, 0F4h, 80h        { 0de1  XOR  AH,80h -- signed to unsigned, }
                             {       and the high byte IS the downshift }
    DB 26h, 88h, 25h         { 0de4  MOV  ES:[DI],AH -- one byte out }
    DB 47h                   { 0de7  INC  DI }
@@MonoPrime:
    DB 8Bh, 04h              { 0de8  MOV  AX,[SI]     -- channel 0 }
    DB 8Bh, 5Ch, 02h         { 0dea  MOV  BX,[SI+02h] -- channel 1 }
    DB 0E2h                  { 0ded  LOOP ... }
@@MonoLoop:
    DB 90h                   { 0dee  ... and the displacement is patched }
    DB 0C3h                  { 0def  RET -- NEAR }
@@MonoClamp:
    JNS     @@MonoLow        { 0df0  sign NOT inverted here: this tests }
                             {       the accumulated sign, not the sum's }
    DB 0B8h, 0FFh, 7Fh       { 0df2  MOV  AX,7FFFh }
    JMP     @@MonoStore      { 0df5 }
@@MonoLow:
    DB 0B8h, 01h, 80h        { 0df7  MOV  AX,8001h }
    JMP     @@MonoStore      { 0dfa }
"""


def mono_lines():
    out = MONO.rstrip("\n").split("\n")
    out += add_run(31, 2, 0x0D7F)
    out += MONO_TAIL.rstrip("\n").split("\n")
    return out


STEREO = r"""
  { ==================================================================
    1a17:0dfc -- THE STEREO OUTPUT LOOP. The other of the two routines
    1a17:1090 selects between; it installs this one when the card reports
    stereo and the mono loop at 0d7c otherwise.

    Same shape as the mono loop -- primed entry at the bottom, unrolled
    ADDs for channels 31 down to 2, LOOP driven by CX -- with the last
    two patch sites:

      @@Stride3      0e5b  the row stride.
      @@StereoLoop   0e72  the LOOP displacement, 3 * (32 - Channels) -
                           74h. Note 74h where the mono loop uses 70h:
                           this loop's tail is four bytes longer, so the
                           same "jump back into the unrolled run" needs a
                           different bias. Two constants, one for each
                           loop, and the configurator writes both.

    THERE IS NO SATURATION HERE, and that is the real difference from the
    mono path rather than the obvious one. AX and BX are not two halves of
    one signal to be summed -- they ARE the two channels, and the filter
    pair has already clamped both. So the loop goes straight from the row
    advance to the output conversion with no ADD and no clamp.

    THE PACK IS THREE INSTRUCTIONS. XOR AH,80h and XOR BH,80h convert both
    to unsigned, then MOV AL,AH / MOV AH,BH puts the left sample in AL and
    the right in AH, and one word store writes the pair. Taking the high
    bytes IS the downshift, as in the mono loop.
    ================================================================== }
@@StereoMix:
    DB 41h                   { 0dfc  INC  CX }
    JMP     @@StereoPrime    { 0dfd  enter at the bottom }
"""

STEREO_TAIL = r"""    DB 81h, 0C6h             { 0e59  ADD  SI,imm16 ... }
@@Stride3:
    DW 1234h                 { 0e5b  ... the row stride, patched }
    DB 80h, 0F4h, 80h        { 0e5d  XOR  AH,80h -- left to unsigned }
    DB 80h, 0F7h, 80h        { 0e60  XOR  BH,80h -- right }
    DB 8Ah, 0C4h             { 0e63  MOV  AL,AH -- left into the low byte }
    DB 8Ah, 0E7h             { 0e65  MOV  AH,BH -- right into the high }
    DB 26h, 89h, 05h         { 0e67  MOV  ES:[DI],AX -- both, one store }
    DB 47h                   { 0e6a  INC  DI }
    DB 47h                   { 0e6b  INC  DI }
@@StereoPrime:
    DB 8Bh, 04h              { 0e6c  MOV  AX,[SI]     -- channel 0 }
    DB 8Bh, 5Ch, 02h         { 0e6e  MOV  BX,[SI+02h] -- channel 1 }
    DB 0E2h                  { 0e71  LOOP ... }
@@StereoLoop:
    DB 8Ch                   { 0e72  ... displacement patched, bias 74h }
    DB 0C3h                  { 0e73  RET -- NEAR }

  { 1a17:0e74 -- ONE BYTE OF STATE, IN THE CODE SEGMENT AGAIN. Written by
    the routine at 0e75 through CS:, and it sits in the gap between that
    RET and the next entry point. The third place this unit keeps a
    variable inside the instruction stream, after the poll's guard at
    CS:$104b and the filter chains' four state immediates. }
@@Flag0e74:
    DB 0                     { 0e74 }
"""


def stereo_lines():
    out = STEREO.rstrip("\n").split("\n")
    out += add_run(31, 2, 0x0DFF)
    out += STEREO_TAIL.rstrip("\n").split("\n")
    return out


CONFIG = r"""
  { ==================================================================
    1a17:0c01 -- THE KERNEL CONFIGURATOR. Frameless, near, and the reason
    everything else in this run is shaped the way it is: it rewrites nine
    bytes and words of the kernels below so that the inner loops carry no
    configuration at all.

    From NumChannels it derives two numbers -- 3 * (32 - Channels), the
    length of the unrolled ADDs to skip, and Channels * 2, the row stride
    -- and writes them into five sites. Then it picks a mixing method by
    writing a JMP displacement, and switches the filter stage on or off by
    writing either C3h or 90h into two more.

    THE TWO LOOP BIASES DIFFER, 70h AND 74h, and that is not a typo: the
    stereo loop's tail is four bytes longer than the mono one's, so the
    same "jump back into the unrolled run" needs a different constant. Get
    them the same way round and one of the two loops reads four bytes into
    the middle of an instruction.

    THE NOP PAIRS after each JZ are the assembler's jump-sizing padding,
    the same as the two at 1a17:1018 in the shared poll -- a near
    conditional was reserved and the short form used. Transcribed verbatim
    because they are in the byte stream and every displacement here is
    measured past them.

    It ends by calling the gain patcher at 0a81, so one call configures
    both the kernels and the volumes.
    ================================================================== }
@@Configure:
    MOV     CX,NumChannels   { 0c01  how many channels are live }
    DB 0BAh, 20h, 00h        { 0c05  MOV  DX,32 }
    DB 2Bh, 0D1h             { 0c08  SUB  DX,CX -- how many are not }
    DB 8Bh, 0DAh             { 0c0a  MOV  BX,DX }
    DB 03h, 0D2h             { 0c0c  ADD  DX,DX }
    DB 03h, 0D3h             { 0c0e  ADD  DX,BX -- DX := 3 * (32 - N) }
    DB 03h, 0C9h             { 0c10  ADD  CX,CX -- CX := 2 * N }

    DB 2Eh, 88h, 16h         { 0c12  MOV  CS:[@@UnrollEntry],DL }
    DW OFFSET @@UnrollEntry
    DB 2Eh, 89h, 0Eh         { 0c17  MOV  CS:[@@Stride],CX }
    DW OFFSET @@Stride

    DB 8Bh, 0DAh             { 0c1c  MOV  BX,DX }
    DB 83h, 0EBh, 70h        { 0c1e  SUB  BX,70h -- the MONO bias }
    DB 90h                   { 0c21  NOP -- jump-sizing padding }
    DB 2Eh, 88h, 1Eh         { 0c22  MOV  CS:[@@MonoLoop],BL }
    DW OFFSET @@MonoLoop

    DB 8Bh, 0DAh             { 0c27  MOV  BX,DX }
    DB 83h, 0EBh, 74h        { 0c29  SUB  BX,74h -- the STEREO bias }
    DB 90h                   { 0c2c  NOP }
    DB 2Eh, 88h, 1Eh         { 0c2d  MOV  CS:[@@StereoLoop],BL }
    DW OFFSET @@StereoLoop

    DB 2Eh, 89h, 0Eh         { 0c32  MOV  CS:[@@Stride2],CX }
    DW OFFSET @@Stride2
    DB 2Eh, 89h, 0Eh         { 0c37  MOV  CS:[@@Stride3],CX }
    DW OFFSET @@Stride3

  { The mixing method, as a JMP displacement: 0, 12h, 30h or 5Ah. }
    MOV     DL,MixMethod     { 0c3c }
    DB 0BBh, 00h, 00h        { 0c40  MOV  BX,0 }
    DB 22h, 0D2h             { 0c43  AND  DL,DL }
    JZ      @@GotMethod      { 0c45 }
    DB 90h                   { 0c47  NOP }
    DB 90h                   { 0c48  NOP }
    DB 0BBh, 12h, 00h        { 0c49  MOV  BX,12h }
    DB 0FEh, 0CAh            { 0c4c  DEC  DL }
    JZ      @@GotMethod      { 0c4e }
    DB 90h                   { 0c50  NOP }
    DB 90h                   { 0c51  NOP }
    DB 0BBh, 30h, 00h        { 0c52  MOV  BX,30h }
    DB 0FEh, 0CAh            { 0c55  DEC  DL }
    JZ      @@GotMethod      { 0c57 }
    DB 90h                   { 0c59  NOP }
    DB 90h                   { 0c5a  NOP }
    DB 0BBh, 5Ah, 00h        { 0c5b  MOV  BX,5Ah }
@@GotMethod:
    DB 2Eh, 89h, 1Eh         { 0c5e  MOV  CS:[@@MethodJmp],BX }
    DW OFFSET @@MethodJmp

  { The filter switch: C3h returns, 90h falls through into the chain. }
    DB 0B4h, 0C3h            { 0c63  MOV  AH,0C3h -- RET, filters off }
    MOV     AL,DoBassPower   { 0c65 }
    DB 22h, 0C0h             { 0c68  AND  AL,AL }
    JZ      @@GotSwitch      { 0c6a }
    DB 90h                   { 0c6c  NOP }
    DB 90h                   { 0c6d  NOP }
    DB 0B4h, 90h             { 0c6e  MOV  AH,90h -- NOP, filters on }
@@GotSwitch:
    DB 2Eh, 88h, 26h         { 0c70  MOV  CS:[@@FilterSwitch],AH }
    DW OFFSET @@FilterSwitch
    DB 2Eh, 88h, 26h         { 0c75  MOV  CS:[@@FilterSwitch2],AH }
    DW OFFSET @@FilterSwitch2

    CALL    @@Patcher        { 0c7a  and the gains, while we are here }
    DB 0C3h                  { 0c7d  RET -- NEAR }
"""


FILL = r"""
  { ==================================================================
    1a17:0e75 -- THE BUFFER-FILL DRIVER. Frameless, near. Configures the
    kernels, then runs the installed output loop over as much of the DMA
    buffer as there is sample data for.

    IT REPURPOSES DS, AND THAT IS WHY THE SS: OVERRIDES ARE THERE.
    `LDS SI,Sounding` at 0e97 points DS at the SAMPLE DATA so the output
    loops can walk it with plain [SI] addressing -- which costs nothing in
    the inner loop and is the whole point. But DGROUP is then unreachable
    through DS, so every global touched after that line is read through
    SS: instead. SS and DS are the same segment in a Pascal program, so
    the override is free. Miss one and it reads the sample buffer as if it
    were the data segment.

    THE WRAP IS HANDLED AS TWO CALLS, NOT A MODULO. The buffer is
    circular; if this batch would run past the end, the first call writes
    as many whole samples as fit (0eb6 divides the remaining bytes by
    BytesPerSample to get that count), then DI is reset to the start and
    the second call writes the rest. Where it fits, 0ea4 jumps straight to
    the single call.

    Note the JC at 0e9e: the end-of-write address is computed as AX+DI and
    can carry out of 16 bits, which is a wrap too -- tested before the
    ordinary CMP, because CMP would compare a wrapped value and get it
    wrong.

    0eda IS WHERE ActualBuffer^.InUse IS CLEARED, and it answers a
    question left open by DoGetBuffer: 1.39b clears the flag when it
    RETIRES a block, 1.31's DoGetBuffer does not, and it is done here
    instead -- when the mixer has actually finished reading the block
    rather than when the queue moves on. Not the leak it looked like.
    ================================================================== }
@@FillBuffer:
    DB 32h, 0C0h             { 0e75  XOR  AL,AL }
    DB 2Eh, 0A2h             { 0e77  MOV  CS:[@@Flag0e74],AL -- clear it }
    DW OFFSET @@Flag0e74
    CALL    @@Configure      { 0e7b  the kernels and the gains }

    MOV     CX,SoundLeft     { 0e7e  how many samples are available }
    MOV     AL,BytesPerSample { 0e82 }
    DB 8Bh, 0D1h             { 0e85  MOV  DX,CX }
    DB 32h, 0E4h             { 0e87  XOR  AH,AH }
    DB 0F7h, 0E2h            { 0e89  MUL  DX -- bytes, not samples }

    LES     DI,DMABufferPtr  { 0e8b  where the mixer got to }
    MOV     BX,WORD PTR DMABuffer   { 0e8f  the buffer's offset }
    ADD     BX,DMABufferSize { 0e93  ... so BX is one past its end }
    LDS     SI,Sounding      { 0e97  DS NOW POINTS AT THE SAMPLES }
    DB 0FCh                  { 0e9b  CLD }

    DB 03h, 0C7h             { 0e9c  ADD  AX,DI -- where writing ends }
    JC      @@Split          { 0e9e  carried out of 16 bits: also a wrap }
    DB 90h                   { 0ea0  NOP -- jump-sizing padding }
    DB 90h                   { 0ea1  NOP }
    DB 3Bh, 0C3h             { 0ea2  CMP  AX,BX }
    JBE     @@OneGo          { 0ea4  it fits -- one call and done }
@@Split:
    DB 2Bh, 0DFh             { 0ea6  SUB  BX,DI -- bytes to the end }
    JZ      @@Wrap           { 0ea8  none, so start at the beginning }
    DB 51h                   { 0eaa  PUSH CX }
    DB 8Bh, 0C3h             { 0eab  MOV  AX,BX }
    DB 36h, 8Ah, 0Eh         { 0ead  MOV  CL,SS:[BytesPerSample] -- SS: }
    DW OFFSET BytesPerSample
    DB 32h, 0EDh             { 0eb2  XOR  CH,CH }
    DB 33h, 0D2h             { 0eb4  XOR  DX,DX }
    DB 0F7h, 0F1h            { 0eb6  DIV  CX -- whole samples that fit }
    DB 8Bh, 0C8h             { 0eb8  MOV  CX,AX }
    DB 51h                   { 0eba  PUSH CX }
    DB 36h, 0FFh, 16h        { 0ebb  CALL WORD PTR SS:[MixRut] }
    DW OFFSET MixRut
    DB 5Bh                   { 0ec0  POP  BX }
    DB 59h                   { 0ec1  POP  CX }
    DB 2Bh, 0CBh             { 0ec2  SUB  CX,BX -- what is left over }
@@Wrap:
    DB 36h, 8Bh, 3Eh         { 0ec4  MOV  DI,SS:[DMABuffer] -- rewind }
    DW OFFSET DMABuffer
@@OneGo:
    DB 36h, 0FFh, 16h        { 0ec9  CALL WORD PTR SS:[MixRut] }
    DW OFFSET MixRut

    DB 8Ch, 0D0h             { 0ece  MOV  AX,SS }
    DB 8Eh, 0D8h             { 0ed0  MOV  DS,AX -- DGROUP back }
    MOV     WORD PTR DMABufferPtr,DI
                             { 0ed2  remember where we got to -- the OFFSET }
                             {       half only, which is what 89 3E stores }
    LES     DI,ActualBuffer  { 0ed6 }
    DB 26h, 0C6h, 05h, 00h   { 0eda  MOV  BYTE PTR ES:[DI],0 -- InUse }
                             {       := FALSE; see the note above }
    DB 0C3h                  { 0ede  RET -- NEAR }
"""


PREP = r"""
  { ==================================================================
    1a17:0edf -- @@Prepare. What SharedPoll calls before the installed
    callback, and the routine whose absence has had the poll stubbed out
    since this unit was started.

    Two paths. On a DMA device (the flag at DS:$0bc7) it just fetches a
    buffer and clears the old one's InUse. Otherwise it works out how far
    the card has drained the DMA buffer, and if the play position has
    caught up with the mix position it calls @@FillBuffer to mix more.

    THE IDLE COUNTER AT 0f32 IS A GIVING-UP RULE, not a timer: the flag at
    @@Flag0e74 is incremented each time there is nothing to do, and once it
    reaches 20 the increment stops and DeviceIdling is set from it. So
    "idle" means twenty consecutive polls with no work, not a duration.
    ================================================================== }
@@Prepare:
    MOV     AL,IsDmaDevice   { 0edf }
    DB 22h, 0C0h             { 0ee2  AND  AL,AL }
    JNZ     @@PrepFetch      { 0ee4  the DMA path is much shorter }
    DB 90h                   { 0ee6  NOP -- jump-sizing padding }
    DB 90h                   { 0ee7  NOP }
    MOV     AX,SoundLeft     { 0ee8 }
    MOV     BL,DMABufferYet  { 0eeb }
    DB 22h, 0DBh             { 0eef  AND  BL,BL }
    JZ      @@PrepMark       { 0ef1 }
    DB 0Eh                   { 0ef3  PUSH CS -- the same-segment far call }
    CALL    NEAR PTR DoGetBuffer { 0ef4 }
    DB 90h                   { 0ef7  NOP }
@@PrepMark:
    DB 0B3h, 01h             { 0ef8  MOV  BL,1 }
    MOV     DMABufferYet,BL  { 0efa }

    DB 3Dh, 0Ah, 00h         { 0efe  CMP  AX,10 -- fewer than ten samples }
    JC      @@PrepIdle       { 0f01  ... is not worth mixing for }
    MOV     DL,BytesPerSample { 0f03 }
    DB 32h, 0F6h             { 0f07  XOR  DH,DH }
    DB 0F7h, 0E2h            { 0f09  MUL  DX -- samples to bytes }
    DB 50h                   { 0f0b  PUSH AX }
    CALL    GetDMACount      { 0f0c  where the card has drained to }
    MOV     BX,DMABufferSize { 0f0f }
    DB 2Bh, 0D8h             { 0f13  SUB  BX,AX -- bytes already played }
    ADD     BX,WORD PTR DMABuffer { 0f15  ... as an offset }
    DB 8Bh, 0CBh             { 0f19  MOV  CX,BX }
    SUB     BX,WORD PTR DMABufferPtr { 0f1b  how far ahead the mixer is }
    DB 73h, 04h              { 0f1f  JNC -- no wrap }
    ADD     BX,DMABufferSize { 0f21  wrapped, so add a lap }
    DB 58h                   { 0f25  POP  AX }
    DB 2Bh, 0D8h             { 0f26  SUB  BX,AX }
    DB 0Fh, 83h, 49h, 0FFh   { 0f28  JNB @@FillBuffer -- a 386 NEAR }
                             {       conditional, out of short range. Its }
                             {       displacement is self-relative and both }
                             {       ends are in this run, so it is a literal }
    DB 32h, 0DBh             { 0f2c  XOR  BL,BL }
    MOV     DMABufferYet,BL  { 0f2e }
@@PrepIdle:
    DB 2Eh, 0A0h             { 0f32  MOV  AL,CS:[@@Flag0e74] }
    DW OFFSET @@Flag0e74
    DB 3Ch, 14h              { 0f36  CMP  AL,20 }
    JNC     @@PrepDone       { 0f38  already given up }
    DB 90h                   { 0f3a  NOP }
    DB 90h                   { 0f3b  NOP }
    DB 2Eh, 0FEh, 06h        { 0f3c  INC  BYTE PTR CS:[@@Flag0e74] }
    DW OFFSET @@Flag0e74
@@PrepDone:
    MOV     DeviceIdling,AL  { 0f41 }
    DB 0C3h                  { 0f44  RET -- NEAR }
@@PrepFetch:
    DB 0Eh                   { 0f45  PUSH CS }
    CALL    NEAR PTR DoGetBuffer { 0f46 }
    DB 90h                   { 0f49  NOP }
    LES     DI,ActualBuffer  { 0f4a }
    DB 26h, 0C6h, 05h, 00h   { 0f4e  MOV  BYTE PTR ES:[DI],0 -- InUse }
    DB 0C3h                  { 0f52  RET -- NEAR }

  { ==================================================================
    1a17:0f53 -- THE INT 8 HANDLER. Its middle is a CHAIN THROUGH THE
    DISPATCH TABLE at DS:$0bf8..$0bfe, which 1a17:1087/1090 fill, so the
    same handler serves a direct DAC and a DMA card without a test:

        0f53  entry, save, set DS   JMP [0bf8] -> 0f64
        0f64  one sample left?      JMP [0bfa] -> 104d
        104d  wait, DSP command     JMP           0f73
        0f73  mix one sample        JMP [0bfc] -> 1063
        1063  wait, write the byte  JMP           0f8d
        0f8d  the tail below

    Every step is a JMP, never a CALL, so there is no return path to
    unwind -- the chain simply ends at the tail, which does the periodic
    bookkeeping and IRETs.
    ================================================================== }
@@Int8:
    DB 0FAh                  { 0f53  CLI }
    DB 50h                   { 0f54  PUSH AX }
    DB 53h                   { 0f55  PUSH BX }
    DB 51h                   { 0f56  PUSH CX }
    DB 52h                   { 0f57  PUSH DX }
    DB 57h                   { 0f58  PUSH DI }
    DB 56h                   { 0f59  PUSH SI }
    DB 1Eh                   { 0f5a  PUSH DS }
    MOV     AX,SEG @DATA     { 0f5b  the original: MOV AX,1caa }
    DB 8Eh, 0D8h             { 0f5e  MOV  DS,AX }
    DB 0FFh, 26h             { 0f60  JMP  WORD PTR [OutSlot0] }
    DW OFFSET OutSlot0
@@Prim0:
    MOV     AX,SoundLeft     { 0f64 }
    DB 23h, 0C0h             { 0f67  AND  AX,AX }
    JZ      @@TimerTail      { 0f69  nothing to play }
    DB 48h                   { 0f6b  DEC  AX }
    MOV     SoundLeft,AX     { 0f6c }
    DB 0FFh, 26h             { 0f6f  JMP  WORD PTR [OutSlot1] }
    DW OFFSET OutSlot1
@@Prim2:
    DB 32h, 0FFh             { 0f73  XOR  BH,BH }
    MOV     DeviceIdling,BH  { 0f75  we are doing work }
    LDS     SI,Sounding      { 0f79  DS to the samples, as in the filler }
    CALL    @@DownMix        { 0f7d  ONE sample through the kernel }
    MOV     DX,SEG @DATA     { 0f80 }
    DB 8Eh, 0DAh             { 0f83  MOV  DS,DX -- DGROUP back }
    MOV     WORD PTR Sounding,SI { 0f85  remember the read position }
    DB 0FFh, 26h             { 0f89  JMP  WORD PTR [OutSlot2] }
    DW OFFSET OutSlot2

  { The tail. Reached from 1063, and the only path that returns. }
@@TimerTail:
    DB 0FBh                  { 0f8d  STI }
    MOV     AX,SystemClockIncr   { 0f8e }
    ADD     ClockAccum,AX    { 0f91  accumulate towards 18.2 Hz }
    JC      @@ChainOld       { 0f95  a whole BIOS tick has passed }
    DB 0B0h, 20h             { 0f97  MOV  AL,20h }
    DB 0E6h, 20h             { 0f99  OUT  20h,AL -- EOI }
@@AfterEoi:
    MOV     CX,PeriodicCount { 0f9b }
    DB 0E3h, 1Dh             { 0f9f  JCXZ @@Periodic }
    DB 49h                   { 0fa1  DEC  CX }
    MOV     PeriodicCount,CX { 0fa2 }
    JZ      @@Periodic       { 0fa6  it fired }
    MOV     AX,SoundLeft     { 0fa8 }
    DB 23h, 0C0h             { 0fab  AND  AX,AX }
    JZ      @@Periodic       { 0fad  out of samples -- go and get some }
@@Iret:
    DB 1Fh                   { 0faf  POP  DS }
    DB 5Eh                   { 0fb0  POP  SI }
    DB 5Fh                   { 0fb1  POP  DI }
    DB 5Ah                   { 0fb2  POP  DX }
    DB 59h                   { 0fb3  POP  CX }
    DB 5Bh                   { 0fb4  POP  BX }
    DB 58h                   { 0fb5  POP  AX }
    DB 0CFh                  { 0fb6  IRET }
@@ChainOld:
    DB 9Ch                   { 0fb7  PUSHF -- the old handler expects it }
    DB 0FFh, 1Eh             { 0fb8  CALLF [OldTimerHandler] }
    DW OFFSET OldTimerHandler
    JMP     @@AfterEoi       { 0fbc  PAST our EOI, not to it: the BIOS }
                             {       handler we just called has already }
                             {       acknowledged the interrupt, and a second }
                             {       OUT 20h,AL would end an interrupt that }
                             {       is not in service }

  { ==================================================================
    0fbe -- the periodic callback, behind a guard that lives IN THE CODE.

    @@Guard0fbf is the IMMEDIATE of the MOV AL at 0fbe, and 0fc6 writes
    over it. The fourth place this unit keeps state inside the instruction
    stream, after the poll's guard at CS:$104b, the filter chains' four
    sample immediates, and @@Flag0e74.

    It has to be a guard: the callback is a music interpreter that can run
    for a while, and the timer will fire again inside it.
    ================================================================== }
@@Periodic:
    DB 0B0h                  { 0fbe  MOV  AL,imm8 ... }
@@Guard0fbf:
    DB 0                     { 0fbf  ... and the immediate IS the guard }
    DB 22h, 0C0h             { 0fc0  AND  AL,AL }
    JNZ     @@Iret           { 0fc2  already inside -- just return }
    DB 0FEh, 0C0h            { 0fc4  INC  AL }
    DB 2Eh, 0A2h             { 0fc6  MOV  CS:[@@Guard0fbf],AL -- take it }
    DW OFFSET @@Guard0fbf

    MOV     AX,SoundLeft     { 0fca }
    DB 23h, 0C0h             { 0fcd  AND  AX,AX }
    JNZ     @@Release        { 0fcf  there is data -- nothing to fetch }
    CALL    @@Configure      { 0fd1 }
    DB 06h                   { 0fd4  PUSH ES }
    DB 0Eh                   { 0fd5  PUSH CS }
    CALL    NEAR PTR DoGetBuffer { 0fd6 }
    DB 90h                   { 0fd9  NOP }
    DB 07h                   { 0fda  POP  ES }
    CALL    @@Configure      { 0fdb  again: DoGetBuffer may have changed }
                             {       the rate, and the kernels encode it }
    MOV     AX,SoundLeft     { 0fde }
    DB 23h, 0C0h             { 0fe1  AND  AX,AX }
    JNZ     @@Release        { 0fe3 }
    DB 0FEh, 0C4h            { 0fe5  INC  AH }
    MOV     DeviceIdling,AH  { 0fe7  still nothing: idle }
@@Release:
    DB 2Eh, 0C6h, 06h        { 0feb  MOV  BYTE PTR CS:[@@Guard0fbf],0 }
    DW OFFSET @@Guard0fbf
    DB 00h

    MOV     AX,PeriodicCount { 0ff1 }
    DB 23h, 0C0h             { 0ff4  AND  AX,AX }
    JNZ     @@Done           { 0ff6  not due yet }
    MOV     AX,PeriodicStart { 0ff8 }
    MOV     PeriodicCount,AX { 0ffb  reload the countdown }
    DB 06h                   { 0ffe  PUSH ES }
    DB 0FBh                  { 0fff  STI -- the callback may take a while }
    DB 0FFh, 1Eh             { 1000  CALLF [PeriodicProc] }
    DW OFFSET PeriodicProc
    DB 07h                   { 1004  POP  ES }
@@Done:
    JMP     @@Iret           { 1005 }

  { 1007 -- one byte of padding in the original, and the ONE byte of this
    whole run that does not match. The run ends on an unconditional JMP and
    the original needs no return after it; Pascal emits a near RET there
    regardless -- confirmed in the probe, which shows the epilogue appearing
    after a trailing internal JMP, after a written RET and after pure data
    alike, so no arrangement of an `assembler` procedure suppresses it.

    The three bytes at 0746 that used to be the other half of this note are
    GONE: nothing calls SetGains by name, so the procedure never needed a
    reachable first instruction. This byte is what is left, and it is not a
    Pascal limitation either -- the original's 00 is the padding an external
    TASM module leaves when it aligns the next PUBLIC label. See the encoding
    table at the head of SOUNDDEV.PAS. One byte in 2,242. }
"""


def to_tasm(lines):
    """Turn the Turbo Pascal `asm` block this generator has always emitted into
    a TASM module body, INCLUDEd by SOUNDDEV.ASM.

    WHY THE RUN IS ASSEMBLED AND NOT COMPILED. 0746..10c3 is one frameless run
    in the original with three entry points and two different returns, and no
    Pascal procedure can be that: wrapping it cost an epilogue at 1007, another
    at 104d and a RETF 4 at 10c1. The original built it as an external TASM
    module linked with $L -- which is how the 1.39b release builds this same
    unit -- and the encodings prove it: 22 C0, 32 C0, 03 C0 and CA 04 00 are
    TASM's, and Turbo Pascal's inline assembler emits none of them. See
    docs/06-transcription.md.

    THE BYTES ARE NOT MEANT TO CHANGE. The DB-encoded instructions stay DBs
    even where TASM would now assemble the mnemonic correctly; converting them
    is a separate step with its own byte comparison, not something to bundle
    into a syntax change. What this does is only:

        { block comment }        ->  ; comment
        trailing { comment }     ->  ; comment
        procedure X; assembler;  ->  PUBLIC X / X:
        asm ... end;             ->  dropped

    Labels keep their `@@` names: with LOCALS off they are ordinary identifiers
    to TASM, and they have to be module-global here because SharedPoll below the
    include references @@Prepare inside it -- which as inline Pascal asm needed a
    hand-computed literal CALL displacement.
    """
    out, in_comment = [], False
    for line in lines:
        s = line.rstrip()
        if not in_comment:
            # a comment that opens and does not close on this line
            i = s.find("{")
            if i >= 0 and "}" not in s[i:]:
                in_comment = True
                out.append("; " + s[:i].rstrip() + s[i + 1:] if s[:i].strip() else "; " + s[i + 1:])
                continue
            if i >= 0:                      # opens and closes: trailing comment
                j = s.rindex("}")
                code, note = s[:i].rstrip(), s[i + 1:j].strip()
                if not code:
                    out.append("; " + note)
                    continue
                s = "%-42s ; %s" % (code, note) if note else code
        else:
            j = s.find("}")
            if j >= 0:
                in_comment = False
                s = s[:j].rstrip()
                out.append("; " + s if s.strip() else ";")
                continue
            out.append("; " + s if s.strip() else ";")
            continue

        # Pascal hex ($00) is not TASM hex. Only the data lines use it, and only
        # in the bit-reversal table, but the substitution is on every code line
        # so a later edit cannot reintroduce it quietly. The leading 0 is not
        # optional: TASM reads 0Ch as a number and Ch as an identifier.
        code, sep, note = s.partition(";")
        if "$" in code:
            code = re.sub(r"\$([0-9A-Fa-f]+)", lambda m: "0%sh" % m.group(1), code)
            s = code + sep + note

        # TURBO PASCAL'S STATEMENT SEPARATOR IS TASM'S COMMENT. The gain cells
        # are written `DB 66h; SAR BX,3` -- two statements on one line in Pascal
        # asm, and in TASM everything after the `;` is a comment, so every cell
        # lost its shift and the ladder came out as runs of bare 66h prefixes.
        # 188 divergent regions, from one character. Split them onto their own
        # lines and keep the note on the first.
        st = s.strip()
        if st and not st.startswith(";") and ";" in st:
            head, _, tail = s.partition(";")
            parts = [x.strip() for x in ([head] + tail.split(";"))]
            note = ""
            code_parts = []
            for k, part in enumerate(parts):
                if k and not re.match(r"(?i)^(DB|DW|DD|[A-Z]{2,6}\b)", part):
                    note = part            # the trailing comment, already converted
                    continue
                if part:
                    code_parts.append(part)
            if len(code_parts) > 1:
                pad = s[:len(s) - len(s.lstrip())]
                first = "%s%-42s ; %s" % (pad, code_parts[0], note) if note else pad + code_parts[0]
                out.append(first)
                for part in code_parts[1:]:
                    out.append(pad + part)
                continue

        st = s.strip()
        if st.startswith("procedure ") and "assembler" in st:
            name = st.split()[1].rstrip(";")
            out.append("")
            out.append("PUBLIC  %s" % name)
            out.append("%s:" % name)
            continue
        if st in ("asm", "end;"):
            continue
        out.append(s)
    return out


def main():
    b = load()

    # Cell boundaries.  These MUST come from decoding forwards, not from
    # scanning for C3: `66 2B C3` (SUB EAX,EBX) ends in C3 as its ModRM byte,
    # so a byte search finds 48 "cells" in a 16-cell family and every table
    # entry then disagrees.  Decode linearly; a cell ends at a real RET.
    def cells(lo, hi):
        out, i = [lo], lo
        while i < hi:
            got = decode(b, i)
            assert got is not None, "undecodable byte at 1a17:%04x" % i
            n, src, _ = got
            i += n
            if src == "DB 0C3h" and i < hi:
                out.append(i)
        return out

    out = []
    w = out.append
    w("{ ==========================================================================")
    w("  GENERATED by emit_gain.py -- DO NOT EDIT.")
    w("")
    w("  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).")
        w("")
    w("  1a17:0746..1a17:0b29 -- the gain ladder and its patcher, decoded from")
    w("  the image rather than typed.")
    w("")
    w("  THE WHOLE REGION IS ONE PROCEDURE, and it has to be. The patcher writes")
    w("  into the tables with MOV CS:[...] and the tables hold offsets of the")
    w("  cells; split across Pascal procedures the labels would not be in scope")
    w("  and the compiler would be free to reorder them, at which point every")
    w("  table entry lies.")
    w("")
    w("  THAT IS ALSO WHY THIS FILE HOLDS THE PROCEDURE AND NOT JUST THE DATA.")
    w("  Turbo Pascal 7 rejects an include directive inside an asm block (error")
    w("  118), so the")
    w("  include has to start outside one. The patcher below is a verbatim hand")
    w("  transcription of 1a17:0a81, carried here rather than in SOUNDDEV.PAS")
    w("  only so that it shares a scope with the labels it patches.")
    w("")
    w("  THE MIXER AT 1a17:0b2a WILL HAVE TO BE EMITTED FROM HERE TOO, and not")
    w("  from SOUNDDEV.PAS. It reaches its gain cells through")
    w("  CALL WORD PTR CS:[@@Patch+n], and @@Patch is a label in this file --")
    w("  labels are procedure-local, so the mixer has to share this procedure.")
    w("  Writing it in SOUNDDEV.PAS after the include does NOT work: TP7 gives")
    w("  error 10 for an asm block that does not close in the file it opened")
    w("  in, the mirror of the error-118 rule above. So when 0b2a is")
    w("  transcribed, it goes in this generator, the RET at 0b29 becomes")
    w("  explicit, and the epilogue RET lands at 0c00 instead.")
    w("")
    w("  NO JMP OVER THE DATA, AND THAT WAS A THREE-BYTE ERROR. This procedure")
    w("  used to open `JMP @@Patcher`, on the reasoning that Pascal enters a")
    w("  procedure at its first byte and here that byte is a gain cell. Nothing")
    w("  enters it that way: `SetGains` is never called by name anywhere in the")
    w("  tree -- the ladder is reached through the patched CS-relative pointers")
    w("  and the patcher through `CALL @@Patcher` at 0c7a, both inside this")
    w("  block. An `assembler` procedure that is never called needs no reachable")
    w("  first instruction, so the cell at 0746 stands where the original has it.")
    w("")
    w("  IT WAS ALSO WRONG BY THREE BYTES IN A WAY THE COMPARISON COULD NOT SEE.")
    w("  The four `DW OFFSET SetGains + delta` patch targets in SOUNDDEV.PAS")
    w("  measure their deltas from 0746 -- 0d7c is +0636 -- and with the JMP in")
    w("  place `OFFSET SetGains` was the JMP, so every one of them pointed three")
    w("  bytes short. They are linker fixups, so they sit in the .TPU as zeros and")
    w("  verify.py files them as pending: four wrong pointers, invisible. This is")
    w("  risk 1 in miniature.")
    w("  ========================================================================== }")
    w("")
    w("procedure SetGains; assembler;")
    w("asm")

    verify = {}      # offset -> expected bytes, rebuilt as we go

    for name, lo, hi, table in FAMILIES:
        starts = cells(lo, hi)
        assert len(starts) == 16, (name, len(starts))
        w("  { ---- %s: 1a17:%04x, %d cells --------------------------------- }"
          % (name, lo, len(starts)))
        for k, s in enumerate(starts):
            e = starts[k + 1] if k + 1 < len(starts) else hi
            g = gain_of(b, s, e)
            w("")
            w("  { gain %-7s }" % (("%s" % g) if g is not None else "?"))
            w("@@%s_%02d:" % (name, k))
            i = s
            while i < e:
                got = decode(b, i)
                assert got is not None
                n, src, why = got
                w("    %-24s { %04x  %s }" % (src, i, why))
                verify[i] = b[i:i + n]
                i += n
        w("")
        w("  { the family's pointer table -- SetGains indexes it by volume     }")
        w("@@%sTable:" % name)
        # The ladder is not an arbitrary list, and saying so is the strongest
        # check available that the decode is right: each family follows a
        # closed form, so a single mis-decoded shift would break it.
        for k, s in enumerate(starts):
            g = gain_of(b, s, starts[k + 1] if k + 1 < len(starts) else hi)
            if name == "G1":
                want = Fraction(16 - k, 16)
            elif name == "G2":
                want = Fraction(16 + k, 16)
            else:
                # bitrev4(k) + 1 -- see the note on the permutation below.
                want = Fraction(int("{:04b}".format(k)[::-1], 2) + 1)
            assert g == want, ("gain mismatch", name, k, g, want)

        for k, s in enumerate(starts):
            got = struct.unpack_from("<H", b, table + k * 2)[0]
            assert got == s, ("table mismatch", name, k, hex(got), hex(s))
            w("    DW OFFSET @@%s_%02d       { %04x }" % (name, k, table + k * 2))
        w("")

    w("  { ---- the patch area, 1a17:%04x ---------------------------------- }" % PATCH)
    w("  { Eight slots, one per channel. SetGains overwrites each with the      }")
    w("  { address of a cell; the mixer CALLs through them. They start at the   }")
    w("  { family-1 unity cell, so an unconfigured mixer passes samples through }")
    w("  { unchanged rather than silencing them.                                }")
    w("@@Patch:")
    for k in range(8):
        got = struct.unpack_from("<H", b, PATCH + k * 2)[0]
        assert got == 0x0746, (k, hex(got))
        w("    DW OFFSET @@G1_00        { %04x  slot %d }" % (PATCH + k * 2, k))
    w("")

    w("  { ---- the 4-bit bit-reversal permutation, 1a17:%04x --------------- }" % BITREV)
    w("  { Channels 1,3,5,7 index family 3 through this rather than directly.   }")
    w("  { Every entry is bitrev4(index), verified below.                       }")
    w("@@BitRev:")
    row = []
    for k in range(16):
        v = b[BITREV + k]
        exp = int("{:04b}".format(k)[::-1], 2)
        assert v == exp, (k, v, exp)
        row.append("$%02X" % v)
    w("    DB " + ", ".join(row))
    w("")

    # ---- the patcher, 1a17:0a81 -------------------------------------------
    # Eight blocks, verbatim.  Which table each channel uses is fixed in the
    # code, not computed: 0 and 4 attenuate, 2 and 6 boost, and the four odd
    # channels take the integer ladder through the permutation.  Addresses are
    # accumulated from 0a81 and the total is checked against 0b29, so a wrong
    # instruction length here is caught rather than printed.
    SLOTS = ["G1", "G3", "G2", "G3", "G1", "G3", "G2", "G3"]
    w("  { ---- the patcher, 1a17:0a81 ------------------------------------- }")
    w("  { Reference Pascal, for reading only -- the real thing is below:      }")
    w("  {   GainSlot[0] := G1Table[Volumes[0]];                               }")
    w("  {   GainSlot[1] := G3Table[BitRev[Volumes[1]]];                       }")
    w("  {   GainSlot[2] := G2Table[Volumes[2]];   ... and so on               }")
    w("@@Patcher:")
    pc = 0x0A81
    for k, fam in enumerate(SLOTS):
        rev = (fam == "G3")
        w("")
        w("  { channel %d -- %s }" % (k, "permuted integer ladder" if rev
                                      else ("attenuate" if fam == "G1" else "boost")))
        vol = "WORD PTR Volumes[%d]" % (k * 2)
        seq = []
        seq.append(("MOV     AX,%s" % vol, 3, "the channel's volume"))
        if rev:
            seq.append(("MOV     BX,OFFSET @@BitRev", 3, ""))
            seq.append(("DB 03h, 0D8h", 2, "ADD BX,AX -- see the encoding note"))
            seq.append(("MOV     AL,CS:[BX]", 3, "permute the index"))
        seq.append(("DB 03h, 0C0h", 2, "ADD AX,AX -- word index"))
        seq.append(("MOV     BX,OFFSET @@%sTable" % fam, 3, ""))
        seq.append(("DB 03h, 0D8h", 2, "ADD BX,AX -- see the encoding note"))
        seq.append(("MOV     AX,CS:[BX]", 3, "the cell's address"))
        slot = "@@Patch" if k == 0 else "@@Patch+%d" % (k * 2)
        seq.append(("MOV     WORD PTR CS:[%s],AX" % slot, 4, "patch slot %d" % k))
        for src, n, why in seq:
            w("        %-34s { %04x  %s }" % (src, pc, why))
            pc += n
    # The patcher's own RET, at 0b29. It used to come free from Pascal's
    # epilogue because the procedure ended here; now that the mixer follows in
    # the same procedure it is mid-stream and has to be written out. The
    # epilogue's RET lands at 0c00 instead, which is where the original's last
    # one is -- so still exactly one RET per RET.
    assert pc == 0x0B29, "patcher ends at %04x, expected 0b29" % pc
    w("    DB 0C3h                                { %04x  RET -- NEAR, the }" % pc)
    w("                                           { patcher's own; explicit }")
    w("                                           { because the procedure }")
    w("                                           { continues past it }")
    for line in MIXER.rstrip("\n").split("\n"):
        w(line)
    for line in CONFIG.rstrip("\n").split("\n"):
        w(line)
    for line in DOWNMIX_HEAD.rstrip("\n").split("\n"):
        w(line)
    for line in downmix_adds():
        w(line)
    for line in DOWNMIX_TAIL.rstrip("\n").split("\n"):
        w(line)
    for line in method_lines():
        w(line)
    for line in mono_lines():
        w(line)
    for line in stereo_lines():
        w(line)
    for line in FILL.rstrip("\n").split("\n"):
        w(line)
    for line in PREP.rstrip("\n").split("\n"):
        w(line)
    w("end;")
    w("")

    sys.stdout.write("\n".join(to_tasm(out)) + "\n")
    sys.stderr.write("emit_gain: %d cells decoded, %d bytes covered, tables verified\n"
                     % (48, sum(len(v) for v in verify.values())))


if __name__ == "__main__":
    main()
