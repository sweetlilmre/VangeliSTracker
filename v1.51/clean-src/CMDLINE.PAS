{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  A REUSABLE COMMAND-LINE PARSER, and nothing about DemoVT's own switches.

  It is a base object. This unit knows how to walk a line, split it into
  tokens, tell a switch from a bare argument, and pull a parameter off a
  switch -- and then hands each token to a method that DOES NOTHING HERE. A
  descendant overrides `InterpretSwitch` and `InterpretNoSwitch` and supplies
  the meanings; VTCmd is that descendant.

  So a reader looking for what `-nb` does will not find it here. What is here
  is the machinery every switch goes through on the way to being recognised.

  `@file` IS THE FEATURE WORTH KNOWING ABOUT. A token beginning `@` names
  another file, and the parser reads it line by line as though its contents had
  been typed on the command line -- which is what makes `DEMOVT @PLAY.CFG`
  work, and what makes a playlist possible at all. It nests: an included file
  may include another, because the parse state is saved and restored around
  the recursion rather than kept in locals. }
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
      { The line being parsed and how far along it the tokeniser has reached.
        They are FIELDS RATHER THAN LOCALS so that `@file` can nest: ParseFile
        saves and restores them around each included line, which a local
        could not survive. }
      Line     : String;          { +$002                                     }
      FileDir  : DirStr;          { +$102  the directory an @file came from,
                                     so a relative name inside it resolves    }
      Idx      : Word;            { +$146  how far along Line we have got    }
      Aborting : Boolean;         { +$148  set by Abort; stops the walk       }

      procedure ParseLine(S : String);                                virtual;
      procedure ParseFile(FName : PathStr);                           virtual;

      { Abandon the rest of the line without tokenising it. A switch whose
        parameter IS the remainder -- a shell command, say -- reads it out of
        `Line` directly and then calls this, so the tokeniser does not hand
        the same text back as more switches. }
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
ParseLine. Split a line into tokens and dispatch each one.

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
ParseFile. Read a file a line at a time and hand each to ParseLine.

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


{ SkipRest. Fourteen bytes: `Idx := 255` and nothing else. That makes
  GetToken's `for I := Idx to Length(Line)` run zero times for ever after, so the rest of
  the line is skipped without touching `Aborting` -- which `ParseLine` tests and would use
  to leave the loop and every enclosing `@file` with it. **Two ways to stop, and this is
  the gentler one.** }
procedure TCmdLineInterpreter.SkipRest;
begin
  Idx := 255
end;


{ --------------------------------------------------------------------------
GetToken. Take the next token from `Line`, advancing `Idx`.

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
CmpSwitch. Does `Token` begin with `Switch`, ignoring case -- and if so,
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


{ TokenParam. The switch's parameter, taking the NEXT token if the switch
  did not carry one. So `-port 220` and `-port:220` are the same thing, and CmpSwitch
  above has already stripped whichever separator was used. }
function TCmdLineInterpreter.TokenParam(var Token : TCmdLine) : TCmdLine;
begin
  if Token = '' then
    Token := GetToken;

  TokenParam := Token
end;


{ Abort. The harder of the two stops: `ParseLine` tests this at the top of
  every iteration and leaves, and `ParseFile` tests it before every line, so setting it
  unwinds the whole nested `@file` chain rather than just the current line. }
procedure TCmdLineInterpreter.Abort;
begin
  Aborting := True
end;


{ THE DOS COMMAND LINE IS AT PSP:$80, length byte first -- which is a Pascal string
  already, so the whole routine is one cast. `PrefixSeg` is Turbo Pascal's own copy of
  the PSP SEGMENT. `TCmdLine` is `String[127]` because $80 is where DOS puts it and 127
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
  virtual methods. **But SEGMENT 1182 contains only EIGHT routine bodies.** Counting
  far returns finds exactly eight, and every one is accounted for:

      01b4 RETF 8    ParseLine        02b9 RETF 4    Rut_0110
      02a8 RETF 8    ParseFile        03a5 RETF 4    GetToken
      045f RETF 12   CmpSwitch        049e RETF 8    TokenParam
      04ae RETF 4    Abort            04ce RETF      GetDOSCmdLine

  `04a2..04b1` is Abort -- `MOV byte ES:[DI+0148],1`, which is `Aborting := True` and
  confirms the field layout a second time -- and `04b2..04cf` is GetDOSCmdLine, whose
  thirty bytes end exactly at the SEGMENT's last byte. **There is no room for the two
  empty overrides and no trace of them.**

  **TURBO PASCAL SMART-LINKS AT THE ROUTINE LEVEL WHEN IT BUILDS THE EXE**, and these two
  are the only routines in the unit that nothing surviving refers to:

      InterpretNoSwitch, InterpretSwitch
          `109c` overrides BOTH, so every live VMT points into 109c instead. And
          `TCmdLineInterpreter` itself is never instantiated -- 109c declares the two
          objects that are -- so the base's own VMT is dead and is dropped, taking the
          last reference to these two with it.  DISCARDED BY THE LINKER.

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
