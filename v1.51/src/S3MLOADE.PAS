{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).
  NOT Asphyxia code. See v1.51/docs/CONTINUATION.md.

  Segment 1664 -- the Scream Tracker 3 (.S3M) loader. 3,472 bytes, of which
  3,458 are the four routines. NEW IN v1.51, and the headline feature:
  WHATSNEW.DOC opens with "Introduced .S3M support".

  NO RELEASE SOURCE, for the same reason STMLOADE.PAS has none -- 1.39b is
  January 1994 and this arrives in April. `MODLOADE.PAS` and `STMLOADE.PAS`
  are the templates; where all three do the same thing they are written the
  same way.

  THE ROUTINE MAP, in address order, which is SOURCE order. The return forms
  are measured and are the signatures:

    0000  no ENTER    RET  $06   SeekPara            Para, St
    002b  ENTER $19b2 RET  $16   ReadPatterns        7 parameters
    06cb  ENTER $17e  RET  $16   ReadInstruments     7 parameters
    0a8b  ENTER $702  RETF $0c   LoadS3MFileFormat   Song, St, Header

  0000 HAS NO `ENTER` AT ALL -- `PUSH BP / MOV BP,SP` -- so it declares no
  locals, which is what makes it a one-statement routine.

  $19b2 IS 6,578 BYTES OF FRAME on ReadPatterns, and that is the S3M packed
  pattern buffer plus the unpacked working set.

  THE FILE FORMAT, read off the code rather than a specification:

    +$000  28 bytes  song name          StrASCIIZ over $1c at 0aca
    +$020  word      OrdNum             the order table's length
    +$022  word      InsNum             instrument count
    +$024  word      PatNum             pattern count
    +$02c  4 bytes   'SCRM'             the magic, DS:$0468
    +$030  byte      global volume
    +$031  byte      initial speed
    +$032  byte      initial tempo
    +$040  32 bytes  channel settings   bit 3 is the pan side; $FF is unused
    +$060            the order table begins -- 0a9f seeks here

  and after the order table come InsNum paragraph pointers, then PatNum of
  them, each a word to be multiplied by 16 and added to the module's base.

  TWO UNIT VARIABLES, both in the uninitialised half of DGROUP:

    DS:$491c  LongInt  the module's own start in the stream, set by the
                       recogniser and read by SeekPara
    DS:$491a  Word     the highest channel actually used, narrowed by
                       ReadPatterns and applied to Song.NumChannels at the end

  ADDRESS MAP
    SeekPara           1664:0000     'SCRM'      DS:$0468
    ReadPatterns       1664:002b     'SCRS'      DS:$046c
    ReadInstruments    1664:06cb
    LoadS3MFileFormat  1664:0a8b
  =========================================================================== }

unit S3MLoader;

interface

uses
  Objects, SongUnit;

procedure LoadS3MFileFormat(var Song : TSong; var St : TStream;
                            var Header : TSongHeader);

implementation

uses
  SongElements, Heaps, AsciiZ, VTNotes;

type
  { The header, to +$60. The order table and the two paragraph-pointer arrays
    follow it in the file and are READ rather than mapped, because their
    lengths are in the header. }
  TS3MFile = record
    Name        : array[1..28] of Char;  { +$00                              }
    Filler1     : array[1..4] of Byte;   { +$1c  the $1A marker and the type  }
    OrdNum      : Word;                  { +$20  read at 0b2e                 }
    InsNum      : Word;                  { +$22                               }
    PatNum      : Word;                  { +$24                               }
    Filler2     : array[1..6] of Byte;   { +$26                               }
    Magic       : array[1..4] of Char;   { +$2c  'SCRM'                       }
    Volume      : Byte;                  { +$30                               }
    Speed       : Byte;                  { +$31                               }
    Tempo       : Byte;                  { +$32                               }
    Filler3     : array[1..13] of Byte;  { +$33                               }
    Channels    : array[1..32] of Byte;  { +$40  bit 3 is the pan side        }
  end;

  { The two paragraph-pointer tables, each read straight off the stream. }
  TS3MParaTable = array[1..256] of Word;

var
  { DS:$491c. `SeekPara` adds a paragraph count to it, so it is the module's
    own origin -- the stream position the recogniser saw before it seeked past
    the header. A plain `var`: it is in the uninitialised half. }
  ModBase : LongInt;

  { DS:$491a. Set to 1 by the recogniser and raised by ReadPatterns as it
    meets channels; the recogniser then narrows Song.NumChannels to it, so a
    module that declares sixteen channels and uses four reports four. }
  ChansUsed : Word;

{ ---------------------------------------------------------------------------
  1664:0000..002a.  No ENTER, RET $06.

  `PUSH BP / MOV BP,SP` and no frame at all, which is Turbo Pascal's shape for
  a routine with no locals. One statement: seek to a paragraph offset measured
  from the module's own start. 1d89:0a13 is the 32-bit multiply, so the Word
  is widened before it is scaled -- a Word times 16 would overflow at $1000
  paragraphs and the file's tables reach further than that.
  --------------------------------------------------------------------------- }
procedure SeekPara(Para : Word; var St : TStream);
begin
  St.Seek(ModBase + LongInt(Para) * 16)
end;

{ ---------------------------------------------------------------------------
  1664:002b..06ca.  ENTER $19b2, RET $16.  NOT TRANSCRIBED.

  PLACEHOLDER holding its position. Turbo Pascal lays routines out in source
  order, so this has to exist and be in the right place or everything below it
  moves; it is the wrong length, so measure this segment per routine and not
  by a prefix.

  Seven parameters, 22 bytes, in this order -- read off the recogniser's call
  site at 0d34 and off the RET.
  --------------------------------------------------------------------------- }
