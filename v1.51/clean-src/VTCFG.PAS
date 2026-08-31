{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE CONFIGURATION FILE READER: turn VT.CFG into the settings the player runs
  on.

  THE FILE IS SECTIONED, and each section is read by its own routine. A section
  header names a subject -- the screen, the sound device, the player, the
  mixer -- and the keys under it are matched one at a time against a list of
  names that routine knows. A key nobody recognises is ignored rather than
  refused, so a config file written for a later version still works here.

  THIS IS ONE OF TWO PLACES THAT WRITE THE GLOBALS. The other is the
  command-line parser, and neither owns them -- which is why VTGlobal exists.
  A setting given in both places is decided by whichever runs last.

  IT USES THE COMMAND-LINE PARSER'S TOKENISER rather than its own. A config
  line and a command line are the same problem, so the same object walks both.

  Everything else -- including GetString's 786 bytes and DoSectPlayMod's twenty
  keys -- compiled byte-exact from `VTCFG.PAS` with no adjustment. **That has not
  happened anywhere else in this project**; the closest was `MyMove` in 12ba, one
  routine. So the release's root-directory sources can be trusted the way `LIB/`'s
  are, and the two absent keys were PREDICTED from the string table before a single
  instruction was read.}
unit VTCfg;

interface

uses
  Dos, SongUnit, VTDriver, SoundDevices, GUS, PlayMod, ModCommands, VTShell,
  VTGlobal, SoundBlaster, DevSB, SongElements;
  { `SongElements` is here for `LowQuality`, its typed constant at $0564, which this
    unit writes from the `LowQuality` key. It was reaching a duplicate declared in
    SongUnit; two bytes of that unit's variables, and removing them is what put
    VTNOTES' `NoteOf` back on $25c6. Already reached through SongUnit, so it cannot
    move a segment. }

{ read and interpret a file as a configuration file. }
procedure ReadConfiguration(FName : PathStr); far;

implementation

