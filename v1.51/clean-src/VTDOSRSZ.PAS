{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Segment 188f -- shrink the program's memory block. 32 bytes, of which 29
  are the one routine.

  DemoVT starts as an ordinary .EXE, so DOS has given it every free paragraph
  in memory. Before it can allocate anything of its own -- the audio buffer,
  the sample pool -- it has to hand back what it is not using, and INT 21h
  function $4A is how. Its companion 1880 does the $48/$49 allocation that
  becomes possible afterwards.

  The new size is worked out as "end here", not "keep this much":

      paragraphs := (TopSeg + ceil(ExtraBytes / 16)) - PrefixSeg

  so the caller names the segment it wants the block to reach rather than
  having to know where the program starts.

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.

  ADDRESS MAP
    SetMemTop  188f:0000
  =========================================================================== }

{ IT IS THE $G SETTING, and this unit is the only one in the program that
  wants it off. At +$1b the original has 5D (POP BP) where a $G+ build emits
  C9 (LEAVE) -- LEAVE is an 80286 instruction, so $G- cannot use it. With the
  directive below the unit is byte-identical on both Turbo Pascal 6 and 7.

  An earlier note here said $G- changed nothing and left the byte unexplained.
  It does change it, on both compilers -- whatever went wrong with that test,
  the conclusion did not hold. $G- must stay LOCAL to this unit -- building the whole tree with it wrecks twelve of the
  fifteen, 164b and 1650 among them, because they do use 286 instructions. }
{$G-}

unit VTDosRsz;

interface

procedure SetMemTop(P : Pointer);

implementation

{ --------------------------------------------------------------------------
  188f:0000.

  HAND ASSEMBLER, verbatim, and it can be nothing else: INT 21h with a
  segment register as an argument is not expressible in Pascal.

  The original reads its base segment from DS:$0c62. That is NOT copied here:
  the standing rule is that no absolute DGROUP address crosses over. It is
  Turbo Pascal's own `PrefixSeg`, and the identification is from the DOS API
  rather than from the address -- INT 21h $4A requires ES to hold the segment
  of an MCB-owned block, and for a running program that is the PSP. Nothing
  else it could be.

  Note `MOV CL,4 / SHR BX,CL` rather than `SHR BX,4`. Shifting by an
  immediate greater than one is a 186 instruction, so this routine runs on an
unlike 1544, whose filter kernels use `SAR AX,2` and do not. The
  two were plainly written by different hands or at different times.

  The result of INT 21h is DISCARDED. Carry means the shrink failed, and
  nothing looks. That is survivable only because shrinking a block you
  already own cannot fail for any reason the caller could act on.

  THE PARAMETER IS ONE `Pointer`, NOT TWO `Word`s, AND A CALLER IN ANOTHER SEGMENT IS
  WHAT SETTLED IT. This routine was declared `SetBlockTop(TopSeg, ExtraBytes : Word)`
  for as long as it existed, and it verified IDENTICAL the whole time -- because both
  spellings put the same four bytes on the stack, so nothing inside these 29 bytes can
  tell them apart. 17cf:01e0 can: it is `PUSH [0c4a] / PUSH [0c48]`, a pointer variable
  pushed whole, where two `Word` arguments taken from a pointer compile to
  `LES DI,[..] / PUSH ES / LES DI,[..] / PUSH DI` -- four instructions instead of two.

  **A PARAMETER LIST CAN BE WRONG IN A WAY ONLY A CALLER IN ANOTHER SEGMENT REVEALS**,
  and no amount of verifying THIS unit would ever have found it.

  AND THE NAME IS `SetMemTop`, which is Borland's. Read as a pointer the arithmetic is
  `(Ofs(P) + 15) shr 4 + Seg(P) - PrefixSeg` -- the paragraph count needed to reach P --
  which is what Turbo Vision's `Memory.SetMemTop` does, and the release's `HEAPS.PAS`
  calls `SetMemTop(HeapEnd)` at exactly the point 17cf:01d3 calls this. So **segment
  188f is probably Borland's `Memory` UNIT rather than DemoVT's own**, smart-linked down
  to the one routine anything references: 32 bytes is a single procedure, and TP's
  linker discards what a unit does not use.

  THE FILENAME AND UNIT NAME ARE STILL THE INVENTED ONES, deliberately. Renaming a unit
  touches build.py's ORDER, units.py's UNITS, every `uses` clause and this header, and
  the identification is strong rather than certain -- 29 bytes are consistent with
  Borland's source without proving they came from it.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Regs.BX := (Ofs(P) + 15) shr 4 + Seg(P) - PrefixSeg;
      Regs.ES := PrefixSeg;
      Regs.AH := $4A;
      Intr($21, Regs)
  -------------------------------------------------------------------------- }
procedure SetMemTop(P : Pointer); assembler;
asm
  MOV  BX, WORD PTR P    { [BP+06h] -- Ofs(P)                    }
  ADD  BX, 000Fh         { round up to a whole paragraph         }
  MOV  CL, 4             { 8086: no shift by immediate > 1       }
  SHR  BX, CL            { bytes -> paragraphs                   }
  ADD  BX, WORD PTR P+2  { [BP+08h] -- Seg(P)                    }
  MOV  AX, PrefixSeg     { was MOV AX,[0C62h]                    }
  SUB  BX, AX            { absolute top -> a length              }
  MOV  ES, AX            { $4A wants the block's own segment     }
  MOV  AH, 4Ah           { DOS: resize memory block              }
  INT  21h               { carry ignored -- see above            }
end;

end.
