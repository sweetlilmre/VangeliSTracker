{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  The output filter: three low-pass kernels and a chooser, run in place over a
  buffer of 16-bit samples.

  WHY A MODULE PLAYER HAS ONE. This is the Amiga-style "LED filter". On real
  hardware the machine had a switchable low-pass on its audio output, and
  music written for it was mixed expecting that softening; played back without
  it, the same module sounds harsh and hissy. The three kernels give a choice
  of how much to soften. `VT.CFG`'s FilterOn / FilterOff / FilterIsOn /
  FilterChange / BassFilter all end up here.

  THE KERNELS ARE NAMED BY CUT-OFF, NOT BY STRENGTH, which is worth knowing
  because the names read backwards otherwise. A cut-off of PI*X means f*X/2 for
  a sampling rate f, so at 20kHz `fm3_4` cuts at 7500Hz. The bigger the
  fraction, the MORE it cuts:

      fm1_2   y := (y + x) / 2                        gentlest
      fm3_4   y := (y/2 + x) / 2, then + y/4 + y/16   middling
      fm7_8   y := (y/4 + x) / 2, then + y/2 + y/16   steepest

  Each is a first-order recursive low-pass: one multiply-free feedback term,
  and the three differ only in how much of the previous output is fed back.

  THE FRACTIONAL TAILS ARE SAR/ADC PAIRS, NOT MULTIPLIES. `ADC` picks up the
  bit `SAR` shifted out, so each term rounds instead of truncating, and on an
  8086 that costs a few cycles where an `IMUL` costs over a hundred. Rounding
  matters here: truncating every term of a recursive filter walks the output
  steadily downwards.

  THE STATE LIVES IN BX ACROSS THE WHOLE RUN and is handed back to the caller,
  so a buffer can be filtered in pieces without a click at the joins. A caller
  that forgets to pass the previous return value back in gets a discontinuity
  at every boundary.

  [re] Segment 1544 -- 144 bytes, all of it.

  [re] THAT IS WHAT THE 3/2/1 SELECTOR WAS. The parameter had been read as a
  "strength" running 3 down to 1, which is exactly ORD(fm1_2)..ORD(fm7_8) of
  the release's enum -- one value per kernel, in the order they sit in the
  segment, with fmNone = 0 falling through untouched.

  [re] NAMES ARE THE 1.39b RELEASE'S. LIB/FILTERS.PAS holds all four of these
  routines instruction for instruction, under the names used below. It also
  holds a BYTE-sized set of the same three kernels and a FilterChunkByte
  beside them, and 1544 has none of that -- 144 bytes is the four Word
  routines and nothing else, so the byte half is later work by the author and
  is deliberately not transcribed here. `FilterMod = ORD(fm1_2) + 1` is in the
  release's interface too; it is left out until something in 1.31 is seen to
  use it. Nothing proves 1.31 spelled any of this the same way: the binary has
  no debug information.

  [re] ADDRESS MAP
    Filter1_2Word  1544:0000    Filter3_4Word    1544:0010
    Filter7_8Word  1544:002e    FilterChunkWord  1544:004c
  =========================================================================== }

{$G+}   { SAR with an immediate count other than 1 is a 186 instruction }

unit Filters;

interface

type
  { Which kernel to run, or none. The ORDER IS DELIBERATE and is relied on
    below: the values run from no filtering through steepest to gentlest, and
    a four-value enum occupies one byte.

    [re] A four-value enum is one byte, so it occupies the same stack word
    `Strength : Byte` did and the kernel test is the same CMP AL,n. }
  TFilterMethod = (fmNone,    { no filtering                   }
                   fm7_8,     { PI*7/8 cut-off -- the steepest }
                   fm3_4,     { PI*3/4                         }
                   fm1_2);    { PI*1/2 -- the gentlest         }

{ Filter `Len` samples of `Buf` in place, starting at sample `Offs` and taking
  every `Offs`th sample thereafter, and return the filter state to hand back on
  the next call.

  `OldSpl` is that state: pass 0 to start a fresh stream, or the previous
  return value to continue one seamlessly. A Method of `fmNone` returns
  `OldSpl` with the buffer untouched, and so does a `Len` of zero.

  [re] 1544:004c. THE PARAMETER ORDER IS READ OFF THE FRAME, not guessed.
  Turbo Pascal pushes left to right, so the FIRST declared parameter sits at
  the HIGHEST [BP+n], and the body's own offsets fix the order beyond doubt:

      Buf [BP+0e]   Len [BP+0c]   Offs [BP+0a]
      Method [BP+08]              OldSpl [BP+06]

  An earlier version of this declaration had the selector second and the count
  fourth, which swapped those two and made the routine read the count from the
  selector and vice versa. It compiled, and it was wrong. }