var
  { The release's names and its comments. Both are DGROUP. }
  ConfFile : Text;                { the open configuration file                }
  Line     : String;              { the last line read from it        }


{ --------------------------------------------------------------------------
  GLOBALS DECLARED HERE THAT DO NOT BELONG HERE, and this is risk 1 deliberately
  rather than by accident.

  The section handlers below write 34 configuration variables. Twelve of them are
  already declared in the units that own them and are referenced properly:

      GUSPort $0582, GUSIrq $0584            GUS
      DoBassPower $0bbb, DMAOffset $0bb8,
        DesiredHz $0bae, SbSplTimeout $0bf0  SoundDevices
      ForceLoopMod $02c9, CanFallBack $02ca,
        FilterOn $02cb, FilterOff $02cc,
        MaxOutputFreq $02ce                  PlayMod
      TicksPerSecond $0bcc                   DevGus (and PlayMod; see risk 1)
      FilterIsOn $0348, PermitFilterChange $0335  ModCommands
      LowQuality $0564                       SongUnit
      ProgName $3ade                         VTShell

  THE REST BELONG TO SEGMENTS THAT ARE NOT TRANSCRIBED, so they are declared here
  and flagged -- what is left of them; see the note in the block itself for the fourteen
  that moved to `VTGLOBAL.PAS` and `SOUNDBLA.PAS` when `109c` landed. A global's
  address is a linker fixup, so this cannot change a byte of
  either unit and the byte comparison cannot see it either way -- which is exactly
  what makes it dangerous, and exactly why it is written down. Move each one when its
  segment lands.
  -------------------------------------------------------------------------- }
  { Segment 193a, the release's `LIB/DEVSB.PAS` -- the SB Pro mixer. }

  { The release's `LIB/DEVDAC.PAS`. NO SEGMENT IN DEMOVT HAS BEEN IDENTIFIED AS THE
    DAC driver, and these three sit immediately after SoundDevices' $0bf0, so they
    may well be SoundDevices' own here. Unresolved. }

  { ---- AND THE VTGlobal GROUP HAS MOVED OUT, to src/VTGLOBAL.PAS ----
    `PermitFade`, `VtVolume`, `ShellLoopMod`, `ShellHz`, `FadeIncr`, `VTLoopMod`,
    `ShellParam`, `DevID`, `StringsFName` and `ModPath` were declared here, privately,
    because this was the only unit that touched them.

    **`109c` IS WHAT FORCED THE MOVE.** VTCmd writes the same settings from the command
    line that this unit writes from the config file, and a private declaration cannot be
    shared. The release has always kept them in its own `VTGLOBAL.PAS`; ours now does
    too. `SbPort`, `SbIrq`, `SbDMAChan` and `SbHiSpeed` went to `SOUNDBLA.PAS`, a
    declared stub for segment `19a0`, for the same reason.

    This unit still verifies IDENTICAL after losing those declarations, which is the
    expected result and worth stating: a DGROUP reference is a linker fixup, so where a
    global is declared cannot change a byte of the code that uses it. }



{ --------------------------------------------------------------------------
KillSpaces. Strip blanks from both ends of a string, in place.

  TWO `while`s AND NOT ONE, and they are not symmetrical: the leading blanks are
  removed by COPYING the string down (`S := Copy(S, 2, 255)`, which costs a 256-byte
  temporary and is the whole of `ENTER 0100,0`), and the trailing ones by decrementing
  the LENGTH BYTE in place. The release is the same, and the asymmetry is the obvious
  one -- there is no cheap way to drop a leading character from a Pascal string.

  `ValidBlanks` INCLUDES #0 AND #255, which is not fussiness -- a config line read
  from a text file can carry either as padding, and a name compared with trailing
  #255 would never match a keyword.
  -------------------------------------------------------------------------- }
procedure KillSpaces(var S : String);
const
  ValidBlanks = [' ', #9, #0, #255];
begin
  while (Length(S) > 0) and (S[1] in ValidBlanks) do
    S := Copy(S, 2, 255);

  while (Length(S) > 0) and (S[Length(S)] in ValidBlanks) do
    Dec(S[0])
end;


{ ==========================================================================
  THE ROUTINE MAP. The frame SIZES are what first mapped these onto the release's
  routine list, and they mapped one to one:

      0097  ENTER 0206   NotInStr          two String value-parameter copies
      0131  ENTER 0412   GetString         two Strings, two temps, four LongInts
      0443  ENTER 0102   GetBool           one String and the result
      05a9  ENTER 0102   GetPath
      05f2  ENTER 020e   GetNum            one String, one temp, three LongInts
      0826  ENTER 0006   GetWord
      0850  ENTER 0006   GetByte
      089f  PUSH BP      DoSectSB
      092a  PUSH BP      DoSectGUS
      097f  PUSH BP      DoSectSBPro
      09f9  PUSH BP      DoSectDAC
      0b0e  PUSH BP      DoSectPlayMod
      0d30  PUSH BP      DoSectMisc
      0d9b  PUSH BP      DoSectScreen      FIVE BYTES -- see below
      0da0  ENTER 0004   DoSectGeneric
      0e0b  PUSH BP      FindNextSect
      0e4f  ENTER 0054   ReadConfiguration one PathStr value-parameter copy
      0f2e  ENTER 0100   the initialisation section, which the release lacks

  EVERY ONE IS NOW CONFIRMED BY ITS BODY, so none of them keeps an address name.

  A LITERAL TABLE PRECEDES EACH SECTION HANDLER. Turbo Pascal pools a routine's
  string literals and emits them immediately before its code, so each `DoSect*` is
  preceded by its own keyword list -- 087a..089e holds `IRQ`, `Port`, `DMA`,
  `SbSplTimeout` and `HiSpeedDMA` for DoSectSB. While the unit was being built the
  prefix therefore stopped on a table rather than an instruction, which was never a
  divergence.
  ========================================================================== }

{ --------------------------------------------------------------------------
NotInStr. TRUE when `S` does NOT begin with `SS`, compared without
  regard to case. The awkward name and the inverted sense are the release's; every
  caller writes `NOT NotInStr(...)`, which is how GetBool tests eleven spellings of
  "true" in four languages.

  `UpCase(S[I]) <> UpCase(SS[I])` EVALUATES ITS RIGHT OPERAND FIRST: 00ee takes
  SS[I], calls UpCase, pushes the answer, and only then does S[I]. That is the third
  independent sighting of the rule that turned up in 142f's StartArpeggio -- Turbo
  Pascal computes the right-hand operand of a binary expression before the left.
  -------------------------------------------------------------------------- }
function NotInStr(S, SS : String) : Boolean;
var
  I : Word;                       { the position being examined               }
begin
  NotInStr := True;
  if Length(SS) > Length(S) then
    Exit;
  for I := 1 to Length(SS) do
    if UpCase(S[I]) <> UpCase(SS[I]) then
      Exit;
  NotInStr := False
end;

{ --------------------------------------------------------------------------
GetString. Take everything after the `=` on the current line and
  return it as a string, honouring quotes and stripping comments. 786 bytes, the
  largest routine in the segment, and almost all of it is Pascal string handling.

  THE QUOTE HANDLING IS THE HALF THAT LOOKS ODD AND IS RIGHT. Inside quotes a doubled
  quote means one literal quote, so the loop appends up to the closing quote, appends
  a quote if another follows immediately, and goes round again. The `if I = 0 then
  I := 254` covers an unterminated quote by taking the rest of the line.

  THE UNQUOTED HALF STOPS AT THE FIRST COMMENT CHARACTER, and semicolon, colon and
  hash are all three of them. The three-way minimum is a running comparison rather
  than a nested Min, and the `if J = 0 then J := Length(S) + 1` is the no-comment
  case.

  `S1[0] := Chr(Ml)` IS A TRUNCATION, not a length check -- it overwrites the length
  byte, which is the cheapest possible way to cut a string to size.

  `L` IS DECLARED AND NEVER USED, in the release too. It is in the frame regardless:
  four LongInts are 16 bytes of `ENTER 0412,0` whether the fourth is read or not, and
  removing it would shift every local below it.
  -------------------------------------------------------------------------- }
function GetString(var St : String; Ml : Word) : Boolean;
var
  S  : String;
  S1 : String;
  I, J,
  K, L : LongInt;
begin
  I := Pos('=', Line) + 1;

  S := Copy(Line, I, 255);
  KillSpaces(S);

  S1 := '';
  while Length(S) > 0 do
    if S[1] = '''' then
    begin
      S  := Copy(S, 2, 255);
      I  := Pos('''', S);
      if I = 0 then I := 254;
      S1 := S1 + Copy(S, 1, I - 1);
      if (Length(S) > I) and (S[I + 1] = '''') then
        S1 := S1 + '''';
      S := Copy(S, I + 1, 255);
      if Pos('''', S) = 0 then S := '';
    end
    else
    begin
      J := Pos(';', S);
      K := Pos(':', S); if (K <> 0) and (J > K) then J := K;
      K := Pos('#', S); if (K <> 0) and (J > K) then J := K;
                        if  J =  0              then J := Length(S) + 1;
      S1 := Copy(S, 1, J - 1);
      KillSpaces(S1);
      S := ''
    end;

  if Length(S1) > Ml then S1[0] := Chr(Ml);
  St := S1;
  GetString := True
end;

{ --------------------------------------------------------------------------
  Read the value after an `=` and decide whether it means true or false.

  IN FOUR LANGUAGES. `S`, `Y`, `OUI`, `DA` and a dozen more all mean yes, and
  the config file was expected to be written by whoever was using the program
  rather than by the program itself. A value matching nothing is false.

  Sixteen literals, eleven true and five false, in the sequence 1.39b's source
  declares them. Turbo Pascal pools a routine's literals and emits them immediately
  before its code, so the table's ORDER is the source's order -- which makes this a
  much stronger check than sixteen names matching would be on its own.

  WHAT THE WORDS ARE, since it is not obvious and it is the nicest thing in the unit:
  `S`/`N` are Spanish si/no, `OUI`/`PAS` French, `DA` Russian or Romanian,
  `POR`/`TAMP` are Spanish por supuesto / tampoco, `TAMB` tambien, `ALSO` German,
  `VERD` verdad, `CIER` cierto, `FALS` falso. Only `TRUE`, `FALSE`, `1` and `0` are
  English or neutral. **The same truncated forms appear in 142f's config keyword
  set**, which is how the `11bb`-to-VTCFG pairing was found in the first place.

  EVERY TEST IS `NOT NotInStr(...)`, which is a double negative and the release's
  own. NotInStr answers "does S fail to start with SS", so `NOT NotInStr` is "S
  starts with SS" -- a prefix match, not equality, so `Yes`, `YEP` and `Y` all pass.
  That is deliberate: a config file written by hand should accept any reasonable
  spelling.

  AND A VALUE THAT MATCHES NEITHER LIST LEAVES `b` ALONE and returns FALSE, which is
  how the caller distinguishes "not set" from "set to false".

  `SizeOf(S) - 1` IS 255, the maximum a String can hold, passed to GetString as its
  truncation limit.
  -------------------------------------------------------------------------- }
function GetBool(var B : Boolean) : Boolean;
var
  S : String;
begin
  GetBool := False;
  if not GetString(S, SizeOf(S) - 1) then Exit;
  if (not NotInStr(S, 'S')) or
     (not NotInStr(S, 'Y')) or
     (not NotInStr(S, 'OUI')) or
     (not NotInStr(S, 'DA')) or
     (not NotInStr(S, 'POR')) or
     (not NotInStr(S, 'TAMB')) or
     (not NotInStr(S, 'ALSO')) or
     (not NotInStr(S, 'TRUE')) or
     (not NotInStr(S, 'VERD')) or
     (not NotInStr(S, 'CIER')) or
     (not NotInStr(S, '1')) then
  begin
    B       := True;
    GetBool := True
  end
  else if (not NotInStr(S, 'N')) or
          (not NotInStr(S, 'PAS')) or
          (not NotInStr(S, 'TAMP')) or
          (not NotInStr(S, 'FALS')) or
          (not NotInStr(S, '0')) then
  begin
    B       := False;
    GetBool := True
  end
end;

{ --------------------------------------------------------------------------
GetPath. GetString, then expand the result against the current
  directory so a relative path in the config file means what the user expects.

  `SizeOf(P) - 1` IS 79 HERE AND 255 IN GetBool, because P is a `PathStr` --
  `String[79]` from the Dos unit -- and S there is a full `String`. Passing a
  String[79] to GetString's `var St : String` needs relaxed var-string checking,
  which the $V- switch gives, and which is in the switch set the original was built
  with.
  -------------------------------------------------------------------------- }
function GetPath(var P : PathStr) : Boolean;
begin
  GetPath := False;
  if not GetString(P, SizeOf(P) - 1) then Exit;
  P := FExpand(P);
  GetPath := True
end;

{ --------------------------------------------------------------------------
GetNum. Read a number, and it accepts two forms.

  THE ORDINARY FORM is a decimal or (via `Val`) a `$`-prefixed hex literal, taken
  from after the `=` and stopped at the first comment character exactly as GetString
  does it -- the same three-way minimum over semicolon, colon and hash, this time
  applied to `Line` directly rather than to a copy.

  THE OTHER FORM IS A MEMORY DEREFERENCE, and it is worth reading twice:

      [ssss:oooo]  ->  the LongInt AT that address

  `IF (Length(s) > 3) AND (s[1] = '[')` peels the brackets, `Val` parses what is
  inside as a number, and then

      i := LP(Ptr((i AND $F0000) SHR 4, i AND $FFFF))^

  splits that number into a segment and an offset and reads four bytes from there.
  So a configuration file can set a value to whatever is in memory at a given
  address. In a tracker that is a debugging hook; in a demo player shipped inside
  another program it is a way for the host to hand values in. Either way it is the
  one place in this unit that can read arbitrary memory, and it is driven by a text
  file.

  `WORD(j)` ON `Val`'s ERROR CODE is the release's cast: Val returns the failing
  position in an Integer and the code compares it against zero, so the cast only
  matters for the declaration's type.
  -------------------------------------------------------------------------- }
function GetNum(var B : LongInt) : Boolean;
type
  LP = ^LongInt;
var
  S       : String;
  I, J, K : LongInt;
begin
  I := Pos('=', Line) + 1;
  J := Pos(';', Line);
  K := Pos(':', Line); if (K <> 0) and (J > K) then J := K;
  K := Pos('#', Line); if (K <> 0) and (J > K) then J := K;
                       if               J = 0  then J := Length(Line) + 1;
  S := Copy(Line, I, J - I);
  KillSpaces(S);

  J := 1;

  if (Length(S) > 3) and (S[1] = '[') then
  begin
    J := Pos(']', S);
    if J <> 0 then
    begin
      Val(Copy(S, 2, J - 2), I, Word(J));
      if J = 0 then
        I := LP(Ptr((I and $F0000) shr 4, I and $FFFF))^;
    end
    else
      J := 1;
  end
  else
    Val(S, I, Word(J));

  if J <> 0 then
  begin
    GetNum := False;
    Exit;
  end;
  B := I;
  GetNum := True
end;

{ --------------------------------------------------------------------------
 -- GetWord and GetByte. GetNum with a cast, and the two
  are identical but for the width. `ENTER 0006,0` each: the LongInt local and the
  one-byte result.
  -------------------------------------------------------------------------- }
function GetWord(var B : Word) : Boolean;
var
  L : LongInt;
begin
  if GetNum(L) then
  begin
    B       := Word(L);
    GetWord := True
  end
  else
    GetWord := False
end;

function GetByte(var B : Byte) : Boolean;
var
  L : LongInt;
begin
  if GetNum(L) then
  begin
    B       := Byte(L);
    GetByte := True
  end
  else
    GetByte := False
end;

{ --------------------------------------------------------------------------
  THE SEVEN SECTION HANDLERS: one per `[VT-...]` section of the config file,
  each a flat chain of "does this line start with that key? then read a value
  into that variable".

  A key none of them recognises falls off the end of the chain and is ignored,
  which is how a file written for a different version still loads.

  ALL SEVEN ARE `far`, and they have to be: DoSectGeneric at 0da0 calls whichever one
  the section named through a procedural variable, so they are addressed rather than
  called by name.

  THE MATCH IS BY PREFIX, NOT BY EQUALITY, because that is what `not NotInStr` means
  -- so a line reading `PortName = 3` would be taken as `Port`. The release has the
  same property. Note also that the tests are NOT mutually exclusive and none of them
  exits early: every key in a section is compared against every line.

  TWO KEYS THE RELEASE HAS ARE ABSENT, and both were predicted from the string table
  before a single instruction was read. `DoSectMisc` has four tests where 1.39b has
  five -- `TmpPath`, the swap-file path, is gone -- and `DoSectScreen` at 0d9b is FIVE
  BYTES, an empty body, where 1.39b reads `ForceEGA`. A headless player has no swap
  file and no screen mode. **The prediction came from 41 of 52 literals matching and
  the three that did not; two of the three are now confirmed absent from the code.**
  -------------------------------------------------------------------------- }
procedure DoSectSB; far;
begin
  if not NotInStr(Line, 'IRQ'         ) then GetWord(SbIrq);
  if not NotInStr(Line, 'Port'        ) then GetWord(SbPort);
  if not NotInStr(Line, 'DMA'         ) then GetWord(SbDMAChan);
  if not NotInStr(Line, 'SbSplTimeout') then GetWord(SbSplTimeout);
  if not NotInStr(Line, 'HiSpeedDMA'  ) then GetBool(SbHiSpeed)
end;

procedure DoSectGUS; far;
begin
  if not NotInStr(Line, 'Port'        ) then GetWord(GUSPort);
  if not NotInStr(Line, 'IRQ'         ) then GetWord(GUSIrq)
end;

procedure DoSectSBPro; far;
begin
  if not NotInStr(Line, 'MasterVol'   ) then GetByte(SbProMixMasterVol);
  if not NotInStr(Line, 'DACVol'      ) then GetByte(SbProMixDACVol);
  if not NotInStr(Line, 'FMVol'       ) then GetByte(SbProMixFMVol);
  if not NotInStr(Line, 'Filter'      ) then GetBool(SbProMixFilter)
end;

procedure DoSectDAC; far;
begin
  if not NotInStr(Line, 'Port' ) then GetWord(DacPort);
  if not NotInStr(Line, 'LPort') then GetWord(LDacPort);
  if not NotInStr(Line, 'RPort') then GetWord(RDacPort)
end;

procedure DoSectPlayMod; far;
begin
  if not NotInStr(Line, 'PermitFade'  ) then GetBool(PermitFade);
  if not NotInStr(Line, 'FadeSpeed'   ) then GetWord(FadeIncr);
  if not NotInStr(Line, 'LoopMod'     ) then GetBool(VTLoopMod);
  if not NotInStr(Line, 'ForceLoopMod') then GetBool(ForceLoopMod);
  if not NotInStr(Line, 'ShellLoopMod') then GetBool(ShellLoopMod);
  if not NotInStr(Line, 'SampleFreq'  ) then GetWord(DesiredHz);
  if not NotInStr(Line, 'TicksPerSec' ) then GetWord(TicksPerSecond);
  if not NotInStr(Line, 'ShellFreq'   ) then GetWord(ShellHz);
  if not NotInStr(Line, 'MaxFreq'     ) then GetWord(MaxOutputFreq);
  if not NotInStr(Line, 'Volume'      ) then GetByte(VtVolume);
  if not NotInStr(Line, 'Device'      ) then GetString(DevID, SizeOf(DevID) - 1);
  if not NotInStr(Line, 'FilterOn'    ) then GetByte(Byte(FilterOn));
  if not NotInStr(Line, 'FilterOff'   ) then GetByte(Byte(FilterOff));
  if not NotInStr(Line, 'FilterIsOn'  ) then GetBool(ModCommands.FilterIsOn);
  if not NotInStr(Line, 'CanFallBack' ) then GetBool(CanFallBack);
  if not NotInStr(Line, 'FilterChange') then GetBool(PermitFilterChange);
  if not NotInStr(Line, 'BassFilter'  ) then GetBool(DoBassPower);
  if not NotInStr(Line, 'DMAOffset'   ) then GetWord(DMAOffset);
  if not NotInStr(Line, 'LowQuality'  ) then GetBool(LowQuality);
  if not NotInStr(Line, 'Volume'      ) then GetByte(VtVolume)
end;

procedure DoSectMisc; far;
begin
  if not NotInStr(Line, 'ShellPath'  ) then GetPath  (ProgName);
  if not NotInStr(Line, 'ShellParams') then GetString(ShellParam, SizeOf(ShellParam) - 1);
  if not NotInStr(Line, 'Language'   ) then GetPath  (StringsFName);
  if not NotInStr(Line, 'ModPath'    ) then GetPath  (ModPath)
end;

{ FIVE BYTES, and an empty body. The release reads `ForceEGA` here; a
  player with no screen has nothing to configure. It exists at all because
  DoSectGeneric's table needs an address for the section. }
procedure DoSectScreen; far;
begin
end;

{ --------------------------------------------------------------------------
DoSectGeneric. Read lines until the next `[` and hand each one to the
  handler for the section we are inside. One routine drives all seven.

  THE HANDLER ARRIVES AS AN OFFSET, NOT A POINTER, and that is why the `asm` block
  exists. `Ptr(Seg(DoSectGeneric), Offs)` rebuilds a full address by borrowing this
  routine's OWN segment -- which is sound because all seven handlers are in this unit
  -- and then `CALL [DoSect]` calls through it. Pascal has procedural variables and
  the release does not use one here; a `Word` in the table is two bytes instead of
  four, and Seg(self) is free.

  IT SKIPS COMMENTS AND STOPS AT THE NEXT SECTION. `;`, `:` and `#` all introduce a
  comment -- the same three GetString and GetNum look for -- and a line starting `[`
  exits without consuming it, so ReadConfiguration's loop sees it.
  -------------------------------------------------------------------------- }
procedure DoSectGeneric(Offs : Word); far;
var
  DoSect : Pointer;               { and the whole of `ENTER 0004,0`    }
begin
  DoSect := Ptr(Seg(DoSectGeneric), Offs);
  while not Eof(ConfFile) do
  begin
    ReadLn(ConfFile, Line);
    KillSpaces(Line);
    if (Length(Line) > 0) then
    begin
      if (Line[1] = '[') then Exit;
      if (Line[1] <> ';') and
         (Line[1] <> ':') and
         (Line[1] <> '#') then
        asm
          CALL    [DoSect]
        end;
    end;
  end;
end;


{ --------------------------------------------------------------------------
  THE SECTION TABLE. Seven entries, each an OFFSET and a name, and the ORDER IS NOT
  THE ROUTINES' ORDER: the handlers sit in the segment as SB, GUS, SBPro, DAC,
  PlayMod, Misc, Screen, and the table lists PlayMod before DAC. The release has both
  orders the same way round, which is one more small confirmation that this is the
  same source rather than a rewrite.

  `Proc : WORD` is what DoSectGeneric's `Offs` parameter receives.
  -------------------------------------------------------------------------- }
const
  NumSects = 7;

  SectList : array[1..NumSects] of record
                                     Proc : Word;
                                     Name : String[16];
                                   end =
  ( ( Proc: Ofs(DoSectSB);      Name: '[VT-SBlaster]' ) ,
    ( Proc: Ofs(DoSectGUS);     Name: '[VT-GUS]' ) ,
    ( Proc: Ofs(DoSectSBPro);   Name: '[VT-SBPro]' ) ,
    ( Proc: Ofs(DoSectPlayMod); Name: '[VT-PlayMod]' ) ,
    ( Proc: Ofs(DoSectDAC);     Name: '[VT-DAC]' ) ,
    ( Proc: Ofs(DoSectMisc);    Name: '[VT-Misc]' ) ,
    ( Proc: Ofs(DoSectScreen);  Name: '[VT-Screen]' )
  );


{ --------------------------------------------------------------------------
FindNextSect. Skip forward to the next line that starts with `[`,
  leaving it in `Line` for the caller to identify.
  -------------------------------------------------------------------------- }
procedure FindNextSect;
begin
  while not Eof(ConfFile) do
  begin
    ReadLn(ConfFile, Line);
    KillSpaces(Line);
    if (Length(Line) > 0) and (Line[1] = '[') then Exit;
  end;
end;


{ --------------------------------------------------------------------------
ReadConfiguration. The only routine this unit publishes: open the
  file, then alternate between finding a section header and running its handler.

  `FileMode` IS SAVED, FORCED TO 0 AND RESTORED around the `Reset`, which is how you
  open a text file READ-ONLY in Turbo Pascal. Without it the open is read/write and
  fails on a read-only medium or a file another process holds -- a config file on a
  CD or a network share. Three lines to avoid one failure mode.

  AND THE ERROR CHECK IS `IOResult` RATHER THAN AN I/O EXCEPTION: the unit is
  compiled with I/O checking OFF -- the release says so with an $I- directive at the
  top of VTCFG.PAS -- so a failed open sets the code instead of halting, and this
  routine just leaves.

  `not NotInStr(SectList[i].Name, Line)` HAS ITS ARGUMENTS THE OTHER WAY ROUND from
  every other call in the unit -- the TABLE ENTRY is the haystack and the LINE is the
  needle. That is deliberate and it matters: it means the line must be a PREFIX of
  the section name, so `[VT-GUS]` in the file matches the table's `[VT-GUS]` but a
  longer line like `[VT-GUSX]` does not. The other direction would accept anything
  beginning `[VT-`.

  `Good` IS THE "did any handler claim this header" FLAG, and its loop is what lets
  an unrecognised section fall through to the outer `while`, which calls
  FindNextSect again and skips it.
  -------------------------------------------------------------------------- }
procedure ReadConfiguration(FName : PathStr);
var
  I    : Word;
  Good : Boolean;
begin
  Assign(ConfFile, FName);
  I := FileMode;
  FileMode := 0;
  Reset(ConfFile);
  FileMode := I;
  if IOResult <> 0 then Exit;

  while not Eof(ConfFile) do
  begin
    FindNextSect;
    Good := True;
    while (Good)              and
          (not Eof(ConfFile)) and
          (Length(Line) <> 0) and
          (Line[1] = '[')    do
    begin
      Good := False;
      for I := 1 to NumSects do
        if not NotInStr(SectList[I].Name, Line) then
        begin
          DoSectGeneric(SectList[I].Proc);
          Good := True;
        end;
    end;
  end;

  Close(ConfFile)
end;


{ ==========================================================================
THE UNIT'S INITIALISATION SECTION, and it reads up to four files.

  THE RULE IS "A FILE NAMED AFTER THE EXECUTABLE, AND VT.CFG AS WELL IF WE ARE NOT
  VT". `FSplit(ParamStr(0), ...)` takes the program's own directory and name, and then

      if Name <> 'VT' then      read VTDir+'VT.CFG' and then 'VT.CFG'
      always                    read VTDir+Name+'.CFG' and then Name+'.CFG'

  so each pair is tried in the executable's directory first and the current directory
  second, and the later read overwrites the earlier. **That is why `PSYCHO.EXE`
  passing `@neurosis.cfg` works**: it is the same mechanism, and the map records this
  as the second rename-sensitive check in the program after the `'inconexi'` one in
  segment 1000. Rename the executable and it reads a different configuration.

  THE RELEASE HAS THIS BLOCK TOO, and an earlier version of this header said it did
  not. That was wrong and it was wrong for an avoidable reason: the claim came from
  the segment map's description of what the init does, not from reading the bottom of
  `VTCFG.PAS`, which has the same block and the same three literals. **Read the file
  before saying what is not in it.**
  ========================================================================== }
var
  Path : PathStr;
  Name : NameStr;
  Ext  : ExtStr;

begin
  Path := ParamStr(0);
  FSplit(Path, VTDir, Name, Ext);
  if Name <> 'VT' then
  begin
    ReadConfiguration(VTDir + 'VT.CFG');
    ReadConfiguration('VT.CFG');
  end;

  ReadConfiguration(VTDir + Name + '.CFG');
  ReadConfiguration(Name + '.CFG')
end.
