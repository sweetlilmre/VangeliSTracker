{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Segment 116a -- make sure a directory string ends in a separator. 64 bytes,
  of which 59 are the one routine and the rest is padding.

  DemoVT builds file names by concatenation, so a directory that does not end
  in a backslash would produce `C:\MODSTUNE.MOD`. This is what stops that.

  It accepts THREE endings as already-terminated -- ':', '\' and '/' -- but
  only ever appends '\'. Accepting '/' matters because DOS itself takes it as
  a separator even though COMMAND.COM does not, so a path typed into VT.CFG
  with forward slashes still works.

  An EMPTY string gets a backslash appended, because Path[0] is then the length
  byte itself, which is zero and matches none of the three. That is almost
  certainly not deliberate, but it is harmless: an empty directory becomes
  '\', the root, which is where a bare file name would have been looked for
  anyway.

  NAMES ARE THE 1.39b RELEASE'S. LIB/FILEUTIL.PAS's AddBar2Path is this
  routine statement for statement -- the same CASE over the same three labels
  in the same order, the same two statements in the ELSE. `bar` is barra, the
  Spanish for the slash it appends.

  The release's FileUtil has six more routines beside it (KillBar2Path,
  FileExists, DeleteFiles, MakePath, SaveFile, LoadFile) and 116a has none of
  them: 59 bytes is this one routine. They are later work by the author, not
  something missing from this transcription. Nothing proves 1.31 spelled any of
  this the same way: the binary has no debug information.

  ADDRESS MAP
    AddBar2Path  116a:0000
  =========================================================================== }

unit FileUtil;

interface

uses
  Dos;   { for PathStr = String[79] -- the release declares this parameter
           as PathStr, not as a generic String }

procedure AddBar2Path(var Path : PathStr); far;

implementation

{ --------------------------------------------------------------------------
  116a:0000. BYTE-IDENTICAL, all 59 of them.

  Plain Pascal in the binary -- the compiler's own `PUSH BP / MOV BP,SP` and
  `LEAVE`, and every access is an LES/MOV pair of the kind TP emits for a
  `var` String parameter. There is no assembler here to preserve.

  THE BINARY RELOADS THE POINTER FROM [BP+6] ON EVERY ACCESS rather than
  keeping it in a register -- five separate `LES DI,[BP+6]` for what is one
  variable -- which is why the routine is 59 bytes for four lines of source:

      the binary, and TP6          TP7
      LES DI,[BP+6]                LES DI,[BP+6]
      MOV AL,ES:[DI]   Length      MOV AL,ES:[DI]
      XOR AH,AH                    XOR AH,AH
      LES DI,[BP+6]    reload      (elided -- the pointer is still in ES:DI)
      ADD DI,AX                    ADD DI,AX

  Twice, once on the read and once on the write, for six bytes. That was the
  whole remaining difference in this unit and it was parked for several
  sessions as "not source shape, cause open" -- correctly, as it turned out.
  **It is Turbo Pascal 6 against 7.** TP6 reloads exactly where the original
  does, and this unit was the cleanest single piece of evidence that the
  original's compiler was TP6: three divergent regions to none, with no change
  to the source at all. See docs/CONTINUATION.md.
  -------------------------------------------------------------------------- }
procedure AddBar2Path(var Path : PathStr);
begin
  { IT IS A CASE, NOT AN IF-CHAIN. The binary loads the character into AL
    once at 116a:0010 and compares AL three times. An `and` chain over three
    separate `Path[Length(Path)] <> c` tests would reload it each time, and
    declaring a local to hold it -- which this file used to do -- makes the
    compiler spill it to [BP-1] and compare against memory (`88 46 ff`,
    `80 7e ff 3a`). A case selector is evaluated once and stays in AL.

    The labels are in SOURCE order, not sorted: $3a, $5c, $2f. }
  case Path[Length(Path)] of                      { .. 116a:0010 }
    ':', '\', '/' : ;
  else
    Path[Length(Path) + 1] := '\';                { .. 116a:002f }
    Inc(Path[0]);                                 { the length   }
  end;
end;

end.
