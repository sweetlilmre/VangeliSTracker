{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 1880 -- DOS memory blocks. 240 bytes, five routines.

  This is what 17cf's pool is built on: 188f hands back the slack the .EXE was
  loaded with, and this asks DOS for it again in named blocks.

  Five routines, in two layers:

      DOSAllocate  1880:0000   INT 21h $48, with a fallback
      DOSFree   1880:005a   INT 21h $49
      UMBLink 1880:0077  INT 21h $5802 / $5803, returns the old state
      UMBAllocate     1880:0097   UMBLink(1), DOSAllocate, put it back
      UMBFree      1880:00cb   UMBLink(1), DOSFree, put it back

  THE FALLBACK IS THE INTERESTING PART. When $48 fails it returns, in BX, the
  size of the largest block that WOULD have succeeded -- and DOSAllocate
  immediately asks for that instead of giving up. A caller that wants 200 KB
  and can live with 120 KB gets 120 KB and is told so by the return value,
  which is the number of bytes actually obtained rather than the number asked
  for. Only if that second attempt also fails does it return zero.

  THE UMB WRAPPERS matter on a 386 with EMM386 loaded. Linking upper memory
  into the DOS chain makes those blocks allocatable, which on a machine with
  a crowded low 640 KB can be the difference between a module fitting and
  not. The old state is always restored, so DemoVT does not leave the DOS
  memory chain reconfigured behind it -- which would affect whatever it
  shells out to, and it shells out to every part of the demo.

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.
  =========================================================================== }

{$X+}   { function results may be discarded -- UMBLink is called for its
          side effect when the old state is being put back }

unit VTDosMem;

interface

{ --------------------------------------------------------------------------
  THE FOUR NAMES BELOW ARE THE RELEASE'S, AND THE PAIRING WAS FOUND BY MEASUREMENT.
  This unit was on the list of eight with "no counterpart in LIB/" and carried invented
  names for its whole life. `demovt/relmatch.py` scores segment 1880 against
  `LIB/UMBUNIT.PAS` at 65.5%, with nothing else above 7% -- and the unit's four
  routines line up one for one, signature for signature:

AllocRaw   -> DOSAllocate (VAR Buf: POINTER; Size: LONGINT) : LONGINT
FreeRaw    -> DOSFree     (VAR Buf: POINTER)
SetUMBLink -> UMBLink
Alloc      -> UMBAllocate (VAR Buf: POINTER; Size: LONGINT) : LONGINT
Free       -> UMBFree     (VAR Buf: POINTER)

  AND 17cf CONFIRMS TWO OF THEM FROM OUTSIDE. It calls 1880:0097 exactly once and
exactly once, which is `TUmbHeap.Init` calling UMBAllocate and
  `TUmbHeap.Done` calling UMBFree -- the release's HEAPS.PAS says so in those words.

  ONE TYPE IS NOT ADOPTED. The release's `UMBLink` takes and returns a `BOOLEAN`; ours
  is a `Byte`, because the code stores and compares the DOS link state as a number and
  hands the previous value straight back. Same single byte either way, and the standing
  rule is not to change a TYPE to match the release.

  THE FILENAME AND UNIT NAME STAY, for now: renaming a unit touches build.py's ORDER,
  verify.py's UNITS and every `uses` clause, and nothing else in the tree references
  these five routines yet.
  -------------------------------------------------------------------------- }

{what everything else should call. }
function  UMBAllocate(var P : Pointer; Size : LongInt) : LongInt; far;
procedure UMBFree(var P : Pointer); far;

{the same without the UMB dance. }
function  DOSAllocate(var P : Pointer; Size : LongInt) : LongInt; far;
procedure DOSFree(var P : Pointer); far;

{ 1880:0077. Returns the PREVIOUS state, so it can be handed straight back. }
function  UMBLink(State : Byte) : Byte; far;

implementation

{ --------------------------------------------------------------------------
ask DOS for Size bytes, settle for less rather than fail.

  Compiler output with an assembler middle, and it has to be that shape: the
  frame is `ENTER 6,0` with a Word local at [BP-6], the two conversions are
  calls to the runtime's 32-bit shift helpers, and only the DOS calls
  themselves are hand-written.

and 1ba1:0aa8 are taken to be 32-bit shift right and shift left
  by CL. The evidence is that they are used here as EXACT INVERSES across one
  allocation -- bytes go in through 0a9c to become paragraphs, paragraphs come
  back out through 0aa8 to become bytes -- and no other reading makes the
  return value mean anything. They are not the multiply and divide helpers at
and 1ba1:0a2e, which take a full 32-bit operand in BX:CX.

  THE PARAGRAPH COUNT IS TRUNCATED, not rounded up: there is no `+15` before
  the shift. Asking for 17 bytes asks DOS for one paragraph and reports 16.
  Every caller reads the return value rather than assuming it got what it
  asked for, so this costs nothing, but it is not what a `Size` parameter
  usually implies.

  ON FAILURE the out pointer is set to nil and the result is zero. On success
  the offset is always zero -- these are whole paragraphs, so the pointer is
  a bare segment.
  -------------------------------------------------------------------------- }
