{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 11bb -- THE CONFIGURATION FILE READER. 4,080 bytes, twenty routines.

  COMPLETE. All 4,080 bytes.

  AND ESSENTIALLY THE WHOLE UNIT WENT IN VERBATIM FROM THE RELEASE. Twenty routines,
  and only three needed anything measured out of the binary rather than copied:

      ShellParam is a `String[127]`   11bb:0d5c pushes 7F, not FF
      TmpPath is absent               DoSectMisc has four tests, not five
      ForceEGA is absent              DoSectScreen is five bytes, an empty body

  Everything else -- including GetString's 786 bytes and DoSectPlayMod's twenty
  keys -- compiled byte-exact from `VTCFG.PAS` with no adjustment. **That has not
  happened anywhere else in this project**; the closest was `MyMove` in 12ba, one
  routine. So the release's root-directory sources can be trusted the way `LIB/`'s
  are, and the two absent keys were PREDICTED from the string table before a single
  instruction was read.

  THE COUNTERPART IS `VangeliSTracker/VTCFG.PAS` AND IT IS IN THE RELEASE'S ROOT,
  NOT IN `LIB/`. Every pairing in this project before this one came from `LIB/`, and
  the working assumption had hardened into "the root holds the tracker's own units
  and will not pair". It was wrong. 41 of VTCFG.PAS's 52 distinctive string literals
  appear in this segment and the segment contains essentially nothing else -- its
  complete string inventory is VTCFG's keyword list plus `VT.CFG` and `.CFG`. Only
  three keys are missing, `ForceEGA`, `Line` and `TmpPath`, which are exactly what a
  headless player drops: a video mode, a mixer line input and a swap path.

  (That test works because Turbo Pascal puts an untyped string constant in the CODE
  segment -- the `PUSH CS` rule from `VTRESID` -- so a segment carries its unit's
  literals verbatim. It is one-way: a high score is strong evidence, a low score is
  none at all. See `demovt/pairmap.py`.)

  `11bb:0000..001f` IS DATA, AND IT IS A SET CONSTANT. The first routine starts at
  0020; the 32 bytes before it are

      01 02 00 00 01 00 ... 00 80

  which is a `set of Char` with exactly four members: bit 0 of byte 0 is #0, bit 1 of
  byte 1 is #9, bit 0 of byte 4 is #32, and bit 7 of byte 31 is #255. That is
  `KillSpaces`'s `ValidBlanks = [' ', #9, #0, #255]` character for character, and
  `11bb:0035` loads it with `MOV DI,0 / PUSH CS / PUSH DI` -- CS-relative, offset
  zero. **So an untyped SET constant goes in the code segment exactly as a string
  literal does**, which extends a rule the docs had only for strings, and it is why
  the segment does not begin on an instruction boundary.

  THE INITIALISATION SECTION AT 11bb:0f2e IS THE RELEASE'S TOO. An earlier draft of
  this header said 1.31 had added it; that was wrong, and wrong for an avoidable
  reason -- it came from the segment map's description of what the init does rather
  than from reading the bottom of `VTCFG.PAS`, which has the same block and the same
  three literals. It splits `ParamStr(0)` and reads up to four files, one pair named
  after the executable and one pair named `VT.CFG`, each tried in the program's own
  directory and then the current one. That is why `PSYCHO.EXE` passing
  `@neurosis.cfg` works, and it is the second rename-sensitive check in the program
  after the `'inconexi'` one in `1000`. See the block itself.
  =========================================================================== }
unit VTCfg;

interface

{ `DevSB` IS HERE FOR THE FOUR SB PRO MIXER BYTES, which this unit writes from its
  `MasterVol`, `DACVol`, `FMVol` and `Filter` keys and which the DGROUP layout showed
  belong to DevSB's block at $09ea. It cannot move a segment: DevSB is reached from the
  program's own clause long before VTCfg, so it is already placed when the walk arrives
  here. `demovt/linkorder.py` is the check. }
