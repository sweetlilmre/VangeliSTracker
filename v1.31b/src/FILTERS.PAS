{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).

  Segment 1544 -- the output filter. 144 bytes, all of it.

  Three first-order FIR low-pass filters, run in place over a strided buffer
  of 16-bit samples, plus a far entry that picks between them. This is the
  Amiga-style "LED filter": NEUROSIS.CFG's FilterOn / FilterOff /
  FilterIsOn / FilterChange / BassFilter all land here.

  The three differ only in how much of the previous output is fed back, and
  the release names them by CUT-OFF FREQUENCY rather than by strength -- a
  cut-off of PI*X means f*X/2 for a sampling rate f, so at 20kHz fm3_4 cuts
  at 7500Hz:

      fm1_2   y := (y + x) / 2                        gentlest
      fm3_4   y := (y/2 + x) / 2, then + y/4 + y/16   middling
      fm7_8   y := (y/4 + x) / 2, then + y/2 + y/16   steepest

  THAT IS WHAT THE 3/2/1 SELECTOR WAS. The parameter had been read as a
  "strength" running 3 down to 1, which is exactly ORD(fm1_2)..ORD(fm7_8) of
  the release's enum -- one value per kernel, in the order they sit in the
  segment, with fmNone = 0 falling through untouched.

  The fractional tails are done with SAR/ADC pairs rather than a multiply --
  ADC picks up the bit SAR shifted out, so it rounds instead of truncating,
  and on an 8086 it is far cheaper than IMUL.

  BX carries the filter state across the whole run and is handed back, so the
  caller can filter a buffer in pieces without a click at the joins.

  NAMES ARE THE 1.39b RELEASE'S. LIB/FILTERS.PAS holds all four of these
  routines instruction for instruction, under the names used below. It also
  holds a BYTE-sized set of the same three kernels and a FilterChunkByte
  beside them, and 1544 has none of that -- 144 bytes is the four Word
  routines and nothing else, so the byte half is later work by the author and
  is deliberately not transcribed here. `FilterMod = ORD(fm1_2) + 1` is in the
  release's interface too; it is left out until something in 1.31 is seen to
  use it. Nothing proves 1.31 spelled any of this the same way: the binary has
  no debug information.

  ADDRESS MAP
    Filter1_2Word  1544:0000    Filter3_4Word    1544:0010
    Filter7_8Word  1544:002e    FilterChunkWord  1544:004c
  =========================================================================== }

{$G+}   { SAR with an immediate count other than 1 is a 186 instruction }

unit Filters;

interface

type
  { The selector, in the release's spelling. A four-value enum is one byte, so
    it occupies the same stack word `Strength : Byte` did and the kernel test
    is the same CMP AL,n. }
  TFilterMethod = (fmNone,    { no filtering                   }
                   fm7_8,     { PI*7/8 cut-off -- the steepest }
                   fm3_4,     { PI*3/4                         }
                   fm1_2);    { PI*1/2 -- the gentlest         }

{ 1544:004c. Returns the filter state to carry into the next call.

  THE PARAMETER ORDER IS READ OFF THE FRAME, not guessed. Turbo Pascal pushes
  left to right, so the FIRST declared parameter sits at the HIGHEST [BP+n],
  and the body's own offsets fix the order beyond doubt:

      Buf [BP+0e]   Len [BP+0c]   Offs [BP+0a]
      Method [BP+08]              OldSpl [BP+06]

  An earlier version of this declaration had the selector second and the count
  fourth, which swapped those two and made the routine read the count from the
  selector and vice versa. It compiled, and it was wrong. }
function FilterChunkWord(var Buf; Len, Offs : Word; Method : TFilterMethod;
                         OldSpl : Word) : Word;

implementation

{ --------------------------------------------------------------------------
  1544:0000, 1544:0010, 1544:002e -- the three kernels.

  HAND ASSEMBLER, verbatim, and they cannot be anything else: all three are
  NEAR routines entered with ES:DI, BX, CX and SI already loaded by the
  caller below, they take no parameters and build no frame, and they leave
  the running state in BX for it. Pascal has no way to say any of that.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 1 to Count do
      begin
        X     := Buf^[K];
        State := State shr Shift + X;          -- shift = 0, 1 or 2
        Y     := State shr 1;
        ... the SAR/ADC tail for kernels 2 and 1 ...
        Buf^[K] := Y;
        State   := X;
        Inc(K, Stride)
      end

  -------------------------------------------------------------------------- }
{ @asm 000 1544:0000 +16 }
procedure Filter1_2Word; assembler;   { 1544:0000 -- y := (prev + x) / 2 }
asm
@@Next:
  MOV  AX, ES:[DI]       { 1544:0000  the sample                             }
  ADD  BX, AX            { 1544:0003  plus the state                         }
  XCHG AX, BX            { 1544:0005  the OLD sample becomes the new state   }
  SAR  AX, 1             { 1544:0006                                         }
  MOV  ES:[DI], AX       { 1544:0008                                         }
  ADD  DI, SI            { 1544:000b  one stride on                          }
  LOOP @@Next            { 1544:000d                                         }
                         { 1544:000f  RET -- NEAR, and supplied by Pascal:   }
                         { an assembler procedure gets its own epilogue, }
                         { so writing RET here emits a SECOND one.       }