function DOSAllocate(var P : Pointer; Size : LongInt) : LongInt;
var
  Paras : Word;          { [BP-6] }
begin
  Paras := Word(Size shr 4);
  asm
    MOV  BX, Paras
    MOV  AH, 48h           {DOS: allocate memory               }
    INT  21h
    JNC  @@Got
    MOV  Paras, BX         {BX now holds the largest available }
    MOV  AH, 48h           {... so ask for exactly that        }
    INT  21h
    JNC  @@Got
    MOV  AX, 0             {give up                            }
    MOV  Paras, AX
  @@Got:
    LES  DI, P             {the ADDRESS of the caller's ptr    }
    MOV  ES:[DI+2], AX     {the segment, or 0                  }
    XOR  AX, AX
    MOV  ES:[DI], AX       {the offset is always zero          }
  end;
  DOSAllocate := LongInt(Paras) shl 4;
end;

{ --------------------------------------------------------------------------
give a block back.

  HAND ASSEMBLER, verbatim: INT 21h $49 wants the block's segment in ES, and
  Pascal cannot load a segment register.

  It clears the caller's pointer BEFORE the DOS call, not after, so a UMBFree
  that fails still leaves the caller holding nil rather than a stale segment.
  The carry flag is discarded either way.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Seg := PtrRec(P).Seg;   P := nil;
      Regs.ES := Seg;  Regs.AH := $49;  Intr($21, Regs)
  -------------------------------------------------------------------------- }
procedure DOSFree(var P : Pointer); assembler;
asm
  LES  DI, P             {the ADDRESS of the caller's pointer  }
  MOV  AX, ES:[DI+2]     {keep the segment                     }
  XOR  BX, BX
  MOV  ES:[DI+2], BX     {P := nil, before the call            }
  MOV  ES:[DI], BX
  MOV  ES, AX            {$49 wants it here                    }
  MOV  AH, 49h           {DOS: free memory                     }
  INT  21h               {carry ignored                        }
end;

{ --------------------------------------------------------------------------
read the UMB link state, set a new one, return the old.

  HAND ASSEMBLER, verbatim. Two DOS calls with the first one's answer carried
  across the second on the stack.

  On error it returns ZERO rather than reporting the failure: `MOV AH,0`
  happens before the carry test, and the exit does `MOV AL,AH`. Zero is also
  a legitimate state ("UMBs not linked"), so a caller cannot tell a failure
  from a machine with no upper memory -- and does not need to, because
  restoring state zero on such a machine is a no-op.
  -------------------------------------------------------------------------- }
function UMBLink(State : Byte) : Byte; assembler;
asm
  MOV  AX, 5802h         {DOS: get UMB link state              }
  INT  21h
  MOV  AH, 0             {the answer if it failed              }
  JC   @@Out
  MOV  AH, AL            {keep the old state                   }
  PUSH AX                {... across the second call           }
  MOV  AX, 5803h         {DOS: set UMB link state              }
  XOR  BH, BH
  MOV  BL, State
  INT  21h
  POP  AX
@@Out:
  MOV  AL, AH            {the result                           }
end;

{ --------------------------------------------------------------------------
and 1880:00cb -- the same two operations with upper memory linked
  in for the duration.

  Plain Pascal in the binary: `ENTER`, a byte local for the old state, and
  three near calls with `PUSH CS` in front of them, which is how Borland
  Pascal reaches a far routine in its own segment.

  Both save the result before restoring the link state, so the restore cannot
  disturb it.
  -------------------------------------------------------------------------- }
function UMBAllocate(var P : Pointer; Size : LongInt) : LongInt;
var
  Old : Byte;            { [BP-5] }
begin
  Old := UMBLink(1);
  UMBAllocate := DOSAllocate(P, Size);
  UMBLink(Old);
end;

procedure UMBFree(var P : Pointer);
var
  Old : Byte;            { [BP-1] }
begin
  Old := UMBLink(1);
  DOSFree(P);
  UMBLink(Old);
end;

end.
