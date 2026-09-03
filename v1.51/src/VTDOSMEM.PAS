{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Get memory from DOS, and give it back.

  This is what the sample pool is built on. VTDosRsz hands back the slack the
  .EXE was loaded with; this asks DOS for it again in named blocks. Five
  routines in two layers -- a plain pair that calls DOS directly, and a pair
  that wraps them in the upper-memory dance.

  [re] SEGMENT 1a68 -- 240 bytes, five routines.

      DOSAllocate  1a68:0000   INT 21h $48, with a fallback
      DOSFree   1a68:005a   INT 21h $49
      UMBLink 1a68:0077  INT 21h $5802 / $5803, returns the old state
      UMBAllocate     1a68:0097   UMBLink(1), DOSAllocate, put it back
      UMBFree      1a68:00cb   UMBLink(1), DOSFree, put it back

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

  [re] NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.
  =========================================================================== }

{$X+}   { function results may be discarded -- UMBLink is called for its
          side effect when the old state is being put back }

unit VTDosMem;

interface

{ [re] --------------------------------------------------------------------
  THE FOUR NAMES BELOW ARE THE RELEASE'S, AND THE PAIRING WAS FOUND BY
  MEASUREMENT.
  This unit was on the list of eight with "no counterpart in LIB/" and carried invented
  names for its whole life. `relmatch.py` scores SEGMENT 1a68 against
  `LIB/UMBUNIT.PAS` at 65.5%, with nothing else above 7% -- and the unit's four
  routines line up one for one, signature for signature:

      1a68:0000  AllocRaw   -> DOSAllocate (VAR Buf: POINTER; Size: LONGINT) : LONGINT
      1a68:005a  FreeRaw    -> DOSFree     (VAR Buf: POINTER)
      1a68:0077  SetUMBLink -> UMBLink
      1a68:0097  Alloc      -> UMBAllocate (VAR Buf: POINTER; Size: LONGINT) : LONGINT
      1a68:00cb  Free       -> UMBFree     (VAR Buf: POINTER)

  [re] AND 17cf CONFIRMS TWO OF THEM FROM OUTSIDE. It calls 1a68:0097 exactly once and
  1a68:00cb exactly once, which is `TUmbHeap.Init` calling UMBAllocate and
  `TUmbHeap.Done` calling UMBFree -- the release's HEAPS.PAS says so in those words.

  [re] ONE TYPE IS NOT ADOPTED. The release's `UMBLink` takes and returns a `BOOLEAN`; ours
  is a `Byte`, because the code stores and compares the DOS link state as a number and
  hands the previous value straight back. Same single byte either way, and the standing
  rule is not to change a TYPE to match the release.

  [re] THE FILENAME AND UNIT NAME STAY, for now: renaming a unit touches build.py's ORDER,
  units.py's UNITS and every `uses` clause, and nothing else in the tree references
  these five routines yet.
  -------------------------------------------------------------------------- }

{ 1a68:0097 / 1a68:00cb -- what everything else should call. }
function  UMBAllocate(var P : Pointer; Size : LongInt) : LongInt; far;
procedure UMBFree(var P : Pointer); far;

{ 1a68:0000 / 1a68:005a -- the same without the UMB dance. }
function  DOSAllocate(var P : Pointer; Size : LongInt) : LongInt; far;
procedure DOSFree(var P : Pointer); far;

{ 1a68:0077. Returns the PREVIOUS state, so it can be handed straight back. }
function  UMBLink(State : Byte) : Byte; far;

implementation

