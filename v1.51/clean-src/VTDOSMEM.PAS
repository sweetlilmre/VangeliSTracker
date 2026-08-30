{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Get memory from DOS, and give it back.

  This is what the sample pool is built on. VTDosRsz hands back the slack the
  .EXE was loaded with; this asks DOS for it again in named blocks. Five
  routines in two layers -- a plain pair that calls DOS directly, and a pair
  that wraps them in the upper-memory dance.

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
  shells out to, and it shells out to every part of the demo.}

{$X+}   { function results may be discarded -- UMBLink is called for its
          side effect when the old state is being put back }

unit VTDosMem;

interface



{ what everything else should call. }
function  UMBAllocate(var P : Pointer; Size : LongInt) : LongInt; far;
procedure UMBFree(var P : Pointer); far;

{ the same without the UMB dance. }
function  DOSAllocate(var P : Pointer; Size : LongInt) : LongInt; far;
procedure DOSFree(var P : Pointer); far;

{ Returns the PREVIOUS state, so it can be handed straight back. }
function  UMBLink(State : Byte) : Byte; far;

implementation

{ --------------------------------------------------------------------------
ask DOS for Size bytes, settle for less rather than fail.

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
  a bare segment.}
function DOSAllocate(var P : Pointer; Size : LongInt) : LongInt;
var
  Paras : Word;
begin
  Paras := Word(Size shr 4);
  asm
    MOV  BX, Paras
    MOV  AH, 48h           { DOS: allocate memory               }
    INT  21h
    JNC  @@Got
    MOV  Paras, BX         { BX now holds the largest available }
    MOV  AH, 48h           { ... so ask for exactly that        }
    INT  21h
    JNC  @@Got
    MOV  AX, 0             { give up                            }
    MOV  Paras, AX
  @@Got:
    LES  DI, P             { the ADDRESS of the caller's ptr    }
    MOV  ES:[DI+2], AX     { the segment, or 0                  }
    XOR  AX, AX
    MOV  ES:[DI], AX       { the offset is always zero          }
  end;
  DOSAllocate := LongInt(Paras) shl 4;
end;

{ --------------------------------------------------------------------------
give a block back.

  IT IS ASSEMBLER BECAUSE INT 21h $49 WANTS THE BLOCK'S SEGMENT IN ES, and
  Pascal has no way to load a segment register.

  IT CLEARS THE CALLER'S POINTER BEFORE THE DOS CALL, not after, so a free that
  fails still leaves the caller holding nil rather than a stale segment that
  looks usable. The carry flag is discarded either way, which makes that
  ordering the only thing standing between a failed free and a dangling
  pointer.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Seg := PtrRec(P).Seg;   P := nil;
      Regs.ES := Seg;  Regs.AH := $49;  Intr($21, Regs)
  -------------------------------------------------------------------------- }
procedure DOSFree(var P : Pointer); assembler;
asm
  LES  DI, P             { the ADDRESS of the caller's pointer  }
  MOV  AX, ES:[DI+2]     { keep the segment                     }
  XOR  BX, BX
  MOV  ES:[DI+2], BX     { P := nil, before the call            }
  MOV  ES:[DI], BX
  MOV  ES, AX            { $49 wants it here                    }
  MOV  AH, 49h           { DOS: free memory                     }
  INT  21h               { carry ignored                        }
end;

{ --------------------------------------------------------------------------
read the UMB link state, set a new one, return the old.

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
  MOV  AX, 5802h         { DOS: get UMB link state              }
  INT  21h
  MOV  AH, 0             { the answer if it failed              }
  JC   @@Out
  MOV  AH, AL            { keep the old state                   }
  PUSH AX                { ... across the second call           }
  MOV  AX, 5803h         { DOS: set UMB link state              }
  XOR  BH, BH
  MOV  BL, State
  INT  21h
  POP  AX
@@Out:
  MOV  AL, AH            { the result                           }
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
  disturb it.}
function UMBAllocate(var P : Pointer; Size : LongInt) : LongInt;
var
  Old : Byte;
begin
  Old := UMBLink(1);
  UMBAllocate := DOSAllocate(P, Size);
  UMBLink(Old);
end;

{ --------------------------------------------------------------------------
  Free with upper memory linked in, then put the link state back.

  THE LINK STATE MUST MATCH THE ONE THE BLOCK WAS ALLOCATED UNDER, which is why
  freeing needs the same dance as allocating rather than being a bare $49: a
  UMB freed with the chain unlinked is not returned to the pool it came from.}
procedure UMBFree(var P : Pointer);
var
  Old : Byte;
begin
  Old := UMBLink(1);
  DOSFree(P);
  UMBLink(Old);
end;

end.
