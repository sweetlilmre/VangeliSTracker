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
  name and stops. Two players on one timer would fight over the sound card. }

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
    inverted exclamation mark and #162 an o-acute, both CP437. }
  Already = #13#10'    ' + #173#173 + 'Ojo, que est' + #160 + ' el ';
  Resident = ' residente!!';

  { Shown instead of a name when a resident answers the handshake but returns
    a null ES:DI -- it identified itself as a DemoVT and then gave nowhere to
    read its name from.

    TYPED, not a plain constant, because Install takes its ADDRESS. An
    untyped Pascal constant has no storage and `@` on one will not compile;
    in the original this is simply a string sitting in DGROUP at $0c20, which
    is exactly what a typed constant produces. }
  NoName : String[10] = #168'?'#168'?'#168'? :-(';

var
  Stub      : Pointer;   { -> OldInt2F                             }
  { NOT VTCtrl's `CtrlBlock`, which is the 768-byte structure itself at $461a.
    This is a FAR POINTER TO IT, in this unit's implementation section and so not
    public -- which is why the linker map cannot settle its address and the
    relative check is all it gets. Two variables, one name, and the map lists the
    other one. }
  CtrlBlock : Pointer;   { what a client reads at ES:[DI-4]     }
  SelfName  : String;    { what INT 2Fh answers with in ES:DI   }
  SavedExit : Pointer;   { the ExitProc we displaced            }

{ --------------------------------------------------------------------------
  Pass an INT 2Fh call on to whoever held the vector before us.

  THE INSTRUCTION IS ITS OWN STORAGE. This is a five-byte JMP FAR, and the
  four bytes of its operand ARE where the displaced vector is kept: Install
  writes the old SEGMENT and offset into the instruction, and from then on
  jumping here jumps there. No variable holds the old vector, and the handler
  chains with one three-byte jump rather than an indirect call through memory.

  It is assembled pointing at itself, so an unpatched stub is an infinite loop
  -- which is safe only because Install always patches it before hooking. }
procedure OldInt2F; assembler;
asm
  DB   0EAh              { JMP FAR seg:ofs                        }
  DW   OFFSET OldInt2F   { patched with the old INT 2Fh offset     }
  DW   SEG OldInt2F      { patched with the old INT 2Fh SEGMENT    }
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
procedure Handler; assembler;
asm
  STI                    { DOS multiplex handlers run enabled     }
  CMP  AX, ReqAX         { 'VT'                                   }
  JNZ  @@NotUs           { not our password -- pass it on         }
  CMP  BX, ReqBX         { 'Tr'                                   }
  JNZ  @@NotUs
  CMP  CX, ReqCX         { 'ac'                                   }
  JNZ  @@NotUs           { all three must match                   }
  XOR  AX, AX            { AX := 0 says "yes, and it is me"       }
  XOR  BX, MaskBX
  XOR  CX, MaskCX
  MOV  DI, SEG @DATA     { the binary has MOV DI,1CAAh -- an
                                      absolute SEGMENT, not ours to copy     }
  MOV  ES, DI            { ES:DI will point at SelfName          }
  MOV  DI, OFFSET SelfName  { the binary has 432Ch. The four bytes
                              BELOW this are CtrlBlock, which is why a client
                              reads its control block from ES:[DI-4].        }
  IRET                   { answered; do NOT chain                }
@@NotUs:
  JMP  OldInt2F          { every failed test lands here           }
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
  last thing installed and the first thing removed. }
procedure ExitHandler; far;
begin
  ExitProc := SavedExit;
  asm
    LES  DI, Stub
    MOV  AX, ES:[DI+1]     { the displaced offset                 }
    MOV  DX, ES:[DI+3]     { and SEGMENT                          }
    MOV  SI, 0
    MOV  ES, SI            { ES := 0000, the vector table         }
    MOV  ES:[0BCh], AX     { $2F * 4 -- the offset half           }
    MOV  SI, 0             { ES is reloaded rather than kept       }
    MOV  ES, SI
    MOV  ES:[0BEh], DX     { and the SEGMENT half                  }
  end;
end;

{ --------------------------------------------------------------------------
  Hook INT 2Fh, publish `Name` and `Block`, and arrange to unhook on exit.

  IT RUNS THE HANDSHAKE ITSELF FIRST, exactly as a client would, and refuses
  to install over a copy that is already there -- printing that copy's name,
  read from the ES:DI it answered with. Two players sharing one timer and one
  sound card would fight, so this is a refusal rather than a warning.

  AFTER THIS RETURNS the program is findable: any process that knows the
  password can reach `Block` through `ES:[DI-4]`. }
procedure Install(Name : String; Block : Pointer);
var
  Found : Boolean;
  Other : Pointer;
begin
  { the same INT 2Fh call src/DEMOVT.PAS's MusicDetect makes. }
  asm
    MOV  AX, ReqAX
    MOV  BX, ReqBX
    MOV  CX, ReqCX
    XOR  DI, DI            { ES:DI := 0:0, so a reply is visible  }
    MOV  ES, DI
    INT  2Fh               { anyone out there answering to this?  }
    XOR  DL, DL            { assume not                           }
    AND  AX, AX            { zero means somebody claimed it       }
    JNZ  @@None
    CMP  BX, 3F17h         { and the signature must be OURS       }
    JNZ  @@None
    CMP  CX, 1343h
    JNZ  @@None
    INC  DL                { a DemoVT is already resident         }
  @@None:
    MOV  Found, DL
    MOV  WORD PTR Other+2, ES  { where its name is, if anywhere   }
    MOV  WORD PTR Other, DI
  end;

  { a resident that answered 0:0 has no name to show. }
  if Other = nil then
    Other := @NoName;

  if Found then
  begin
    WriteLn(Already + String(Other^) + Resident);
    Halt(1);
  end;

  CtrlBlock := Block;
  SelfName  := Name;
  Stub      := @OldInt2F;

  { take INT 2Fh, and leave the displaced vector inside the
    JMP FAR so the chain works without a variable to hold it. }
  asm
    MOV  SI, 0
    MOV  ES, SI            { ES := 0, the vector table            }
    MOV  AX, ES:[0BCh]     { read the old INT 2Fh offset          }
    MOV  SI, 0
    MOV  ES, SI
    MOV  DX, ES:[0BEh]     { and its SEGMENT                      }
    LES  DI, Stub          { the JMP FAR that will chain to it    }
    MOV  ES:[DI+1], AX     { patch it INTO the instruction        }
    MOV  ES:[DI+3], DX
    MOV  AX, OFFSET Handler{ the binary has 0006h                 }
    MOV  DX, SEG Handler   { and 1B54h                            }
    MOV  SI, 0
    MOV  ES, SI
    MOV  ES:[0BCh], AX     { and only NOW take the vector         }
    MOV  SI, 0
    MOV  ES, SI
    MOV  ES:[0BEh], DX
  end;

  SavedExit := ExitProc;
  ExitProc  := @ExitHandler;
end;

end.
