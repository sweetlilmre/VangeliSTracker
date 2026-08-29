{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).
  NOT Asphyxia code. See v1.51/docs/CONTINUATION.md.

  Segment 15d0 -- the Scream Tracker 2 (.STM) loader. 2,368 bytes, of which
  2,365 are the four routines. NEW IN v1.51; v1.31b has no such unit.

  THERE IS NO RELEASE SOURCE FOR THIS UNIT. The 1.39b release is January 1994
  and DemoVT 1.51 is April; S3M and STM support arrive in between, so every
  other unit in this tree could be checked against LIB/*.PAS and this one
  cannot. Nothing here is a release name. What IS available is `MODLOADE.PAS`,
  which is byte-exact and which this unit shadows almost statement for
  statement -- so the names are ITS names, and where the two units do the same
  thing they are written the same way on purpose.

  HOW IT WAS FOUND. `segpair.py --pair` reports 15d0 as a segment of v1.51 that
  nothing in v1.31b pairs with; the SongLoaders table at DS:$0430 names
  15d0:0764 as entry [3] of four, where v1.31b's table at DS:$03c4 has two.
  Ghidra's decompiler read the four routines.

  THE ROUTINE MAP, in address order -- which is SOURCE order, because Turbo
  Pascal lays a unit's routines out as they are written. The return forms are
  the signature and are measured:

    0000  ENTER $a2a  RET  $0a   ProcessPatterns     Song, St, Num
    03db  ENTER $12c  RET  $0c   ProcessInstruments  Song, St, Stm
    0581  ENTER $28   RET  $08   LoadSamples         Song, St
    0764  ENTER $206  RETF $0c   LoadSTMFileFormat   Song, St, Header

  Only the last is far: the other three are near, so they are local to the
  implementation and nothing outside can call them. That matches MODLOADE
  exactly, and it is why the interface publishes one procedure.

  $a2a IS THE FRAME THAT NAMES ProcessPatterns' LOCALS: 1024 for one STM
  pattern (64 rows x 4 channels x 4 bytes), 1536 for a TFullTrack, 20 for the
  note scratch, and 22 of counters. MODLOADE's equivalent is $e20 with 2048
  for the pattern, because a MOD may have eight channels and an STM has four.

  WHAT THE FILE FORMAT IS. Scream Tracker 2, and the offsets are read off the
  code rather than taken from a specification:

    +$000  20 bytes  song name
    +$014   8 bytes  '!Scream!'          the magic, DS:$0460
    +$020   1 byte   initial tempo, in the HIGH nibble
    +$021   1 byte   pattern count
    +$022   1 byte   global volume
    +$030  31 x 32   instrument headers  -- instrument i at +$010 + i*$20
    +$410  128       the order table
    +$490            pattern data begins  -- 0764 seeks here

  ADDRESS MAP
    ProcessPatterns    15d0:0000     '!Scream!'        DS:$0460, 8 raw bytes
    ProcessInstruments 15d0:03db     the period table  DS:$04bc, VTNotes'
    LoadSamples        15d0:0581
    LoadSTMFileFormat  15d0:0764
  =========================================================================== }

unit StmLoader;

interface

uses
  Objects, SongUnit;

procedure LoadSTMFileFormat(var Song : TSong; var St : TStream;
                            var Header : TSongHeader);

implementation

uses
  SongElements, Heaps, AsciiZ, VTNotes;

var
  { A TWO-SUBSCRIPT VIEW OF VTNotes' FLAT TABLE, AND IT IS MEASURED RATHER THAN
    convenient. 0343 is `IMUL DI,AX,18` with the note term already doubled by
    `SHL AX,1` -- the element scale distributed across the two TERMS of the
    index. A single-subscript access scales the SUM instead and emits
    `IMUL AX,AX,0C / ADD AX,DX / MOV DI,AX / SHL DI,1`, two bytes longer.

    probe/IDXPROBE.PAS settles it: five candidate forms compiled with TP6, and
    only the two-subscript one reproduces the original's bytes. The other four
    -- both operand orders, an explicit *1 on the note term, and the index
    built in a variable first -- all emit the scale-the-sum shape.

    IT CANNOT BE VTNotes' OWN DECLARATION. MODCOMMANDS indexes NotePeriods with
    a SINGLE subscript and is byte-exact in v1.31b, which a two-dimensional
    declaration would not compile against at all. So the table is flat where it
    is declared and this unit lays a grid over it. `absolute` costs no data and
    no code: the base is the same DS:$4bc either way. }
  NoteGrid : array[0..Octaves - 1, 0..Semis - 1] of Word absolute NotePeriods;

{ ---------------------------------------------------------------------------
  THE FILE FORMAT RECORDS.

  Read off the code, not off a specification -- the same discipline
  `MODLOADE.PAS` records, and here there is no release source to fall back on
  at all. Each offset below is cited at the instruction that proves it.

    TStmFileInstrument   14 + 2 + 2 + 2 + 2 + 1 + 1 + 2 + 4 + 2   =  32
    instrument i at      $10 + i * $20, so instrument 1 at $30
    the order table at   $410 = $30 + 31*32 + 16

  THE NAME IS FOURTEEN CHARACTERS, not the twelve a Scream Tracker 2 header
  actually carries. 15d0:03db reads it as `StrASCIIZ(..., $0e)`, and $0e is 14:
  the author declared the field over the two bytes that follow the name as
  well. Transcribing what the code does rather than what the format says is the
  standing rule, and it costs nothing here because StrASCIIZ stops at the NUL.
  --------------------------------------------------------------------------- }

type
  TStmFileInstrument = record
    Name      : array[1..14] of Char;  { StrASCIIZ over 14 at 15d0:0416      }
    { TWO BYTES, AND WITHOUT THEM THE RECORD IS 30 AND EVERYTHING DOWNSTREAM
      MOVES. `Len` is read at record offset $10, which is 16, and the name runs
      to 13 -- so 14 and 15 are unaccounted for. Thirty bytes puts the order
      table at $30 + 31*30 = $3d2, and that is exactly the immediate our build
      emitted where the original has $410. }
    { The format's in-memory sample pointer, meaningless in a file -- which is why
      it can go unread and why the record is 32 bytes and not 30. }
    IntPos    : Word;                  { +$0e                                }
    Len       : Word;                  { +$10  read at 15d0:0448            }
    LoopStart : Word;                  { +$12  read at 15d0:0465            }
    LoopEnd   : Word;                  { +$14  read at 15d0:0472            }
    Vol       : Byte;                  { +$16  read at 15d0:04c1            }
    Reserved17: Byte;                  { +$17                                }
    C2Spd     : Word;                  { +$18  read at 15d0:04d3            }
    Reserved1A: array[1..4] of Byte;   { +$1a  in-memory only                }
    ParaLen   : Word;                  { +$1e                                }
  end;

  { One note as the file stores it. Four bytes, and the packing is what the
    decoder spends most of its length unpicking. }
  TStmFileNote = record
    b1,                                { note: high nibble octave, low note   }
    b2,                                { instrument in 7..3, volume low in 2..0 }
    b3,                                { volume high in 7..4, command in 3..0 }
    b4 : Byte;                         { parameter                            }
  end;

  { A pattern as the file stores it: 64 rows of four channels. 1,024 bytes,
    which is the `St.Read` length at 15d0:00b2 and the largest local in
    ProcessPatterns' $a2a frame. }
  { BASE ONE IN BOTH SUBSCRIPTS, and 15d0:011e is the whole argument:
    `LEA DI,[BP+DI-0414]` with DI = i*16 + j*4. The buffer itself is at -$400,
    so the folded constant is -$400 - 1*16 - 1*4 -- one row and one channel
    below the base, which is what a base-1 array of base-1 rows folds to. A
    base-0 outer bound would give -$404. See the wiki's
    `subscript-fold-names-the-bounds`. }
  TStmFilePattern = array[1..64] of array[1..4] of TStmFileNote;

  TStmFile = record
    Name        : array[1..20] of Char;
    Magic       : array[1..8] of Char;  { +$14  '!Scream!'                    }
    { **NAMED FROM THE FORMAT'S OWN LAYOUT, NOT FROM A SPIKE.** docs/07-s3m-format.md
      exists for S3M and has no counterpart for STM, so these three carry less weight
      than S3MLOADE's equivalents: they are the widely-published Scream Tracker 2
      header and 1.39b's own record agrees on their EXTENT (`fill1 : LONGINT`) while
      naming none of them. Offsets measured, names sourced weakly -- said here rather
      than left to be assumed. }
    EofMark     : Byte;                 { +$1c  $1A                           }
    FileType    : Byte;                 { +$1d  2 = a module                  }
    VerMajor    : Byte;                 { +$1e                                }
    VerMinor    : Byte;                 { +$1f                                }
    Tempo       : Byte;                 { +$20  the HIGH nibble is the tempo  }
    NumPatterns : Byte;                 { +$21                                }
    Volume      : Byte;                 { +$22                                }
    Reserved23  : array[1..13] of Byte; { +$23  reserved by the format        }
    Instruments : array[1..31] of TStmFileInstrument;   { +$30                }
    { BASE ONE, AND THE DISPLACEMENT IS WHAT SAYS SO. The scan reads the table
      with the immediate $40f where the table itself begins at $410. Turbo
      Pascal folds an array's low bound into the address, so a base-1 array
      indexed `[i]` addresses base-1+i -- and base-0 indexed `[i-1]` computes
      base+(i-1) and emits $410. One byte, and it names the bounds; see the
      wiki's `subscript-fold-names-the-bounds`. }
    PatternList : array[1..128] of Byte;                { +$410               }
  end;

{ ---------------------------------------------------------------------------
  15d0:0000..03da.  ENTER $a2a, RET $0a.

  MODLOADE's ProcessPatterns with the channel count fixed at four, so none of
  its Patt4/Patt5/Patt6/Patt7 repacking is here -- an STM pattern is already
  four channels wide and is read straight into the array.

  THE COMMAND MAP IS THE WHOLE POINT OF THE ROUTINE. Scream Tracker numbers its
  effects A..Z from 1; the player's own `TModCommand` is the ProTracker set
  shifted up by one, and the nine that correspond are translated by name. What
  does NOT correspond is passed through as `Ord(mcLast) + code`, which is the
  `+ $24` at 15d0:0288 -- an ordinal past the end of the enumeration, which
  compiles only because the tree builds with range checking off.
  --------------------------------------------------------------------------- }
procedure ProcessPatterns(var Song : TSong; var St : TStream; Num : Word);
var
  Patt      : TStmFilePattern;
  FullTrack : TFullTrack;
  Pattern   : PPattern;
  Track     : PTrack;
  { TWO BYTES BETWEEN `Track` AND `i` THAT NOTHING READS. Track is the far
    pointer at -$a08, and the row counter is at -$a0c -- so -$a0a is a
    declared local no instruction in the routine touches. Size measured, name
    and type invented, exactly as in ProcessInstruments. }
  Unused    : Word;
  i, j      : Word;
  n, t      : Word;
  { THREE WORDS NOTHING READS, AND THEY ARE PINNED RATHER THAN GUESSED: `w`
    below has to land at -$a1a, which is four slots under `t` at -$a12, so
    exactly six bytes sit between them. }
  Pad1, Pad2, Pad3 : Word;
  w         : Word;
  { FOUR MORE BYTES, and they are the last thing in the frame: with the body
    already the original's length, every remaining difference was a compiler
    temporary sitting four bytes high. MODLOADE's ProcessPatterns ends with a
    LongInt, so this one is written the same way. Size measured, type carried. }
  l         : LongInt;
begin
  t := 1;
  for n := 1 to Num do
    begin
      { The cast is the duplicate-type debt SONGUNIT.PAS documents, not a
        conversion -- see the identical note in MODLOADE.PAS. }
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

      St.Read(Patt, 64*4*4);

      if St.Status <> stOk then
        begin
          Song.Status := msFileTooShort;
          Exit
        end;

      for j := 1 to Song.NumChannels do
        begin
          FillChar(FullTrack, SizeOf(FullTrack), 0);

          for i := 1 to 64 do
            { `FullTrack[i - 1]`, NOT `FullTrack[i]`. 012a computes
              `(i-1)*6` at RUNTIME and adds it to -$a00, which is the buffer's
              own base -- so the row subscript is one below the counter.
              TFullTrack is array[0..255] and the stride is 6, which Turbo
              Pascal cannot fold into the displacement the way it folds a
              power of two, so the decrement is visible rather than absorbed. }
            with FullTrack[i - 1], Patt[i][j] do
              begin
                { 012a..0147 -- SIX BYTES CLEARED PER NOTE, and the whole-array
                  FillChar before the channel loop does NOT make it redundant
                  in the emitted code. The draft had only the outer one and was
                  thirty bytes short here. Every field below is written on some
                  path and left alone on another, so the clear is what makes an
                  untouched field zero rather than the previous row's value. }
                FillChar(FullTrack[i - 1], SizeOf(TFullNote), 0);

                if b1 <> $FF then
                  begin
                    Period := b1;
                    { THREE CLAUSES, AND THE MIDDLE ONE IS DEAD CODE THE
                      COMPILER STILL EMITS. 017b is `AND AX,00F0 / OR AX,AX /
                      JB` -- and `OR AX,AX` clears the carry flag, so the JB is
                      never taken. It is `< $00` on a Word: a range test whose
                      low bound happens to be zero, written the symmetric way.
                      Turbo Pascal does not fold it away, so leaving it out is
                      fifteen bytes short. Transcribe what the code does. }
                    if ((Period and $F0) > $70) or
                       ((Period and $F0) < $00) or
                       ((Period and $0F) > $0B) then
                      Period := 0;
                    Instrument := b2 shr 3
                  end;

                Volume := ((b3 and $F0) shr 1) + (b2 and 7);
                if Volume > $40 then
                  Volume := 0
                else if Volume < $40 then
                  Inc(Volume);

                Parameter := b4;

                case b3 and $0F of
                  0  : Command := mcNone;
                  1  : begin
                         Command   := mcSetTempo;
                         Parameter := b4 shr 4
                       end;
                  2  : begin
                         Command := mcJumpPattern;
                         Inc(Parameter)
                       end;
                  3  : Command := mcEndPattern;
                  4  : Command := mcVolSlide;
                  5  : Command := mcTPortDown;
                  6  : Command := mcTPortUp;
                  7  : Command := mcNPortamento;
                  8  : Command := mcVibrato;
                  10 : Command := mcArpeggio;
                else
                  Command := TModCommand(Ord(mcLast) + (b3 and $0F))
                end;

                if ((Command = mcEndPattern) or (Command = mcJumpPattern)) and
                   (Pattern^.Patt^.NNotes > i) then
                  Pattern^.Patt^.NNotes := i;

                { NotePeriods IS FLAT, and the binary's own arithmetic says
                  so: `(octave)*$18 + (note)*2` is a byte offset, and $18 is
                  twelve words. So the index is octave*12 + note into VTNotes'
                  one-dimensional table, not a two-subscript lookup.

                  It can run off the end. `Notes` is 84 -- seven octaves -- and
                  the guard above admits octave 7, whose top semitone indexes
                  95. The original does not bound this either; the tree builds
                  with range checking off, so transcribing the arithmetic is
                  transcribing the behaviour. }
                if Period <> 0 then
                  begin
                    w := NoteGrid[Period shr 4, Period and $0F];
                    Period := w
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

          Inc(t)
        end
    end
end;

{ ---------------------------------------------------------------------------
  15d0:03db..0580.  ENTER $12c, RET $0c.

  `St` IS DECLARED AND NEVER READ. The routine is `RET $0c` -- three far
  pointers -- and touches only the first and the third. MODLOADE's
  ProcessInstruments takes the same three and does use its stream, because a
  MOD stores each sample straight after the headers; an STM stores every sample
  after every pattern, which is why LoadSamples below exists at all and why
  this routine has nothing to read.

  NAdj IS A CONSTANT HERE. MODLOADE looks its numerator up in a sixteen-entry
  finetune table; STM has no finetune, so the numerator is $2100 for every
  instrument and the C2 rate carries the pitch in DAdj.
  --------------------------------------------------------------------------- }
procedure ProcessInstruments(var Song : TSong; var St : TStream;
                             var Stm : TStmFile);
var
  { THE FIRST THREE ARE READ; THE LAST FOUR ARE A SIZE AND NOTHING MORE.
    03df puts the counter at -$22, 03e9 FillChars 28 bytes at -$1c, and 0404
    stores a far pointer at -$20 -- so the record is declared first, the
    pointer second and the counter third, which is the order below.

    Ten further bytes sit at -$2c..-$23 and NO INSTRUCTION IN THE ROUTINE
    TOUCHES THEM. Turbo Pascal does not drop an unused local, so ten bytes of
    declaration are there; their names, types and division are inventions.
    They are written as MODLOADE.PAS's ProcessInstruments declares its
    leftovers, because this unit shadows that one throughout -- `Acc` is a
    ShortInt there and the odd byte is padded to even, which is what makes the
    total 10 rather than 9. Any other ten bytes compile the same.

    What makes the guess safe to act on is that it is the ONLY thing left: with
    the body already agreeing byte for byte over 422 bytes, the frame is the
    last difference, so this is not a total being balanced. }
  Instrument : TInstrumentRec;
  Instr      : PInstrument;
  i          : Word;
  j, k       : Word;
  l          : LongInt;
  Acc        : ShortInt;
begin
  for i := 1 to 31 do
    with Instrument do
      begin
        FillChar(Instrument, SizeOf(Instrument), 0);

        Instr := PInstrument(Song.GetInstrument(i));
        if Instr = nil then
          begin
            Song.Status := msOutOfMemory;
            Exit
          end;

        Instr^.SetName(StrASCIIZ(Stm.Instruments[i].Name, 14));

        Len := Stm.Instruments[i].Len;

        { BOTH TESTS ARE WRITTEN THE POSITIVE WAY ROUND, AND THE DRAFT HAD BOTH
          INVERTED. The values are identical either way; the code is not,
          because Turbo Pascal emits the `then` branch as the fall-through and
          jumps to the `else`. Put the trivial arm first and the two blocks
          swap places in the segment.

          045c is a signed LongInt `> 0`:

            CMP [BP-1a],0 / JG take / JGE testlow / JMP skip
            CMP [BP-1c],0 / JA take / JMP skip

          -- high word signed, low word unsigned, which is the shape of a
          32-bit `> 0` and not of `= 0`. An equality test is
          `MOV AX,lo / OR AX,hi / JNE`, which is what the draft emitted.

          047b is a short-circuit `or`:

            CMP ES:[DI+22],0  / JNE real
            CMP ES:[DI+24],-1 / JE  zero

          -- the first test jumping TO the work when it succeeds is `or`, not
          `and`; an `and` would jump AWAY on failure. }
        if Len > 0 then
          begin
            if (Stm.Instruments[i].LoopStart <> 0) or
               (Stm.Instruments[i].LoopEnd   <> $FFFF) then
              begin
                Reps := Stm.Instruments[i].LoopStart;
                Repl := LongInt(Stm.Instruments[i].LoopEnd) - Reps
              end
            else
              begin
                Reps := 0;
                Repl := 0
              end;

            { THE ORDER IS Vol, DAdj, NAdj -- 04e5, 04f7, 04fe -- and the
              constant goes LAST. Writing NAdj before DAdj moves the eighteen
              bytes that fetch C2Spd (`MOV AX,[BP-22] / SHL AX,5 /
              LES DI,[BP+04] / ADD DI,AX / MOV AX,ES:[DI+28] / MOV [BP-0c],AX`)
              past the five that store the literal. Same three values, and the
              statements are in the segment in the order they are written. }
            Vol  := Stm.Instruments[i].Vol;
            DAdj := Stm.Instruments[i].C2Spd;
            NAdj := $2100;

            if Vol > $40 then
              Vol := $40;

            if Repl        > Len then Repl := Len;
            if Reps + Repl > Len then Repl := Len - Reps;

            Instr^.Change(@Instrument)
          end
        else
          Instr^.Change(nil)
      end
end;

{ ---------------------------------------------------------------------------
  15d0:0581..0763.  ENTER $28, RET $08.

  THE HALF OF ProcessInstruments AN STM MAKES SEPARATE. Every sample follows
  every pattern in the file, so the data cannot be read while the headers are
  being parsed; this walks the instruments again, in the same order, and reads
  each one's bytes where the stream has now arrived.

  THE $FFF1 BRANCH IS A 64K BOUNDARY, not a size check. A sample at or above
  $FFF0 bytes cannot be read in one call on a 16-bit stream, so it is taken in
  two: $FFF0 into the first block and the remainder into a second allocation.
  --------------------------------------------------------------------------- }
procedure LoadSamples(var Song : TSong; var St : TStream);
var
  { THE ORDER IS THE MEASUREMENT, and the whole $28 frame is accounted for.
    Turbo Pascal allocates locals downward in declaration order, so the first
    declared sits closest to BP. Reading the routine's BP displacements back:

      -$04  Instr        4   a far pointer
      -$20  Instrument  28   TInstrumentRec -- and its OWN field offsets prove
                             it: Data is at record +18, which is -$0e, and
                             every `LES DI,[BP-0e]` in the routine is that
                             field; Xtra is at +22, which is -$0a.
      -$22  i            2   `MOV [BP-22],1` then INC, pushed to GetInstrument
      -$24  j            2   NOTHING REFERENCES IT -- see below
      -$28  Avail        4   a LongInt: GetSize - GetPos, in an AX/DX pair

    4 + 28 + 2 + 2 + 4 = 40 = $28, exactly.

    `j` IS DECLARED AND NEVER USED, and that is a claim the binary supports
    only negatively: two bytes at -$24 that no instruction touches, between a
    counter and a LongInt. Turbo Pascal does not drop an unused local from the
    frame, so an unreferenced slot IS a declaration -- but its NAME and TYPE
    are inventions, and any other 2-byte local would compile the same. It is
    written as `i, j` because MODLOADE.PAS declares its counters that way. }
  Instr      : PInstrument;
  Instrument : TInstrumentRec;
  i, j       : Word;
  Avail      : LongInt;
begin
  for i := 1 to 31 do
    begin
      Instr := PInstrument(Song.GetInstrument(i));

      if Instr^.Instr <> nil then
        if Instr^.Instr^.Len > 0 then
          begin
            Move(Instr^.Instr^, Instrument, SizeOf(Instrument));
            Instr^.FreeContents;

            { 05ed..0614 -- TWO STATEMENTS, AND `Avail` IS ITS OWN
              ACCUMULATOR. The original calls GetPos and stores the result
              straight into the local, then calls GetSize and subtracts the
              local from it in place:

                05f8  MOV [BP-28],AX / MOV [BP-26],DX     Avail := GetPos
                0609  SUB AX,[BP-28] / SBB DX,[BP-26]     GetSize - Avail
                060f  MOV [BP-28],AX / MOV [BP-26],DX     Avail := that

              Written as the single expression `St.GetSize - St.GetPos` it is
              six bytes longer and starts `PUSH DX / PUSH AX`: Borland
              evaluates the right operand first and has nowhere to put it but
              the stack, because the destination is not free yet. Same value,
              different code. }
            Avail := St.GetPos;
            Avail := St.GetSize - Avail;

            if Instrument.Len > Avail then
              begin
                Song.Status := msFileTooShort;
                Instrument.Len := Avail
              end;

            if Instrument.Len > 0 then
              { $FFF0 WITH `<=`, NOT $FFF1 WITH `<`. The two are the same
                set of values and they are not the same instruction: 0657 is
                `CMP [BP-20],F0 / JA`, and `< $FFF1` emits `CMP ...,F1 / JAE`.
                One byte of immediate and one of opcode. }
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
                    end
                end
              else
                begin
                  FullHeap.HGetMem(Pointer(Instrument.Data), $FFF0);
                  FullHeap.HGetMem(Pointer(Instrument.Xtra),
                                   Instrument.Len - $FFF0);
                  { ONE `if`, NOT TWO, AND THE SHARED JUMP TARGET IS WHY.
                    Both nil tests branch to the SAME address in the original
                    -- Ghidra names it LAB_15d0_06ea and sends both there --
                    so there is one copy of the failure block, not one per
                    test. Written as two statements it is ten bytes longer:
                    a second `MOV ES:[DI+79],04` and its jump.

                    The build has complete boolean evaluation OFF, so `or`
                    short-circuits and the two tests stay separate
                    comparisons rather than a combined boolean. }
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
          end;

      { 15d0:0745.  `CMP BYTE PTR [060c],00` -- and DS:$060c is SongElements'
        `LowQuality`, which sits at DS:$0564 in v1.31b and moved with the rest
        of the initialised half by +$a8. Not MODLOADE's `DeltaSamples`, which
        is a different byte in a different unit's block. }
      if LowQuality then
        Instr^.Desample
    end
end;

{ ---------------------------------------------------------------------------
  15d0:0764..093d.  ENTER $206, RETF $0c.  SongLoaders[3].

  The recogniser. `FileFormat` is written BEFORE the comparison and stays
  written even when the routine declines -- safe only because callers test
  `Status`, which is the same contract every loader here keeps.

  THE FRAME IS TWO 256-BYTE STRING TEMPORARIES and six bytes of counters. Turbo
  Pascal converts each side of a char-array comparison into a String temporary
  and compares those, which is two calls to 1d89:0c05 and one to 1d89:0bc8; the
  temporaries are the compiler's and must NOT be declared. Declaring them is
  the mistake UNKLOADE.PAS records costing forty bytes.
  --------------------------------------------------------------------------- }
procedure LoadSTMFileFormat(var Song : TSong; var St : TStream;
                            var Header : TSongHeader);
const
  { DS:$0460, eight raw bytes with no length prefix -- the routine compares
    exactly eight, so it is a fixed-width character run and not a String. It is
    this unit's first typed constant, and DGROUP puts the unit's block at
    $0460 immediately after SongUnit's, which ends at $045f. }
  StmIdString : array[1..8] of Char = '!Scream!';
var
  Stm : TStmFile absolute Header;
  { DECLARED FIRST, AND THE DISPLACEMENT IS WHAT SAYS SO. 0782 is
    `MOV [BP-04],AX / MOV [BP-02],DX`, so the LongInt sits at -$04..-$01 --
    closest to BP, which is where Turbo Pascal puts the FIRST local. Declared
    after `i` it lands at -$06 and every reference in the routine is two bytes
    out: same frame size, 233 differing bytes.

    It is a named LongInt rather than an inline `St.GetPos + $490` because 0770
    calls GetPos and stores the result before adding to it. }
  Pos : LongInt;
  i   : Word;
begin
  Song.FileFormat := mffSTM;                       { 0768..076f  +$7d := $0b }

  { 0770..0799.  Past the header, the instrument table and the order table:
    $410 + $80 = $490. GetPos is VMT +$10 and Seek is VMT +$1c. }
  Pos := St.GetPos;
  St.Seek(Pos + $490);

  { 079a..07d3.  AN EARLY-EXIT GUARD, NOT AN if/else, AND THE JUMP SENSE IS
    WHAT SAYS SO. 07c2 calls the string compare and 07c7 is `JE 07d4` -- a jump
    INTO the body on equality, with the failure path falling through. Turbo
    Pascal compiles `if cond then A else B` as jump-if-FALSE over A, so a jump
    taken when the operands are EQUAL means the tested condition is `<>`.

    IT IS ALSO WORTH 256 BYTES OF FRAME. Both sides of a char-array comparison
    become String temporaries, and a temporary stays live for the whole
    statement -- so with the body nested inside the `if`, StrAsciiZ's result
    below cannot reuse either of them and the frame gets a third. Written as a
    guard, the compare is its own statement, its two temporaries die at the
    semicolon, and the rest of the routine reuses them: $206, which is
    2 x 256 + 6, against $304 for the nested form. }
  if Stm.Magic <> StmIdString then
    begin
      Song.Status := msNotLoaded;                  { 07cc  +$79 := 0 }
      Exit
    end;

    Song.Status := msOk;                         { 07d7  +$79 := 1 }

    Song.Name := FullHeap.HNewStr(StrASCIIZ(Stm.Name, 20));

    { 0814..0824.  $40 is clamped BEFORE the shift so the byte cannot
      overflow when it is multiplied by four. }
    if Stm.Volume = $40 then
      Stm.Volume := $3F;

    Song.FirstTick    := 1;
    Song.InitialTempo := Stm.Tempo shr 4;
    Song.InitialBPM   := 125;
    Song.Volume       := Stm.Volume shl 2;
    Song.NumChannels  := 4;

    { 0860..0899.  The order table ends at the first entry of 99 or more, so
      the length is the LAST index below it rather than the first at or
      above -- which is why this is a scan and not a `while`. }
    Song.SequenceLength := 0;
    for i := 1 to 128 do
      if Stm.PatternList[i] < 99 then
        Song.SequenceLength := i;

    Song.SequenceRepStart := 1;

    Move(Stm.PatternList, Song.PatternSequence^, Song.SequenceLength);

    { NO `Len` LOCAL AND NO ZERO GUARD, and the second is the subtler of the
      two. A `for` limit that is not a constant is evaluated once into a
      compiler temporary, and the loop's own entry test compares against it --
      so `if Song.SequenceLength <> 0 then for i := 1 to Song.SequenceLength`
      emits that test TWICE, and the surplus copy is eleven bytes:
      `LES DI,[BP+0e] / CMP WORD ES:[DI+55],0 / JE +32`.

      What made it look necessary was Ghidra rendering the loop as
      `local_a = Song.SequenceLength; if (local_a != 0) then a for loop` -- but
      `local_a` IS the limit temporary and the test IS the loop's. A decompiler
      showing a guard is not evidence of a guard in the source. }
    for i := 1 to Song.SequenceLength do
      Inc(Song.PatternSequence^[i]);

    { 08ae..093a -- A CHAIN OF GUARDS, NOT NESTED ifs, AND THE LAST ONE PROVES
      IT. 0931 is `CMP ES:[DI+79],02 / JLE 093a / JMP 093a` -- both arms jump
      to the same address, which is what an `Exit` guard compiles to when it is
      the routine's LAST statement: the "skip" target and the exit target are
      one place, and Turbo Pascal does not fold the jump away. A nested `if`
      would have nothing to jump over and would emit no second jump at all.

      Ghidra shows the two earlier tests as nesting and elides this one
      entirely, because to a decompiler both arms going to the same block is
      dead code. The bytes disagree, and the bytes are the measurement.

      THE THRESHOLDS DIFFER, AND THEY ARE READ RATHER THAN ASSUMED: `> msOk`
      after each of the first two, `> msFileTooShort` after the last. That is
      the same pair MODLOADE's LoadMod uses, which is where the v1.31b tree
      established that this field is a SIGNED byte. }
    ProcessInstruments(Song, St, Stm);
    if Song.Status > msOk then Exit;

    ProcessPatterns(Song, St, Stm.NumPatterns);
    if Song.Status > msOk then Exit;

    LoadSamples(Song, St);
    if Song.Status > msFileTooShort then Exit
end;

end.
