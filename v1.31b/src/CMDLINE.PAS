{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).

  Segment 116e -- THE COMMAND LINE. 1,232 bytes, nine routines.

  COMPLETE at 1,232 of 1,232 bytes, 158 pending fixups. Our code is 1,282: the two empty
  overrides at the bottom are routines the ORIGINAL'S LINKER DROPPED, which is why they
  sit last. Read the note there before moving them.

  THE COUNTERPART IS `LIB/CMDLINE.PAS`, measured at 59.5% by `demovt/relmatch.py` with
  nothing else above 7%. Its own header describes it as "a workframe for a command line
  options interpreter -- you just have to make a descendant object overriding the
  InterpretNoSwitch and InterpretSwitch methods", and that is exactly the shape of the
  pair `116e` and `109c`: this segment is the framework and `109c` is the descendant
  holding the switch table. `109c` scores 42.1% against the release's own descendant,
  `VTCMD.PAS`.

  THE VMT LAYOUT IS READ OFF THE CALL SITES, and it says 1.31 has ONE MORE VIRTUAL
  METHOD than the release:

      +04  Done               Objects.TObject's
      +08  ParseLine          called once, from ParseFile
      +0c  ParseFile          called once, from ParseLine
      +10  SkipRest           NEVER CALLED from inside this segment -- 109c:0835 is
      +14  GetToken           called FOUR times: three in ParseLine, one in TokenParam
      +18  CmpSwitch
      +1c  TokenParam
      +20  Abort
      +24  InterpretNoSwitch  called once, from ParseLine's else branch
      +28  InterpretSwitch    called once, from ParseLine's switch branch

  `GetToken` AT +14 IS THE ANOMALY. The release declares ParseLine, ParseFile, GetToken,
  which would put GetToken at +10; four calls land on +14 instead, so something sits
  between ParseFile and GetToken. That something is `116e:02ac`, fourteen bytes that set
  `Idx := 255` and nothing else. `Abort` still exists separately at +20 and sets
  `Aborting`.

  **AND `109c` NAMED IT.** The method had no caller inside this segment and was
  `Rut_0110` until one turned up: `109c:0835` is a `CALLF [DI+10]` and it is the LAST
  thing `TVTCmdSwitch.CmdInitShell` does, immediately after
  `ShellParam := Copy(Line, Idx, 255)`. A method that has just read the rest of the line
  out of `Line` directly needs the tokeniser to stop handing the same text back as
  switches -- so `SkipRest` it is. **The name is ours; the release has no such method.**

  AND `Idx` AT +$146 CONFIRMS THE RELEASE'S FIELD LAYOUT EXACTLY. `116e:02b2` writes a
  Word 255 at Self+$146, which is 326. With the VMT link at +0, `Line : String` at +2
  and `FileDir : DirStr` after it, Idx lands at 2 + 256 + 68 = 326 -- and 68 is
  `DirStr`, which is `String[67]` and not the 80 of `PathStr`. Turbo Pascal splits a
  path as 67 + 8 + 4 = 79, which is where those three sizes come from.
  =========================================================================== }
unit CmdLine;

interface

uses
  Dos, Objects;

type
  TSwitch = String[4];

  PCmdLine = ^TCmdLine;
  TCmdLine = String[127];

  PCmdLineInterpreter = ^TCmdLineInterpreter;
  TCmdLineInterpreter =
    object(TObject)
      Line     : String;          { +$002                                     }
      FileDir  : DirStr;          { +$102  String[67], so 68 bytes            }
      Idx      : Word;            { +$146  ANCHORED by 116e:02b2              }
      Aborting : Boolean;         { +$148                                     }

      procedure ParseLine(S : String);                                virtual;
      procedure ParseFile(FName : PathStr);                           virtual;

      { 116e:02ac -- the extra virtual, VMT +$10; see the header. }
      procedure SkipRest;                                             virtual;

      function  GetToken : TCmdLine;                                  virtual;
      function  CmpSwitch(var Token : TCmdLine; Switch : TSwitch) : Boolean; virtual;
      function  TokenParam(var Token : TCmdLine) : TCmdLine;          virtual;
      procedure Abort;                                                virtual;

      procedure InterpretNoSwitch(Token : TCmdLine);                  virtual;
      procedure InterpretSwitch  (Token : TCmdLine);                  virtual;
    end;

function GetDOSCmdLine : TCmdLine;

implementation

{ --------------------------------------------------------------------------
  116e:0002 -- ParseLine. Split a line into tokens and dispatch each one.

  THREE KINDS OF TOKEN, distinguished by the first character: `/` or `-` is a switch,
  `@` names another file to read, anything else is a bare argument. The `@` case is
  what makes `PSYCHO.EXE @neurosis.cfg` work.

  `Line` AND `Idx` ARE SAVED AND RESTORED AROUND THE RECURSION, which is the whole
  reason they are fields rather than locals: `ParseFile` re-enters `ParseLine` for every
  line of the included file, and both share this one cursor. Saving them here is what
  makes `@file` nest.

  THE DOUBLED `GetToken` AT THE TOP is not a mistake. An empty first token means the
  line began with a separator, so it is fetched again -- once, not in a loop, so a line
  of nothing but separators yields one empty token and the `while` never runs.
  -------------------------------------------------------------------------- }
