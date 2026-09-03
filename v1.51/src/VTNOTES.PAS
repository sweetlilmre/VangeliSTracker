{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Answer "which note is this?" for every period a module can hold, once, at
  startup.

  A TRACKER PATTERN STORES A PERIOD, NOT A NOTE. A period is how many timer
  ticks lie between output samples -- the Amiga's way of saying pitch, and
  lower means higher. Going the other way, from a period back to a note name
  or a note number, is a search through a table, and the player needs it often
  enough that doing it per event would cost real time. So this builds the
  whole answer table once and every later lookup is one indexed read.

  2048 entries covers every period a module can express.

  EACH ANSWER IS PACKED TWICE OVER, because its two consumers want different
  shapes: a nibble pair for anything displaying "octave 4, note 3", and a
  single linear 0..83 for anything that wants to index a table by note.

  [re] Segment 183e -- 160 bytes, all of it, one routine, no parameters. The
  body calls it once at 1000:05d7.

  [re] IN     DS:$04bc  the period table: 7 octaves x 12 semitones, words, on a
                   stride of 24 bytes. Each octave is the one above halved:

                     oct 0  1664 1570 1482 1399 1321 1247
                            1177 1110 1048  989  934  881
                     oct 1   832  785 ...                 440
                     ...
                     oct 6    26   24 ...                  14

           DS:$04d2  is not a separate table -- it is $04bc + 22, i.e. the
                     LAST entry of each row, so [$04d2 + Oct*24] is the
                     smallest period that octave holds.

  [re] OUT    DS:$25c6  2048 words, indexed by period. Each packs the answer
                   twice over:  high byte = Oct*16 + Note   (a nibble each)
                                low  byte = Oct*12 + Note   (0..83, linear)

  [re] NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.
  =========================================================================== }

unit VTNotes;

interface

