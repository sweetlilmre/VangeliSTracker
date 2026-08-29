{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 164b -- the JMPlayer recogniser. 80 bytes, of which 77 are the
  single routine.

  IT RECOGNISES A FORMAT IN ORDER TO REFUSE IT. This is the part that was
  read backwards for a long time. On a MATCH it stores 6, which is
  msFileFormatNotSupported; on no match it stores 0, which is msNotLoaded --
  the initial state, meaning "not mine, ask someone else". So the routine
  exists to spot a JMPlayer module and produce a proper error for it, rather
  than let a later recogniser mistake it for something playable and emit
  noise. Compare 154d, which tests offset 1080 for 'M.K.' or '.WOW' and
  claims what it finds.

  Format is written BEFORE the comparison and stays written even when the
  routine declines. That is safe only because Status is what callers test.

  NAMES ARE THE 1.39b RELEASE'S. LIB/UNKLOADE.PAS is this unit statement for
  statement -- the same three assignments around the same comparison, and the
  same six-character marker under the same name.

  ITS TYPES ARE NOT ADOPTED. The release declares
  `LoadJMFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader)`
  and lays a `TModJMIdString ABSOLUTE Header` over the third parameter. A `var`
  parameter and a pointer are the same four bytes on the stack, so the frame and
  the RETF $0C would survive the change -- but `TStream` is Turbo Vision's and
  pulling `Objects` into a 77-byte unit to name a parameter the routine never
  reads is a type change wearing a rename's clothes. The pointer types stay and
  carry the release's spellings.

  Nothing proves 1.31 spelled any of this the same way: no debug information.

  ADDRESS MAP
    LoadJMFileFormat  164b:0000     ModJMIdString  DS:$040e, six raw bytes
  =========================================================================== }

unit UnkLoader;

interface

uses
  Objects, SongUnit;

type
  { DS:$040e holds six bytes with NO length prefix, and the routine compares
    exactly six, so the marker is a fixed-width character run rather than a
    Pascal string. }
  PModJMIdString = ^TModJMIdString;
  TModJMIdString = array[1..6] of Char;

{ THE SIGNATURE IS THE RELEASE'S, AND 14b9 IS WHAT CORRECTED IT. This was
  declared (Song : PSong; St : Pointer; Header : PModJMIdString) -- three
  pointer VALUE parameters, which occupy the same twelve bytes of frame and
  leave this routine's own code identical either way. It is only visible from
  the CALLER: 14b9:00dc pushes Self, St and Header as three var parameters, and
  SongUnit's SongLoaders table types them so. Fourth time in the tree that a
  byte-exact unit had a wrong interface -- see VTDOSRSZ, VTDOSMEM and GUS. }
procedure LoadJMFileFormat(var Song : TSong; var St : TStream;
                           var Header : TSongHeader); far;

implementation

const
  ModJMIdString : TModJMIdString = 'JMPLAY';

{ --------------------------------------------------------------------------
  164b:0000.

  Plain Pascal in the binary, and the shape of it is worth reading carefully
  because getting it wrong costs 40 bytes.

  The frame is `ENTER $200,0` and the body pushes a destination, a source and
  a literal 6 into the compiler's array-of-char-to-String helper (1ba1:0c05)
  TWICE, then calls its string compare (1ba1:0bc8).

  THOSE TWO 256-BYTE SLOTS ARE COMPILER TEMPORARIES, NOT VARIABLES. Turbo
  Pascal permits `=` between two char arrays and implements it by converting
  both to String temporaries and comparing those; `LEA DI,[BP-$100]` and
  `LEA DI,[BP-$200]` are those temporaries. An earlier version of this file
  declared two `String` locals and assigned into them, which produces the
  same two helper calls PLUS a copy into each local -- the whole of the size
  discrepancy this unit used to carry.

  So the faithful transcription is the direct comparison, and it is also the
  short one.

  THE MIDDLE PARAMETER IS NEVER READ. The routine is `RETF $0C` -- twelve
  bytes, three far pointers -- but touches only the first and the last. It is
  declared to keep the frame and the RETF right.
  -------------------------------------------------------------------------- }
procedure LoadJMFileFormat(var Song : TSong; var St : TStream;
                           var Header : TSongHeader);
var
  { The release's own device for reading the first six bytes of a 2,048-byte
    buffer: an ABSOLUTE alias costs no code and no frame, where a typed pointer
    would need a load. }
  ModJM : TModJMIdString absolute Header;
begin
  Song.FileFormat := mffJMPlayer;                 {+$5d := 4 }

  if ModJM = ModJMIdString then
    Song.Status := msFileFormatNotSupported       {+$59 := 6 }
  else
    Song.Status := msNotLoaded;                   {+$59 := 0 }
end;

end.