{ --------------------------------------------------------------------------
  1a68:0000 -- ask DOS for Size bytes, settle for less rather than fail.

  THE FALLBACK IS THE WHOLE POINT OF THE ROUTINE. When $48 fails it returns,
  in BX, the size of the largest block that WOULD have succeeded -- so instead
  of giving up, this asks for exactly that. A caller wanting 200 KB on a
  machine with 120 KB free gets 120 KB, and is told so by the RETURN VALUE,
  which is the bytes actually obtained rather than the bytes asked for. Only
  if the second attempt also fails does it return zero.

  Only the DOS calls are hand-written; the conversions either side are the
  compiler's own 32-bit shifts.

  THE PARAGRAPH COUNT IS TRUNCATED, not rounded up: there is no `+15` before
  the shift. Asking for 17 bytes asks DOS for one paragraph and reports 16.
  Every caller reads the return value rather than assuming it got what it
  asked for, so this costs nothing, but it is not what a `Size` parameter
  usually implies.

  ON FAILURE the out pointer is set to nil and the result is zero. On success
  the offset is always zero -- these are whole paragraphs, so the pointer is
  a bare SEGMENT.

  [re] Compiler output with an assembler middle, and it has to be that shape:
  the frame is `ENTER 6,0` with a Word local at [BP-6], the two conversions are
  calls to the runtime's 32-bit shift helpers, and only the DOS calls
  themselves are hand-written.

  [re] 1d89:0a9c and 1d89:0aa8 are taken to be 32-bit shift right and shift
  left by CL. The evidence is that they are used here as EXACT INVERSES across
  one allocation -- bytes go in through 0a9c to become paragraphs, paragraphs
  come back out through 0aa8 to become bytes -- and no other reading makes the
  return value mean anything. They are not the multiply and divide helpers at
  1d89:0a13 and 1d89:0a2e, which take a full 32-bit operand in BX:CX.
  -------------------------------------------------------------------------- }
function DOSAllocate(var P : Pointer; Size : LongInt) : LongInt;
var
  Paras : Word;          { [BP-6] }