uses
  Dos, SongUnit, VTDriver, SoundDevices, GUS, PlayMod, ModCommands, VTShell,
  VTGlobal, SoundBlaster, DevSB, SongElements;
  { `SongElements` is here for `LowQuality`, its typed constant at $0564, which this
    unit writes from the `LowQuality` key. It was reaching a duplicate declared in
    SongUnit; two bytes of that unit's variables, and removing them is what put
    VTNOTES' `NoteOf` back on $25c6. Already reached through SongUnit, so it cannot
    move a segment. }

{read and interpret a file as a configuration file. }
procedure ReadConfiguration(FName : PathStr); far;

implementation

var
  { The release's names and its comments. Both are DGROUP. }
  ConfFile : Text;                { the open configuration file                }
  Line     : String;              { DS:$1090  the last line read from it        }


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

  **AND `FilterIsOn` AT $0348 IS A RETROSPECTIVE CONFIRMATION.** 142f left two
  variables of that name -- PlayMod's at $02cd and ModCommands' at $0348 -- with
  nothing in the transcribed tree reading the second, and ModCommands kept its copy
  unexported so the two could not shadow each other. 11bb:0b0e's `FilterIsOn` key
  writes $0348. So the config file is what sets it, the duplication is real, and the
  decision not to export it was right for a reason that had not appeared yet.

  THE REST BELONG TO SEGMENTS THAT ARE NOT TRANSCRIBED, so they are declared here
  and flagged -- what is left of them; see the note in the block itself for the fourteen
  that moved to `VTGLOBAL.PAS` and `SOUNDBLA.PAS` when `109c` landed. A global's
  address is a linker fixup, so this cannot change a byte of
  either unit and the byte comparison cannot see it either way -- which is exactly
  what makes it dangerous, and exactly why it is written down. Move each one when its
  segment lands.
  -------------------------------------------------------------------------- }
{ ~~THIS UNIT DECLARED FOURTEEN GLOBALS AND NOW DECLARES NONE.~~ The last four went
  with the DGROUP layout: the three DAC ports are SoundDevices' typed constants and
  `VTDir` is VTGlobal's, all four at addresses this unit already carried but could
  not own. It writes every one of them from a config key and reaches them all
  through a `uses`. See the notes below, which are kept for what they record. }
  { Segment 193a, the release's `LIB/DEVSB.PAS` -- the SB Pro mixer. }
  { ~~SbProMixMasterVol $09ea, SbProMixDACVol $09eb, SbProMixFMVol $09ec,
    SbProMixFilter $09ed~~ -- ALL FOUR MOVED TO DEVSB.PAS. This unit writes them, from
    the `MasterVol`, `DACVol`, `FMVol` and `Filter` keys, which is why they were
    declared here; it cannot OWN them, because its own DGROUP block is $0240..$02c3 and
    these four are inside DevSB's, $09ea..$0adb. They are the first four bytes of it.
    See the note at their declaration there -- the image holds `ff ff ff 00`, which is
    the release's three-volumes-at-full-and-filter-off default. }

  { The release's `LIB/DEVDAC.PAS`. NO SEGMENT IN DEMOVT HAS BEEN IDENTIFIED AS THE
    DAC driver, and these three sit immediately after SoundDevices' $0bf0, so they
    may well be SoundDevices' own here. Unresolved. }
  { ~~DacPort $0bf2, LDacPort $0bf4, RDacPort $0bf6~~ -- SOUNDDEVICES' TYPED CONSTANTS,
    all three holding $378 (LPT1). This unit WRITES them, from its `Port`, `LPort` and
    `RPort` keys in the DAC section, which is why they were declared here with the right
    addresses; it cannot own them, because $0bf2 is inside SoundDevices' block. The
    references below now spell them `DacPort`, `LDacPort` and `RDacPort`, which is that
    unit's -- and the release's -- capitalisation. }

  { ---- AND THE VTGlobal GROUP HAS MOVED OUT, to demovt/src/VTGLOBAL.PAS ----
    `PermitFade`, `VtVolume`, `ShellLoopMod`, `ShellHz`, `FadeIncr`, `VTLoopMod`,
    `ShellParam`, `DevID`, `StringsFName` and `ModPath` were declared here, privately,
    because this was the only unit that touched them.

    **`109c` IS WHAT FORCED THE MOVE.** VTCmd writes the same settings from the command
    line that this unit writes from the config file, and a private declaration cannot be
    shared. The release has always kept them in its own `VTGLOBAL.PAS`; ours now does
    too. `SbPort`, `SbIrq`, `SbDMAChan` and `SbHiSpeed` went to `SOUNDBLA.PAS`, a
    declared stub for segment `19a0`, for the same reason.

    **AND `VTDir` WAS WRONG.** It was declared here as a `PathStr` at `DS:$09e8`, marked
    provisional, on the strength of `11bb:0a00` referring to `09e8`. That reference is
    `MOV DI,09e8 / PUSH CS / PUSH DI` -- a far pointer into THIS UNIT'S OWN CODE
    SEGMENT, a string constant, not a DGROUP address at all. The DGROUP byte at `$09e8`
    is `109c`'s no-banner Boolean, which `1000` tests one byte at a time. `VTDir` is
    gone; nothing read it. **A `PUSH CS` before the pointer is the tell, and it was
    there to be seen.**

    This unit still verifies IDENTICAL after losing those declarations, which is the
    expected result and worth stating: a DGROUP reference is a linker fixup, so where a
    global is declared cannot change a byte of the code that uses it. }

  { THE VARIABLE IS REAL AND THE ADDRESS WAS NOT. The initialisation section below fills
    it with the executable's own directory and nothing in the transcribed tree reads it,
    so it stays private to this unit -- but the `DS:$09e8` it used to carry is deleted.
    That byte is `109c`'s no-banner Boolean; see VTGLOBAL.PAS. **No address is known for
    VTDir**, and saying so is better than quoting one that belongs to something else. }
  { ~~VTDir : PathStr, no measured address~~ -- IT IS `VTGlobal.VTDir` AT $083a, and it
    has an address again after this file withdrew one. The layout is what found it: the
    original's `1000` and `11bb` both reach $083a, VTGlobal's DGROUP block runs
    $083a..$09e8, and $083a is its first datum -- a `DirStr` typed constant, sixty-eight
    bytes, which is exactly what closes the gap down to `DevPtr` at $087e. Declared here
    as a `PathStr` var it was eighty bytes of THIS unit's variables, which is most of the
    86 that had every unit after it in the wrong place. }


{ --------------------------------------------------------------------------
KillSpaces. Strip blanks from both ends of a string, in place.

  TWO `while`s AND NOT ONE, and they are not symmetrical: the leading blanks are
  removed by COPYING the string down (`S := Copy(S, 2, 255)`, which costs a 256-byte
  temporary and is the whole of `ENTER 0100,0`), and the trailing ones by decrementing
  the LENGTH BYTE in place. The release is the same, and the asymmetry is the obvious
  one -- there is no cheap way to drop a leading character from a Pascal string.

  `Dec(S[0])` IS THE LENGTH BYTE. `S[0]` is a `Char` holding the length, so `Dec` on
  it shortens the string; 11bb:008e is `DEC byte ptr ES:[DI]` with DI at the string's
  base. Written `S[0] := Chr(Ord(S[0]) - 1)` it would be several instructions.

  `ValidBlanks` INCLUDES #0 AND #255, which is not fussiness -- a config line read
  from a text file can carry either as padding, and a name compared with trailing
  #255 would never match a keyword.
  -------------------------------------------------------------------------- }
procedure KillSpaces(var S : String);
const
  { The 32 bytes at 11bb:0000, and the reason the segment starts with data. }
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

  BOTH PARAMETERS ARE `String` BY VALUE, and that is most of the frame. Turbo Pascal
  passes a value `String` as a far pointer and makes the callee copy it, so 009b and
  00ae are two 256-byte copies into [BP-102] and [BP-202] before a single comparison
  happens -- 512 of the 518 bytes of `ENTER 0206,0`. The remaining six are the loop
  variable, the `for` limit temporary and the one-byte result at [BP-1].

  AND THE COPIES GO IN PARAMETER ORDER, WHICH FIXES WHICH IS WHICH: [BP+8] is the
  first-declared and lands at [BP-102], [BP+4] is the second and lands at [BP-202].
  00c5 then reads the length at [BP-202] and compares it against [BP-102], which is
  `Length(SS) > Length(S)` and not the other way round.

  `UpCase(S[I]) <> UpCase(SS[I])` EVALUATES ITS RIGHT OPERAND FIRST: 00ee takes
  SS[I], calls UpCase, pushes the answer, and only then does S[I]. That is the third
  independent sighting of the rule that turned up in 142f's StartArpeggio -- Turbo
  Pascal computes the right-hand operand of a binary expression before the left.
  -------------------------------------------------------------------------- }
function NotInStr(S, SS : String) : Boolean;
var
  I : Word;                       { [BP-204]; [BP-206] is the `for` limit      }
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

  `11bb:0127..0130` IS ITS DATA. Ten bytes, five length-1 string literals --
  `01 3D`, `01 27`, `01 3B`, `01 3A`, `01 23` -- which are the five characters this
  routine and GetNum look for with `Pos`: equals, quote, semicolon, colon and hash.
  A one-character Pascal literal is still a string with a length byte, and it goes in
  the code segment like any other. That is the second block of data in this segment
  after the set constant at 0000.

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
  11bb:0443 -- GetBool. Read the value after the `=` and decide whether it means
  true or false, in four languages.

  `11bb:0407..0442` IS ITS LITERAL TABLE and the ORDER IS THE RELEASE'S EXACTLY:

      01 'S'   01 'Y'   03 'OUI'  02 'DA'   03 'POR'  04 'TAMB' 04 'ALSO'
      04 'TRUE' 04 'VERD' 04 'CIER' 01 '1'
      01 'N'   03 'PAS' 04 'TAMP' 04 'FALS' 01 '0'

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
and 11bb:0850 -- GetWord and GetByte. GetNum with a cast, and the two
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
  11bb:089f..0d9f -- THE SEVEN SECTION HANDLERS. One per `[VT-...]` section, each a
  flat chain of `if not NotInStr(Line, <key>) then Get<Type>(<variable>)`.

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

{ The big one: twenty tests, and `Volume` appears TWICE -- first and last. The
  release has the duplicate too, and it is not a transcription slip: 11bb:0b0e's
  chain writes DS:$08ba at both the tenth and the twentieth test. Harmless, since
  the second overwrites the first with the same value. }
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
  { QUALIFIED ON PURPOSE. PlayMod now exports a `FilterIsOn` of its own at
its address forced it into that unit's interface -- and this unit
    uses both, so a bare reference would bind to whichever `uses` entry comes
    last. 11bb:0b0e writes $0348, which is ModCommands'. }
  if not NotInStr(Line, 'FilterIsOn'  ) then GetBool(ModCommands.FilterIsOn);
  if not NotInStr(Line, 'CanFallBack' ) then GetBool(CanFallBack);
  if not NotInStr(Line, 'FilterChange') then GetBool(PermitFilterChange);
  if not NotInStr(Line, 'BassFilter'  ) then GetBool(DoBassPower);
  if not NotInStr(Line, 'DMAOffset'   ) then GetWord(DMAOffset);
  if not NotInStr(Line, 'LowQuality'  ) then GetBool(LowQuality);
  if not NotInStr(Line, 'Volume'      ) then GetByte(VtVolume)
end;

{ FOUR TESTS, NOT THE RELEASE'S FIVE: `TmpPath` is absent. And `ShellPath` writes
  VTShell's `ProgName` at DS:$3ade, which is the release's name for it -- ours came
  from 109c overwriting it with the program Psycho Neurosis actually runs. }
procedure DoSectMisc; far;
begin
  if not NotInStr(Line, 'ShellPath'  ) then GetPath  (ProgName);
  if not NotInStr(Line, 'ShellParams') then GetString(ShellParam, SizeOf(ShellParam) - 1);
  if not NotInStr(Line, 'Language'   ) then GetPath  (StringsFName);
  if not NotInStr(Line, 'ModPath'    ) then GetPath  (ModPath)
end;

{FIVE BYTES, and an empty body. The release reads `ForceEGA` here; a
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
  DoSect : Pointer;               { [BP-4], and the whole of `ENTER 0004,0`    }
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

  `11bb:0f1f..0f2d` IS ITS DATA: three literals, `02 'VT'`, `06 'VT.CFG'` and
  `04 '.CFG'`, which are exactly the three the release's block uses.

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
