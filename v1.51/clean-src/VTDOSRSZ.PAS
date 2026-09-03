{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Shrink the program's own memory block, so that it can allocate.

  WHY THIS HAS TO HAPPEN FIRST. DemoVT starts as an ordinary .EXE, and DOS
  hands such a program every free paragraph in memory. Nothing is left for
  INT 21h $48 to hand back, so before the player can allocate anything of its
  own -- the audio buffer, the sample pool -- it has to give back what it is
  not using. INT 21h function $4A is how. Its companion VTDosMem does the
  $48/$49 allocation that becomes possible afterwards.

  THE NEW SIZE IS "END HERE", NOT "KEEP THIS MUCH":

      paragraphs := (TopSeg + ceil(ExtraBytes / 16)) - PrefixSeg

  so a caller names the address it wants the block to reach and does not have
  to know where the program starts. That is why the parameter is a pointer:
  the caller passes the end of its own heap and the arithmetic here turns that
  into a length. }

{ This unit is held to 8086 instructions. $G- forbids the 80286 forms Turbo
  Pascal would otherwise emit, and it must stay LOCAL to this unit -- most of
  the rest of the program does use 286 instructions and will not build under
  it. }

{$G-}

unit VTDosRsz;

interface

procedure SetMemTop(P : Pointer);

implementation

{ --------------------------------------------------------------------------
  Ask DOS to shrink this program's memory block so that it ends at `P`.

  `P` is an address, not a size. Everything from the program's start up to `P`
  is kept; everything above it is returned to DOS and becomes available to
  later allocations. Passing a pointer BELOW the program's own code would ask
  DOS to discard the running program, and nothing here stops that -- the
  caller is trusted to pass the top of its heap.

  THE RESULT IS DISCARDED. Carry set means the shrink failed and nothing
  looks. That is survivable because shrinking a block you already own cannot
  fail for any reason a caller could act on: DOS refuses only if the block is
  not yours or the new size is larger, and neither is reachable from here.

  IT RUNS ON AN 8086. `MOV CL,4 / SHR BX,CL` rather than `SHR BX,4`, because
  shifting by an immediate greater than one is an 80286 instruction. Worth
  noticing, because the filter kernels in Filters do NOT hold to that -- they
  use `SAR AX,2` freely. The two were written to different assumptions.

  EQUIVALENT PASCAL, REFERENCE ONLY -- the assembler below is what runs:

      Regs.BX := (Ofs(P) + 15) shr 4 + Seg(P) - PrefixSeg;
      Regs.ES := PrefixSeg;
      Regs.AH := $4A;
      Intr($21, Regs)

  **A PARAMETER LIST CAN BE WRONG IN A WAY ONLY A CALLER IN ANOTHER SEGMENT
  REVEALS**, and no amount of verifying THIS unit would ever have found it. }
procedure SetMemTop(P : Pointer); assembler;
asm
  MOV  BX, WORD PTR P    { Ofs(P)                    }
  ADD  BX, 000Fh         { round up to a whole paragraph         }
  MOV  CL, 4             { 8086: no shift by immediate > 1       }
  SHR  BX, CL            { bytes -> paragraphs                   }
  ADD  BX, WORD PTR P+2  { Seg(P), giving the top    }
  MOV  AX, PrefixSeg     { the program's own PSP SEGMENT         }
  SUB  BX, AX            { absolute top -> a length in paragraphs}
  MOV  ES, AX            { $4A wants the block's own SEGMENT     }
  MOV  AH, 4Ah           { DOS: resize memory block              }
  INT  21h               { carry ignored -- see above            }
end;

end.
