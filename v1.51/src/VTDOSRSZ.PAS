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
  into a length.

  [re] SEGMENT 1a77 -- 32 bytes, of which 29 are the one routine.

  [re] NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.

  [re] 1a77 IN THIS IMAGE, NOT 188f. The map said 188f, which is this unit's
  SEGMENT in v1.31b; these addresses were inherited when the file was and
  never re-based. Measured two ways -- segpair --pair over the two
  reference images, and a byte search bounded by the paired extent: a 16-byte PREFIX only, at 1a77:0000 -- located, code CHANGED.
  The per-line addresses through this file are re-based to this image too;
  the OFFSETS are inherited and are verified only where an @asm marker sits.
  [re] ADDRESS MAP
    SetMemTop  1a77:0000
  =========================================================================== }

{ This unit is held to 8086 instructions. $G- forbids the 80286 forms Turbo
  Pascal would otherwise emit, and it must stay LOCAL to this unit -- most of
  the rest of the program does use 286 instructions and will not build under
  it. }

{ [re] IT IS THE $G SETTING, and this unit is the only one in the program that
  wants it off. At +$1b the original has 5D (POP BP) where a $G+ build emits
  C9 (LEAVE) -- LEAVE is an 80286 instruction, so $G- cannot use it. With the
  directive below the unit is byte-identical on both Turbo Pascal 6 and 7.

  ~~An earlier note here said $G- changed nothing~~ and left the byte
  unexplained. It does change it, on both compilers. Building the whole tree
  with it wrecks twelve of the fifteen, 164b and 1650 among them. }
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

  [re] HAND ASSEMBLER, verbatim, and it can be nothing else: INT 21h with a
  SEGMENT register as an argument is not expressible in Pascal. The original
  reads its base SEGMENT from DS:$0c62, which is NOT copied here -- no absolute
  DGROUP address crosses over. It is Turbo Pascal's own `PrefixSeg`, and the
  identification is from the DOS API rather than from the address: INT 21h $4A
  requires ES to hold the SEGMENT of an MCB-owned block, and for a running
  program that is the PSP.

  [re] THE PARAMETER IS ONE `Pointer`, NOT TWO `Word`s, AND A CALLER IN ANOTHER
  SEGMENT IS WHAT SETTLED IT. This was declared `SetBlockTop(TopSeg,
  ExtraBytes : Word)` for as long as it existed, and it verified IDENTICAL the
  whole time -- because both spellings put the same four bytes on the stack, so
  nothing inside these 29 bytes can tell them apart. 19b7:01e0 can: it is
  `PUSH [0c4a] / PUSH [0c48]`, a pointer variable pushed whole, where two
  `Word` arguments taken from a pointer compile to `LES DI,[..] / PUSH ES /
  LES DI,[..] / PUSH DI` -- four instructions instead of two.

  **A PARAMETER LIST CAN BE WRONG IN A WAY ONLY A CALLER IN ANOTHER SEGMENT
  REVEALS**, and no amount of verifying THIS unit would ever have found it.

  [re] AND THE NAME IS `SetMemTop`, which is Borland's. Read as a pointer the
  arithmetic is `(Ofs(P) + 15) shr 4 + Seg(P) - PrefixSeg` -- the paragraph
  count needed to reach P -- which is what Turbo Vision's `Memory.SetMemTop`
  does, and the release's `HEAPS.PAS` calls `SetMemTop(HeapEnd)` at exactly the
  point 19b7:01d3 calls this. So **SEGMENT 1a77 is probably Borland's `Memory`
  UNIT rather than DemoVT's own**, smart-linked down to the one routine
  anything references. THE FILENAME AND UNIT NAME ARE STILL THE INVENTED ONES,
  deliberately: renaming a unit touches the build order, the unit table, every
  `uses` clause and this header, and the identification is strong rather than
  certain.
  -------------------------------------------------------------------------- }
{ @asm 000 1a77:0000 }
procedure SetMemTop(P : Pointer); assembler;
asm
  MOV  BX, WORD PTR P    { 1a77:0003  [BP+06h] -- Ofs(P)                    }
  ADD  BX, 000Fh         { 1a77:0006  round up to a whole paragraph         }
  MOV  CL, 4             { 1a77:0009  8086: no shift by immediate > 1       }
  SHR  BX, CL            { 1a77:000b  bytes -> paragraphs                   }
  ADD  BX, WORD PTR P+2  { 1a77:000d  [BP+08h] -- Seg(P), giving the top    }
  MOV  AX, PrefixSeg     { 1a77:0010  the program's own PSP SEGMENT         }
  SUB  BX, AX            { 1a77:0013  absolute top -> a length in paragraphs}
  MOV  ES, AX            { 1a77:0015  $4A wants the block's own SEGMENT     }
  MOV  AH, 4Ah           { 1a77:0017  DOS: resize memory block              }
  INT  21h               { 1a77:0019  carry ignored -- see above            }
end;

end.
