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
  single linear 0..83 for anything that wants to index a table by note.}

unit VTNotes;

interface

const
  Octaves  = 7;                   { stops the octave scan at 6 }
  Semis    = 12;                  { stops the note scan at $0B }
  Notes    = Octaves * Semis;     { 84 -- the linear form NoteOf's low byte holds }
  Periods  = 2048;                { stops at $7FF }
  RowBytes = 24;                  { IMUL by $18 }

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
  is why it can be a lookup rather than a calculation.}
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

{ The answer table this unit exists to build: 2048 words, indexed by period.}
var
  NoteOf    : array[0..Periods - 1] of Word;         { 4,096 bytes }

  { The printed name of each note -- 'A#2' and the like -- for anything that
    displays a pattern rather than plays it.}
  NoteStr   : array[0..84] of String[3];             { 340 bytes  }

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
  effects code, by octave row here, which is why this one keeps its 2-D shape.}
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

  Called once, from the program's startup.}
procedure BuildNoteTable;
label
  Found, Store;
var
  { Four bytes the original's frame reserves and its code never reads. Kept so
    that the frame is the size it was.

    Declared here to reproduce the frame. Its type cannot be recovered -- a
    LongInt, a Pointer and two Words are indistinguishable when nothing reads
    them -- so LongInt is a guess and only its SIZE is evidence. }
  Unused : LongInt;               { never referenced            }

  P    : Word;                    { the period being answered   }
  Oct  : Word;
  Note : Word;
begin
  for P := 0 to Periods - 1 do
  begin
    for Oct := 0 to Octaves - 1 do
      if P > NoteBounds[Oct][Semis - 1] then
        goto Found;

    Note := 0;
    Oct  := 0;
    goto Store;

  Found:
    for Note := 0 to Semis - 1 do
      if NoteBounds[Oct][Note] < P then
        goto Store;

    Note := 0;
    Oct  := 0;                                    { falls through }

    { both forms in one word. The low byte is the linear note
      number a sample rate is worked out from; the high byte is the nibble
      pair a pattern display wants. }
  Store:
    NoteOf[P] := ((Oct shl 4) + Note) shl 8
                 + (Oct * Semis + Note);
  end;
end;

end.
