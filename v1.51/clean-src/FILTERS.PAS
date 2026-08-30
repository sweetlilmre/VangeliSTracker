{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

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
the three kernels.

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
procedure Filter1_2Word; assembler;   {y := (prev + x) / 2 }
asm
@@Next:
  MOV  AX, ES:[DI]       { the sample                             }
  ADD  BX, AX            { plus the state                         }
  XCHG AX, BX            { the OLD sample becomes the new state   }
  SAR  AX, 1
  MOV  ES:[DI], AX
  ADD  DI, SI            { one stride on                          }
  LOOP @@Next
                         { RET -- NEAR, and supplied by Pascal:   }
                         { an assembler procedure gets its own epilogue, }
                         { so writing RET here emits a SECOND one.       }
end;

procedure Filter3_4Word; assembler;
asm
@@Next:
  MOV  AX, ES:[DI]
  SAR  BX, 1             { half the state, not all of it          }
  ADD  BX, AX
  XCHG AX, BX
  SAR  AX, 1
  MOV  DX, AX
  SAR  AX, 2
  ADC  DX, AX            { ADC, so the shifted-out bit rounds     }
  SAR  AX, 2
  ADC  AX, DX
  MOV  ES:[DI], AX
  ADD  DI, SI
  LOOP @@Next
                         { RET, supplied by Pascal                }
end;

procedure Filter7_8Word; assembler;   {the steepest }
asm
@@Next:
  MOV  AX, ES:[DI]
  SAR  BX, 2             { a quarter of the state                 }
  ADD  BX, AX
  XCHG AX, BX
  SAR  AX, 1
  MOV  DX, AX
  SAR  AX, 1
  ADC  DX, AX
  SAR  AX, 3
  ADC  AX, DX
  MOV  ES:[DI], AX
  ADD  DI, SI
  LOOP @@Next
                         { RET, supplied by Pascal                }
end;

{ --------------------------------------------------------------------------
pick a kernel and run it.

  HAND ASSEMBLER, verbatim. The whole routine is register setup and three
  near CALLs, and the result is whatever BX ended up as.

  Note Offs is doubled on the way in: the parameter counts SAMPLES and
  the buffer holds words.

  A Method of fmNone falls through with the buffer untouched, and so does a
  Len of zero -- JCXZ before anything is loaded.
  -------------------------------------------------------------------------- }
function FilterChunkWord(var Buf; Len, Offs : Word; Method : TFilterMethod;
                         OldSpl : Word) : Word; assembler;
asm
  MOV  SI, Offs          { [BP+0Ah]                               }
  ADD  SI, SI            { samples -> bytes                       }
  LES  DI, Buf           { [BP+0Eh]                               }
  MOV  BX, OldSpl        { [BP+06h]                               }
  MOV  CX, Len           { [BP+0Ch]                               }
  JCXZ @@Done            { nothing to do                          }
  MOV  AL, Method        { [BP+08h]                               }
  CMP  AL, fm1_2         { the enum -- and ORD(fm1_2) is 3        }
  JNZ  @@Try2
  CALL Filter1_2Word
  JMP  @@Done
@@Try2:
  CMP  AL, fm3_4
  JNZ  @@Try1
  CALL Filter3_4Word
  JMP  @@Done
@@Try1:
  CMP  AL, fm7_8
  JNZ  @@Done
  CALL Filter7_8Word
@@Done:
  MOV  AX, BX            { the state, for the next call           }
end;

end.