function FilterChunkWord(var Buf; Len, Offs : Word; Method : TFilterMethod;
                         OldSpl : Word) : Word;

implementation

{ --------------------------------------------------------------------------
  The gentlest kernel: each output is the mean of this sample and the last one.

  It is entered with its registers already loaded by FilterChunkWord below and
  it takes no parameters -- ES:DI addresses the first sample, SI is the stride
  in bytes, CX is the count, and BX carries the running state in and out.

  EQUIVALENT PASCAL, REFERENCE ONLY -- the assembler below is what runs:

      for I := 1 to Count do
      begin
        X       := Buf^[K];
        Buf^[K] := (State + X) div 2;
        State   := X;
        Inc(K, Stride)
      end

  [re] HAND ASSEMBLER, verbatim, and it cannot be anything else: it is a NEAR
  routine entered with registers already loaded, takes no parameters, builds no
  frame, and leaves the running state in BX for its caller. Pascal has no way
  to say any of that.
  -------------------------------------------------------------------------- }
procedure Filter1_2Word; assembler;
asm
@@Next:
  MOV  AX, ES:[DI]     { 1544:0000  the sample about to be filtered        }
  ADD  BX, AX          { 1544:0003  state + x, the whole of this kernel's sum }
  XCHG AX, BX          { 1544:0005  AX := the sum; BX := x, which is the NEXT state }
  SAR  AX, 1           { 1544:0006  halve the sum -- the mean of the two samples }
  MOV  ES:[DI], AX     { 1544:0008  written back in place, over the sample just read }
  ADD  DI, SI          { 1544:000b  one stride on: the buffer may be interleaved }
  LOOP @@Next          { 1544:000d  CX counts samples, not bytes           }
                       { [re] 1544:000f  RET -- NEAR, and supplied by
                         Pascal: an assembler procedure gets its own
                         epilogue, so writing RET here emits a SECOND one. }
end;

{ --------------------------------------------------------------------------
  The middling kernel: half the previous output is fed back, and two rounded
  fractional terms are added on top.

  Same register contract as the kernel above.

  EQUIVALENT PASCAL, REFERENCE ONLY -- the assembler below is what runs:

      for I := 1 to Count do
      begin
        X       := Buf^[K];
        Y       := (State div 2 + X) div 2;
        Buf^[K] := Y + Y div 4 + Y div 16;    -- each term rounded, not
                                              -- truncated; see ADC below
        State   := X;
        Inc(K, Stride)
      end
  -------------------------------------------------------------------------- }
procedure Filter3_4Word; assembler;
asm
@@Next:
  MOV  AX, ES:[DI]     { 1544:0010  the sample about to be filtered        }
  SAR  BX, 1           { 1544:0013  half the state, not all of it -- a weaker feed }
  ADD  BX, AX          { 1544:0015  state/2 + x                            }
  XCHG AX, BX          { 1544:0017  AX := the sum; BX := x, the next state }
  SAR  AX, 1           { 1544:0018  y := sum / 2                           }
  MOV  DX, AX          { 1544:001a  keep y; DX accumulates the output      }
  SAR  AX, 2           { 1544:001c  y/4, and the shifted-out bit lands in the carry }
  ADC  DX, AX          { 1544:001f  + y/4, ADC so that bit ROUNDS rather than is lost }
  SAR  AX, 2           { 1544:0021  (y/4)/4 = y/16, carry again            }
  ADC  AX, DX          { 1544:0024  + y/16, giving y + y/4 + y/16          }
  MOV  ES:[DI], AX     { 1544:0026  written back in place                  }
  ADD  DI, SI          { 1544:0029  one stride on                          }
  LOOP @@Next          { 1544:002b  next sample                            }
                       { [re] 1544:002d  RET, supplied by Pascal }
end;

{ --------------------------------------------------------------------------
  The steepest kernel: only a quarter of the previous output is fed back, and
  the fractional tail is correspondingly larger.

  Same register contract as the two above.

  EQUIVALENT PASCAL, REFERENCE ONLY -- the assembler below is what runs:

      for I := 1 to Count do
      begin
        X       := Buf^[K];
        Y       := (State div 4 + X) div 2;
        Buf^[K] := Y + Y div 2 + Y div 16;    -- each term rounded
        State   := X;
        Inc(K, Stride)
      end
  -------------------------------------------------------------------------- }
procedure Filter7_8Word; assembler;
asm
@@Next:
  MOV  AX, ES:[DI]     { 1544:002e  the sample about to be filtered        }
  SAR  BX, 2           { 1544:0031  a quarter of the state -- the weakest feed }
  ADD  BX, AX          { 1544:0034  state/4 + x                            }
  XCHG AX, BX          { 1544:0036  AX := the sum; BX := x, the next state }
  SAR  AX, 1           { 1544:0037  y := sum / 2                           }
  MOV  DX, AX          { 1544:0039  keep y; DX accumulates the output      }
  SAR  AX, 1           { 1544:003b  y/2, carry holds the bit shifted out   }
  ADC  DX, AX          { 1544:003d  + y/2, rounded                         }
  SAR  AX, 3           { 1544:003f  (y/2)/8 = y/16, carry again            }
  ADC  AX, DX          { 1544:0042  + y/16, giving y + y/2 + y/16          }
  MOV  ES:[DI], AX     { 1544:0044  written back in place                  }
  ADD  DI, SI          { 1544:0047  one stride on                          }
  LOOP @@Next          { 1544:0049  next sample                            }
                       { [re] 1544:004b  RET, supplied by Pascal }
end;

{ --------------------------------------------------------------------------
  Load the registers the kernels expect, call whichever one the selector
  names, and return the state it left behind.

  The whole routine is register setup and three near CALLs; there is no
  filtering arithmetic here at all. It is written in assembler because the
  kernels take their arguments in registers, which Pascal cannot express.

  EQUIVALENT PASCAL, REFERENCE ONLY -- the assembler below is what runs:

      SI := Offs * 2;  ES:DI := @Buf;  BX := OldSpl;  CX := Len;
      if CX <> 0 then
        case Method of
          fm1_2 : Filter1_2Word;
          fm3_4 : Filter3_4Word;
          fm7_8 : Filter7_8Word;
        end;                      -- fmNone falls through untouched
      Result := BX

  The tests run gentlest-first, which is the order the kernels sit in memory.
  -------------------------------------------------------------------------- }
function FilterChunkWord(var Buf; Len, Offs : Word; Method : TFilterMethod;
                         OldSpl : Word) : Word; assembler;
asm
  MOV  SI, Offs        { 1544:004f  the stride, in SAMPLES as the caller counts them }
  ADD  SI, SI          { 1544:0052  doubled to BYTES: the buffer holds words }
  LES  DI, Buf         { 1544:0054  ES:DI := the first sample; Buf is a far pointer }
  MOV  BX, OldSpl      { 1544:0057  the state the caller carried over, or 0 to start }
  MOV  CX, Len         { 1544:005a  how many samples; the kernels LOOP on CX }
  JCXZ @@Done          { 1544:005d  nothing to do -- and BX is already the answer }
  MOV  AL, Method      { 1544:005f  the selector, one byte                 }
  CMP  AL, fm1_2       { 1544:0062  gentlest first: it sits first in the segment }
  JNZ  @@Try2          { 1544:0064                                         }
  CALL Filter1_2Word   { 1544:0066  NEAR -- all four routines share one segment }
  JMP  @@Done          { 1544:0069                                         }
@@Try2:
  CMP  AL, fm3_4       { 1544:006b                                         }
  JNZ  @@Try1          { 1544:006d                                         }
  CALL Filter3_4Word   { 1544:006f                                         }
  JMP  @@Done          { 1544:0072                                         }
@@Try1:
  CMP  AL, fm7_8       { 1544:0074                                         }
  JNZ  @@Done          { 1544:0076  no match, so fmNone: leave the buffer alone }
  CALL Filter7_8Word   { 1544:0078                                         }
@@Done:
  MOV  AX, BX          { 1544:007b  the state, returned for the caller's next chunk }
end;

end.
