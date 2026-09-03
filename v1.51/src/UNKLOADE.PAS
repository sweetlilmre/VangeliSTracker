{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  The JMPlayer recogniser.

  IT RECOGNISES A FORMAT IN ORDER TO REFUSE IT, which is the opposite of what
  a loader usually does and is the thing to understand about this unit. On a
  MATCH it sets the status to msFileFormatNotSupported; on NO match it sets
  msNotLoaded -- the initial state, meaning "not mine, ask someone else".

  So this exists to spot a JMPlayer module and produce a proper error for it,
  rather than let a later recogniser mistake it for something playable and
  emit noise. Compare ModLoader, which tests for 'M.K.' or '.WOW' and CLAIMS
  what it finds; this one claims nothing and only ever declines.

  It is called first in the loader chain for that reason: the cost of getting
  the order wrong is a wrong answer, not a slow one.

  FileFormat IS WRITTEN BEFORE THE COMPARISON and stays written even when the
  routine declines. A caller that reads FileFormat without checking Status
  will see mffJMPlayer on a file that is nothing of the kind. That is safe
  only because Status is what callers actually test.

  [re] SEGMENT 1839 -- 80 bytes, of which 77 are the single routine.

  [re] NAMES ARE THE 1.39b RELEASE'S. LIB/UNKLOADE.PAS is this unit statement
  for statement -- the same three assignments around the same comparison, and
  the same six-character marker under the same name.

  [re] ITS TYPES ARE NOT ADOPTED. The release declares
  `LoadJMFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader)`
  and lays a `TModJMIdString ABSOLUTE Header` over the third parameter. A `var`
  parameter and a pointer are the same four bytes on the stack, so the frame
  and the RETF $0C would survive the change -- but `TStream` is Turbo Vision's
  and pulling `Objects` into a 77-byte unit to name a parameter the routine
  never reads is a type change wearing a rename's clothes. The pointer types
  stay and carry the release's spellings. Nothing proves 1.31 spelled any of
  this the same way: no debug information.

  [re] 1839 IN THIS IMAGE, NOT 164b, and DS:$04b6 not DS:$040e. Charted in
  Ghidra rather than inferred: `ENTER $200,0` (C8 00 02 00) occurs exactly
  unit's single routine sits. The 76 bytes there are this routine statement
  for statement -- two temporaries at BP-$100 and BP-$200, two helper calls
  each pushing a literal 6, the string compare, a store of 6 or 0, RETF $0C
  itself is at 1e92:04b6, so DGROUP is 1e92 here.
  [re] ADDRESS MAP
  TWICE in this image and one of them is 1839:0000, which is where this
  -- and it carries `MOV DI,04b6`, which is 'JMPLAY' re-based. 'JMPLAY'
    LoadJMFileFormat  1839:0000     ModJMIdString  DS:$04b6, six raw bytes
  =========================================================================== }

unit UnkLoader;

interface

uses
  Objects, SongUnit;

type
  { The marker is a FIXED-WIDTH CHARACTER RUN, not a Pascal string: six bytes
    with no length prefix, and the routine compares exactly six. }
  PModJMIdString = ^TModJMIdString;
  TModJMIdString = array[1..6] of Char;

{ Decide whether `Header` is a JMPlayer module and record the answer in
  `Song.Status`. Never loads anything.

  [re] THE SIGNATURE IS THE RELEASE'S, AND 14b9 IS WHAT CORRECTED IT. This was
  declared (Song : PSong; St : Pointer; Header : PModJMIdString) -- three
  pointer VALUE parameters, which occupy the same twelve bytes of frame and
  leave this routine's own code identical either way. It is only visible from
  the CALLER: 153a:00dc pushes Self, St and Header as three var parameters, and
  SongUnit's SongLoaders table types them so. Fourth time in the tree that a
  byte-exact unit had a wrong interface -- see VTDOSRSZ, VTDOSMEM and GUS. }
procedure LoadJMFileFormat(var Song : TSong; var St : TStream;
                           var Header : TSongHeader); far;

implementation

const
  { [re] 1e92:040e }
  ModJMIdString : TModJMIdString = 'JMPLAY';

{ --------------------------------------------------------------------------
  Compare the first six bytes of the loaded header against 'JMPLAY' and set
  the song's status to "recognised but unsupported" if they match, or back to
  "not loaded" if they do not.

  THE MIDDLE PARAMETER IS NEVER READ. Three far pointers come in and only the
  first and the last are touched. It is declared because the caller pushes it
  and the routine has to clean up the right number of bytes on return.

  Nothing here reads the file. The header has already been read into memory by
  the caller, and this routine only looks at what it was handed -- which is why
  a recogniser can be this cheap to try.

  [re] 1839:0000. Plain Pascal in the binary, and the shape of it is worth
  reading carefully because getting it wrong costs 40 bytes. The frame is
  `ENTER $200,0` and the body pushes a destination, a source and a literal 6
  into the compiler's array-of-char-to-String helper (1d89:0c05) TWICE, then
  calls its string compare (1d89:0bc8).

  [re] THOSE TWO 256-BYTE SLOTS ARE COMPILER TEMPORARIES, NOT VARIABLES. Turbo
  Pascal permits `=` between two char arrays and implements it by converting
  both to String temporaries and comparing those; `LEA DI,[BP-$100]` and
  `LEA DI,[BP-$200]` are those temporaries. An earlier version of this file
  declared two `String` locals and assigned into them, which produces the same
  two helper calls PLUS a copy into each local -- the whole of the size
  discrepancy this unit used to carry. So the faithful transcription is the
  direct comparison, and it is also the short one.
  -------------------------------------------------------------------------- }
{ @asm 000 1839:0000 }
procedure LoadJMFileFormat(var Song : TSong; var St : TStream;
                           var Header : TSongHeader);
var
  { Read the first six bytes of the header buffer with no load and no copy: an
    ABSOLUTE alias is a second name for storage that is already there. }
  ModJM : TModJMIdString absolute Header;
begin
  Song.FileFormat := mffJMPlayer;                 { 1839:0007  +$5d := 4 }

  if ModJM = ModJMIdString then                   { 1839:0019..0035      }
    Song.Status := msFileFormatNotSupported       { 1839:003a  +$59 := 6 }
  else
    { Not a JMPlayer module -- put the status back exactly as it was found, so
      the next recogniser in the chain sees an untouched song. }
    Song.Status := msNotLoaded;                   { 1839:0044  +$59 := 0 }
end;

end.
