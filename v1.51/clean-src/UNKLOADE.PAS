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
  only because Status is what callers actually test.}

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
  `Song.Status`. Never loads anything.}
procedure LoadJMFileFormat(var Song : TSong; var St : TStream;
                           var Header : TSongHeader); far;

implementation

const
  
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
  a recogniser can be this cheap to try.}
procedure LoadJMFileFormat(var Song : TSong; var St : TStream;
                           var Header : TSongHeader);
var
  { Read the first six bytes of the header buffer with no load and no copy: an
    ABSOLUTE alias is a second name for storage that is already there. }
  ModJM : TModJMIdString absolute Header;
begin
  Song.FileFormat := mffJMPlayer;                 { +$5d := 4 }

  if ModJM = ModJMIdString then
    Song.Status := msFileFormatNotSupported       { +$59 := 6 }
  else
    { Not a JMPlayer module -- put the status back exactly as it was found, so
      the next recogniser in the chain sees an untouched song. }
    Song.Status := msNotLoaded;                   { +$59 := 0 }
end;

end.