end;

{ @asm 000 1544:0010 +30 }
procedure Filter3_4Word; assembler;   { 1544:0010 }
asm
@@Next:
  MOV  AX, ES:[DI]       { 1544:0010                                         }
  SAR  BX, 1             { 1544:0013  half the state, not all of it          }
  ADD  BX, AX            { 1544:0015                                         }
  XCHG AX, BX            { 1544:0017                                         }
  SAR  AX, 1             { 1544:0018                                         }
  MOV  DX, AX            { 1544:001a                                         }
  SAR  AX, 2             { 1544:001c                                         }
  ADC  DX, AX            { 1544:001f  ADC, so the shifted-out bit rounds     }
  SAR  AX, 2             { 1544:0021                                         }
  ADC  AX, DX            { 1544:0024                                         }
  MOV  ES:[DI], AX       { 1544:0026                                         }
  ADD  DI, SI            { 1544:0029                                         }
  LOOP @@Next            { 1544:002b                                         }
                         { 1544:002d  RET, supplied by Pascal                }
end;

{ @asm 000 1544:002e +30 }
procedure Filter7_8Word; assembler;   { 1544:002e -- the steepest }
asm
@@Next:
  MOV  AX, ES:[DI]       { 1544:002e                                         }
  SAR  BX, 2             { 1544:0031  a quarter of the state                 }
  ADD  BX, AX            { 1544:0034                                         }
  XCHG AX, BX            { 1544:0036                                         }
  SAR  AX, 1             { 1544:0037                                         }
  MOV  DX, AX            { 1544:0039                                         }
  SAR  AX, 1             { 1544:003b                                         }
  ADC  DX, AX            { 1544:003d                                         }
  SAR  AX, 3             { 1544:003f                                         }
  ADC  AX, DX            { 1544:0042                                         }
  MOV  ES:[DI], AX       { 1544:0044                                         }
  ADD  DI, SI            { 1544:0047                                         }
  LOOP @@Next            { 1544:0049                                         }
                         { 1544:004b  RET, supplied by Pascal                }
end;

{ --------------------------------------------------------------------------
  1544:004c -- pick a kernel and run it.

  HAND ASSEMBLER, verbatim. The whole routine is register setup and three
  near CALLs, and the result is whatever BX ended up as.

  Note Offs is doubled on the way in: the parameter counts SAMPLES and
  the buffer holds words.

  A Method of fmNone falls through with the buffer untouched, and so does a
  Len of zero -- JCXZ before anything is loaded.
  -------------------------------------------------------------------------- }
{ @asm 000 1544:004c }
function FilterChunkWord(var Buf; Len, Offs : Word; Method : TFilterMethod;
                         OldSpl : Word) : Word; assembler;
asm
  MOV  SI, Offs          { 1544:004f  [BP+0Ah]                               }
  ADD  SI, SI            { 1544:0052  samples -> bytes                       }
  LES  DI, Buf           { 1544:0054  [BP+0Eh]                               }
  MOV  BX, OldSpl        { 1544:0057  [BP+06h]                               }
  MOV  CX, Len           { 1544:005a  [BP+0Ch]                               }
  JCXZ @@Done            { 1544:005d  nothing to do                          }
  MOV  AL, Method        { 1544:005f  [BP+08h]                               }
  CMP  AL, fm1_2         { 1544:0062  the enum -- and ORD(fm1_2) is 3        }
  JNZ  @@Try2            { 1544:0064                                         }
  CALL Filter1_2Word     { 1544:0066                                         }
  JMP  @@Done            { 1544:0069                                         }
@@Try2:
  CMP  AL, fm3_4         { 1544:006b                                         }
  JNZ  @@Try1            { 1544:006d                                         }
  CALL Filter3_4Word     { 1544:006f                                         }
  JMP  @@Done            { 1544:0072                                         }
@@Try1:
  CMP  AL, fm7_8         { 1544:0074                                         }
  JNZ  @@Done            { 1544:0076                                         }
  CALL Filter7_8Word     { 1544:0078                                         }
@@Done:
  MOV  AX, BX            { 1544:007b  the state, for the next call           }
end;

end.
