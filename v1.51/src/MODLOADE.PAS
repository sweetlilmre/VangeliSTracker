{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE PROTRACKER LOADER: read a .MOD file off a stream and build a playable
  song out of it.

  WHAT A MOD FILE IS. A fixed header, then everything else by position -- no
  offsets, no directory, nothing that says how long anything is. Twenty bytes
  of title; thirty-one instrument headers of thirty bytes each, holding a name,
  a length, a loop and a volume; a song length and an order list of 128 bytes;
  a four-byte MAGIC; then the pattern data; then the raw sample bytes, one
  after another in instrument order.

  THE MAGIC IS FOUR CHARACTERS AND IT DECIDES THE CHANNEL COUNT. 'M.K.' and
  'FLT4' mean four channels, '6CHN' six, '8CHN' eight, and the tracker that
  wrote the file is inferred from which of them it is. A file with no
  recognisable magic is a fifteen-instrument SoundTracker module from before
  the convention existed -- which is why LoadMod15 is a separate routine and
  not an error path.

  NOTHING IN THE FILE SAYS HOW MANY PATTERNS THERE ARE. It has to be worked out
  by taking the highest entry in the order list, which is why the order list is
  read before the patterns can be.

  '.WOW' IS THE TRAP. A Grave Composer file also carries 'M.K.', with eight
  channels rather than four, and the only way to tell it apart is the file's
  EXTENSION -- so the loader looks at the name it was given. A format that can
  only be identified from outside its own contents is unusual and it is real.

  [re] Segment 173d. **COMPLETE: 3,920 of 3,920 bytes.** Five routines, 302
  pending fixups, no real difference anywhere. It went in in one pass: the
  release's five bodies transferred essentially verbatim and THREE measured
  differences had to be found -- a ninety-two-byte delta-decoding block the
  release has not got, `Status` being signed, and EIGHT magic branches where
  1.39b has four.

  [re] IT EXISTS AS A FILE ALREADY because 14b9's `SongLoaders` table names it. That
  declaration -- `LoadModFileFormat` with the release's three var parameters --
  is confirmed by the call site at 153a:00dc and is the one thing in this file
  that is measured rather than scouted.

  [re] THE PAIRING WITH `LIB/MODLOADE.PAS` IS CONFIRMED THREE WAYS, all recorded in
  docs/CONTINUATION.md: TModFile31 is 1,084 bytes with Magic at offset 1080 and
  173d:0c27 reads Header+$438, which is 1080 exactly; 173d:0bf7 loads through
  Objects.TStream as the release does; and '.WOW' is a literal in both, compared
  at 173d:0c4d against TSong+$1f, which 14b9 has now independently confirmed is
  `FileExt`.

  [re] WHAT THE SCOUTING NOTE USED TO SAY IS NOW MOSTLY OBSOLETE. It listed four
  kinds of scaffolding needed before the first byte could be measured: 14b9,
  165a, a TStream stub, and the MOD record types. **Three are gone.** 14b9 and
  165a are byte-exact; TStream and TDosStream came in with 14b9's Load and
  LoadFName and are proven in use. The records are below. And the remaining
  objection -- that every `Song.X(...)` in the release is a method call where
  1.31 has free functions -- was WRONG: TSong turned out to be an OBJECT, and
  `Song.GetTrack(t)`, `Song.GetPattern(i)` and `Song.GetInstrument(i)` all exist
  and are byte-exact. The release's calls transfer as written.

  ---------------------------------------------------------------------------
  THE ROUTINE MAP, and it is SEVEN routines where the release has FIVE.

  [re] `survey.py` finds exactly ONE far return in 3,920 bytes -- `0f40 RETF 12` --
  so `LoadModFileFormat` is the only routine anything outside the segment can
  reach, and every other routine here is NEAR. That is what a unit with one
  exported procedure and a pile of implementation-section helpers looks like,
  and it matches the release's shape exactly.

  [re] `scan_funcs.py` finds five prologues, and the near-call targets add two more
  the scanner cannot see (the same lesson as 142f and 154d's own earlier scout):

      0000  ENTER $e20   \
      04e2  ENTER $564    |
      06ae  (near target) | -- read the calls, not just the prologues
      0829  (near target) |
      09d7  ENTER $10c    |
      0b72  ENTER $002   /
      0bf7  ENTER $1000  -- the '.WOW' literal at 0bf3 belongs to it, and
                            literals precede their routine

  The release's five are ProcessPatterns, ProcessInstruments, LoadMod, LoadMod15
  and LoadModFileFormat, in that implementation order. Turbo Pascal lays
  routines out in source order, so the pairing has to be made against ADDRESS
  order -- which is how 165a's fifteen were confirmed all at once. **Do not
  assume the two extra routines are extra; 1.31 may split one of the release's
  differently.** Establish that before writing, because a misplaced routine
  displaces everything below it.

  [re] WHAT IT CALLS OUTSIDE ITSELF, from survey.py, and every one now exists:

      [re] 153a:04b6  GetPattern      from 0030
      153a:0404  GetTrack        from 0476
      153a:0352  GetInstrument   from 051d
      1848:08e2, 1848:07c0, 1848:012a
      1830:0000  AsciiZ
      1ba1:*     System -- the string helpers at 0c05 (x16) and 0bc8 (x10) are
                 the char-array-to-String conversion and compare pair, which is
                 how the magics are tested; 0a2e/0a13 (x4 each) are LongInt
                 divide and multiply

  [re] MIND THE FALSE POSITIVES IN THE FAR-CALL LIST. survey.py scans for the `9A`
  opcode byte and several of its hits here decode to nonsense segments
  (`3bc0:31fb`, `8936:77fb`, `e903:76fb` and three more, all in 0794..0895).
  Those are data or the middle of another instruction, not calls. The rule this
  project already has for `disassemble_bytes` applies to any byte-pattern scan:
  a hit is a candidate, not a finding.
  ===========================================================================

  [re] START HERE: transcribe strictly top-down from 0000, add 154d to units.py only
  when a real body exists, and use a per-block check rather than the prefix --
  `blockcmp.py` is the template and took ten minutes to point at a new
  segment. }

unit ModLoader;

interface

uses
  Objects, SongUnit;

procedure LoadModFileFormat(var Song : TSong; var St : TStream;
                            var Header : TSongHeader);

implementation

uses
  SongElements, Heaps, AsciiZ;

{ ---------------------------------------------------------------------------
  THE FILE FORMAT RECORDS, TAKEN FROM THE RELEASE AND SAFE TO TAKE.

  The standing rule is that the release settles SHAPES and NAMES and is worth
  nothing for DATA -- and these are the exception that proves it, because they
  are not DemoVT's data at all. They are the ProTracker file format, which is
  fixed outside both versions. The arithmetic is checked rather than trusted:

    TModFileInstrument   22 + 2 + 1 + 1 + 2 + 2                    =   30
    TModFile31           20 + 31*30 + 1 + 1 + 128 + 4              = 1084
    Magic at             20 + 930 + 1 + 1 + 128                    = 1080
    TModFile15           20 + 15*30 + 1 + 1 + 128                  =  600

  [re] and 1080 is what 173d:0c27 reads as `Header + 0438`. That is the measurement
  the pairing rests on, so the record is confirmed from the binary at the one
  offset that matters most.
  --------------------------------------------------------------------------- }

const
  { A TYPED CONSTANT, AND THE LAYOUT IS WHY. $03cc is the FIRST two bytes of this
    unit's DGROUP block -- SongUnit's `SongLoaders` ends at $03cb and the four delta
    magics begin at $03ce -- so it is in the initialised region, between two things
    that are certainly typed constants, and a plain `var` puts it in the other region
    and leaves nothing here. It holds 0, and the pad at $03cd is TP word-aligning the
    magics after it. Declared FIRST in the unit because $03cc is below them. }
  DeltaSamples : Byte = 0;

type
  TModFileMagic = array[0..3] of Char;

const
  { EIGHT MAGICS, NOT THE RELEASE'S FOUR. 1.31 tests each of 1.39b's four twice:
    once plainly, and once against a second constant that ALSO sets
    DeltaSamples. The eight branches are read straight off the stores --

      0c65/0c6d  8 / mffWow8      the M.K. branch's `.WOW` arm
      0c77/0c7f  4 / mffMod31M_K_ ...and its else
      0ccb/0cd3  4 / mffMod31FLT4
      0d1f/0d27  6 / mffFastTracker
      0d73/0d7b  8 / mffFastTracker
      0dc4       DeltaSamples := 1, then the M.K. pair again (0de1..0dfb)
      0e44       DeltaSamples := 1, then FLT4  again (0e4c/0e54)
      0e9d       DeltaSamples := 1, then 6CHN  again (0ea5/0ead)
      0ef5       DeltaSamples := 1, then 8CHN  again (0efd/0f05)
      0f21/0f29  4 / mffMod15     the final else -> LoadMod15

    -- and every one ends in LoadMod, exactly as the release's four do.

    THE DELTA CONSTANTS' CONTENTS ARE READ FROM THE IMAGE, NOT INVENTED: at file
    offset $00daaa the DATA holds `M    F    6    8   `
    immediately before `M.K.FLT46CHN8CHN`, which is four TModFileMagic constants
    declared BEFORE the plain four -- Turbo Pascal lays typed constants down in
    declaration order, so that ordering is what fixes which group is which.

    **THEIR VALUES CANNOT BE CHECKED BY THE BYTE COMPARISON.** A typed constant
    is initialised DGROUP data and is not in a .TPU's code, and each comparison
    reaches its constant through a DGROUP offset, which is a fixup. So the
    branch STRUCTURE below is measured and the constant CONTENTS are read from
    the image -- two different kinds of evidence, and the second is risk 1.
    The names are ours; the release has no counterpart for these four. }
  Mod31MagicDeltaM : TModFileMagic = ('M', #0, #0, #0);
  Mod31MagicDeltaF : TModFileMagic = ('F', #0, #0, #0);
  Mod31MagicDelta6 : TModFileMagic = ('6', #0, #0, #0);
  Mod31MagicDelta8 : TModFileMagic = ('8', #0, #0, #0);

  Mod31MagicM_K_ : TModFileMagic = ('M', '.', 'K', '.');
  Mod31MagicFLT4 : TModFileMagic = ('F', 'L', 'T', '4');
  Mod31Magic6CHN : TModFileMagic = ('6', 'C', 'H', 'N');
  Mod31Magic8CHN : TModFileMagic = ('8', 'C', 'H', 'N');

type
  { An instrument as the file stores it. 30 bytes. }
  TModFileInstrument = record
    Name      : array[1..22] of Char;  { AsciiZ, the instrument's name       }
    Len       : Word;                  { sample length DIV 2                 }
    FineTune,
    Vol       : Byte;
    LoopStart,                         { loop offset DIV 2                   }
    LoopLen   : Word;                  { loop length DIV 2                   }
  end;

  { A note as the file stores it. 4 bytes, and the variants are how the
    loader gets at the packed period and effect nibbles. }
  PModFileNote = ^TModFileNote;
  TModFileNote = record
    case Integer of
      1 : ( l              : LongInt );
      2 : ( w1, w2         : Word );
      3 : ( b1, b2, b3, b4 : Byte );
  end;

  PModFilePattern = ^TModFilePattern;
  TModFilePattern =
    record
      case Byte of
        4 : ( Patt4 : array[0..63] of array[1..4] of TModFileNote );
        5 : ( Patt5 : array[0..63] of array[1..5] of TModFileNote );
        6 : ( Patt6 : array[0..63] of array[1..6] of TModFileNote );
        7 : ( Patt7 : array[0..63] of array[1..7] of TModFileNote );
        8 : ( Patt8 : array[0..63] of array[1..8] of TModFileNote );
    end;

  { The 15-sample header. 600 bytes. }
  PModFile15 = ^TModFile15;
  TModFile15 = record
    Name        : array[1..20] of Char;
    Samples     : array[1..15] of TModFileInstrument;
    SongLen     : Byte;
    SongRep     : Byte;
    PatternList : array[0..127] of Byte;
  end;

  { The 31-sample header. 1084 bytes, Magic at 1080 -- see above. }
  PModFile31 = ^TModFile31;
  TModFile31 = record
    Name        : array[1..20] of Char;
    Samples     : array[1..31] of TModFileInstrument;
    SongLen     : Byte;
    SongRep     : Byte;
    PatternList : array[0..127] of Byte;
    Magic       : TModFileMagic;
  end;

{ ---------------------------------------------------------------------------
  ALL FIVE PAIR BY ADDRESS, and the frames are what settled it -- Turbo Pascal
  lays routines out in source order, so agreement across all five at once is a
  stronger check than any one of them:

    0000  ENTER $e20   ProcessPatterns      Patt 2048 + FullTrack 1536 + 20
    04e2  ENTER $564   ProcessInstruments   the 1084-byte VALUE parameter + locals
    09d7  ENTER $10c   LoadMod              12 of locals + a 256-byte String temp
                                            for StrASCIIZ's result
    0b72  ENTER $002   LoadMod15            one Word; both Mod31 and Mod15 are
                                            ABSOLUTE and cost nothing
    0bf7  ENTER $1000  LoadModFileFormat    EIGHT 256-byte String temporaries --
                                            four magic comparisons, two char-array
                                            conversions each

  [re] AND survey.py's CALL COUNTS AGREE WITH THAT LAST ONE EXACTLY: 1d89:0c05
  (char array -> String) is called eight times inside 0bf7's range and 1d89:0bc8
  (string compare) five times -- four magics plus the '.WOW' test on FileExt.
  --------------------------------------------------------------------------- }

{ 173d:0000..04e1.  Near -- nothing outside the segment calls it. }
procedure ProcessPatterns(var Song : TSong; var St : TStream; Num : Word);
var
  Patt      : TModFilePattern;
  FullTrack : TFullTrack;
  Pattern   : PPattern;
  Track     : PTrack;
  i, j      : Word;
  n, t      : Word;
  l         : LongInt;
begin
  t := 1;
  for n := 1 to Num do
    begin
      { The cast is the duplicate-type debt SONGUNIT.PAS documents, not a
        conversion: TSong.GetPattern is declared to return SongUnit's look-alike
        PPattern -- the view PLAYMOD reads as Rows^.RowCount/Speed -- and this
        unit wants SongElements' real TPattern, whose Patt^.NNotes/Tempo are the
        same two bytes. A pointer cast costs nothing. Removing the duplication
        means renaming those fields in PLAYMOD, which is its own pass. }
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

      l := St.GetPos;
      St.Read(Patt, 64*4*Song.NumChannels);

      if St.Status <> stOk then
        begin
          Song.Status := msFileTooShort;
          Exit
        end;

      case Song.NumChannels of
        4 : for i := 63 downto 0 do
              for j := Song.NumChannels downto 1 do
                Patt.Patt8[i][j] := Patt.Patt4[i][j];
        5 : for i := 63 downto 0 do
              for j := Song.NumChannels downto 1 do
                Patt.Patt8[i][j] := Patt.Patt5[i][j];
        6 : for i := 63 downto 0 do
              for j := Song.NumChannels downto 1 do
                Patt.Patt8[i][j] := Patt.Patt6[i][j];
        7 : for i := 63 downto 0 do
              for j := Song.NumChannels downto 1 do
                Patt.Patt8[i][j] := Patt.Patt7[i][j];
      end;

      for j := 1 to Song.NumChannels do
        begin
          FillChar(FullTrack, SizeOf(FullTrack), 0);

          for i := 0 to 63 do
            with FullTrack[i], Patt.Patt8[i][j] do
              begin
                Command := TModCommand((b3 and $F) + 1);
                if Command = mcExtended then
                  begin
                    Parameter := b4 and $F;
                    Command   := TModCommand(($11 + (b4 shr 4)))
                  end
                else if (Command = mcArpeggio) and (b4 = 0) then
                  begin
                    Parameter := 0;
                    Command   := mcNone
                  end
                else
                  Parameter := b4;

                Period     := b2 + (Word(b1 and $7) shl 8);
                Instrument := (b3 shr 4) + (b1 and 16);

                if ((Command = mcEndPattern) or (Command = mcJumpPattern)) and
                   (Pattern^.Patt^.NNotes > i + 1) then
                  Pattern^.Patt^.NNotes := i + 1;

                if (Command = mcSetVolume) and (Parameter > $40) then
                  Parameter := $40;

                if (Command = mcJumpPattern) then
                  Parameter := (Parameter and $0F) +
                               (Parameter shr   4)*10 + 1;

                if (Command = mcEndPattern) then
                  Parameter := (Parameter and 63) + 1
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

{ 173d:04e2..09d6.  `Mod31` is a VALUE parameter -- 1,084 bytes copied into the
  frame on entry, which is most of the ENTER. }
procedure ProcessInstruments(var Song : TSong; var St : TStream;
                             Mod31 : TModFile31);
const
  MinLoop = 1024;
  FineTuneTable : array[0..15] of Word = ( $43CD,$444B,$44CA,$454A,
                                           $45CA,$464C,$46CF,$4752,
                                           $4000,$4076,$40EE,$4166,
                                           $41E0,$425A,$42D5,$4351 );
var
  Instrument : TInstrumentRec;
  Instr      : PInstrument;
  i, j, k    : Word;
  { [re] DECLARED LAST ON PURPOSE. Turbo Pascal allocates locals downward in
    declaration order, and the original puts this byte at [BP-0463] -- one below
    `k` at [BP-0462]. Anywhere else and every offset under it shifts. It is also
    the whole of the frame difference: the original's ENTER is $564 against the
    release's shape's $562, and one byte plus alignment is two. }
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

        Instr^.SetName(StrASCIIZ(Mod31.Samples[i].Name, 22));

        Len := LongInt(Swap(Mod31.Samples[i].Len)) shl 1;

        if Len > St.GetSize - St.GetPos then
          begin
            Len := St.GetSize - St.GetPos;
            Song.Status := msFileTooShort
          end;

        if Len > 0 then
          begin
            Reps := LongInt(Swap(Mod31.Samples[i].LoopStart)) shl 1;
            Repl := LongInt(Swap(Mod31.Samples[i].LoopLen)) shl 1;
            Vol  := Mod31.Samples[i].Vol;

            if Repl        > Len then Repl := Len;
            if Reps + Repl > Len then Reps := Len - Repl;

            if Mod31.Samples[i].Vol > $40 then
              Mod31.Samples[i].Vol := $40;

            if Vol > $40 then
              Vol := $40;

            NAdj := FineTuneTable[0];
            DAdj := FineTuneTable[Mod31.Samples[i].FineTune and $F];

            if Len <= MaxSample then
              begin
                if Repl > 4 then
                  FullHeap.HGetMem(Pointer(Data), Len+Repl*(MinLoop div Repl))
                else
                  FullHeap.HGetMem(Pointer(Data), Len);

                if Data = nil then
                  begin
                    Song.Status := msOutOfMemory;
                    Exit
                  end;

                St.Read(Data^, Len);

                { ------------------------------------------------------------
                  DELTA-ENCODED SAMPLES. Some MOD files store each sample byte
                  as the DIFFERENCE from the one before rather than as its own
                  value, which compresses smoothly-varying waveforms. This
                  block undoes that in place: a running sum over the sample,
                  each byte replaced by the total so far.

                  It costs nothing when it is not wanted -- a global says
                  whether the file being read is delta-encoded, and the whole
                  block is skipped when it is not.

                  [re] 173d:0778..07d3 -- NINETY-TWO BYTES THE RELEASE HAS NOT
                  GOT, and the whole of ProcessInstruments' length difference.

                  It is a RUNNING SUM over the sample, in place:

                    [re] 0778  CMP byte [03cc],0 / JZ            the guard
                    077f  MOV byte [BP-0463],0              Acc := 0
                    0784  Len - 1 as a LongInt, low word kept as the FOR limit
                    07b2  MOV AL,ES:[DI] / ADD [BP-0463],AL     Acc := Acc + x
                    07c7  MOV ES:[DI],DL                        x := Acc

                  which is DELTA DECODING -- each byte in the file is a step
                  rather than a level, and the loop integrates them. 1.39b has a
                  loop commented out at exactly this point in the source (a
                  -128 to -127 clamp), so the AUTHOR was editing this region
                  between the two versions; what 1.31 does here is not what the
                  comment says, and the comment must not be used to guess it.

                  [re] THE GUARD IS A GLOBAL AT DS:$03cc AND NOTHING ELSE IN THE TREE
                  TOUCHES IT. It is declared in this unit's implementation
                  because this is the only reader; the name is OURS, taken from
                  the role, since the release has no counterpart. If a later
                  segment turns out to WRITE it -- 109c's switches or 11bb's
                  config keys are the candidates -- move the declaration there
                  and rename it to whatever sets it.
                  ------------------------------------------------------------ }
                if DeltaSamples <> 0 then
                  begin
                    Acc := 0;
                    for j := 0 to Len - 1 do
                      begin
                        Inc(Acc, Data^[j]);
                        Data^[j] := Acc
                      end
                  end;

                if Repl > 4 then
                  for j := 1 to MinLoop div Repl do
                    for k := 0 to Repl - 1 do
                      Data^[Reps + j*Repl + k] := Data^[Reps + k];

                if Repl > 4 then
                  begin
                    Len  := Len  + Repl*(MinLoop div Repl);
                    Repl := Repl + Repl*(MinLoop div Repl)
                  end;

                if St.Status <> stOk then
                  begin
                    Song.Status := msFileDamaged;
                    Exit
                  end
              end
            else
              begin
                FullHeap.HGetMem(Pointer(Data), MaxSample);
                FullHeap.HGetMem(Pointer(Xtra), Len-MaxSample);

                if (Data = nil) or (Xtra = nil) then
                  begin
                    Song.Status := msOutOfMemory;
                    Exit
                  end;

                St.Read(Data^, MaxSample);
                St.Read(Xtra^, Len-MaxSample);

                if St.Status <> 0 then
                  begin
                    Song.Status := msFileDamaged;
                    Exit
                  end
              end;

            Instr^.Change(@Instrument)
          end
      end
end;

{ 173d:09d7..0b71.  The $10c frame is 12 bytes of locals plus the 256-byte
  temporary StrASCIIZ's String result needs. }
procedure LoadMod(var Song : TSong; var St : TStream; var Mod31 : TModFile31);
var
  j, k,
  i, w             : Word;
  IsMod31          : Boolean;
  NumberOfPatterns : Word;
begin
  { Initial checkings to see if it's a real MOD. }

  Song.Status := msFileDamaged;

  { GONE IN v1.51, AND IT IS THE ONLY REAL CHANGE IN THIS WHOLE UNIT. v1.31b
    opened LoadMod with

        for i := 0 to 127 do
          if Mod31.PatternList[i] > 63 then Exit;

    [re] -- 35 bytes at 173d:09e3, and `verdiff.py 154d -> 173d` reports it as the
    single non-shift difference between the two versions of a 3,920-byte unit.
    The removal is deliberate rather than incidental: v1.51's WHATSNEW.DOC lists
    "Now it can play MODs with more than 64 different patterns" under v1.50,
    credited to Jare, and a pattern number above 63 is exactly what this loop
    rejected. Every other byte of the unit is a displacement or a DGROUP address
    that moved.

    THE VALIDATION BELOW STAYS. Only the pattern-number ceiling went; the name
    and the sequence-length checks are still here, so the loader has not stopped
    validating -- it has stopped enforcing a limit the player outgrew. }

  for i := 1 to 20 do
    if (Mod31.Name[i] < ' ') and
       (Mod31.Name[i] <> #0) then Exit;

  if (Mod31.SongLen > 128) or (Mod31.SongRep > 128) then Exit;

  { Processing of the header }

  Song.Status := msOK;

  Song.Name := FullHeap.HNewStr(StrASCIIZ(Mod31.Name, 20));

  Song.InitialTempo := 6;
  Song.InitialBPM   := 125;
  Song.Volume       := 255;

  for i := 0 to 127 do
    Inc(Mod31.PatternList[i]);
  Move(Mod31.PatternList, Song.PatternSequence^, Mod31.SongLen);
  Song.SequenceLength   := Mod31.SongLen;
  Song.SequenceRepStart := Mod31.SongRep + 1;

  NumberOfPatterns := 0;
  for i := 0 to 127 do
    if NumberOfPatterns < Mod31.PatternList[i] then
      NumberOfPatterns := Mod31.PatternList[i];

  { Processing of the patterns (the partiture) }

  ProcessPatterns(Song, St, NumberOfPatterns);
  if Song.Status > msOk then Exit;

  { Processing of the instruments }

  ProcessInstruments(Song, St, Mod31);
  if Song.Status > msFileTooShort then Exit
end;

{ 173d:0b72..0bf6.  ENTER 0002 -- one Word. Both ABSOLUTE aliases cost nothing,
  which is what makes the frame that small and identifies the routine. }
procedure LoadMod15(var Song : TSong; var St : TStream; var Header : TSongHeader);
var
  i     : Word;
  Mod31 : TModFile31 absolute Header;
  Mod15 : TModFile15 absolute Header;
begin
  Move(Mod15.SongLen, Mod31.SongLen, 130);
  for i := 16 to 31 do
    FillChar(Mod31.Samples[i], SizeOf(Mod31.Samples[i]), 0);

  St.Seek(St.GetPos - SizeOf(TModFile31) + SizeOf(TModFile15));

  LoadMod(Song, St, Mod31)
end;

{ 173d:0bf7..0f4f.  RETF 12 -- the ONLY far return in 3,920 bytes, and the only
  routine anything outside the segment can reach. The '.WOW' literal at 0bf3
  sits immediately before it, which is where Turbo Pascal puts a routine's
  literals. }
procedure LoadModFileFormat(var Song : TSong; var St : TStream;
                            var Header : TSongHeader);
var
  Mod31 : TModFile31 absolute Header;
begin
  St.Seek(St.GetPos + SizeOf(TModFile31));       { 0bfb..0c18 }
  DeltaSamples := 0;                             { 0c19       }

  if (Mod31.Magic = Mod31MagicM_K_) then
    begin
      if Song.FileExt = '.WOW' then
        begin
          Song.NumChannels := 8;
          Song.FileFormat  := mffWow8
        end
      else
        begin
          Song.NumChannels := 4;
          Song.FileFormat  := mffMod31M_K_
        end;
      LoadMod(Song, St, Mod31)
    end
  else if (Mod31.Magic = Mod31MagicFLT4) then
    begin
      Song.NumChannels := 4;
      Song.FileFormat  := mffMod31FLT4;
      LoadMod(Song, St, Mod31)
    end
  else if (Mod31.Magic = Mod31Magic6CHN) then
    begin
      Song.NumChannels := 6;
      Song.FileFormat  := mffFastTracker;
      LoadMod(Song, St, Mod31)
    end
  else if (Mod31.Magic = Mod31Magic8CHN) then
    begin
      Song.NumChannels := 8;
      Song.FileFormat  := mffFastTracker;
      LoadMod(Song, St, Mod31)
    end

  else if (Mod31.Magic = Mod31MagicDeltaM) then
    begin
      DeltaSamples := 1;
      if Song.FileExt = '.WOW' then
        begin
          Song.NumChannels := 8;
          Song.FileFormat  := mffWow8
        end
      else
        begin
          Song.NumChannels := 4;
          Song.FileFormat  := mffMod31M_K_
        end;
      LoadMod(Song, St, Mod31)
    end
  else if (Mod31.Magic = Mod31MagicDeltaF) then
    begin
      DeltaSamples := 1;
      Song.NumChannels := 4;
      Song.FileFormat  := mffMod31FLT4;
      LoadMod(Song, St, Mod31)
    end
  else if (Mod31.Magic = Mod31MagicDelta6) then
    begin
      DeltaSamples := 1;
      Song.NumChannels := 6;
      Song.FileFormat  := mffFastTracker;
      LoadMod(Song, St, Mod31)
    end
  else if (Mod31.Magic = Mod31MagicDelta8) then
    begin
      DeltaSamples := 1;
      Song.NumChannels := 8;
      Song.FileFormat  := mffFastTracker;
      LoadMod(Song, St, Mod31)
    end

  else
    begin
      Song.NumChannels := 4;
      Song.FileFormat  := mffMod15;
      LoadMod15(Song, St, Header)
    end
end;

end.