procedure ReadPatterns(var Song : TSong; var St : TStream;
                       var Buf; var Para : TS3MParaTable;
                       Num, A, B : Word);
begin
end;

{ ---------------------------------------------------------------------------
  1664:06cb..0a8a.  ENTER $17e, RET $16.  NOT TRANSCRIBED.

  PLACEHOLDER, as above. What is known: it walks 1..Num, seeks to each
  instrument's paragraph, reads an $50-byte header, takes the name from +$30
  when it is non-empty and from +$01 when it is not, builds a TInstrumentRec,
  allocates and reads the sample, and then decides whether the sample is
  SIGNED by counting sign transitions against magnitude transitions -- the
  block at 0938. `A` selects the pitch numerator: $2100 when zero, $20ab when
  not.
  --------------------------------------------------------------------------- }
procedure ReadInstruments(var Song : TSong; var St : TStream;
                          var Buf; var Para : TS3MParaTable;
                          Num, A, B : Word);
begin
end;

{ ---------------------------------------------------------------------------
  1664:0a8b..0d83.  ENTER $702, RETF $0c.  SongLoaders[2].

  The recogniser. Same contract as every loader here: FileFormat is written
  before the test and stays written when the routine declines, because callers
  test Status.

  $702 IS 1,794 BYTES and names the three buffers: two 256-byte String
  temporaries for the magic comparison, a 256-byte scratch, and the two
  paragraph tables at 512 bytes each.
  --------------------------------------------------------------------------- }
procedure LoadS3MFileFormat(var Song : TSong; var St : TStream;
                            var Header : TSongHeader);
const
  { DS:$0468, four raw bytes with no length prefix. }
  S3MIdString : array[1..4] of Char = 'SCRM';
var
  S3M     : TS3MFile absolute Header;
  { THE ORDER IS READ OFF THE COUNTER'S OWN DISPLACEMENT. 0b8e is
    `MOV [BP-0402],1` for `for i := 1 to 32`, so exactly $400 bytes of locals
    sit ABOVE the counter -- the two 512-byte paragraph tables and nothing
    else. The scratch buffer is declared after it, at -$502. Turbo Pascal
    allocates downward in declaration order, so this order is the measurement
    and not a preference: with the buffer first, every local below it is 256
    bytes out and the frame is still $702. }
  InsPara : TS3MParaTable;
  PatPara : TS3MParaTable;
  i       : Word;
  Buf     : array[1..256] of Byte;
begin
  Song.FileFormat := mffS3M;                       { 0a90  +$7d := 9 }

  { 0a95..0ab5.  The module's own origin, kept for SeekPara. }
  ModBase := St.GetPos;
  St.Seek(ModBase + $60);

  { A GUARD, NOT AN if/else -- the same shape STMLOADE's recogniser has, and
    for the same reason: the comparison's two String temporaries die at the
    semicolon and the body reuses them. }
  if S3M.Magic <> S3MIdString then
    begin
      Song.Status := msNotLoaded;
      Exit
    end;

  Song.Status := msOk;

  FillChar(Buf, SizeOf(Buf), 0);

  Song.Name := FullHeap.HNewStr(StrASCIIZ(S3M.Name, 28));

  if S3M.Volume = $40 then
    S3M.Volume := $3F;

  Song.InitialTempo := S3M.Speed;
  Song.InitialBPM   := S3M.Tempo;
  Song.Volume       := S3M.Volume * 4 + 3;
  Song.NumChannels  := $10;

  ChansUsed := 1;

  { 0b06..0b2d.  THE CONSUMER OF TSong.ChannelPan. Bit 3 of a channel's
    setting is its side; $FF means the channel is not present at all and its
    pan is left as InitValues put it. }
  for i := 1 to 32 do
    if S3M.Channels[i] <> $FF then
      if (S3M.Channels[i] and 8) = 0 then
        Song.ChannelPan[i] := $40
      else
        Song.ChannelPan[i] := $B0;

  Song.SequenceRepStart := 0;

  St.Read(Song.PatternSequence^, S3M.OrdNum);

  { 0c09 LOADS OrdNum FIRST and compares it against SongLen, so the header's
    field is the left operand: `if S3M.OrdNum > Song.SongLen`. Written the
    other way round the two loads swap and the jump inverts. }
  if S3M.OrdNum > Song.SongLen then
    S3M.OrdNum := Song.SongLen;

  Song.SequenceLength := S3M.OrdNum;

  for i := 1 to S3M.OrdNum do
    Inc(Song.PatternSequence^[i]);

  St.Read(InsPara, S3M.InsNum * 2);
  St.Read(PatPara, S3M.PatNum * 2);

  { 0c66..0c8a.  Trailing empty orders are dropped, but never the last one. }
  while (Song.SequenceLength > 1) and
        (Song.PatternSequence^[Song.SequenceLength] = 0) do
    Dec(Song.SequenceLength);

  for i := 1 to Song.SongStart - 1 do
    Song.PatternSequence^[i] := 0;

  ReadPatterns(Song, St, Buf, PatPara, S3M.PatNum, 1, $FFFF);
  if Song.Status > msOk then Exit;

  ReadInstruments(Song, St, Buf, InsPara, S3M.InsNum, 1, $FFFF);
  if Song.Status > msFileTooShort then Exit;

  if ChansUsed < Song.NumChannels then
    Song.NumChannels := ChansUsed
end;

end.
