unit PROBE;
{ A COMPILER PROBE, not part of the reconstruction.

  One routine per divergence that survives both recorded compilers, written to
  the shape the source already has in the tree, so that the .TPU can be read
  straight against the original's bytes quoted in each comment. Nothing here is
  transcribed from the binary; it exists only to be compiled by two compilers
  and compared.

  Switches come from build.py's SWITCHES on the command line, exactly as the
  units do -- $G+ in particular decides whether 286 instructions are emitted at
  all. Nothing is set in the source: a directive LIST carries one dollar sign
  for the whole list, and repeating it per switch is Error 17 on both
  compilers. }

interface

{$F+}
procedure ProbeRegAlloc;
procedure ProbeGotoFold;
procedure ProbePortOrder;
procedure ProbeValueString(ID : String);
procedure ProbeAsmEncoding;
procedure ProbeEpilogueRet;
procedure ProbeEpilogueJmp;
procedure ProbeEpilogueFarRet;
procedure ProbeEpilogueData;
procedure ProbeUnnamedParams(A, B : Word);
{$F-}

implementation

var
  DMABufferSize : Word;
  GUSPort       : Word;
  DeviceName    : String[8];

{ The far call whose result the original leaves in AX. Far because 1a17:070f
  calls across a unit boundary, and the call's own encoding is not the point. }
{$F+}
function GetDMACount : Word;
begin
  GetDMACount := DMABufferSize;
end;
{$F-}

{ 1. REGISTER ALLOCATION -- 1a17:070f, ten bytes for the original's nine.

    original   CALL / MOV BX,DMABufferSize / SUB BX,AX / MOV [BP-6],BX
    TP6, TP7   CALL / MOV DX,AX / MOV AX,DMABufferSize / SUB AX,DX / MOV [BP-6],AX

  Left is a local so that the store is frame-relative as it is in the original.
  There is nothing in the statement to rearrange, so if a compiler emits the
  original's three-instruction form it is a property of that code generator. }
procedure ProbeRegAlloc;
var
  Left : Word;
begin
  Left := DMABufferSize - GetDMACount;
  DMABufferSize := Left;
end;

{ 2. BRANCH FOLDING -- 1723:04b5.

  Both recorded compilers fold `if C then goto L` into one inverted branch; the
  original compiles the goto as an independent statement and emits JZ +2 / JMP L.
  The shape is the release's ProbeUltrasound, so the source is not in question. }
procedure ProbeGotoFold;
label
  Fail;
begin
  if DMABufferSize <> 0 then goto Fail;
  GUSPort := 1;
Fail:
  GUSPort := 0;
end;

{ 3. PORT OPERAND ORDER -- 1723:02f4 against 1723:03c4.

  The same statement, same length, opposite order: the original emits the value
  first once and the port first once, and the only difference in context is that
  one follows an OUT and the other a CALL. Both are reproduced here, in that
  context, so a scheduler difference would show as one of the pair flipping. }
procedure ProbePortOrder;
begin
  Port[GUSPort] := $0B;                  { after nothing }
  Port[GUSPort] := $0B;                  { after an OUT }
  GetDMACount;
  Port[GUSPort] := $0B;                  { after a CALL }
end;

{ 4. THE VALUE-STRING COPY -- 1a17:024c, the test that settled TP6 against TP7.

  A String parameter passed by value is copied onto the frame before the body
  runs. The original CALLs a helper at 1ba1:0add; TP7 inlines LDS SI / LODSB;
  TP6 makes the call. Included as a REGRESSION check: a newer TP6 that inlined
  it would be disqualified by this line alone. }
procedure ProbeValueString(ID : String);
begin
  DeviceName := ID;
end;

{ 5. WHICH DIRECTION THE INLINE ASSEMBLER PICKS -- the 1a17:070f question.

  The original's statement is not `MOV DX,AX`-shaped at all:

      070c  e8 db ff     CALL GetDMACount     (near, back to 06ea)
      070f  8b 1e a4 0b  MOV  BX,DMABufferSize
      0713  29 c3        SUB  BX,AX
      0715  89 5e fa     MOV  [BP-6],BX

  `29 c3` is `SUB r/m,reg` -- the direction a 1990s assembler emits for
  `SUB BX,AX`. Turbo Pascal's own CODE GENERATOR emits `2b` (`SUB reg,r/m`),
  which is why our line comes out as `SUB AX,DX`. The question this settles is
  what TP's INLINE ASSEMBLER does with the same mnemonic: if it emits `29 c3`
  then the original's four instructions were HAND-WRITTEN asm, like the dead
  code immediately above them, and the site is reachable after all. }
procedure ProbeAsmEncoding; assembler;
asm
  SUB  BX,AX
  SUB  AX,BX
  ADD  BX,AX
  XOR  BX,AX
  AND  BX,AX
  MOV  BX,DMABufferSize
end;

{ 6..9. WHEN DOES AN `assembler` PROCEDURE GET AN EPILOGUE?

  1a17's last three regions are all this question. The note in SOUNDDEV.PAS says
  a frameless run wrapped in a Pascal procedure "must have one entry and one
  exit" and calls the cost unfixable:

      0746      three bytes  JMP @@Patcher, because Pascal enters at byte one
      1007      one byte     the epilogue RET, where the original has a 00 pad
      10c1..c3  three bytes  the epilogue, where the original has RETF 4

  The original's byte at 1007 is `00`, not `C3` -- so whatever produced it did
  NOT emit an epilogue after a procedure ending in `JMP`, and the byte is
  alignment padding. These four routines ask the compiler directly: does a
  trailing RET, a trailing JMP, a trailing far RET-with-count or a body of pure
  data get a `C3` (or a `CB`) added after it? }
procedure ProbeEpilogueRet; assembler;
asm
  MOV  AX,1
  RET
end;

procedure ProbeEpilogueJmp; assembler;
asm
  MOV  AX,2
  JMP  ProbeEpilogueRet
end;

procedure ProbeEpilogueFarRet; assembler;
asm
  MOV  AX,3
  RET  4
end;

procedure ProbeEpilogueData; assembler;
asm
  DB 0B8h, 04h, 00h        { MOV AX,4 as data, so nothing is recognised }
  DB 0C3h                  { a hand-written near RET the parser never sees }
end;

{ 10. A FAR `assembler` PROCEDURE WITH PARAMETERS IT NEVER NAMES.

  1a17:10c1 wants `RETF 4` -- `CA 04 00` -- and gets the compiler's plain `CB`,
  because `SelectOutput` is declared without parameters even though the run
  reads its first argument through [BP+8] and ends on a 4-byte return. The note
  in SOUNDDEV.PAS says declaring them "makes Turbo Pascal emit a frame at 104d,
  three bytes before 1087's hand-written ENTER". But the rule recorded elsewhere
  in the same document is that **an `assembler` procedure naming no parameter
  gets NO frame**, and this transcription reads its arguments through
  DB-encoded [BP+8] rather than by name. Both cannot be true. }
procedure ProbeNearJmpTail; forward;
procedure ProbeNearPlainTail; forward;

procedure ProbeUnnamedParams(A, B : Word); assembler;
asm
  MOV  AX,5
  DB   8Bh, 46h, 08h       { MOV AX,[BP+8] -- the parameter, unnamed }
end;

{ 11. A NEAR `assembler` PROCEDURE THAT ENDS ON AN INTERNAL JMP.

  1a17:1007 is `00` in the original where ours is `C3`. The run ends on
  `JMP @@Iret` at 1005, an unconditional near jump BACKWARDS INSIDE the same
  procedure, and the note in VTGAIN.INC reads the `00` as padding that Pascal
  cannot produce because "a Pascal procedure must have one exit". Routine 7
  above tested a jump to ANOTHER procedure, which assembles to a far `JMP` and
  does get an epilogue. This is the case that actually occurs: near procedure,
  near jump, own label. }
procedure ProbeNearJmpTail; assembler;   { near: declared in the implementation }
asm
@@Top:
  MOV  AX,6
  JMP  @@Top
end;

{ And the same thing with the epilogue's own byte value made visible: a near
  procedure ending on a plain instruction, for the contrast. }
procedure ProbeNearPlainTail; assembler;
asm
  MOV  AX,7
end;

end.
