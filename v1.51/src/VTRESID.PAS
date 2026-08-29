{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 1b54 -- residency: the INT 2Fh server, the chain to whoever held
  the vector before, and the exit handler that gives it back. 432 bytes, all
  of it, nothing left unread.

  This is the half of the handshake that the Psycho Neurosis reconstruction's
  own src/DEMOVT.PAS talks to. Everything that file assumes is confirmed here
  -- see demovt/docs/01-int2f.md.

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information, so no unit
  or routine name survives.

  ADDRESS MAP
    OldInt2F     1b54:0000     Handler      1b54:0006
    ExitHandler  1b54:002f     'Ojo...'     1b54:0061
    ' residente' 1b54:007b     Install      1b54:0088
  =========================================================================== }

unit VTResid;

interface

procedure Install(Name : String; Block : Pointer);

implementation

const
  { The handshake. 'VT' 'Tr' 'ac' spells VTrac(ker); the reply is not stored
    anywhere, it is computed by XORing the request with these two masks. }
  ReqAX = $5654;    ReqBX = $5472;    ReqCX = $6163;
  MaskBX = $6B65;   MaskCX = $7220;   { $5472 xor $6B65 = $3F17 }
                                      { $6163 xor $7220 = $1343 }

  { 1b54:0061 and 1b54:007b. CP437: #173 is the inverted exclamation mark,
    #162 an o-acute. }
  Already = #13#10'    ' + #173#173 + 'Ojo, que est' + #160 + ' el ';
  Resident = ' residente!!';

  { 1caa:0c20 -- ten characters, stood in for the name of a resident that
    answered the handshake but returned a null ES:DI. Written with #168 for
    the inverted question mark so this file stays seven-bit; the binary holds
    it as CP437 $A8.

    TYPED, not a plain constant, because Install takes its ADDRESS. An
    untyped Pascal constant has no storage and `@` on one will not compile;
    in the original this is simply a string sitting in DGROUP at $0c20, which
    is exactly what a typed constant produces. }
  NoName : String[10] = #168'?'#168'?'#168'? :-(';

var
  Stub      : Pointer;   { DS:$4324 -> OldInt2F                             }
  { NOT VTCtrl's `CtrlBlock`, which is the 768-byte structure itself at $461a.
    This is a FAR POINTER TO IT, in this unit's implementation section and so not
    public -- which is why the linker map cannot settle its address and the
    relative check is all it gets. Two variables, one name, and the map lists the
    other one. }
  CtrlBlock : Pointer;   { DS:$4328 -- what a client reads at ES:[DI-4]     }
  SelfName  : String;    { DS:$0006 -- what INT 2Fh answers with in ES:DI   }
  SavedExit : Pointer;   { DS:$442c -- the ExitProc we displaced            }

{ --------------------------------------------------------------------------
  1b54:0000 -- the chain to the previous INT 2Fh handler.

  HAND ASSEMBLER, and it must be: like the timer chain in the program itself,
  this is a five-byte JMP FAR whose OPERAND is the storage. Install patches
  the two words at +1 and +3 with the vector it displaced, and ExitHandler
  reads them straight back out of the instruction.

  It is assembled pointing at itself, which is why the disassembly shows
  `JMP FAR 1b54:0000` at 1b54:0000.
  -------------------------------------------------------------------------- }
procedure OldInt2F; assembler;
asm
  DB   0EAh              { 1b54:0000  JMP FAR seg:ofs                        }
  DW   OFFSET OldInt2F   { 1b54:0001  patched with the old INT 2Fh offset     }
  DW   SEG OldInt2F      { 1b54:0003  patched with the old INT 2Fh segment    }
                         { 1b54:0005  RET -- supplied by Pascal, not written  }
                         { here: an assembler procedure already gets an  }
                         { epilogue and a written one duplicates it.     }
end;

{ --------------------------------------------------------------------------
  1b54:0006 -- the INT 2Fh handler.

  HAND ASSEMBLER, verbatim. Pascal cannot express it: it must not touch a
  single register it has not been asked about, it answers in AX/BX/CX/ES/DI
  rather than by returning anything, and it either IRETs or falls through to
  a JMP FAR at another address entirely.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if (AX = $5654) and (BX = $5472) and (CX = $6163) then
      begin
        AX := 0;  BX := $3F17;  CX := $1343;
        ES := Seg(SelfName);  DI := Ofs(SelfName);
        IRET
      end
      else chain to the old handler;

  -------------------------------------------------------------------------- }
procedure Handler; assembler;
asm
  STI                    { 1b54:0006  DOS multiplex handlers run enabled     }
  CMP  AX, ReqAX         { 1b54:0007  'VT'                                   }
  JNZ  @@NotUs           { 1b54:000a                                         }
  CMP  BX, ReqBX         { 1b54:000c  'Tr'                                   }
  JNZ  @@NotUs           { 1b54:0010                                         }
  CMP  CX, ReqCX         { 1b54:0012  'ac'                                   }
  JNZ  @@NotUs           { 1b54:0016                                         }
  XOR  AX, AX            { 1b54:0018  AX := 0 says "yes, and it is me"       }
  XOR  BX, MaskBX        { 1b54:001a  -> $3F17                               }
  XOR  CX, MaskCX        { 1b54:001e  -> $1343                               }
  MOV  DI, SEG @DATA     { 1b54:0022  the binary has MOV DI,1CAAh -- an
                                      absolute segment, not ours to copy     }
  MOV  ES, DI            { 1b54:0025                                         }
  MOV  DI, OFFSET SelfName  { 1b54:0027  the binary has 432Ch. The four bytes
                              BELOW this are CtrlBlock, which is why a client
                              reads its control block from ES:[DI-4].        }
  IRET                   { 1b54:002a                                         }
@@NotUs:
  { A NEAR JUMP, not a far one. The original is `E9 D2FF` -- three bytes
    back to offset 0000 -- because the chain target IS the JMP FAR stub
    above, whose operand holds the displaced vector. Jumping FAR here
    assembles a five-byte JMP to the stub's address instead, which is two
    bytes longer and one indirection short of the idiom. }
  JMP  OldInt2F          { 1b54:002b  every failed test lands here           }
end;

{ --------------------------------------------------------------------------
  1b54:002f -- the ExitProc. Put INT 2Fh back and hand the exit chain on.

  The old vector is read out of the JMP FAR's own operand bytes, +1 and +3.
  -------------------------------------------------------------------------- }
procedure ExitHandler; far;
begin
  ExitProc := SavedExit;                          { 1b54:0032, 1b54:0039 }
  asm
    LES  DI, Stub          { 1b54:0040                                       }
    MOV  AX, ES:[DI+1]     { 1b54:0044  the displaced offset                 }
    MOV  DX, ES:[DI+3]     { 1b54:0048  and segment                          }
    MOV  SI, 0             { 1b54:004c  MOV, not XOR -- the original loads an }
                           { immediate zero, and BASM emits what it is told   }
    MOV  ES, SI            { 1b54:004f  ES := 0000, the vector table         }
    MOV  ES:[0BCh], AX     { 1b54:0051  $2F * 4                              }
    MOV  SI, 0             { 1b54:0055                                       }
    MOV  ES, SI            { 1b54:0058                                       }
    MOV  ES:[0BEh], DX     { 1b54:005a                                       }
  end;
end;

{ --------------------------------------------------------------------------
  1b54:0088 -- go resident.

  RETF 8: Name at [BP+$0a], Block at [BP+6]. The program calls it as
  Install('DemoVT v1.31 (beta)', @CtrlBlock).

  It runs the very same handshake a client would first, and refuses to
  install over a copy that is already there. The name it prints in that case
  is the OTHER copy's, read from the ES:DI it answered with -- which is why
  there is a fallback string for a resident that answers 0:0.
  -------------------------------------------------------------------------- }
{ THE FRAME IS `ENTER 0206,0` AND ONLY $106 OF IT IS DECLARED. The other 256
  bytes are at [BP-$206] and they are a COMPILER TEMPORARY, not a variable: the
  string the WriteLn below concatenates. This procedure previously declared an
  `S : String` to account for them and copied `Name` into it, which put every
  local 256 bytes lower than the original's -- eleven single-byte divergences,
  all of them the high byte of a `[BP-nnnn]` displacement.

  Two ways to tell a temporary from a variable here. `Name` is a value
  `String` parameter, so the compiler ALREADY copies it to [BP-$100] on entry;
  a second copy into a local would be visible and there is none at 1b54:009a,
  which goes straight to the INT 2Fh call. And 1b54:0137 copies [BP-$100] --
  the parameter's own slot -- into `SelfName`, so the assignment is
  `SelfName := Name` with nothing in between. }
procedure Install(Name : String; Block : Pointer);
var
  Found : Boolean;       { [BP-$101] }
  Other : Pointer;       { [BP-$106] }
begin
  { 1b54:009f -- the same INT 2Fh call src/DEMOVT.PAS's MusicDetect makes. }
  asm
    MOV  AX, ReqAX         { 1b54:009f                                       }
    MOV  BX, ReqBX         { 1b54:00a2                                       }
    MOV  CX, ReqCX         { 1b54:00a5                                       }
    XOR  DI, DI            { 1b54:00a8                                       }
    MOV  ES, DI            { 1b54:00aa                                       }
    INT  2Fh               { 1b54:00ac                                       }
    XOR  DL, DL            { 1b54:00ae                                       }
    AND  AX, AX            { 1b54:00b0                                       }
    JNZ  @@None            { 1b54:00b2                                       }
    CMP  BX, 3F17h         { 1b54:00b4                                       }
    JNZ  @@None            { 1b54:00b8                                       }
    CMP  CX, 1343h         { 1b54:00ba                                       }
    JNZ  @@None            { 1b54:00be                                       }
    INC  DL                { 1b54:00c0                                       }
  @@None:
    MOV  Found, DL         { 1b54:00c2                                       }
    MOV  WORD PTR Other+2, ES  { 1b54:00c6                                   }
    MOV  WORD PTR Other, DI    { 1b54:00ca                                   }
  end;

  { 1b54:00ce -- a resident that answered 0:0 has no name to show. }
  if Other = nil then                             { 1b54:00d2 }
    Other := @NoName;                             { 1b54:00d8  DS:$0c20 }

  { ONE WriteLn OF A CONCATENATION, not three Writes and a WriteLn. The
    original pushes `Output` once, at 1b54:00ec, and then builds the whole line
    in the [BP-$206] temporary before writing it:

      00ec  MOV DI,4536 / PUSH DS / PUSH DI     Output
      00f1  LEA DI,[BP-$206] / PUSH SS / PUSH DI    the concatenation temp
      00f7  MOV DI,0061  / PUSH CS / PUSH DI    'Ojo, que est. el ' -- CS!
      00fc  CALL 0ba1:0ac3                      temp := that
      0101  LES DI,Other / PUSH ES / PUSH DI
      0107  CALL 0ba1:0b50                      temp := temp + Other^
      010c  MOV DI,007b  / PUSH CS / PUSH DI    ' residente!!'
      0111  CALL 0ba1:0b50                      temp := temp + that
      0116  PUSH 0 / CALL 0ba1:0972             write it, width 0
      011d  CALL 0ba1:08ec                      the line break

    Three separate Writes emit three of those push-and-call groups and no
    temporary at all, which is a different shape and a different frame.

    The two literals are pushed from CS, and that is the reason they are plain
    untyped constants above rather than typed ones: an untyped string constant
    is a literal, and Turbo Pascal lays a literal down in the CODE segment --
    at 1b54:0061 and 1b54:007b, in the gap between ExitHandler and here. A
    typed constant would live in DGROUP and be pushed from DS. `NoName` is the
    exception and has to be typed, because Install takes its address. }
  if Found then                                   { 1b54:00e5 }
  begin
    WriteLn(Already + String(Other^) + Resident); { 1b54:00ec }
    Halt(1);                                      { 1b54:0122 }
  end;

  CtrlBlock := Block;                             { 1b54:0130 }
  SelfName  := Name;                              { 1b54:0137 }
  Stub      := @OldInt2F;                         { 1b54:0150 }

  { 1b54:0157 -- take INT 2Fh, and leave the displaced vector inside the
    JMP FAR so the chain works without a variable to hold it. }
  asm
    MOV  SI, 0             { 1b54:0157  MOV SI,0000 -- NOT `XOR SI,SI`       }
    MOV  ES, SI            { 1b54:015a                                       }
    MOV  AX, ES:[0BCh]     { 1b54:015c                                       }
    MOV  SI, 0             { 1b54:0160                                       }
    MOV  ES, SI            { 1b54:0163                                       }
    MOV  DX, ES:[0BEh]     { 1b54:0165                                       }
    LES  DI, Stub          { 1b54:016a                                       }
    MOV  ES:[DI+1], AX     { 1b54:016e                                       }
    MOV  ES:[DI+3], DX     { 1b54:0172                                       }
    MOV  AX, OFFSET Handler{ 1b54:0176  the binary has 0006h                 }
    MOV  DX, SEG Handler   { 1b54:0179  and 1B54h                            }
    MOV  SI, 0             { 1b54:017c                                       }
    MOV  ES, SI            { 1b54:017f                                       }
    MOV  ES:[0BCh], AX     { 1b54:0181                                       }
    MOV  SI, 0             { 1b54:0185                                       }
    MOV  ES, SI            { 1b54:0188                                       }
    MOV  ES:[0BEh], DX     { 1b54:018a                                       }
  end;

  SavedExit := ExitProc;                          { 1b54:018f, 1b54:0196 }
  ExitProc  := @ExitHandler;                      { 1b54:019d, 1b54:01a3 }
end;

end.
