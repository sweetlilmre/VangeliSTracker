{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  HOW A DEMO FINDS THE PLAYER: an INT 2Fh handler that answers a password.

  THE PROBLEM THIS SOLVES. DemoVT runs first and stays in memory; the demo
  runs afterwards, as a separate program, and has to locate the player's
  control block in someone else's address space. DOS offers no way to ask
  "is program X running, and where is its data?" -- so DemoVT hooks INT 2Fh,
  the multiplex interrupt, which exists precisely for programs to shout into
  and see who answers.

  THE PASSWORD IS 'VTrac' SPREAD ACROSS THREE REGISTERS. A caller loads AX,
  BX and CX with 'VT', 'Tr' and 'ac' and issues INT 2Fh. Anything else on the
  chain sees a request it does not recognise and passes it on; this handler
  sees its own name and answers. The reply is the request XORed with two
  masks, so a caller can be sure it is talking to DemoVT and not to some other
  resident that happened to return zero.

  AND THE ANSWER CARRIES AN ADDRESS. ES:DI comes back pointing at the player's
  own name, with the control block's far pointer in THE FOUR BYTES BELOW IT --
  so a client reads `ES:[DI-4]` and has everything. That negative offset is not
  a trick; it is what lets one pointer answer two questions.

  INSTALLING TWICE IS REFUSED. Install runs the handshake itself before
  hooking anything, and if a DemoVT is already there it prints that copy's
  name and stops. Two players on one timer would fight over the sound card.

  [re] Segment 1d3c -- 432 bytes, all of it, nothing left unread. This is the
  half of the handshake that the Psycho Neurosis reconstruction's own
  src/DEMOVT.PAS talks to; everything that file assumes is confirmed here. See
  ../v1.31b/docs/01-int2f.md.

  [re] NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information, so no
  unit or routine name survives.

  [re] ADDRESS MAP
  [re] 1d3c IN THIS IMAGE, NOT 1b54. The map said 1b54, which is this unit's
  segment in v1.31b; these addresses were inherited when the file was and
  never re-based. Measured two ways -- segpair --pair over the two
  reference images, and a byte search bounded by the paired extent: 48 bytes unchanged at 1d42:0001.
  The per-line addresses through this file are re-based to this image too;
  the OFFSETS are inherited and are verified only where an @asm marker sits.
    OldInt2F     1d3c:0000     Handler      1d3c:0006
    ExitHandler  1d3c:002f     'Ojo...'     1d3c:0061
    ' residente' 1d3c:007b     Install      1d3c:0088
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

  { The refusal message, in Spanish: "watch out, the <name> is resident!!".
    Written with character codes so this file stays seven-bit -- #173 is the
    inverted exclamation mark and #162 an o-acute, both CP437.

    [re] 1d3c:0061 and 1d3c:007b. }
  Already = #13#10'    ' + #173#173 + 'Ojo, que est' + #160 + ' el ';
  Resident = ' residente!!';

  { Shown instead of a name when a resident answers the handshake but returns
    a null ES:DI -- it identified itself as a DemoVT and then gave nowhere to
    read its name from.

    [re] 1e92:0c20 -- ten characters. Written with #168 for
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
  Pass an INT 2Fh call on to whoever held the vector before us.

  THE INSTRUCTION IS ITS OWN STORAGE. This is a five-byte JMP FAR, and the
  four bytes of its operand ARE where the displaced vector is kept: Install
  writes the old segment and offset into the instruction, and from then on
  jumping here jumps there. No variable holds the old vector, and the handler
  chains with one three-byte jump rather than an indirect call through memory.

  It is assembled pointing at itself, so an unpatched stub is an infinite loop
  -- which is safe only because Install always patches it before hooking.

  [re] 1d3c:0000. Like the timer chain in the program itself. ExitHandler reads
  the two words at +1 and +3 straight back out of the instruction.
  -------------------------------------------------------------------------- }
{ @asm 000 1d3c:0000 +6 }
procedure OldInt2F; assembler;
asm
  DB   0EAh              { 1d3c:0000  JMP FAR seg:ofs                        }
  DW   OFFSET OldInt2F   { 1d3c:0001  patched with the old INT 2Fh offset     }
  DW   SEG OldInt2F      { 1d3c:0003  patched with the old INT 2Fh segment    }
                       { [re] 1d3c:0005  RET -- supplied by Pascal, not
                         written here: an assembler procedure already gets an
                         epilogue and a written one duplicates it. }
end;

{ --------------------------------------------------------------------------
  Answer the handshake, or pass the call on.

  EVERY PROGRAM ON THE MACHINE SEES EVERY INT 2Fh CALL, so the first thing this
  does is decide whether the call is for it. Three compares; any mismatch and
  the call goes down the chain untouched. That is why the tests come before
  anything else and why nothing is saved first: a handler that clobbered a
  register before deciding the call was not its own would break somebody else's
  driver.

  ON A MATCH it answers in registers and IRETs -- AX zero for "yes", BX and CX
  XORed into a signature the caller can verify, ES:DI pointing at the player's
  name with the control block just below it.

  IT IS ASSEMBLER BECAUSE PASCAL CANNOT EXPRESS ANY OF THAT: it must not touch
  a register it has not been asked about, it answers in registers rather than
  by returning, and it either IRETs or jumps somewhere else entirely.

  EQUIVALENT PASCAL, REFERENCE ONLY -- the assembler below is what runs:

      if (AX = $5654) and (BX = $5472) and (CX = $6163) then
      begin
        AX := 0;  BX := $3F17;  CX := $1343;
        ES := Seg(SelfName);  DI := Ofs(SelfName);
        IRET
      end
      else chain to the old handler;

  -------------------------------------------------------------------------- }
{ @asm 000 1d3c:0006 +41 }
procedure Handler; assembler;
asm
  STI                    { 1d3c:0006  DOS multiplex handlers run enabled     }
  CMP  AX, ReqAX         { 1d3c:0007  'VT'                                   }
  JNZ  @@NotUs           { 1d3c:000a  not our password -- pass it on         }
  CMP  BX, ReqBX         { 1d3c:000c  'Tr'                                   }
  JNZ  @@NotUs           { 1d3c:0010                                         }
  CMP  CX, ReqCX         { 1d3c:0012  'ac'                                   }
  JNZ  @@NotUs           { 1d3c:0016  all three must match                   }
  XOR  AX, AX            { 1d3c:0018  AX := 0 says "yes, and it is me"       }
  XOR  BX, MaskBX        { 1d3c:001a  -> $3F17                               }
  XOR  CX, MaskCX        { 1d3c:001e  -> $1343                               }
  MOV  DI, SEG @DATA     { 1d3c:0022  the binary has MOV DI,1CAAh -- an
                                      absolute segment, not ours to copy     }
  MOV  ES, DI            { 1d3c:0025  ES:DI will point at SelfName          }
  MOV  DI, OFFSET SelfName  { 1d3c:0027  the binary has 432Ch. The four bytes
                              BELOW this are CtrlBlock, which is why a client
                              reads its control block from ES:[DI-4].        }
  IRET                   { 1d3c:002a  answered; do NOT chain                }
@@NotUs:
  { [re] A NEAR JUMP, not a far one. The original is `E9 D2FF` -- three bytes
    back to offset 0000 -- because the chain target IS the JMP FAR stub
    above, whose operand holds the displaced vector. Jumping FAR here
    assembles a five-byte JMP to the stub's address instead, which is two
    bytes longer and one indirection short of the idiom. }
  JMP  OldInt2F          { 1d3c:002b  every failed test lands here           }
end;

{ --------------------------------------------------------------------------
  Put INT 2Fh back the way it was found, on the way out of the program.

  THE OLD VECTOR IS READ OUT OF THE JMP FAR'S OWN OPERAND BYTES, which is the
  other half of the trick above: the chain stub was the storage all along, so
  restoring means copying two words out of an instruction.

  IT WRITES THE VECTOR TABLE DIRECTLY rather than calling DOS. That is the
  usual hazard with unhooking -- if another program hooked INT 2Fh after this
  one and is still resident, this overwrites ITS handler and the machine is
  left with a dangling chain. Nothing here checks; DemoVT expects to be the
  last thing installed and the first thing removed.

  [re] 1d3c:002f. The operand bytes are +1 and +3.
  -------------------------------------------------------------------------- }
{ @asm 000 1d3c:002f +89 }
procedure ExitHandler; far;
begin
  ExitProc := SavedExit;                          { 1d3c:0032, 1d3c:0039 }
  asm
    LES  DI, Stub          { 1d3c:0040                                       }
    MOV  AX, ES:[DI+1]     { 1d3c:0044  the displaced offset                 }
    MOV  DX, ES:[DI+3]     { 1d3c:0048  and segment                          }
    MOV  SI, 0             { 1d3c:004c  [re] MOV, not XOR -- the original
                             loads an immediate zero, and BASM emits what it
                             is told }
    MOV  ES, SI            { 1d3c:004f  ES := 0000, the vector table         }
    MOV  ES:[0BCh], AX     { 1d3c:0051  $2F * 4 -- the offset half           }
    MOV  SI, 0             { 1d3c:0055  ES is reloaded rather than kept       }
    MOV  ES, SI            { 1d3c:0058                                       }
    MOV  ES:[0BEh], DX     { 1d3c:005a  and the segment half                  }
  end;
end;

{ --------------------------------------------------------------------------
  Hook INT 2Fh, publish `Name` and `Block`, and arrange to unhook on exit.

  IT RUNS THE HANDSHAKE ITSELF FIRST, exactly as a client would, and refuses
  to install over a copy that is already there -- printing that copy's name,
  read from the ES:DI it answered with. Two players sharing one timer and one
  sound card would fight, so this is a refusal rather than a warning.

  AFTER THIS RETURNS the program is findable: any process that knows the
  password can reach `Block` through `ES:[DI-4]`.

  [re] 1d3c:0088. RETF 8: Name at [BP+$0a], Block at [BP+6]. The program calls
  it as Install('DemoVT v1.31 (beta)', @CtrlBlock).
  -------------------------------------------------------------------------- }
{ [re] THE FRAME IS `ENTER 0206,0` AND ONLY $106 OF IT IS DECLARED. The other 256
  bytes are at [BP-$206] and they are a COMPILER TEMPORARY, not a variable: the
  string the WriteLn below concatenates. This procedure previously declared an
  `S : String` to account for them and copied `Name` into it, which put every
  local 256 bytes lower than the original's -- eleven single-byte divergences,
  all of them the high byte of a `[BP-nnnn]` displacement.

  [re] Two ways to tell a temporary from a variable here. `Name` is a value
  `String` parameter, so the compiler ALREADY copies it to [BP-$100] on entry;
  a second copy into a local would be visible and there is none at 1d3c:009a,
  which goes straight to the INT 2Fh call. And 1d3c:0137 copies [BP-$100] --
  the parameter's own slot -- into `SelfName`, so the assignment is
  `SelfName := Name` with nothing in between. }
{ @asm 000 1d3c:0088 }
procedure Install(Name : String; Block : Pointer);
var
  Found : Boolean;       { [BP-$101] }
  Other : Pointer;       { [BP-$106] }
begin
  { 1d3c:009f -- the same INT 2Fh call src/DEMOVT.PAS's MusicDetect makes. }
  asm
    MOV  AX, ReqAX         { 1d3c:009f                                       }
    MOV  BX, ReqBX         { 1d3c:00a2                                       }
    MOV  CX, ReqCX         { 1d3c:00a5                                       }
    XOR  DI, DI            { 1d3c:00a8  ES:DI := 0:0, so a reply is visible  }
    MOV  ES, DI            { 1d3c:00aa                                       }
    INT  2Fh               { 1d3c:00ac  anyone out there answering to this?  }
    XOR  DL, DL            { 1d3c:00ae  assume not                           }
    AND  AX, AX            { 1d3c:00b0  zero means somebody claimed it       }
    JNZ  @@None            { 1d3c:00b2                                       }
    CMP  BX, 3F17h         { 1d3c:00b4  and the signature must be OURS       }
    JNZ  @@None            { 1d3c:00b8                                       }
    CMP  CX, 1343h         { 1d3c:00ba                                       }
    JNZ  @@None            { 1d3c:00be                                       }
    INC  DL                { 1d3c:00c0  a DemoVT is already resident         }
  @@None:
    MOV  Found, DL         { 1d3c:00c2                                       }
    MOV  WORD PTR Other+2, ES  { 1d3c:00c6  where its name is, if anywhere   }
    MOV  WORD PTR Other, DI    { 1d3c:00ca                                   }
  end;

  { 1d3c:00ce -- a resident that answered 0:0 has no name to show. }
  if Other = nil then                             { 1d3c:00d2 }
    Other := @NoName;                             { 1d3c:00d8  DS:$0c20 }

  { [re] ONE WriteLn OF A CONCATENATION, not three Writes and a WriteLn. The
    original pushes `Output` once, at 1d3c:00ec, and then builds the whole line
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

    [re] Three separate Writes emit three of those push-and-call groups and no
    temporary at all, which is a different shape and a different frame.

    [re] The two literals are pushed from CS, and that is the reason they are plain
    untyped constants above rather than typed ones: an untyped string constant
    is a literal, and Turbo Pascal lays a literal down in the CODE segment --
    at 1d3c:0061 and 1d3c:007b, in the gap between ExitHandler and here. A
    typed constant would live in DGROUP and be pushed from DS. `NoName` is the
    exception and has to be typed, because Install takes its address. }
  if Found then                                   { 1d3c:00e5 }
  begin
    WriteLn(Already + String(Other^) + Resident); { 1d3c:00ec }
    Halt(1);                                      { 1d3c:0122 }
  end;

  CtrlBlock := Block;                             { 1d3c:0130 }
  SelfName  := Name;                              { 1d3c:0137 }
  Stub      := @OldInt2F;                         { 1d3c:0150 }

  { 1d3c:0157 -- take INT 2Fh, and leave the displaced vector inside the
    JMP FAR so the chain works without a variable to hold it. }
  asm
    MOV  SI, 0             { 1d3c:0157  [re] MOV SI,0000 -- NOT `XOR SI,SI` }
    MOV  ES, SI            { 1d3c:015a  ES := 0, the vector table            }
    MOV  AX, ES:[0BCh]     { 1d3c:015c  read the old INT 2Fh offset          }
    MOV  SI, 0             { 1d3c:0160                                       }
    MOV  ES, SI            { 1d3c:0163                                       }
    MOV  DX, ES:[0BEh]     { 1d3c:0165  and its segment                      }
    LES  DI, Stub          { 1d3c:016a  the JMP FAR that will chain to it    }
    MOV  ES:[DI+1], AX     { 1d3c:016e  patch it INTO the instruction        }
    MOV  ES:[DI+3], DX     { 1d3c:0172                                       }
    MOV  AX, OFFSET Handler{ 1d3c:0176  the binary has 0006h                 }
    MOV  DX, SEG Handler   { 1d3c:0179  and 1B54h                            }
    MOV  SI, 0             { 1d3c:017c                                       }
    MOV  ES, SI            { 1d3c:017f                                       }
    MOV  ES:[0BCh], AX     { 1d3c:0181  and only NOW take the vector         }
    MOV  SI, 0             { 1d3c:0185                                       }
    MOV  ES, SI            { 1d3c:0188                                       }
    MOV  ES:[0BEh], DX     { 1d3c:018a                                       }
  end;

  SavedExit := ExitProc;                          { 1d3c:018f, 1d3c:0196 }
  ExitProc  := @ExitHandler;                      { 1d3c:019d, 1d3c:01a3 }
end;

end.
