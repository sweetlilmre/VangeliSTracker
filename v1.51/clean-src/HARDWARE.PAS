{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  The two chips every sound card on a PC has to be wired through: the 8259
  interrupt controllers and the 8237 DMA channels.

  UNDER EVERY DRIVER IN THE PROGRAM. A Sound Blaster needs a DMA channel and
  an IRQ; a Gravis needs an IRQ. Neither card can be told to play until
  somebody has unmasked its interrupt line and pointed a DMA channel at a
  buffer, and this is where that happens -- once, for all of them.

  WHAT MAKES IT FIDDLY IS THE ADDRESSING, not the logic. There are TWO 8259s,
  cascaded, so an IRQ above 7 lives on the second one and needs a different
  port and a different bit. And an 8237 channel's page register is not beside
  its other registers at all: the page bits live on a separate chip at
  unrelated port numbers, in an order that is not the channel order. Most of
  this unit is tables that say where each thing actually is.

  DGROUP
    $0c10  the 16-bit page-register ports    $0c18  the 8-bit ones

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.
  =========================================================================== }

{$G+}   { SHR AX,imm in DMASet -- a 186 instruction }

unit Hardware;

interface

uses
  Dos;                 { for GetIntVec and SetIntVec, to swap an IRQ's
                         handler and put the old one back            }

{ ---- the 8259s ---------------------------------------------------------- }

procedure EnableIRQ(IRQ : Word); far;
procedure DisableIRQ(IRQ : Word); far;
function  IRQState(IRQ : Word) : Boolean; far;
function  SetIRQVector(IRQ : Word; Vec : Pointer) : Pointer; far;

{ ---- the 8237s ---------------------------------------------------------- }

{ the one callers should use. Size is in BYTES and is passed
  as given; the minus-one the hardware wants is applied here. }
procedure DMASet(Channel, Mode : Word; Buf : Pointer; Size : Word); far;

function  GetDMACount(Channel : Byte) : Word; far;
procedure DMAReset(Channel : Byte); far;

{ DMASet with the address already split into page and offset. }
procedure DMARawSet(Channel, Mode, Page : Byte; Offs, Size : Word); far;

implementation

