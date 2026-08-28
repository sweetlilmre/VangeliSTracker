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

    0000  no ENTER    RET  $06   SeekPara            St, Para
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

  { The 0x50-byte instrument header, read one at a time into the frame. Every
    offset is cited at the instruction that reads it; the sizes follow from
    the gaps between them and from the two StrASCIIZ lengths.

      1 + 13 + 2 + 4 + 4 + 4 + 1 + 2 + 1 + 2 + 14 + 25 + 7  =  80 = $50 }
  TS3MInstrument = record
    Typ      : Byte;                  { +$00  tested against 1 at 0770       }
    DosName  : array[1..13] of Char;  { +$01  StrASCIIZ over $0d at 0757     }
    MemSeg   : Word;                  { +$0e  the sample's own paragraph     }
    Length   : LongInt;               { +$10                                 }
    LoopBeg  : LongInt;               { +$14                                 }
    LoopEnd  : LongInt;               { +$18                                 }
    Vol      : Byte;                  { +$1c                                 }
    Filler1  : array[1..2] of Byte;   { +$1d                                 }
    Flags    : Byte;                  { +$1f  zero means no loop             }
    C2Spd    : Word;                  { +$20                                 }
    Filler2  : array[1..14] of Byte;  { +$22                                 }
    Name     : array[1..25] of Char;  { +$30  StrASCIIZ over $19 at 0775     }
    Filler3  : array[1..7] of Byte;   { +$49  and the 'SCRS' marker          }
  end;

  { The two paragraph-pointer tables, each read straight off the stream. }
  TS3MParaTable = array[1..256] of Word;

  { The recogniser's scratch, passed to both readers as an untyped `var`. }
  TS3MFlags = array[1..256] of Byte;

  PSampleBytes = ^TSampleBytes;
  TSampleBytes = array[0..65520] of Byte;

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
procedure SeekPara(var St : TStream; Para : Word);
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
var
  { $17e is 126 bytes of locals and one 256-byte String temporary, and the
    126 divide exactly: 2 + 28 + 4 + 80 + 2 + 2 + 4 + 4. The header record's
    own field offsets place it -- Length is read at -$62 and the record starts
    at -$72, which is +$10, the offset the file format uses. }
  Instrument : TInstrumentRec;    { -$1e                                    }
  Instr      : PInstrument;       { -$22                                    }
  Hdr        : TS3MInstrument;    { -$72                                    }
  i          : Word;              { -$74                                    }
  j          : Word;              { -$76                                    }
  Falls      : LongInt;           { -$7a  see the sign detection below      }
  Rises      : LongInt;           { -$7e                                    }
begin
  { NO ZERO TEST AT ALL. 06cf is `MOV AX,[BP+08] / MOV [BP-7e],AX /
    MOV AX,1 / CMP AX,[BP-7e] / JBE / JMP end` -- the loop's own limit
    temporary and its own entry test, which already skips a zero count. Both
    an `if Num <> 0 then` wrapper and an `if Num = 0 then Exit` guard emit that
    comparison a SECOND time. Same defect as ProcessPatterns in STMLOADE, and
    the same tell: a decompiler renders the loop's entry test as a guard. }
  for i := 1 to Num do
    begin
      FillChar(Instrument, SizeOf(Instrument), 0);

      Instr := PInstrument(Song.GetInstrument(i));
      if Instr = nil then
        begin
          Song.Status := msOutOfMemory;
          Exit
        end;

      SeekPara(St, Para[i]);
      St.Read(Hdr, SizeOf(Hdr));

      { THE DOS FILENAME IS THE FALLBACK, NOT THE OTHER WAY ROUND. 0771 tests
        the FIRST character of the long name and takes the short one when it
        is NUL. }
      if Hdr.Name[1] <> #0 then
        Instr^.SetName(StrASCIIZ(Hdr.Name, 25))
      else
        Instr^.SetName(StrASCIIZ(Hdr.DosName, 13));

      if Hdr.Typ = 1 then
        begin
          { The recogniser's scratch says which instruments a pattern actually
            referenced; one nobody plays keeps a zero length and is dropped. }
          if TS3MFlags(Buf)[i] <> 0 then
            Instrument.Len := Hdr.Length;

          { `> 0` WITH THE WORK FIRST, as in STMLOADE's ProcessInstruments.
            The original's three-branch LongInt compare -- high word signed,
            low word unsigned -- is the shape of `> 0`; `<= 0` inverts it and
            swaps the two blocks in the segment. }
          if Instrument.Len > 0 then
            begin
              if Hdr.Flags = 0 then
                begin
                  Instrument.Reps := 0;
                  Instrument.Repl := 0
                end
              else
                begin
                  Instrument.Reps := Hdr.LoopBeg;
                  Instrument.Repl := Hdr.LoopEnd - Hdr.LoopBeg
                end;

              Instrument.Vol  := Hdr.Vol;
              Instrument.DAdj := Hdr.C2Spd;

              { TWO NUMERATORS, and the parameter chooses. $2100 is the same
                constant STMLOADE uses; $20ab is 21/32 of a semitone below it. }
              if A = 0 then
                Instrument.NAdj := $2100
              else
                Instrument.NAdj := $20AB;

              if Instrument.Repl > Instrument.Len then
                Instrument.Repl := Instrument.Len;
              if Instrument.Reps + Instrument.Repl > Instrument.Len then
                Instrument.Repl := Instrument.Len - Instrument.Reps;

              { The HEADER's field is tested and the RECORD's is clamped --
                0a20 reads -$56 and writes -$12, which are different bytes. }
              if Hdr.Vol > $3F then
                Instrument.Vol := $3F;

              SeekPara(St, Hdr.MemSeg);

              if Instrument.Len < $FFF1 then
                begin
                  FullHeap.HGetMem(Pointer(Instrument.Data), Instrument.Len);
                  if Instrument.Data = nil then
                    begin
                      Song.Status := msOutOfMemory;
                      Exit
                    end;
                  St.Read(Instrument.Data^, Instrument.Len);
                  if St.Status <> stOk then
                    begin
                      Song.Status := msFileDamaged;
                      Exit
                    end;

                  { ------------------------------------------------------
                    SIGNED OR UNSIGNED, DECIDED BY COUNTING. An S3M sample
                    may be stored either way and the header does not say
                    which, so the loader looks at the data: for every pair of
                    adjacent bytes whose top bits DIFFER, it asks whether both
                    are far from the midpoint on the same side. Reading the
                    run as unsigned makes a quiet signal cross $80 constantly;
                    reading it as signed makes it cross zero. The tally that
                    wins says which convention the file used, and $80 is
                    subtracted from every byte when it was the other one.
                    ------------------------------------------------------ }
                  Falls := 0;
                  Rises := 0;

                  if Instrument.Len <> 1 then
                    for j := 1 to Instrument.Len - 1 do
                      if ((PSampleBytes(Instrument.Data)^[j - 1] xor PSampleBytes(Instrument.Data)^[j]) and $80) <> 0 then
                        if (ShortInt(PSampleBytes(Instrument.Data)^[j] - $40) < 0) and
                           (ShortInt(PSampleBytes(Instrument.Data)^[j - 1] - $40) < 0) then
                          Inc(Falls)
                        else if (ShortInt(PSampleBytes(Instrument.Data)^[j] - $40) >= 0) and
                                (ShortInt(PSampleBytes(Instrument.Data)^[j - 1] - $40) >= 0) then
                          Inc(Rises);

                  if Falls < Rises then
                    for j := 0 to Instrument.Len - 1 do
                      Dec(PSampleBytes(Instrument.Data)^[j], $80)
                end
              else
                begin
                  FullHeap.HGetMem(Pointer(Instrument.Data), $FFF0);
                  FullHeap.HGetMem(Pointer(Instrument.Xtra),
                                   Instrument.Len - $FFF0);
                  if (Instrument.Data = nil) or (Instrument.Xtra = nil) then
                    begin
                      Song.Status := msOutOfMemory;
                      Exit
                    end;
                  St.Read(Instrument.Data^, $FFF0);
                  St.Read(Instrument.Xtra^, Instrument.Len - $FFF0);
                  if St.Status <> stOk then
                    begin
                      Song.Status := msFileDamaged;
                      Exit
                    end
                end;

              Instr^.Change(@Instrument)
            end
          else
            Instr^.Change(nil)
        end
    end
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
