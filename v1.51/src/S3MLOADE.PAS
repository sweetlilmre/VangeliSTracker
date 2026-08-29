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
    { **NAMED FROM docs/07-s3m-format.md**, which is the point of that document.
      Nothing here reads these four; the OFFSETS either side are measured, and the
      spec's field list fills the gap exactly. }
    EofMark     : Byte;                  { +$1c  $1A, so TYPE stops here      }
    FileType    : Byte;                  { +$1d  16 = an ST3 module           }
    Reserved1E  : Word;                  { +$1e                               }
    OrdNum      : Word;                  { +$20  read at 0b2e                 }
    InsNum      : Word;                  { +$22                               }
    PatNum      : Word;                  { +$24                               }
    Flags       : Word;                  { +$26  mostly legacy; see the doc    }
    CwtV        : Word;                  { +$28  created-with tracker/version  }

    { **+$2a IS THE SAMPLE SIGNEDNESS FIELD**, and naming it is worth more than the
      other five put together: 1 means signed samples, 2 unsigned. This loader reads
      every sample as ShortInt whatever it holds -- 1664:0b8a's `CBW` is what proved
      that -- so an unsigned module plays wrong and the field that says so is right
      here, unread. A gap you have named is a decision you can see. }
    Ffi         : Word;                  { +$2a  1 = signed, 2 = unsigned      }
    Magic       : array[1..4] of Char;   { +$2c  'SCRM'                       }
    { **$31 AND $32 CARRY 1.39b's NAMES, NOT THE SPECIFICATION'S.** The spec calls
      them "initial speed" and "initial tempo"; the release's own S3M loader calls
      them `Tempo` and `BPM`, and its STM loader assigns the matching pair. The
      consumers at the foot of this unit settle which vocabulary belongs here --
      `Song.InitialTempo := S3M.Tempo` and `Song.InitialBPM := S3M.BPM` read as one
      thought, where the spec's names made the same two lines cross over. }
    Volume      : Byte;                  { +$30                               }
    Tempo       : Byte;                  { +$31  ticks per row                 }
    BPM         : Byte;                  { +$32  the spec's "initial tempo"    }
    MasterVol   : Byte;                  { +$33  bit 7 is stereo              }
    UltraClick  : Byte;                  { +$34  GUS click-removal channels    }
    DefaultPan  : Byte;                  { +$35  252 = a pan table follows     }
    Reserved36  : array[1..8] of Byte;   { +$36                               }
    Special     : Word;                  { +$3e  custom data parapointer       }
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
    Reserved1D : Byte;                { +$1d                                 }
    Pack       : Byte;                { +$1e  1 = DP30ADPCM, unused by ST3.01 }
    { 1.39b DECLARES THIS ONE `Looped : BOOLEAN`, and that is a stronger claim
      than `Flags` -- it says what the byte is for rather than what shape it has.
      It is also what this loader does with it: the only reader is the loop test
      below. The spec lists other bits; nothing here looks at them. }
    Looped   : Boolean;               { +$1f                                 }
    C2Spd    : Word;                  { +$20                                 }
    { C2Spd IS FOUR BYTES IN THE FILE and two here, because 1664 reads a Word --
      the spec's own note is that ST3 only uses the lower sixteen bits. The upper
      half is the first of these. }
    C2SpdHi    : Word;                { +$22                                 }
    Reserved24 : LongInt;             { +$24                                 }

    { THE THREE `Int:` FIELDS ARE IN-MEMORY ONLY. ST3 uses them while a module is
      loaded and they are meaningless in a file, which is exactly why a loader can
      leave them unread -- but named, that is a fact about the format rather than a
      gap in the transcription. }
    IntGusPos  : Word;                { +$28  sample address in GUS RAM / 32  }
    IntSbFlags : Word;                { +$2a  SoundBlaster loop expansion     }
    IntLastUsed: LongInt;             { +$2c  last used position, SB only     }
    Name     : array[1..25] of Char;  { +$30  StrASCIIZ over $19 at 0775     }
    { The name is 28 bytes in the file and 1664 reads 25 of them, so three remain
      before the marker. }
    NameTail   : array[1..3] of Char; { +$49                                 }
    Magic      : array[1..4] of Char; { +$4c  'SCRS'                          }
  end;

  { The two paragraph-pointer tables, each read straight off the stream. }
  TS3MParaTable = array[1..256] of Word;

  { The recogniser's scratch, passed to both readers as an untyped `var`. }
  TS3MFlags = array[1..256] of Byte;

  { SIGNED, AND THE WIDENING INSTRUCTION SAYS SO. The comparison chain in the
    sign-detection loop widens each byte with `CBW` -- sign extension -- where
    a Byte element gives `XOR AH,AH`. Four sites, two bytes each. So the
    sample is read as ShortInt even though what the loop is deciding is
    whether it was WRITTEN signed. }
  PSampleBytes = ^TSampleBytes;
  TSampleBytes = array[0..65520] of ShortInt;

var

  { DS:$491a. Set to 1 by the recogniser and raised by ReadPatterns as it
    meets channels; the recogniser then narrows Song.NumChannels to it, so a
    module that declares sixteen channels and uses four reports four. }
  { **DS:$491a, AND IT IS DECLARED FIRST.** 1664:02ab reads it at $491a and 1664:0014
    adds into a LongInt at $491c/$491e, which is ModBase -- so the Word comes ahead of
    the LongInt in this unit's block. Declared the other way round it lands at $491e
    and ModBase at $491a, and eleven operands across three routines are wrong with
    nothing else to say why. }
  ChansUsed : Word;

  { DS:$491c. `SeekPara` adds a paragraph count to it, so it is the module's
    own origin -- the stream position the recogniser saw before it seeked past
    the header. A plain `var`: it is in the uninitialised half. }
  ModBase : LongInt;


  { THE SAME TWO-SUBSCRIPT VIEW STMLOADE LAYS OVER VTNotes' FLAT TABLE, and
    this unit needs it for the same reason: 0250 is
    `IMUL DI,AX,18 / ADD DI,DX` with the note term already doubled, which is
    per-term scaling and therefore two subscripts. The row index is
    `(Period shr 4) - 2` here, so S3M's octave numbering starts two above the
    table's. }
  NoteGrid : array[0..Octaves - 1, 0..Semis - 1] of Word absolute NotePeriods;

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
                       Num : Word; A : Boolean; B : Byte);
label
  Found, NextPattern;
var
  { $19b2 = 6,578, and it divides as 2 + 5000 + 1536 + 40. The packed buffer
    is declared FIRST after one Word, and the St.Read lands at -$138a with a
    5,000-byte cap, which is what places it. }
  { NOTHING ABOVE `Blk`. Its address is -$1388 and it is 5,000 bytes, so it
    reaches -$0001 and is the FIRST local. FullTrack follows at -$1988. }
  Blk       : array[1..5000] of Byte;
  FullTrack : TFullTrack;
  Pattern   : PPattern;
  Track     : PTrack;
  Note      : TFullNote;
  c         : Byte;
  k, j      : Word;
  n, t      : Word;
  Row       : Word;
  Len       : Word;
  { FOUR BYTES BETWEEN `Len` AND `MaxChan` THAT NOTHING READS. With the body
    already the original's length to within three bytes, the frame was the
    only difference left; size measured, names and types invented, as in the
    other two routines of this unit. }
  { SIX BYTES BELOW `Len` THAT NOTHING READS -- the original's -$19a6..-$19ab.
    Size measured from the frame with everything else placed; names invented. }
  Pad1, Pad2, Pad3 : Word;
  MaxChan   : Word;

begin
  t := 1;

  for n := 1 to Num do
    begin
      { THE PATTERN IS ONLY READ IF THE ORDER TABLE USES IT, and the search is
        a `for` with two labels, not a `while`. 0060 is the loop's own entry
        test against Song.SequenceLength -- which also covers a zero-length
        sequence, so no guard is needed and adding one costs seven bytes. The
        fall-through past the loop is the NOT-FOUND path; Turbo Pascal 6 has
        no `Break` and no `Continue`, so both exits are `goto`. }
      for k := 1 to Song.SequenceLength do
        if Song.PatternSequence^[k] = n then goto Found;
      goto NextPattern;

    Found:
        begin
          Pattern := PPattern(Song.GetPattern(n));
          if Pattern = nil then
            begin
              Song.Status := msOutOfMemory;
              Exit
            end;

          with Pattern^.Patt^ do
            begin
              NNotes := 64;
              NChans := Song.NumChannels;
              Tempo  := 0;
              BPM    := 0
            end;

          SeekPara(St, Para[n]);

          { The block's own length prefix, except where the caller says the
            format does not carry one. }
          { BOTH TAIL PARAMETERS ARE BYTE-SIZED: 0113 is `CMP BYTE PTR
            [BP+06],00` and 0119 is `CMP BYTE PTR [BP+04],1A`. And the bound is
            `<= $1A`, which emits JBE; `< $1B` is the same set of values and
            emits JB against a different immediate. }
          if A or (B > $1A) then
            St.Read(Len, 2)
          else
            Len := $138A;

          Dec(Len, 2);
          if Len > 5000 then
            Len := 5000;

          St.Read(Blk[1], Len);
          if St.Status <> stOk then
            begin
              Song.Status := msFileTooShort;
              Exit
            end;

          MaxChan := 1;

          { A `for` OVER THE CHANNELS, AND ITS ZERO CASE JUMPS TO NextPattern.
            018d is the loop's own entry test against Song.NumChannels and
            0193 is `JMP 06ba` -- so a channel count of zero skips the whole
            pattern, and no `if NumChannels <> 0` guard is written. The
            MaxChan exit cannot be a `Break` in TP6, so it is the same `goto`. }
          for j := 1 to Song.NumChannels do
            begin
                FillChar(FullTrack, SizeOf(FullTrack), 0);

                k   := 1;
                Row := 0;

                while (k <= Len) and (A or (Row < 64)) do
                  begin
                    c := Blk[k];
                    Inc(k);

                    if c = 0 then
                      Inc(Row)
                    else if (c and $1F) = j - 1 then
                      begin
                        FillChar(Note, SizeOf(Note), 0);

                        if (c and $20) <> 0 then
                          begin
                            Note.Period := Blk[k];
                            if not A then
                              Inc(Note.Period, $20);

                            if ((Note.Period and $F0) > $90) or
                               ((Note.Period and $F0) < $20) or
                               ((Note.Period and $0F) > $0B) then
                              begin
                                if Note.Period = $FE then
                                  Note.Volume := 1;
                                Note.Period := 0
                              end;

                            if Note.Period <> 0 then
                              begin
                                Note.Period :=
                                  NoteGrid[(Note.Period shr 4) - 2,
                                           Note.Period and $0F];
                                if ChansUsed <= (c and $1F) then
                                  ChansUsed := (c and $1F) + 1
                              end;

                            Note.Instrument := Blk[k + 1];
                            if Note.Instrument <> 0 then
                              TS3MFlags(Buf)[Note.Instrument] := 1;

                            Inc(k, 2)
                          end;

                        if (c and $40) <> 0 then
                          begin
                            Note.Volume := Blk[k] + 1;
                            if Note.Volume > $40 then
                              Note.Volume := $40;
                            Inc(k)
                          end;

                        if (c and $80) <> 0 then
                          begin
                            Note.Parameter := Blk[k + 1];
                            { A `case`, NOT AN if/else CHAIN, AND THE COMPARE OPERAND IS THE
                              TELL. The original tests `CMP AL,n` over and over -- the
                              effect byte held in a register and compared in place. An
                              if/else chain on a local emits `CMP BYTE PTR [BP-19a9],n`
                              every time, four bytes against two, at more than twenty sites.
                              Turbo Pascal keeps a case selector in AL when the labels are
                              sparse enough for a compare chain. }
                            case Blk[k] of
                              1  : begin
                                     Note.Command := mcSetTempo;
                                     if not A then
                                       Note.Parameter := Note.Parameter shr 4
                                   end;
                              2  : begin
                                     Note.Command := mcJumpPattern;
                                     { `Inc`, NOT `x := x + 1`. 035b is
                                       `INC BYTE PTR [BP-1991]` -- one
                                       instruction against a load, a widen, an
                                       increment and a store. The wiki's
                                       `inc-is-not-an-assignment`. }
                                     Inc(Note.Parameter)
                                   end;
                              3  : Note.Command := mcEndPattern;
                              { THE THREE SLIDE ARMS ALL TEST POSITIVELY AND PUT THE FINE CASE
                                FIRST. 0372 is `CMP ...,F0 / JBE` and 03be and 0400 are
                                `CMP ...,F0 / JB` -- so the conditions are `> $F0` and `>= $F0`,
                                with the coarse slide as the final `else`. The draft had each of
                                the three inverted: the same values, and the two blocks the other
                                way round in the segment. }
                              4  : if Note.Parameter > $F0 then
                                     begin
                                       Note.Command := mcVolFineDown;
                                       Note.Parameter := (Note.Parameter and $0F) + 1
                                     end
                                   else if ((Note.Parameter and $0F) = $0F) and
                                           (Note.Parameter > $0F) then
                                     begin
                                       Note.Command := mcVolFineUp;
                                       Note.Parameter := Note.Parameter shr 4
                                     end
                                   else
                                     Note.Command := mcVolSlide;
                              5  : if Note.Parameter >= $F0 then
                                     begin
                                       Note.Command := mcFinePortaDn;
                                       Note.Parameter := (Note.Parameter and $0F) + 1
                                     end
                                   else if Note.Parameter >= $E0 then
                                     begin
                                       Note.Command := mcFinePortaDn;
                                       { `+ 2` COMPILES TO TWO `INC AX`, not `ADD AX,2` -- Borland
                                         emits one operation per operator and turns 1 and 2 into
                                         INC and DEC. 03ed is the pair. }
                                       Note.Parameter := ((Note.Parameter and $0F) + 2) shr 2
                                     end
                                   else
                                     Note.Command := mcTPortDown;
                              6  : if Note.Parameter >= $F0 then
                                     begin
                                       Note.Command := mcFinePortaUp;
                                       Note.Parameter := Note.Parameter and $0F
                                     end
                                   else if Note.Parameter >= $E0 then
                                     begin
                                       Note.Command := mcFinePortaUp;
                                       Note.Parameter := ((Note.Parameter and $0F) + 2) shr 2
                                     end
                                   else
                                     Note.Command := mcTPortUp;
                              7  : begin
                                     Note.Command := mcNPortamento;
                                     if Note.Parameter <> 0 then
                                       Inc(Note.Parameter)
                                   end;
                              8  : Note.Command := mcVibrato;
                              10 : Note.Command := mcArpeggio;
                              $0B : Note.Command := mcVib_VSlide;
                              $0C : Note.Command := mcT_VSlide;
                              $0F : Note.Command := mcSampleOffs;
                              { A SELF-ASSIGNMENT, AND IT IS IN THE BINARY.
                                049f is `MOV AL,[BP-1991] / MOV [BP-1991],AL`
                                -- Note.Parameter loaded and stored straight
                                back, eight bytes that compute nothing. Turbo
                                Pascal does not elide it. Transcribed because
                                the rule is to write what the code does. }
                              $11 : begin
                                      Note.Command := mcS3mRetrigNote;
                                      Note.Parameter := Note.Parameter
                                    end;
                              $12 : Note.Command := mcTremolo;
                              $13 : begin
                                      case Note.Parameter shr 4 of
                                        0  : Note.Command := mcSetFilter;
                                        1  : Note.Command := mcGlissCtrl;
                                        2  : Note.Command := mcFineTune;
                                        3  : Note.Command := mcVibCtrl;
                                        4  : Note.Command := mcTremCtrl;
                                        8  : Note.Command := mcNPI2;
                                        $B : Note.Command := mcJumpLoop;
                                        $C : Note.Command := mcNoteCut;
                                        $D : Note.Command := mcNoteDelay;
                                        $E : Note.Command := mcPattDelay;
                                        $F : Note.Command := mcFunkIt;
                                      else
                                        Note.Command := TModCommand((Note.Parameter shr 4) + $50)
                                      end;
                                      Note.Parameter := Note.Parameter and $0F
                                    end;
                              $14 : if Note.Parameter > $30 then
                                      Note.Command := mcSetTempo
                                    else
                                      Note.Command := mcNone;
                              $18 : Note.Command := mcNPI1;
                            else
                              Note.Command := TModCommand(Blk[k] + $24)
                            end;


                            if (Note.Command = mcEndPattern) or
                               (Note.Command = mcJumpPattern) then
                              { `NNotes > Row + 1`, NOT `Row + 1 < NNotes`.
                                Borland evaluates the RIGHT operand first, and
                                05ab computes Row + 1 into DX before loading
                                NNotes -- so Row + 1 is on the right. }
                              if Pattern^.Patt^.NNotes > Row + 1 then
                                Pattern^.Patt^.NNotes := Row + 1;

                            Inc(k, 2)
                          end;

                        FullTrack[Row] := Note
                      end
                    else
                      begin
                        if (j = 1) and (MaxChan < (c and $1F) + 1) then
                          MaxChan := (c and $1F) + 1;
                        if (c and $20) <> 0 then
                          Inc(k, 2);
                        if (c and $40) <> 0 then
                          Inc(k);
                        if (c and $80) <> 0 then
                          Inc(k, 2)
                      end
                  end;

                Track := Song.GetTrack(t);
                if Track = nil then
                  begin
                    Song.Status := msOutOfMemory;
                    Exit
                  end;

                Track^.SetFullTrack(FullTrack);

                Pattern^.Patt^.Channels[j] := t;

                Inc(t);

                { `j > MaxChan`, and the loads say which is which: 06a3
                  reads j and compares it against MaxChan. }
                if j > MaxChan then goto NextPattern
            end
        end;
    NextPattern:
    end
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
                          Num : Word; A : Boolean; B : Word);
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
              { THE WORK COMES FIRST. 07f7 is `JE` to the zeroing block, and
                Turbo Pascal jumps if FALSE, so the tested condition is the
                positive one. Written the other way the two blocks swap places --
                eighteen bytes moved, nothing computed differently. A `Boolean`
                tested bare and a `Byte` tested `<> 0` compile identically. }
              if Hdr.Looped then
                begin
                  { THE SECOND STATEMENT REUSES THE FIRST'S RESULT. 0908
                    subtracts the pair at -$18, which is Instrument.Reps just
                    assigned, not the header's LoopBeg at -$5c. Same value,
                    a different load. }
                  Instrument.Reps := Hdr.LoopBeg;
                  Instrument.Repl := Hdr.LoopEnd - Instrument.Reps
                end
              else
                begin
                  Instrument.Reps := 0;
                  Instrument.Repl := 0
                end;

              Instrument.Vol  := Hdr.Vol;
              Instrument.DAdj := Hdr.C2Spd;

              { A IS A Boolean, AND THE COMPARE WIDTH SAYS SO: 07fe is
                `CMP BYTE PTR [BP+06],00`, where a Word parameter gives
                `CMP WORD PTR`. The value still occupies two bytes of the
                parameter block -- Turbo Pascal pushes a byte-sized value
                parameter as a word -- so the RET $16 is unchanged.

                $2100 is the numerator STMLOADE uses; $20ab is the other, and
                the TRUE arm takes it. }
              if A then
                Instrument.NAdj := $20AB
              else
                Instrument.NAdj := $2100;

              if Instrument.Repl > Instrument.Len then
                Instrument.Repl := Instrument.Len;
              if Instrument.Reps + Instrument.Repl > Instrument.Len then
                Instrument.Repl := Instrument.Len - Instrument.Reps;

              { THE RECORD'S OWN FIELD, TESTED AND CLAMPED. 0858 is
                `CMP BYTE PTR [BP-10],3F / JBE / MOV BYTE PTR [BP-10],3F` --
                one displacement, read and written, and -$10 is
                Instrument.Vol (record offset 12 against a record at -$1c).

                MODLOADE's ProcessInstruments does the odd thing here and tests
                the HEADER's copy before clamping the record's; this routine
                does not, and carrying that habit across cost two loads. Read
                each unit, do not carry the sibling's quirk. }
              if Instrument.Vol > $3F then
                Instrument.Vol := $3F;

              SeekPara(St, Hdr.MemSeg);

              { $FFF0 WITH `<=`, as in STMLOADE's LoadSamples: `CMP ...,F0 /
                JA` against `CMP ...,F1 / JAE`. The same 64K read boundary and
                the same two-byte difference. }
              if Instrument.Len <= $FFF0 then
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

                  { NO `Len <> 1` GUARD. `for j := 1 to Len - 1` already has
                    its own entry test, and with Len = 1 the limit is zero and
                    the loop is skipped. The explicit test is fifteen bytes of
                    LongInt comparison the original does not have -- the third
                    time this exact redundancy has appeared in these two
                    units. }
                    for j := 1 to Instrument.Len - 1 do
                      if ((PSampleBytes(Instrument.Data)^[j - 1] xor
                           PSampleBytes(Instrument.Data)^[j]) and $80) <> 0 then
                        { THE CAST IS BACK, AND `OR AL,AL` IS WHY. 0930 tests
                          only the LOW byte of the difference; without the cast
                          the subtraction stays an Integer and the test is
                          `OR AX,AX`. One byte per site, four sites. }
                        if (ShortInt(PSampleBytes(Instrument.Data)^[j] - $40) < 0) and
                           (ShortInt(PSampleBytes(Instrument.Data)^[j - 1] - $40) < 0) then
                          Inc(Falls)
                        else if (ShortInt(PSampleBytes(Instrument.Data)^[j] - $40) >= 0) and
                                (ShortInt(PSampleBytes(Instrument.Data)^[j - 1] - $40) >= 0) then
                          Inc(Rises);

                  { `Rises > Falls`, AND THE OPERAND ORDER IS IN THE LOADS.
                    0992 loads the pair at -$7c (Rises) into AX:DX and compares
                    it against the pair at -$78 (Falls), so Rises is the LEFT
                    operand. `Falls < Rises` is the same condition and swaps
                    which pair is loaded. }
                  if Rises > Falls then
                    for j := 0 to Instrument.Len - 1 do
                      { `Inc`, NOT `Dec`. 09c4 is `ADD BYTE PTR ES:[DI],80`
                        -- a byte-wide ADD. `Dec(x, $80)` promotes, because 128
                        does not fit a ShortInt, and emits a word SUB. On a
                        signed byte the two produce the same value; they are
                        not the same instruction. }
                      Inc(PSampleBytes(Instrument.Data)^[j], $80)
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

  { **TWO MORE FOUR-BYTE CONSTANTS, AND NOTHING REFERENCES EITHER.** DGROUP holds
    `SCRM SCRS SCRM` at $0468, $046c and $0470 -- twelve bytes where this routine
    used four -- and it was the LAYOUT that found them, not a call site: this unit's
    code is byte-exact without them, so the original's are unreferenced too. The same
    shape as PlayMod's dead `Pannings` table, from the opposite direction: there a
    declaration outlived its readers, here two declarations never had any.

    THE FIRST OF THE TWO IS THE SAMPLE MAGIC, and this file's own address map named
    it before it was declared -- line 53 records `'SCRS'  DS:$046c`. Scream Tracker 3
    stamps every instrument header with it at +$4c, and this loader reads that byte
    range as `Filler3` and never checks it. Declared and unchecked is what the
    original is; transcribed as found.

    THE SECOND IS 'SCRM' AGAIN. Turbo Pascal emits one typed constant per
    declaration, so the author wrote it twice. }
  S3MInsString  : array[1..4] of Char = 'SCRS';   { DS:$046c  never read        }
  S3MIdString2  : array[1..4] of Char = 'SCRM';   { DS:$0470  never read        }
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

  ReadPatterns(Song, St, Buf, PatPara, S3M.PatNum, True, $FF);
  if Song.Status > msOk then Exit;

  ReadInstruments(Song, St, Buf, InsPara, S3M.InsNum, True, $FFFF);
  if Song.Status > msFileTooShort then Exit;

  if ChansUsed < Song.NumChannels then
    Song.NumChannels := ChansUsed
end;

end.