type
  { Reaching the two halves of a Pointer VALUE. `Seg(P)` and `Ofs(P)` would
    give the address OF the variable, not the address stored IN it, so a cast
    is the only way. Turbo Pascal's own idiom. }
  TPtrRec = record
    Ofs, Seg : Word;
  end;

const
  { The page register for a DMA channel is not at a
    port you can compute -- IBM scattered them -- so both controllers need a
    lookup. These are the standard PC assignments.

    The 16-bit table is indexed by the channel number MINUS FOUR, so entry 0
    is DMA 4, which is the cascade to the first controller and can never be
    used for a transfer. It is zero, and nothing ever reads it. }
  Page16 : array[0..3] of Word = ($0000, $008B, $0089, $008A);
  Page8  : array[0..3] of Word = ($0087, $0083, $0081, $0082);

{ --------------------------------------------------------------------------
let an IRQ through.

  HAND ASSEMBLER, verbatim: IN and OUT are not expressible in Pascal.

  A bit in an 8259 mask register SET means masked, so enabling is an AND with
  the complement. IRQ 8..15 live on the second controller at $A0, and enabling
  one of those ALSO has to clear IRQ 2 on the first -- that is the cascade
  line the second controller is wired to, and a masked IRQ 2 makes the whole
  upper eight silent. $FB is the complement of bit 2.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if IRQ < 8 then
        Port[$21] := Port[$21] and not (1 shl IRQ)
      else
      begin
        Port[$A1] := Port[$A1] and not (1 shl (IRQ - 8));
        Port[$21] := Port[$21] and $FB
      end
  -------------------------------------------------------------------------- }
{ PASCAL, NOT ASSEMBLER. This routine used to carry the note "IN and OUT are
  not expressible in Pascal", which is wrong: Turbo Pascal's Port[] with a
  CONSTANT index compiles to exactly `IN AL,21h` and `OUT 21h,AL`. (It is only
  a computed port number that goes through DX and needs assembler -- see the
  note on 1723's register interface.)

  Written by hand the instructions were right and the ENCODINGS were not:
  TP7's built-in assembler picks `89 C2` for MOV DX,AX and `21 D0` for
  AND AX,DX, where the compiler emits `8B D0` and `23 C2`. Same instructions,
  different direction bit, and the unit diverged at the first one.

  The 1.39b release has this routine as EnableIRQ in LIB/HARDWARE.PAS, in
  Pascal, in this shape.

  A bit in an 8259 mask register SET means masked, so enabling is an AND with
  the complement. IRQ 8..15 live on the second controller at $A0, and enabling
  one of those ALSO has to clear IRQ 2 on the first -- that is the cascade
  line the second controller is wired to, and a masked IRQ 2 makes the whole
  upper eight silent. }
procedure EnableIRQ(IRQ : Word);
begin
  if IRQ < 8 then
    Port[$21] := Port[$21] and not (1 shl IRQ)
  else
  begin
    Port[$A1] := Port[$A1] and not (1 shl (IRQ - 8));
    Port[$21] := Port[$21] and not (1 shl 2)      { -> AND AL,0FBh }
  end
end;

{ --------------------------------------------------------------------------
shut an IRQ out.

  HAND ASSEMBLER, verbatim. The mirror of the above, except that it does NOT
  re-mask the cascade when disabling a slave IRQ -- and must not, because
  some other slave IRQ may still be in use. Masking IRQ 2 would silence that
  one too. The asymmetry is deliberate.
  -------------------------------------------------------------------------- }
{ Pascal, for the same reason as EnableIRQ above. }
procedure DisableIRQ(IRQ : Word);
begin
  if IRQ < 8 then
    Port[$21] := Port[$21] or (1 shl IRQ)
  else
    Port[$A1] := Port[$A1] or (1 shl (IRQ - 8))
end;

{ --------------------------------------------------------------------------
is this IRQ currently getting through?

  HAND ASSEMBLER, verbatim.

  The slave case is the reason this routine is worth having. It reports a
  slave IRQ as DISABLED whenever the cascade at IRQ 2 is masked, whatever the
  slave's own mask bit says -- which is correct, and is the question a caller
  actually means to ask. Reading the slave mask alone would answer it wrongly
  on a machine where something else had masked IRQ 2.
  -------------------------------------------------------------------------- }
{ Pascal. Note the second arm is an AND of two comparisons, not a nested if:
  an IRQ on the slave is only really open if the CASCADE is open too, and a
  masked IRQ 2 silences the whole upper eight. }
function IRQState(IRQ : Word) : Boolean;
begin
  if IRQ < 8 then
    IRQState := (Port[$21] and (1 shl IRQ)) = 0
  else
    IRQState := ((Port[$21] and 4) = 0) and     { the cascade }
                  ((Port[$A1] and (1 shl (IRQ - 8))) = 0)
end;

{ --------------------------------------------------------------------------
point an IRQ's vector somewhere, and hand back the old one.

  The vector number is the only arithmetic. IRQ 0..7 are INT $08..$0F and
  IRQ 8..15 are INT $70..$77, so the second controller's offset is $68 rather
  than the $8 the first one uses -- `IRQ + $68` puts IRQ 8 at INT $70.
  Returning the displaced vector is what makes an install/uninstall pair
  possible without a separate save call.
  -------------------------------------------------------------------------- }
function SetIRQVector(IRQ : Word; Vec : Pointer) : Pointer;
var
  p : Pointer;
  j : Word;
begin
  if IRQ < 8 then
    j := IRQ + 8                                { INT $08..$0F }
  else
    j := IRQ + $68;                             { INT $70..$77 }

  GetIntVec(j, p);
  SetIntVec(j, Vec);
  SetIRQVector := p;
end;

{ --------------------------------------------------------------------------
program a 16-bit DMA channel. FRAMELESS.

  HAND ASSEMBLER, verbatim, and it could not be anything else: it takes no
  parameters and builds no frame. Everything arrives in registers, put there
  by DMARawSet below:

      AH  the channel, 0..3, meaning DMA 4..7
      CH  the mode byte, added to the channel for the mode register
      CL  the page
      BX  the 16-bit address
      SI  the count, already minus one

  THE ADDRESS IS HALVED. A 16-bit channel counts WORDS, not bytes, so the
  24-bit address CL:BX is shifted right one place -- `SHR CL,1` drops a bit
  into carry and `RCR BX,1` catches it. `ADD CL,CL` then puts CL back where
  it was, because the PAGE register is not halved, only the offset within it.
  Three instructions for what would otherwise need a 32-bit shift.

  The order is the one the 8237 requires: mask the channel, clear the
  byte-pointer flip-flop, set the mode, then write address and count as
  low-then-high byte pairs to the same port, and unmask last.
  -------------------------------------------------------------------------- }
procedure DMA16Set; assembler;
asm
  AND  AH, 3             { DMA 4..7 -> 0..3 on this controller   }
  SHR  CL, 1             { CL:BX >> 1 -- 16-bit DMA counts words }
  RCR  BX, 1
  ADD  CL, CL            { ... but the page is NOT halved        }
  MOV  AL, AH
  ADD  AL, 4             { bit 2 = set mask                      }
  OUT  0D4h, AL          { mask the channel                      }
  XOR  AL, AL
  OUT  0D8h, AL          { clear the byte-pointer flip-flop      }
  MOV  AL, AH
  ADD  AL, CH            { channel + mode                        }
  OUT  0D6h, AL          { mode register                         }
  XOR  DH, DH
  MOV  DL, AH
  ADD  DX, DX
  ADD  DX, DX            { channel * 4                           }
  ADD  DX, 00C0h         { the address port                      }
  MOV  AL, BL
  OUT  DX, AL            { address, low                          }
  MOV  AL, BH
  OUT  DX, AL            { address, high                         }
  PUSH DX
  MOV  DL, AH
  ADD  DX, DX            { channel * 2                           }
  MOV  BX, OFFSET Page16 { was MOV BX,0C10h                      }
  ADD  BX, DX
  MOV  DX, [BX]          { this channel's page port              }
  MOV  AL, CL
  OUT  DX, AL
  POP  DX
  INC  DX
  INC  DX                { the count port is address + 2         }
  MOV  BX, SI
  MOV  AL, BL
  OUT  DX, AL            { count, low                            }
  MOV  AL, BH
  OUT  DX, AL            { count, high                           }
  MOV  AL, AH
  OUT  0D4h, AL          { unmask -- bit 2 clear                 }
end;

{ --------------------------------------------------------------------------
program an 8-bit DMA channel. FRAMELESS.

  HAND ASSEMBLER, verbatim. The same sequence against the first controller's
  ports, and WITHOUT the halving -- an 8-bit channel counts bytes, so the
  address goes across as it stands. Its ports are also packed twice as
  tightly: address at channel*2 and count at channel*2 + 1, rather than the
  second controller's stride of four.
  -------------------------------------------------------------------------- }
procedure DMA8Set; assembler;
asm
  MOV  AL, AH
  ADD  AL, 4
  OUT  0Ah, AL           { mask the channel                      }
  XOR  AL, AL
  OUT  0Ch, AL           { clear the flip-flop                   }
  MOV  AL, AH
  ADD  AL, CH
  OUT  0Bh, AL           { mode register                         }
  XOR  DH, DH
  MOV  DL, AH
  ADD  DX, DX            { channel * 2 = the address port        }
  MOV  AL, BL
  OUT  DX, AL            { address, low                          }
  MOV  AL, BH
  OUT  DX, AL            { address, high                         }
  PUSH DX
  MOV  BX, OFFSET Page8  { was MOV BX,0C18h                      }
  ADD  BX, DX
  MOV  DX, [BX]
  MOV  AL, CL
  OUT  DX, AL            { page                                  }
  POP  DX
  INC  DX                { count port = address port + 1         }
  MOV  BX, SI
  MOV  AL, BL
  OUT  DX, AL
  MOV  AL, BH
  OUT  DX, AL
  MOV  AL, AH
  OUT  0Ah, AL           { unmask                                }
end;

{ --------------------------------------------------------------------------
 -- mask a channel and leave it masked. FRAMELESS.
  Channel in AH. Two instructions and an OUT; the whole of stopping a
  transfer.
  -------------------------------------------------------------------------- }
procedure DMA16Reset; assembler;
asm
  AND  AH, 3
  MOV  AL, AH
  ADD  AL, 4
  OUT  0D4h, AL
end;

procedure DMA8Reset; assembler;
asm
  MOV  AL, AH
  ADD  AL, 4
  OUT  0Ah, AL
end;

{ --------------------------------------------------------------------------
how far has a 16-bit transfer got? FRAMELESS, channel in AH,
  answer in AX.

  HAND ASSEMBLER, verbatim. Clear the flip-flop, then two reads from the
  count port give low byte then high byte.
  -------------------------------------------------------------------------- }
procedure GetDMA16Count; assembler;
asm
  AND  AH, 3
  XOR  AL, AL
  OUT  0D8h, AL          { clear the flip-flop                   }
  XOR  DH, DH
  MOV  DL, AH
  ADD  DX, DX
  ADD  DX, DX
  ADD  DX, 00C2h         { the COUNT port: $C0 + chan*4 + 2      }
  IN   AL, DX
  MOV  BL, AL
  IN   AL, DX
  MOV  BH, AL
  MOV  AX, BX
end;

{ --------------------------------------------------------------------------
how far has an 8-bit transfer got? FRAMELESS.

  HAND ASSEMBLER, verbatim, and the most interesting routine in the unit.

  A DMA counter is DECREMENTING WHILE YOU READ IT, one byte at a time through
  a single port. The two halves can straddle a change, giving a value that
  was never real -- and on a sound card that shows up as a click, because the
  mixer uses this to decide how much of the buffer it may refill.

  So it reads the counter TWICE and judges the pair:

      difference < 5        the counter barely moved; trust the second read
      difference < $104     it moved a little; trust the FIRST read, which is
                            the one taken before the movement
      difference >= $FF01   it wrapped past zero; trust the second
      otherwise             the two reads disagree by more than any real
                            transfer could in this time -- return $FFFF and
                            let the caller decide

  Reporting a refusal rather than a plausible-looking wrong number is the
  part worth copying. $FFFF is not a valid count here.
  -------------------------------------------------------------------------- }
procedure GetDMA8Count; assembler;
asm
  XOR  AL, AL
  OUT  0Ch, AL           { clear the flip-flop                   }
  XOR  DH, DH
  MOV  DL, AH
  ADD  DX, DX
  INC  DX                { count port = chan*2 + 1               }
  IN   AL, DX            { - first read                        }
  MOV  BL, AL
  IN   AL, DX
  MOV  BH, AL
  MOV  CX, BX            { keep it                               }
  IN   AL, DX            { - second read                       }
  MOV  BL, AL
  IN   AL, DX
  MOV  BH, AL
  MOV  AX, BX            { assume the second                     }
  MOV  SI, CX
  SUB  SI, BX            { how far it moved between reads        }
  CMP  SI, 5
  JC   @@Out             { barely moved -> the second read       }
  MOV  AX, CX
  CMP  SI, 0104h
  JC   @@Out             { moved a little -> the FIRST read      }
  MOV  AX, BX
  CMP  SI, 0FF01h
  JNC  @@Out             { wrapped past zero -> the second       }
  MOV  AX, 0FFFFh        { no idea; say so                       }
@@Out:
end;

{ --------------------------------------------------------------------------
pick a controller by channel number.

  HAND ASSEMBLER, verbatim. Three identical shapes, differing only in which
  pair of kernels they call. Channel arrives in AH.

  CHANNELS 2 AND 4 RETURN WITHOUT DOING ANYTHING. Channel 2 is the floppy
  controller's, and taking it would break disk access; channel 4 is the
  cascade that wires the second 8237 to the first, and is not a transfer
  channel at all. Refusing them here means no driver has to know.

  Below 4 goes to the 8-bit controller, above 4 to the 16-bit one.
  -------------------------------------------------------------------------- }
{ **HOW FAR HAS THE CARD GOT?** The 8237 counts DOWN as it transfers, so the
  value read here is how much of the buffer is still to go. That is what lets
  the player know where the hardware is reading and refill the part it has
  already passed, without any interrupt from the card itself.

  The same channel guard as the two routines below -- see the block there for
  why 2 and 4 are refused. }
procedure GetDMACountAsm; far; assembler;
asm
  CMP  AH, 2             { the floppy                            }
  JZ   @@Out
  CMP  AH, 4             { the cascade                           }
  JZ   @@Out
  JC   @@Eight
  CALL GetDMA16Count
  JMP  @@Out
@@Eight:
  CALL GetDMA8Count
@@Out:
end;

{ ===========================================================================
  **CHOOSING A DMA CONTROLLER, AND REFUSING TWO CHANNELS THAT MUST NOT BE USED.**
  Both this routine and DMAResetAsm below open with the same four instructions,
  and all four are about the shape of a PC rather than about sound.

  A PC has TWO DMA controllers. The original 8-bit one owns channels 0..3; a
  second, 16-bit one was added with the AT and owns 5..7. They have different
  port addresses and different register widths, so the channel number decides
  which set of ports to write -- that is what `JC @@Eight` is doing, taking
  anything below 4 to the 8-bit path.

  CHANNEL 4 IS NOT A CHANNEL. It is the cascade: the 8-bit controller is wired
  into it so that the two chips can work together, and programming it would
  disconnect the first controller from the bus. Refused.

  CHANNEL 2 IS THE FLOPPY DISK CONTROLLER, on every PC ever built. A sound card
  jumpered to channel 2 would work until the moment something touched a disk,
  and then one of the two would lose its transfer. Refused as well.

  So a caller asking for 2 or 4 gets silence rather than an error -- `JZ @@Out`
  goes to the routine's end and nothing is programmed. That is the same
  fail-quietly choice the card detection makes: this runs under an interrupt on
  hardware that may be configured any way at all, and a wrong jumper setting
  should cost the sound rather than the machine.
  =========================================================================== }
procedure DMASetAsm; far; assembler;
asm
  CMP  AH, 2             { the floppy controller's channel        }
  JZ   @@Out             { refuse it                              }
  CMP  AH, 4             { the cascade, not a usable channel      }
  JZ   @@Out             { refuse that too                        }
  JC   @@Eight           { below 4: the 8-bit controller          }
  CALL DMA16Set
  JMP  @@Out
@@Eight:
  CALL DMA8Set
@@Out:
end;

{ The same guard as DMASetAsm above, for the same two reasons. }
procedure DMAResetAsm; far; assembler;
asm
  CMP  AH, 2
  JZ   @@Out
  CMP  AH, 4
  JZ   @@Out
  JC   @@Eight
  CALL DMA16Reset
  JMP  @@Out
@@Eight:
  CALL DMA8Reset
@@Out:
end;

{ --------------------------------------------------------------------------
the Pascal-callable faces.

  HAND ASSEMBLER, verbatim: each one is nothing but moving parameters into
  the registers the kernels expect, and a far call.
  -------------------------------------------------------------------------- }
procedure DMARawSet(Channel, Mode, Page : Byte; Offs, Size : Word); assembler;
asm
  MOV  AH, BYTE PTR Channel
  MOV  CH, BYTE PTR Mode
  MOV  CL, BYTE PTR Page
  MOV  BX, Offs
  MOV  SI, Size
  CALL DMASetAsm
end;

function GetDMACount(Channel : Byte) : Word; assembler;
asm
  MOV  AH, BYTE PTR Channel
  CALL GetDMACountAsm
end;


{ --------------------------------------------------------------------------
take a Pointer and a byte count, do the rest.

  Plain Pascal in the binary. Two things happen: the far pointer is split
  into a DMA page and a 16-bit address, and the count is decremented, because
  an 8237 counts "one fewer than this many".

  READ THE ADDRESS ARITHMETIC CAREFULLY -- it is not the obvious formula, and
  the transcription keeps what is there rather than correcting it.

  The page comes out as the top nibble of the SEGMENT, which is right: for a
  linear address of Seg*16 + Ofs, bits 16..19 are exactly `Seg shr 12`.

  The 16-bit part, though, is computed as `(Seg and $0FFF) + Ofs`, with NO
  shift left by four on the SEGMENT term. The exact answer would be
  `((Seg and $0FFF) shl 4) + Ofs`. Treating a paragraph count as a byte count
  is only correct when `Seg and $0FFF` is ZERO -- that is, when the buffer's
  SEGMENT is a multiple of $1000, so the buffer starts on a 64 KB boundary.

  So the routine carries an unwritten CONTRACT: hand it a pointer whose
  SEGMENT is 64 KB aligned. That is not an unreasonable thing to require of a
  DMA buffer -- a transfer may not cross a 64 KB boundary anyway, so a caller
  has to think about alignment regardless, and 17cf's pool is where the
  buffer comes from.

  The overflow test just above it is consistent with that reading: it checks
  whether `Ofs + (Seg and $0FFF)` would carry out of sixteen bits and bumps
  the page if so. That is a correction for a SLIGHTLY misaligned SEGMENT, and
  it is exact only in the same case the main formula is.

  Flagged rather than fixed. Resolving it properly needs the callers in 12ba
  and 19a0, which have not been transcribed.
  -------------------------------------------------------------------------- }
procedure DMASet(Channel, Mode : Word; Buf : Pointer; Size : Word);
var
  Segm : Word;
  Offs : Word;
begin
  Segm := Seg(Buf^) and $F000;
  Offs := Seg(Buf^) and $0FFF;

  if ($FFFF - Ofs(Buf^)) < Offs then              { would carry }
  begin
    Inc(Segm, $1000);                             { next page   }

    Offs := Offs - $10000 + Ofs(Buf^);
  end
  else
    Offs := Ofs(Buf^) + Offs;

  Dec(Size);                                      { the 8237 wants N-1 }

  DMARawSet(Channel, Mode, Segm shr 12, Offs, Size);
end;

procedure DMAReset(Channel : Byte); assembler;
asm
  MOV  AH, BYTE PTR Channel
  CALL DMAResetAsm
end;

end.