procedure TCmdLineInterpreter.ParseLine(S : String);
var
  Token    : TCmdLine;
  SaveLine : String;
  SaveIdx  : Word;
  I        : Word;
begin
  I := Pos(';', S);
  if I > 0 then
    S := Copy(S, 1, I - 1);

  Line     := S;
  Idx      := 1;
  Aborting := False;

  Token := GetToken;
  if Token = '' then
    Token := GetToken;

  while Token <> '' do
  begin
    if Aborting then Exit;

    if      (Token[1] = '/') or
            (Token[1] = '-') then
      InterpretSwitch(Copy(Token, 2, 255))
    else if (Token[1] = '@') then
    begin
      SaveLine := Line;
      SaveIdx  := Idx;

      ParseFile(Copy(Token, 2, 255));

      Line := SaveLine;
      Idx  := SaveIdx;
    end
    else
      InterpretNoSwitch(Token);

    Token := GetToken;
  end;
end;


{ --------------------------------------------------------------------------
  116e:01b8 -- ParseFile. Read a file a line at a time and hand each to ParseLine.

  `FSplit(FExpand(FName), FileDir, Name, Ext)` KEEPS THE DIRECTORY IN A FIELD and
  throws the name and extension away -- `FileDir` is what a nested `@file` would be
  resolved against, and it is the only reason those two locals exist.

  `if IOResult <> 0 then;` WITH AN EMPTY STATEMENT IS DELIBERATE AND IS THE RELEASE'S.
  Under `$I-` every I/O call leaves a code that the NEXT call would otherwise inherit,
  so reading and discarding it is how you clear it. It appears twice, after each
  `Close`.
  -------------------------------------------------------------------------- }
procedure TCmdLineInterpreter.ParseFile(FName : PathStr);
var
  F    : Text;
  Name : NameStr;
  Ext  : ExtStr;
begin
  Aborting := False;

  FSplit(FExpand(FName), FileDir, Name, Ext);

  Assign(F, FName);
  Reset(F);
  if IOResult <> 0 then Exit;

  while not Eof(F) do
  begin
    if Aborting then Exit;

    ReadLn(F, Line);
    if IOResult <> 0 then
    begin
      Close(F);
      if IOResult <> 0 then;
      Exit;
    end;
    ParseLine(Line);
  end;

  Close(F);
  if IOResult <> 0 then;
end;


{ 116e:02ac -- SkipRest. Fourteen bytes: `Idx := 255` and nothing else. That makes
  GetToken's `for I := Idx to Length(Line)` run zero times for ever after, so the rest of
  the line is skipped without touching `Aborting` -- which `ParseLine` tests and would use
  to leave the loop and every enclosing `@file` with it. **Two ways to stop, and this is
  the gentler one.**

  ITS ONE CALLER IS `109c:0835`, at the end of `CmdInitShell`, which is what gives it its
  name: `-sh PROG args...` hands everything after the switch to the shelled program, so
  the interpreter must not then read those arguments as its own. }
procedure TCmdLineInterpreter.SkipRest;
begin
  Idx := 255
end;


{ --------------------------------------------------------------------------
  116e:02dd -- GetToken. Take the next token from `Line`, advancing `Idx`.

  IT BUILDS THE RESULT IN PLACE, one character at a time, rewriting the length byte on
  every iteration -- `GetToken[0] := Chr(i - Idx + 1)`. A Pascal function returning a
  String is handed a hidden var parameter, so `GetToken[n]` really is the caller's
  buffer and there is no local copy to make. That is why the frame is four bytes for a
  routine that returns 128.

  AND `Idx := 255` IS THE END SENTINEL rather than `Length(Line) + 1`, which is what
  makes the extra virtual above work: any value past 255 would do, and 255 is what both
  routines use.
  -------------------------------------------------------------------------- }