begin
  Paras := Word(Size shr 4);                      { 1a68:000f  1d89:0a9c }
  asm
    MOV  BX, Paras         { 1a68:0017                                     }
    MOV  AH, 48h           { 1a68:001a  DOS: allocate memory               }
    INT  21h               { 1a68:001c                                     }
    JNC  @@Got             { 1a68:001e                                     }
    MOV  Paras, BX         { 1a68:0020  BX now holds the largest available }
    MOV  AH, 48h           { 1a68:0023  ... so ask for exactly that        }
    INT  21h               { 1a68:0025                                     }
    JNC  @@Got             { 1a68:0027                                     }
    MOV  AX, 0             { 1a68:0029  give up                            }
    MOV  Paras, AX         { 1a68:002c                                     }
  @@Got:
    LES  DI, P             { 1a68:002f  the ADDRESS of the caller's ptr    }
    MOV  ES:[DI+2], AX     { 1a68:0032  the SEGMENT, or 0                  }
    XOR  AX, AX            { 1a68:0036                                     }
    MOV  ES:[DI], AX       { 1a68:0038  the offset is always zero          }
  end;
  DOSAllocate := LongInt(Paras) shl 4;               { 1a68:0045  1d89:0aa8 }
end;

{ --------------------------------------------------------------------------
  1a68:005a -- give a block back.

  IT IS ASSEMBLER BECAUSE INT 21h $49 WANTS THE BLOCK'S SEGMENT IN ES, and
  Pascal has no way to load a SEGMENT register.

  IT CLEARS THE CALLER'S POINTER BEFORE THE DOS CALL, not after, so a free that
  fails still leaves the caller holding nil rather than a stale SEGMENT that
  looks usable. The carry flag is discarded either way, which makes that
  ordering the only thing standing between a failed free and a dangling
  pointer.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Seg := PtrRec(P).Seg;   P := nil;
      Regs.ES := Seg;  Regs.AH := $49;  Intr($21, Regs)
  -------------------------------------------------------------------------- }
procedure DOSFree(var P : Pointer); assembler;
asm
  LES  DI, P             { 1a68:005d  the ADDRESS of the caller's pointer  }
  MOV  AX, ES:[DI+2]     { 1a68:0060  keep the SEGMENT                     }
  XOR  BX, BX            { 1a68:0064                                       }
  MOV  ES:[DI+2], BX     { 1a68:0066  P := nil, before the call            }
  MOV  ES:[DI], BX       { 1a68:006a                                       }
  MOV  ES, AX            { 1a68:006d  $49 wants it here                    }
  MOV  AH, 49h           { 1a68:006f  DOS: free memory                     }
  INT  21h               { 1a68:0071  carry ignored                        }
end;

{ --------------------------------------------------------------------------
  1a68:0077 -- read the UMB link state, set a new one, return the old.

  Two DOS calls, with the first one's answer carried across the second on the
  stack. Assembler because the answer has to survive a second INT 21h that
  overwrites the register holding it.

  On error it returns ZERO rather than reporting the failure: `MOV AH,0`
  happens before the carry test, and the exit does `MOV AL,AH`. Zero is also
  a legitimate state ("UMBs not linked"), so a caller cannot tell a failure
  from a machine with no upper memory -- and does not need to, because
  restoring state zero on such a machine is a no-op.
  -------------------------------------------------------------------------- }
function UMBLink(State : Byte) : Byte; assembler;
asm
  MOV  AX, 5802h         { 1a68:007a  DOS: get UMB link state              }
  INT  21h               { 1a68:007d                                       }
  MOV  AH, 0             { 1a68:007f  the answer if it failed              }
  JC   @@Out             { 1a68:0081                                       }
  MOV  AH, AL            { 1a68:0083  keep the old state                   }
  PUSH AX                { 1a68:0085  ... across the second call           }
  MOV  AX, 5803h         { 1a68:0086  DOS: set UMB link state              }
  XOR  BH, BH            { 1a68:0089                                       }
  MOV  BL, State         { 1a68:008b                                       }
  INT  21h               { 1a68:008e                                       }
  POP  AX                { 1a68:0090                                       }
@@Out:
  MOV  AL, AH            { 1a68:0091  the result                           }
end;

{ --------------------------------------------------------------------------
  Allocate with upper memory linked in for the duration, then put the link
  state back.

  ON A 386 WITH EMM386 LOADED this is what makes upper memory allocatable at
  all. Linking UMBs into the DOS chain lets $48 hand out blocks above 640 KB,
  which on a machine with a crowded low 640 can be the difference between a
  module fitting and not.

  THE OLD STATE IS ALWAYS RESTORED, and that matters more than it looks: the
  player shells out to other programs, and leaving the DOS memory chain
  reconfigured would change how THEY allocate.

  The result is saved before the link state is put back, so the restore cannot
  disturb it.

  [re] 1a68:0097. Plain Pascal in the binary: `ENTER`, a byte local for the old
  state, and three near calls with `PUSH CS` in front of them, which is how
  Borland Pascal reaches a far routine in its own SEGMENT.
  -------------------------------------------------------------------------- }
function UMBAllocate(var P : Pointer; Size : LongInt) : LongInt;
var
  Old : Byte;            { [BP-5] }
begin
  Old := UMBLink(1);                           { 1a68:009b }
  UMBAllocate := DOSAllocate(P, Size);                     { 1a68:00b0 }
  UMBLink(Old);                                { 1a68:00be }
end;

{ --------------------------------------------------------------------------
  Free with upper memory linked in, then put the link state back.

  THE LINK STATE MUST MATCH THE ONE THE BLOCK WAS ALLOCATED UNDER, which is why
  freeing needs the same dance as allocating rather than being a bare $49: a
  UMB freed with the chain unlinked is not returned to the pool it came from.

  [re] 1a68:00cb. Same shape as UMBAllocate above.
  -------------------------------------------------------------------------- }
procedure UMBFree(var P : Pointer);
var
  Old : Byte;            { [BP-1] }
begin
  Old := UMBLink(1);                           { 1a68:00cf }
  DOSFree(P);                                     { 1a68:00de }
  UMBLink(Old);                                { 1a68:00e6 }
end;

end.