const
  Octaves  = 7;                   { 183e:0027 stops the octave scan at 6 }
  Semis    = 12;                  { 183e:0059 stops the note scan at $0B }
  Notes    = Octaves * Semis;     { 84 -- the linear form NoteOf's low byte holds }
  Periods  = 2048;                { 183e:0089 stops at $7FF }
  RowBytes = 24;                  { 183e:001b, 183e:0048 -- IMUL by $18 }

type
  TPeriodRow = array[0..Semis - 1] of Word;

{ --- THE PERIOD TABLE ------------------------------------------------------
  The period for each of the 84 notes, flat, indexed by the linear
  `Oct*12 + Note` that NoteOf's low byte holds. The two are made for each
  other: look a period up in NoteOf, take the low byte, index here.

  IT IS THE PROTRACKER PERIOD TABLE, 1712 down to 14 over seven octaves, and
  the shape of it is the equal-tempered scale: each semitone is the one below
  divided by the twelfth root of two, so each octave is the one above doubled.
  Any module written for an Amiga tracker holds periods from this table, which
  is why it can be a lookup rather than a calculation.

  [re] EXPORTED BECAUSE 142f READS IT, and finding that is what turned up the
  pair below. `147d:005d` is `MOV AX,[DI+0414]` with DI = note * 2. DS:$0414.
  Transcribed from 1e92:0414 rather than computed, per the standing rule.
  ------------------------------------------------------------------------- }
const
  NotePeriods : array[0..Notes - 1] of Word = (
    1712, 1616, 1525, 1440, 1359, 1283, 1211, 1143, 1078, 1018,  961,  907,
     856,  808,  763,  720,  679,  641,  605,  571,  539,  509,  480,  453,
     428,  404,  381,  360,  340,  321,  303,  286,  270,  254,  240,  227,
     214,  202,  191,  180,  170,  160,  151,  143,  135,  127,  120,  113,
     107,  101,   95,   90,   85,   80,   76,   71,   67,   64,   60,   57,
      53,   50,   48,   45,   42,   40,   38,   36,   34,   32,   30,   28,
      27,   25,   24,   22,   21,   20,   19,   18,   17,   16,   15,   14
  );

{ The answer table this unit exists to build: 2048 words, indexed by period.

  [re] EXPORTED BECAUSE 142f READS IT: 147d:004c is `MOV AX,[DI+25c6]` with DI
  the period doubled, and it takes the LOW BYTE -- the linear `Oct*12 + Note`
  form -- to index NotePeriods above. The two tables are a matched pair and
  both ends of the pairing are now in the tree. }
var
  NoteOf    : array[0..Periods - 1] of Word;         { DS:$4920  4,096 bytes }

  { The printed name of each note -- 'A#2' and the like -- for anything that
    displays a pattern rather than plays it.

    [re] DS:$35c6 -- 340 BYTES THAT HAD TO BE HERE, and the release names them. This unit's
    variable block ends where GUS's begins at $371a, and $25c6 + 4096 is $35c6, so there
    are exactly $154 bytes after `NoteOf` -- which is 340, which is 85 times 4, which is
    `array[0..84] of String[3]`. `LIB/SONGUTIL.PAS` -- the release counterpart
    `relmatch.py` scored this segment against at 71.1% -- declares `NoteIdx : TNoteSet`
    and `NoteStr : TNoteStringSet` as its two variables, and its `NoteStr` holds the
    printed name of each note, "e.g. 'A#2'". `NoteOf` is `NoteIdx`; this is the other one.

    [re] NOTHING IN THE TRANSCRIBED TREE READS IT, and it holds no data -- it is a `var`, so
    the image is silent about it and `survey.py` finding no printable string in the
    segment is consistent. It is here for its 340 bytes and its name, and the arithmetic
    is what says it exists. }
  NoteStr   : array[0..84] of String[3];             { DS:$5920  340 bytes  }

procedure BuildNoteTable; far;

implementation

{ --- THE SEARCH THRESHOLDS -------------------------------------------------
  NOT A SECOND PERIOD TABLE -- THE BOUNDARIES BETWEEN THE FIRST ONE'S NOTES.
  Each entry is the GEOMETRIC midpoint between two adjacent semitones:

      NoteBounds[i] = round(sqrt(NotePeriods[i] * NotePeriods[i+1]))

  and geometric rather than arithmetic because PITCH IS LOGARITHMIC. Halfway
  between two notes in the way a listener hears it is the square root of the
  product, not the average. Using the average would put the boundary in the
  wrong place by a few cents, which for periods in the upper octaves -- where
  adjacent entries differ by one or two -- is the difference between the right
  note and its neighbour.

  WHAT IT BUYS IS ROUNDING TO THE NEAREST SEMITONE. The search below takes the
  first entry the period does not exceed. Against a table of periods that would
  answer "the next note down" for anything not exactly on a table value, which
  is every period a slide or a fine-tune produces. Against a table of midpoints
  it answers the nearest note, which is what a listener would call it.

  The last entry has no successor and repeats the last period, 14.

  Two tables, then: one holds the notes' values, the other holds the walls
  between them. Each is indexed the way its own consumer wants -- flat by the
  effects code, by octave row here, which is why this one keeps its 2-D shape.

  [re] Checked across all 83 pairs against the bytes at 1e92:04bc and
  1e92:0414 -- **83 of 83, no exceptions**; sqrt(1712*1616) is 1663.3 and the
  entry is 1664, sqrt(1616*1525) is 1570.0 and the entry is 1570, and so on to
  the end. They sit next to each other in DGROUP ($0414 then $04bc, 168 bytes
  each). `183e:0048` is `IMUL DI,Oct,$18` and a flat declaration would lose
  that instruction.

  [re] ORDINARY DGROUP DATA, not `absolute`. This pair was once declared
  `absolute 0:$04bc`, which is segment ZERO -- the interrupt vector table -- and
  made every access a far one through ES. The original indexes them DS-relative:
  183e:004e is `MOV AX,[DI+04BC]`, a plain DGROUP reference with the offset in the
  instruction. The offsets themselves are decided by link order, which is the open
  problem for a byte-exact EXE; inside a .TPU they are pending fixups and compare
  as zero either way.
  ------------------------------------------------------------------------- }
const
  NoteBounds : array[0..Octaves - 1] of TPeriodRow = (
    (1664, 1570, 1482, 1399, 1321, 1247, 1177, 1110, 1048,  989,  934,  881),
    ( 832,  785,  741,  699,  660,  623,  588,  555,  524,  494,  466,  440),
    ( 416,  392,  370,  350,  330,  312,  294,  278,  262,  247,  233,  220),
    ( 208,  196,  185,  175,  165,  155,  147,  139,  131,  123,  116,  110),
    ( 104,   98,   92,   87,   82,   78,   73,   69,   65,   62,   58,   55),
    (  51,   49,   46,   43,   41,   39,   37,   35,   33,   31,   29,   27),
    (  26,   24,   23,   21,   20,   19,   18,   17,   16,   15,   14,   14)
  );



{ --------------------------------------------------------------------------
  Fill NoteOf: for every period from 0 to 2047, find the note nearest it and
  store the answer in both of its packed forms.

  TWO NESTED SEARCHES, OCTAVE THEN SEMITONE. The octave scan finds the row
  whose smallest period the target still exceeds; the semitone scan then walks
  that row for the first boundary the period falls below. Linear both times,
  which is affordable because this runs once.

  BOTH SEARCHES FALL OFF THE END DELIBERATELY. A period too large for any
  octave, or too large for any semitone within the one chosen, answers octave 0
  note 0 rather than running past the table. Nothing checks the result and
  nothing needs to -- there is no input for which the answer is undefined, only
  inputs for which it is arbitrary.

  Called once, from the program's startup.

  [re] 183e:0000. Plain Pascal in the binary -- ENTER $0A,0, no assembler.
  -------------------------------------------------------------------------- }
procedure BuildNoteTable;
label
  Found, Store;
var
  { Four bytes the original's frame reserves and its code never reads. Kept so
    that the frame is the size it was.

    [re] The original's frame is ENTER $0a,0 --
    ten bytes -- but only six are referenced, and its three counters sit at
    [BP-6], [BP-8] and [BP-$a]. Turbo Pascal allocates the first declared
    local nearest BP, so something four bytes wide is declared ahead of them
    and never used.

    Declared here to reproduce the frame. Its type cannot be recovered -- a
    LongInt, a Pointer and two Words are indistinguishable when nothing reads
    them -- so LongInt is a guess and only its SIZE is evidence. }
  Unused : LongInt;               { [BP-4]  never referenced            }

  P    : Word;                    { [BP-6]  the period being answered   }
  Oct  : Word;                    { [BP-8]                              }
  Note : Word;                    { [BP-$a]                             }
begin
  { [re] THREE `FOR` LOOPS AND TWO `GOTO`s. Each loop head is the giveaway:
    `MOV <var>,0 / JMP over / INC <var> / <body>` is Borland's FOR, and a
    WHILE compiles with the test at the top and no jump past an increment.
    Written as WHILE loops -- which this file did -- the increments land in
    the wrong place and every branch after them shifts.

    The searches leave early by jumping OUT of the loop, and both fall-off-
    the-end paths answer octave 0, note 0 rather than indexing off the table.
    Nothing checks; it simply cannot go wrong. }
  for P := 0 to Periods - 1 do                    { 183e:0004, 0089 }
  begin
    for Oct := 0 to Octaves - 1 do                { 183e:000e, 0027 }
      if P > NoteBounds[Oct][Semis - 1] then        { 183e:001f }
        goto Found;                               { 183e:0025 }

    Note := 0;                                    { 183e:002d }
    Oct  := 0;                                    { 183e:0032 }
    goto Store;                                   { 183e:0037 }

  Found:
    for Note := 0 to Semis - 1 do                 { 183e:0039, 0059 }
      if NoteBounds[Oct][Note] < P then             { 183e:0052 }
        goto Store;                               { 183e:0057 }

    Note := 0;                                    { 183e:005f }
    Oct  := 0;                                    { 183e:0064  falls through }

    { 183e:0069 -- both forms in one word. The low byte is the linear note
      number a sample rate is worked out from; the high byte is the nibble
      pair a pattern display wants. }
  Store:
    NoteOf[P] := ((Oct shl 4) + Note) shl 8       { 183e:0072 .. 183e:007e }
                 + (Oct * Semis + Note);          { 183e:0069 }
  end;
end;

end.