function TCmdLineInterpreter.GetToken : TCmdLine;
const
  Spaces = [#0, #9, ' ', ','];
var
  I : Word;
begin
  GetToken[0] := #0;
  for I := Idx to Length(Line) do
  begin
    if Line[I] in Spaces then
    begin
      while (I <= Length(Line)) and (Line[I] in Spaces) do
        Inc(I);

      Idx := I;
      Exit;
    end;

    GetToken[I - Idx + 1] := Line[I];
    GetToken[0]           := Chr(I - Idx + 1);
  end;
  Idx := 255
end;


{ --------------------------------------------------------------------------
  116e:03a9 -- CmpSwitch. Does `Token` begin with `Switch`, ignoring case -- and if so,
  CONSUME the switch and leave the parameter behind in `Token`.

  IT IS A TEST THAT MUTATES ITS ARGUMENT, which is why every caller in `109c` reads
  `if CmpSwitch(Token, 'port') then CmdSetPort(TokenParam(Token))`: by the time the
  parameter is wanted, `Token` is already just the parameter. A `:` separator is
  swallowed too, so `port:220` and `port220` both work.

  NOTE IT COMPARES ONLY `Length(Switch)` CHARACTERS and does not check what follows, so
  a four-character switch matches any longer token beginning with it. The same
  prefix-matching looseness `11bb`'s config keys have.
  -------------------------------------------------------------------------- }
function TCmdLineInterpreter.CmpSwitch(var Token : TCmdLine; Switch : TSwitch) : Boolean;
var
  I : Word;
begin
  CmpSwitch := False;
  for I := 1 to Length(Switch) do
    if UpCase(Switch[I]) <> UpCase(Token[I]) then
      Exit;

  CmpSwitch := True;
  Token     := Copy(Token, Length(Switch) + 1, 255);

  if Token[1] = ':' then
    Token   := Copy(Token, 2, 255)
end;


{ 116e:0463 -- TokenParam. The switch's parameter, taking the NEXT token if the switch
  did not carry one. So `-port 220` and `-port:220` are the same thing, and CmpSwitch
  above has already stripped whichever separator was used. }
function TCmdLineInterpreter.TokenParam(var Token : TCmdLine) : TCmdLine;
begin
  if Token = '' then
    Token := GetToken;

  TokenParam := Token
end;


{ 116e:04a2 -- Abort. The harder of the two stops: `ParseLine` tests this at the top of
  every iteration and leaves, and `ParseFile` tests it before every line, so setting it
  unwinds the whole nested `@file` chain rather than just the current line. }
procedure TCmdLineInterpreter.Abort;
begin
  Aborting := True
end;


{ THE DOS COMMAND LINE IS AT PSP:$80, length byte first -- which is a Pascal string
  already, so the whole routine is one cast. `PrefixSeg` is Turbo Pascal's own copy of
  the PSP segment. `TCmdLine` is `String[127]` because $80 is where DOS puts it and 127
  is all the room there is. }
function GetDOSCmdLine : TCmdLine;
begin
  GetDOSCmdLine := PCmdLine(Ptr(PrefixSeg, $80))^
end;


{ ==========================================================================
  THESE TWO BODIES ARE HERE, AT THE BOTTOM, BECAUSE THE ORIGINAL'S LINKER DROPPED THEM AND
  OURS CANNOT. Their position is a property of the measurement, not a convenience.

  (An earlier version of this note called it "a construction rather than a finding" and
  said the anomaly was unresolved. `109c` resolved it; the reasoning is below and in
  docs/CONTINUATION.md.)

  `ParseLine` calls VMT slots +$24 and +$28, so `TCmdLineInterpreter` must declare nine
  virtual methods. **But segment 116e contains only EIGHT routine bodies.** Counting
  far returns finds exactly eight, and every one is accounted for:

      01b4 RETF 8    ParseLine        02b9 RETF 4    Rut_0110
      02a8 RETF 8    ParseFile        03a5 RETF 4    GetToken
      045f RETF 12   CmpSwitch        049e RETF 8    TokenParam
      04ae RETF 4    Abort            04ce RETF      GetDOSCmdLine

  `04a2..04b1` is Abort -- `MOV byte ES:[DI+0148],1`, which is `Aborting := True` and
  confirms the field layout a second time -- and `04b2..04cf` is GetDOSCmdLine, whose
  thirty bytes end exactly at the segment's last byte. **There is no room for the two
  empty overrides and no trace of them.**

  **TURBO PASCAL SMART-LINKS AT THE ROUTINE LEVEL WHEN IT BUILDS THE EXE**, and these two
  are the only routines in the unit that nothing surviving refers to:

      ParseLine, ParseFile, SkipRest, GetToken, CmpSwitch, TokenParam, Abort
          all reached through `TVTCmd`'s VMT, because `109c` overrides none of them --
          and `SkipRest` is called from `109c:0835` as well.  KEPT.

      InterpretNoSwitch, InterpretSwitch
          `109c` overrides BOTH, so every live VMT points into 109c instead. And
          `TCmdLineInterpreter` itself is never instantiated -- 109c declares the two
          objects that are -- so the base's own VMT is dead and is dropped, taking the
          last reference to these two with it.  DISCARDED BY THE LINKER.

  `109c:0b7c` IS WHAT PROVED THE SLOT COUNT: it is a `CALLF [DI+2c]`, and +$2c is the first
  virtual `TVTCmdSwitch` ADDS. A new virtual at +$2c means the inherited ones stop at +$28,
  so nine slots is right and `InterpretSwitch` really is the base's ninth.

  SO OUR `.TPU` HOLDS TWO ROUTINES THE ORIGINAL SEGMENT DOES NOT, and 1,282 bytes against
  1,232 is the fifty they cost. Turbo Pascal lays `.TPU` code out in SOURCE ORDER, so they
  have to be last: anywhere else and everything after them shifts by fifty and the
  comparison fails. **Do not move them, and do not delete them either** -- the object needs
  its bodies to compile.
  ========================================================================== }
procedure TCmdLineInterpreter.InterpretNoSwitch(Token : TCmdLine);
begin
end;

procedure TCmdLineInterpreter.InterpretSwitch(Token : TCmdLine);
begin
end;

end.
