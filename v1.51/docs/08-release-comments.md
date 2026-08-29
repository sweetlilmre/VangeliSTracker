# The release's own comments

**These are v1.39b's comments, not ours.** They are the author writing about the author's code, at the time of writing it, and that is a class of evidence this reconstruction cannot produce for itself: bytes say what a routine does and never say why.

Harvested with `kit/tools/pascal/harvest.py` from the units v1.51 also has — 669 comments kept from the 1,672 those files hold, after dropping directives, rules, boilerplate headers, commented-out statements, restatements of the declaration beside them, and duplicates.

## How to read this

* `|` means the comment sat on the same line as the code shown; `>` means it stood alone and the code shown is the next line.
* `(disabled)` means it was inside a routine the release had commented out — see below.
* Spanish comments are given in translation with the original beneath. English comments are quoted verbatim.

## Three warnings

**A comment here is a candidate, not a fact.** v1.39b is a different program from v1.51 — a tracker rather than a player — and a note describing a routine that changed is worse than no note. Every one of these has to be checked against the code it would be placed beside.

**The mixer is commented out in the release.** `UnCanal` and its inner loop sit inside a `(* ... *)` block roughly ten thousand characters long. That is where almost every Spanish comment lives, and it is the most valuable passage in the tree: the author's line-by-line account of the mixing loop, preserved but disabled. In v1.51 that code is live.

**Provenance must survive the copy.** A translated release comment is the author saying what the code does. A note written here after reading the bytes is something else. When these are placed, they should read as the first and not be mistaken for the second.


## `v1.39b/LIB/ASCIIZ.PAS`

* **24** `|` — Converts the AsciiZ string 's' to a
  <br>`FUNCTION StrAsciiZ(VAR s; l: WORD) : STRING;`
* **25** `>` — TP string with a maximum length.
  <br>`IMPLEMENTATION`


## `v1.39b/LIB/CMDLINE.PAS`

* **6** `>` — options interpreter. You just have to make a desdendant
* **7** `>` — object overriding the InterpretNoSwitch and
* **8** `>` — InterpretSwitch methods.
* **11** `>` — the command line written from the DOS prompt.


## `v1.39b/LIB/DEVGUS.PAS`

* **23** `>` — Device ID String.
  <br>`CONST`
* **72** `>` — Autodetect routine. It's always present.
  <br>`FUNCTION DevDetect : BOOLEAN; FAR;`
* **91** `>` — Device Initialisation routine.
  <br>`PROCEDURE DevInit(Hz: WORD); FAR;`
* **99** `>` — CalcTimerData(TicksPerSecond); { Then do the standard polling initialisation. } InitTimer;
  <br>`CalcTimerData(TicksPerSecond);    { Then do the standard polling initialisation. }`
* **112** `>` — Device deinitialisation routine.
  <br>`PROCEDURE DevEnd; FAR;`
* **125** `>` — Accesory routines.
  <br>`FUNCTION DevGetRealFreq(Hz: WORD) : WORD; FAR;`
* **145** `>` — Device record.
  <br>`CONST`
* **158** `>` — Init code.
  <br>`BEGIN`


## `v1.39b/LIB/DEVSB.PAS`

* **6** `>` — compatibles, including the Sound Blaster Pro, Sound
* **7** `>` — Booster, etc...
* **8** `>` — Uses both: DMA and timer polling.
* **15** `>` — of the SB Pro yet.
* **34** `|` — Master volume of the SB Pro mixer.
  <br>`SbProMixMasterVol : BYTE    = 255;`
* **35** `|` — DAC volume.
  <br>`SbProMixDACVol    : BYTE    = 255;`
* **36** `|` — FM music volume.
  <br>`SbProMixFMVol     : BYTE    = 255;`
* **37** `|` — TRUE = Activate SB Pro output filter.
  <br>`SbProMixFilter    : BOOLEAN = FALSE;`
* **142** `>` — ****************** DMA Stuff ********************
  <br>`CONST`
* **168** `>` — MOV AX,$B800 MOV DS,AX INC [WORD PTR DS:0]
  <br>`MOV     AX,$B800`
* **199** `>` — PUSH 100 PUSH sdcSetTimeConst CALL SbWriteByte PUSH 100 PUSH 232 CALL SbWriteByte
  <br>`PUSH    100`
* **207** `|` — MOV AL,232 MOV [TimeConst],AL
  <br>`}`


## `v1.39b/LIB/FILTERS.PAS`

* **6** `>` — They all are 1st order FIR filters (in case you know what
* **25** `>` — NOTE: A cut-off frequency of PI*X means that the cut-off frequency is at f*X/2 where f is the sampling rate. For example, with a sampling rate of 20000 Hz, a PI*3/4 means a cut-off frequency of 7500 Hz.
  <br>`at f*X/2 where f is the sampling rate. For example, with a`
* **30** `|` — No filtering.
  <br>`TFilterMethod = (fmNone,`
* **31** `|` — Filter with a PI*7/8 cut-off frequency.
  <br>`fm7_8,`
* **32** `|` — Filter with a PI*3/4 cut-off frequency.
  <br>`fm3_4,`
* **33** `|` — Filter with a PI*1/2 cut-off frequency.
  <br>`fm1_2`
* **57** `>` — Word size filters.
  <br>`PROCEDURE Filter1_2Word; ASSEMBLER;`
* **138** `>` — Byte size filters.
  <br>`PROCEDURE Filter1_2Byte; ASSEMBLER;`


## `v1.39b/LIB/GUS.PAS`

* **89** `>` — Basic procedures
  <br>`PROCEDURE SetGusVoice (Voice: BYTE); ASSEMBLER;`
* **305** `>` — MOV AX,$B800 MOV DS,AX INC [WORD PTR 10]
  <br>`MOV     AX,$B800`
* **458** `|` — Turn off output, to avoid clicks.
  <br>`MOV     AL,00001011b    ;`
* **462** `|` — Reset the GUS card.
  <br>`SetGusRegister8  (grReset, 0);          ;`
* **464** `|` — DAC turned off.
  <br>`SetGusRegister8  (grReset, 1);          ;`
* **481** `|` — Decreasing Ramp
  <br>`SetGusRegister8  (grVolumeControl, $40);   ;`
* **485** `|` — DAC turned on.
  <br>`SetGusRegister8  (grReset, 7);          ;`
* **489** `|` — Turn on output
  <br>`MOV     AL,00001100b    ;`
* **834** `>` *(disabled)* — MOV AL,[First] JZ @@nof XOR AL,AL MOV [First],AL SUB DX,2 MOV AL,grCurrentAddrLow+$80 OUT DX,AL INC DX IN AX,DX MOV SI,AX MOV CX,10000 @@lp: IN AX,DX CMP AX,SI JNZ @@nof LOOP @@lp @@nof:
  <br>`MOV     AL,[First]`


## `v1.39b/LIB/HARDWARE.PAS`

* **6** `>` — like the PIC, the DMA controller, etc...
* **50** `>` — PIC routines.
  <br>`PROCEDURE EnableIRQ(i: WORD);`
* **103** `>` — DMA routines.
  <br>`AH = Channel`
* **106** `>` — AH = Channel CH = Mode CL = Page BX = Offset SI = Size
  <br>`AH = Channel`
* **125** `|` — Disable DMA channel.
  <br>`MOV  AL,AH;  ADD  AL,$04; OUT $D4,AL`
* **126** `|` — Clear BYTE POINTER flip-flop to lower byte.
  <br>`XOR  AL,AL;               OUT $D8,AL`
* **127** `|` — DMA Mode register.
  <br>`MOV  AL,AH;  ADD  AL,CH;  OUT $D6,AL`
* **131** `|` — Calculate DMA base port.
  <br>`ADD  DX,DX`
* **134** `|` — Offset of the buffer, low & high bytes.
  <br>`MOV  AL,BL;               OUT  DX,AL`
* **142** `|` — Calculate page register port.
  <br>`ADD  BX,DX`
* **144** `|` — Set DMA page.
  <br>`MOV  AL,CL;               OUT  DX,AL`
* **148** `|` — Calculate DMA counter port.
  <br>`INC  DX`
* **151** `|` — Size of the buffer minus 1, low & high byte.
  <br>`MOV  AL,BL;               OUT  DX,AL`
* **153** `|` — Enable DMA channel.
  <br>`MOV  AL,AH;               OUT $D4,AL`
* **262** `>` — PUSH AX MOV DL,[Debug] PUSH DX MOV DL,1 MOV [Debug],DL PUSH AX PUSH BX PUSH CX PUSH $7 CALL WriteSNum POP BX PUSH BX PUSH $6 CALL WriteSNum POP AX PUSH AX PUSH $4 CALL WriteSNum POP DX MOV [Debug],DL POP AX
  <br>`PUSH    AX`
* **295** `|` *(disabled)* — Get the value that repeats.
  <br>`CMP  SI,DI`


## `v1.39b/LIB/HEAPS.PAS`

* **110** `>` — Functions that handle pointers.
  <br>`FUNCTION IncPtr(P: POINTER; L: LONGINT) : POINTER;`
* **134** `>` — Utilities for initialising and managing heaps.
  <br>`PROCEDURE InitUmbHeap;`
* **203** `>` — THeap object implementation.
  <br>`CONSTRUCTOR THeap.Init(Buffer: POINTER; Size: LONGINT);`
* **360** `>` — TUmbHeap object implementation.
  <br>`CONSTRUCTOR TUmbHeap.Init;`
* **386** `>` — THeapColl object implementation.
  <br>`CONSTRUCTOR THeapColl.Init;`
* **544** `>` — Normal Heap variables initialisation and deinitialisation. Looking for
  <br>`PROCEDURE InitHeapVariables;`
* **545** `>` — every tiny bit of memory available.
  <br>`PROCEDURE InitHeapVariables;`


## `v1.39b/LIB/MODCOMMA.PAS`

* **6** `>` — various commands that appear in a MOD file`s partiture
* **8** `>` — It's independent of the number of channels used.
* **10** `>` — Designed for use from within the PlayMod UNIT.
* **17** `>` — PlayMod UNIT, but it was getting too big.
  <br>`UNIT ModCommands;`
* **35** `|` — TRUE if the partiture is allowed to change the filter.
  <br>`PermitFilterChange : BOOLEAN       = FALSE;`
* **49** `>` — Values common to all the channels.
  <br>`CONST`
* **52** `|` — Position of the filter (FALSE = OFF).
  <br>`FilterIsOn         : BOOLEAN       = FALSE;`
* **53** `|` — Number of ticks in the current note.
  <br>`Tempo              : BYTE          = 6;`
* **58** `>` — Values set from outside this UNIT, apart from this one.
  <br>`CONST`
* **61** `|` — Next note in the pattern.
  <br>`NextNote           : WORD          = 1;`
* **62** `|` — Next pattern index (for the next note).
  <br>`NextSeq            : WORD          = 1;`
* **63** `>` — They both must have been set BEFORE calling this UNIT.
  <br>`TempoCt            : BYTE          = 0;      { Number of the actual tick. Not changed in this UNIT. `
* **65** `|` — Number of the actual tick. Not changed in this UNIT.
  <br>`TempoCt            : BYTE          = 0;`
* **70** `>` — General definition of the state of a channel.
  <br>`TYPE                       { Channel state definition. }`
* **72** `|` — Channel state definition.
  <br>`TYPE`
* **75** `|` — Note being played in the channel.
  <br>`Note       : TFullNote;`
* **76** `|` — Pointer to the instrument data.
  <br>`Instrument : PInstrumentRec;`
* **79** `|` — Actual adjusted Period.
  <br>`RealPeriod : WORD;`
* **81** `|` — Note portamento increment.
  <br>`PeriodIncr,`
* **82** `|` — Note portamento destination.
  <br>`PeriodDest : INTEGER;`
* **84** `|` — Arpeggio count.
  <br>`arpct      : BYTE;`
* **85** `|` — Arpeggio 1st Period.
  <br>`arp0,`
* **86** `|` — Arpeggio 2nd Period.
  <br>`arp1,`
* **87** `|` — Arpeggio 3rd Period.
  <br>`arp2       : WORD;`
* **89** `|` — Vibrato wave form.
  <br>`VibWave,`
* **90** `|` — Vibrato position.
  <br>`VibPos,`
* **91** `|` — Vibrato width (period).
  <br>`VibWidth,`
* **92** `|` — Vibrato depth (amplitude).
  <br>`VibDepth   : BYTE;`
* **95** `|` — Tone portamento increment.
  <br>`TPortaIncr : INTEGER;`
* **127** `>` — Command routines, for the start of a note and for each tick.
  <br>*es:* Rutinas de comandos, para el comienzo y cada Tick.
* **129** `>` — The tick routines are entered with SI pointing at the relevant TCanal.
  <br>*es:* En las del tick, se entra con SI apuntando al TCanal correspondiente.
* **217** `>` — JNC @@c XOR AX,AX @@c:
  <br>`JNC     @@c`
* **222** `>` — JC @@c2 CMP AX,$39 JA @@c1 @@c2:MOV AX,$39 @@c1:
  <br>`JC      @@c2`
* **240** `>` — CMP AX,$6B0 JB @@c1 MOV AX,$6B0 @@c1:
  <br>`CMP     AX,$6B0`
* **325** `|` — Sinus table for the vibrato.
  <br>`VibTabla : ARRAY[0..31] OF BYTE = (`
* **637** `>` — E Ax y E Bx
  <br>`PROCEDURE StartVolFineUp(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);`


## `v1.39b/LIB/MODLOADE.PAS`

* **23** `>` — Internal definitions. Format of the files.
  <br>`TYPE`
* **37** `>` — Instrument in a MOD file. 30 bytes.
  <br>`TModFileInstrument = RECORD`
* **40** `|` — AsciiZ string, name of the instrument.
  <br>`Name       : ARRAY [1..22] OF CHAR;`
* **41** `|` — Length of the sample DIV 2.
  <br>`Len        : WORD;`
* **42** `|` — Fine tuning value.
  <br>`FineTune,`
* **43** `|` — Default volume.
  <br>`Vol        : BYTE;`
* **44** `|` — Offset of the loop DIV 2.
  <br>`LoopStart,`
* **45** `|` — Length of the loop DIV 2.
  <br>`LoopLen    : WORD;`
* **48** `>` — Note in the file. 4 bytes.
  <br>`PModFileNote = ^TModFileNote;`
* **69** `>` — 15 samples module header format. 600 bytes.
  <br>`PModFile15 = ^TModFile15;`
* **73** `|` — AsciiZ song name.
  <br>`Name        : ARRAY [1..20] OF CHAR;`
* **75** `|` — Length of the sequency of the song.
  <br>`SongLen     : BYTE;`
* **76** `|` — Song loop start position.
  <br>`SongRep     : BYTE;`
* **80** `>` — 31 samples module header format. 1084 bytes.
  <br>`PModFile31 = ^TModFile31;`
* **89** `|` — Magic number ("M.K.", "FLT4", etc.)
  <br>`Magic       : TModFileMagic;`
* **329** `>` — Initial checkings to see if it's a real MOD.
  <br>`Song.Status := msFileDamaged;`
* **348** `>` — Processing of the header
  <br>`Song.Status := msOK;`
* **370** `>` — Processing of the patterns (the partiture)
  <br>`ProcessPatterns(Song, St, NumberOfPatterns);`
* **376** `>` — Processing of the instruments
  <br>`ProcessInstruments(Song, St, Mod31);`


## `v1.39b/LIB/PLAYMOD.PAS`

* **6** `>` — device supported in the SoundDevices sound system.
* **9** `>` — StopMod To stop playing the MOD.
* **12** `>` — Luis Crespo (parts extracted from the JAMP 1.5 MOD Player)
* **17** `>` — Internal cleaning, which was quite needed.
* **18** `>` — UnCanal routine made even faster.
* **20** `>` — enhancements since June, but they weren't
* **21** `>` — documented. Mainly more speed-ups.
* **41** `|` — Volume set (all channels).
  <br>`TVolumes  = ARRAY[1..MaxChannels] OF BYTE;`
* **46** `>` — General definitions about the way of playing the music.
  <br>`CONST`
* **47** `>` — Music player configuration.
  <br>`CONST`
* **51** `|` — TRUE if music can be played forever.
  <br>`LoopMod            : BOOLEAN       = TRUE;`
* **52** `|` — TRUE if music must be played forever.
  <br>`ForceLoopMod       : BOOLEAN       = FALSE;`
* **53** `|` — TRUE if fall-back is allowed.
  <br>`CanFallBack        : BOOLEAN       = TRUE;`
* **54** `|` — Initial value of the ON filter.
  <br>`FilterOn           : TFilterMethod = fmNone;`
* **55** `|` — Initial value of the OFF filter.
  <br>`FilterOff          : TFilterMethod = fmNone;`
* **56** `|` — Initial position of the filter (FALSE = OFF).
  <br>`FilterIsOn         : BOOLEAN       = FALSE;`
* **57** `|` — Maximum frequency of the output sound.
  <br>`MaxOutputFreq      : WORD          = 45000;`
* **58** `>` — Less means less memory for buffers.
  <br>`DontExecute        : BOOLEAN       = FALSE;`
* **66** `>` — Exported variables.
  <br>`CONST`
* **69** `|` — (Read only) TRUE if the music is sounding right now.
  <br>`Playing          : BOOLEAN = FALSE;`
* **73** `|` — Desired freq. of the sound.
  <br>`ActualHz        : WORD;`
* **74** `|` — Freq. to be used in the current tick.
  <br>`NoteHz          : WORD;`
* **76** `|` — Channel volumes.
  <br>`UserVols        : TVolumes;`
* **77** `|` — Permissions for playing the channels.
  <br>`Permisos        : ARRAY[1..MaxChannels] OF BOOLEAN;`
* **78** `|` — Ticks counter. Increments each tick.
  <br>`TickCount       : WORD;`
* **80** `|` — Actual permission to fall-back.
  <br>`MyCanFallBack   : BOOLEAN;`
* **81** `|` — Method of the filter to be used.
  <br>`FilterVal       : TFilterMethod;`
* **84** `>` — Definition of the local stack.
  <br>`CONST`
* **87** `|` — Size of the stack.
  <br>`PlayModStackSize = 500;`
* **93** `>` — Definitions concerning a note. Buffer of the last N notes.
  <br>`TYPE`
* **98** `|` — TRUE if it is the note following the last.
  <br>`EoMod       : BOOLEAN;`
* **99** `|` — Number of ticks the note will last.
  <br>`Tempo       : BYTE;`
* **100** `|` — Index of the note inside the pattern.
  <br>`NotePlaying : BYTE;`
* **101** `|` — Sequence number of the pattern to which the note belongs.
  <br>`SeqPlaying  : BYTE;`
* **102** `|` — Volumes of the channels.
  <br>`Volume      : TVolumes;`
* **103** `|` — Notes of the channels.
  <br>`Note        : ARRAY[1..MaxChannels] OF TFullNote;`
* **104** `|` — Number of samples processed for each note.
  <br>`NMuestras   : WORD;`
* **105** `|` — To make it a 32-byte record.
  <br>`fill        : BYTE;`
* **109** `|` — Number of note buffers.
  <br>`NoteBuffSize = 1;`
* **122** `|` — State of the channels.
  <br>`Canales : ARRAY[1..MaxChannels] OF TCanal;`
* **128** `>` — Definition of the buffers where the samples are placed.
  <br>`CONST`
* **132** `|` — Maximum samples in the buffer. Means maximum samples per tick.
  <br>`MaxSplPerTick : WORD = 880;`
* **133** `|` — Number of buffers.
  <br>`NumBuffers           = 3;`
* **136** `|` — Tail of the buffer.
  <br>`BuffIdx,`
* **137** `|` — Head of the buffer.
  <br>`BuffGive : WORD;`
* **145** `>` — Exported procedures.
  <br>`PROCEDURE PlayStart(VAR Song: TSong);`
* **171** `>` — General definitions of the module player. They define its actual state.
  <br>`VAR`
* **175** `|` — TRUE means it couldn't fill the samples buffer.
  <br>`DelaySamples    : BOOLEAN;`
* **176** `|` — Number of samples that there are in a tick at the actual freq.
  <br>`MuestrasPerTick : WORD;`
* **181** `>` — Raw channel definitions.
  <br>`TYPE`
* **187** `|` — Channel flags (see below).
  <br>`Flags      : BYTE;`
* **189** `|` — Position fraction.
  <br>`SplPosFrac : WORD;`
* **190** `|` — Position offset.
  <br>`SplPosInt  : WORD;`
* **191** `|` — Position segment.
  <br>`SplPosSeg  : WORD;`
* **193** `|` — Actual sample part offset.
  <br>`SplOfs     : WORD;`
* **194** `|` — Actual sample part segment.
  <br>`SplSeg     : WORD;`
* **195** `|` — Actual sample part size.
  <br>`SplLimit   : WORD;`
* **197** `|` — First sample part offset.
  <br>`SplOfs1    : WORD;`
* **198** `|` — First sample part segment.
  <br>`SplSeg1    : WORD;`
* **199** `|` — First sample part size.
  <br>`SplLimit1  : WORD;`
* **201** `|` — Second sample part offset.
  <br>`SplOfs2    : WORD;`
* **202** `|` — Second sample part segment.
  <br>`SplSeg2    : WORD;`
* **203** `|` — Second sample part size.
  <br>`SplLimit2  : WORD;`
* **205** `|` — Sample incement fraction.
  <br>`StepFrac   : WORD;`
* **206** `|` — Sample incement integer.
  <br>`StepInt    : WORD;`
* **208** `|` — Volume to be used.
  <br>`Volume     : BYTE;`
* **210** `|` — Offset of the end of the loop in its part.
  <br>`LoopEnd    : WORD;`
* **211** `|` — Size of the loop in its part.
  <br>`LoopLen    : WORD;`
* **214** `|` — TModRawChan.Flags
  <br>`CONST`
* **215** `|` — Set if it's a long (more than 65520 bytes) sample.
  <br>`rcfLongSample     = $01;`
* **216** `|` — Set if the channel is activated (permission to sound).
  <br>`rcfActiveChannel  = $02;`
* **217** `|` — Set of the sample has a loop.
  <br>`rcfDoesLoop       = $04;`
* **218** `|` — Set if playing the 2nd part of the long loop.
  <br>`rcfPlaying2nd     = $08;`
* **219** `|` — Loop size goes from the 2nd part to the 1st.
  <br>`rcfLongLoopLen    = $10;`
* **220** `|` — Loop ends in the 2nd part.
  <br>`rcfLongLoopEnd    = $20;`
* **221** `|` — Set if the sample has already finished.
  <br>`rcfSampleFinished = $40;`
* **223** `|` — Raw channels.
  <br>`VAR`
* **230** `>` — Basic, fast assembler routines.
* **257** `|` — AND ( Raw.Volume <> 0)
  <br>`((Raw.Flags  AND rcfSampleFinished) =  0)`
* **258** `|` — AND FALSE
  <br>`( Raw.Volume                        <> 0) }`
* **304** `>` *(disabled)* — Fills a buffer with 8 bit samples, calculated from a sample, a freq. and
* **305** `>` *(disabled)* — a volume (a RawChannel).
* **306** `>` *(disabled)* — Implemented as several specialised routines, for speed's sake.
* **307** `>` *(disabled)* — It doesn't play long samples yet.
* **308** `>` *(disabled)* — This routine self-modifies, for speed's sake.
* **310** `>` *(disabled)* — IN: CX = Number of samples.
* **311** `>` *(disabled)* — BX = Offset of the channel data (TModRawChan).
* **312** `>` *(disabled)* — DI = Offset of the buffer to be filled.
* **314** `>` *(disabled)* — OUT: The buffer will have been filled.
* **316** `>` *(disabled)* — MODIFIES: Every register except DS.
  <br>`PROCEDURE UnCanal; ASSEMBLER;`
* **329** `|` *(disabled)* — Is the channel active?
  <br>*es:* ¿Active channel?
  <br>`TEST    [TModRawChan(DS:BX).Flags],rcfActiveChannel`
* **330** `|` *(disabled)* — If not -> do the silent loop
  <br>`JZ      @@Desactivado`
* **332** `|` *(disabled)* — Has it already finished?
  <br>*es:* ¿Already finished?
  <br>`TEST    [TModRawChan(DS:BX).Flags],rcfSampleFinished`
* **333** `|` *(disabled)* — If it is -> do the silent loop
  <br>`JNZ     @@Desactivado`
* **338** `|` *(disabled)* — BX is saved for restoring data at the end
  <br>`PUSH    BX`
* **340** `|` *(disabled)* — Does the sample have a loop?
  <br>*es:* ¿Does the sample have a loop?
  <br>`TEST    [TModRawChan(DS:BX).Flags],rcfDoesLoop`
* **341** `|` *(disabled)* — If not -> do the loop-less routine
  <br>`JZ      @@NoDoesLoop`
* **343** `>` *(disabled)* — Sample with a loop (it doesn't check the end of the sample).
  <br>`Sample with a loop (it doesn't check the end of the sample).`
* **350** `|` *(disabled)* — Puts the loop-end OFFSET in its instruction
  <br>`MOV     WORD PTR [CS:@@dlData2-2],AX`
* **353** `|` *(disabled)* — Puts the loop-size in its instruction
  <br>`MOV     WORD PTR [CS:@@dlData3-2],AX`
* **356** `|` *(disabled)* — Increment fraction
  <br>`MOV     AL,[TModRawChan(DS:BX).StepFrac]`
* **357** `|` *(disabled)* — Increment integer
  <br>`MOV     BP,[TModRawChan(DS:BX).StepInt]`
* **359** `|` *(disabled)* — Position OFFSET
  <br>`MOV     AH,[TModRawChan(DS:BX).SplPosFrac]`
* **361** `|` *(disabled)* — Pointer to the next sample to be read
  <br>`LDS     SI,DWORD PTR [TModRawChan(DS:BX).SplPosInt]`
* **363** `|` *(disabled)* — DO NOT TOUCH!!! (BX is the pointer to the buffer)
  <br>*es:* ¡¡¡No tocar!!! (BX es el puntero al buffer)
  <br>`MOV     BX,AX`
* **364** `>` *(disabled)* — The loop. Entered with: DL = volume, BL = fractional part of the increment, BP = integer part of the increment, BH = fractional part of the position within the sample, SI = integer part of the position within the sample, ES = segment of the buffer, DI = offset within the buffer, CX = number of samples to produce.
  <br>*es:* Bucle. Se entra con: DL = Volumen BL = Parte fraccionaria del incremento. BP = Parte entera del incremento. BH = Parte fraccionaria de la posición en el sample. SI = Parte entera de la posición en el sample. ES = Segmento del buffer. DS = Segmento del sample. DI = Buffer donde se almacenan las muestras. CX = Número total de muestras a generar.
  <br>`Bucle. Se entra con:`
* **380** `|` *(disabled)* — Read the sample for this position
  <br>*es:* Leo la muestra correspondiente
  <br>`MOV     AL,[SI]`
* **381** `|` *(disabled)* — Multiply by the volume
  <br>*es:* Multiplico por el volumen
  <br>`IMUL    DL`
* **382** `|` *(disabled)* — Store it in the buffer (SELF-MODIFYING INSTRUCTION)
  <br>*es:* Lo meto en el buffer (Instrucción automodificada)
  <br>`MOV     [ES:DI],AX`
* **386** `|` *(disabled)* — Add the fractional increment
  <br>*es:* Añade el incremento fraccionario
  <br>`ADD     BH,BL`
* **387** `|` *(disabled)* — Add the integer increment
  <br>*es:* Añade el incremento entero
  <br>`ADC     SI,BP`
* **388** `|` *(disabled)* — Carry means it has certainly passed the limit
  <br>*es:* Carry -> Ha pasado el límite, seguro
  <br>`JC      @@dlSplLoop`
* **389** `>` *(disabled)* — (maximum number of samples = 65520)
  <br>*es:* (máximo nº de muestras = 65520)
  <br>`@@dlChkLoop:`
* **391** `|` *(disabled)* — CMP BP,[TModRawChan(DS:BX).LoopEnd]
  <br>`CMP     SI,$1234`
* **392** `|` *(disabled)* — Have I reached the loop's return point?
  <br>*es:* ¿He llegado al pto. de retorno del loop?
  <br>`@@dlData2:`
* **396** `|` *(disabled)* — SUB BP,[TModRawChan(DS:BX).LoopLen]
  <br>`SUB     SI,$1234`
* **397** `|` *(disabled)* — If so, go back. Doing this is very important
  <br>*es:* Si es así, vuelvo para atrás. Esto es muy importante hacerlo
  <br>`@@dlData3:`
* **398** `>` *(disabled)* — by subtracting the loop length and keeping the fractional part.
  <br>*es:* restando el tamaño del bucle, y conservando la parte frac.
  <br>`@@dlNoLoop:`
* **401** `|` *(disabled)* — Y fin del bucle
  <br>`LOOP    @@dlLoop`
* **403** `|` *(disabled)* — Jump to the end, where the values are stored for where
  <br>*es:* Salta al final, donde se almacenan los valores de por donde
  <br>`JMP     @@Finish`
* **404** `>` *(disabled)* — the pointers and the rest ended up
  <br>*es:* han quedado los punteros y demás
  <br>`Sample sin loop (no comprueba el fin de loop).`
* **406** `>` *(disabled)* — Sample with no loop (does not test for the loop end). Same idea as above.
  <br>*es:* Sample sin loop (no comprueba el fin de loop). Filosofía igual al anterior.
  <br>`Sample sin loop (no comprueba el fin de loop).`
* **415** `|` *(disabled)* — Put the OFFSET of the sample's end into the instruction
  <br>*es:* Pone el OFFSET del fin del sample en la instrucción
  <br>`MOV     AX,[TModRawChan(DS:BX).SplLimit]`
* **419** `|` *(disabled)* — Parte fraccionaria del incremento
  <br>`MOV     AL,[TModRawChan(DS:BX).StepFrac]`
* **420** `|` *(disabled)* — Fractional part of the OFFSET of the sample pointer
  <br>*es:* Parte fraccionaria del OFFSET del puntero a la muestra
  <br>`MOV     AH,[TModRawChan(DS:BX).SplPosFrac]`
* **422** `|` *(disabled)* — Parte entera del incremento
  <br>`MOV     BP,[TModRawChan(DS:BX).StepInt]`
* **424** `|` *(disabled)* — Pointer to the next sample to read
  <br>*es:* Puntero a la próxima muestra a leer
  <br>`LDS     SI,DWORD PTR [TModRawChan(DS:BX).SplPosInt]`
* **446** `|` *(disabled)* — Store it in the buffer
  <br>*es:* Lo meto en el buffer
  <br>`MOV     [ES:DI],AX`
* **452** `|` *(disabled)* — Carry means it has certainly passed the sample's limit
  <br>*es:* Carry -> Ha pasado el límite del sample, seguro
  <br>`JC      @@nlSeguroFin`
* **455** `|` *(disabled)* — CMP BP,[TModRawChan(DS:BX).SplLimit]
  <br>`CMP     SI,$1234`
* **456** `|` *(disabled)* — Have I reached the end of the sample?
  <br>*es:* ¿He llegado al final del sample?
  <br>`@@nlData2:`
* **457** `|` *(disabled)* — If so, stop calculating
  <br>*es:* Si es así, dejo de calcular
  <br>`JNB     @@nlSeguroFin`
* **465** `|` *(disabled)* — Se ha terminado el sample
  <br>`@@nlSeguroFin:`
* **466** `|` *(disabled)* — Reinicializamos DS
  <br>`MOV     BX,SEG @Data`
* **468** `|` *(disabled)* — Recupera el TModRawChan en BX
  <br>`POP     BX`
* **469** `|` *(disabled)* — Switch the channel off
  <br>*es:* Desactivo el canal
  <br>`OR      BYTE PTR [TModRawChan(DS:BX).Flags],rcfSampleFinished`
* **470** `|` *(disabled)* — Decrement the sample count; it could not be done earlier
  <br>*es:* Decrementa el número de muestras, no se ha podido hacer antes
  <br>`DEC     CX`
* **471** `|` *(disabled)* — If there are no more left, we are done
  <br>*es:* Si ya no hay más -> bye
  <br>`JCXZ    @@Fin`
* **473** `>` *(disabled)* — The loop for an empty sample. It cannot be removed, because it has to at least fill the buffer with zeros.
  <br>*es:* Bucle correspondiente a un sample vacío. No se puede eliminar porque tiene que, por lo menos, poner el buffer a cero.
  <br>`Bucle correspondiente a un sample vacío. No se puede eliminar`
* **481** `|` *(disabled)* — Todas las muestras a cero
  <br>`XOR     AX,AX`
* **483** `|` *(disabled)* — Store the zero in the buffer
  <br>*es:* Le meto el cero en el buffer
  <br>`MOV     [ES:DI],AX`
* **486** `|` *(disabled)* — Fin del bucle
  <br>`LOOP    @@Data2`
* **488** `|` *(disabled)* — And return without restoring anything
  <br>*es:* Y me vuelvo sin restaurar nada
  <br>`JMP     @@Fin`
* **499** `|` *(disabled)* — Recupero el TModRawChan
  <br>`POP     BP`
* **500** `|` *(disabled)* — And save the OFFSET of the sample where it stopped
  <br>*es:* Y guardo el OFFSET del sample donde se ha quedado
  <br>`MOV     [TModRawChan(DS:BP).SplPosInt],SI`
* **513** `>` — Routines that interpret the score.
  <br>*es:* Rutinas que se dedican a interpretar la partitura.
* **523** `>` — Start a new sample on one of the channels.
  <br>*es:* Inicializa un nuevo sample en uno de los canales.
* **526** `>` — Spl : TSample correspondinte al canal.
* **549** `|` — Set up the minimum values
  <br>*es:* Inicializa los valores mínimos
  <br>`MOV     TModRawChan([DI]).SplSeg1,AX`
* **560** `|` — If it has a loop (not sure this test is a good one
  <br>*es:* Si tiene loop (no sé si es buena la comprobación
  <br>`@@1:    MOV     f,0`
* **579** `|` — Comes here if it is a long sample (more than 65520 bytes)
  <br>*es:* Entra aquí si es un sample largo (mayor de 65520 bytes)
  <br>`MOV     DI,WORD PTR Raw`
* **592** `|` — Set up the values for the long sample
  <br>*es:* Inicializa valores para el sample largo
  <br>`Raw.SplLimit2 := Spl^.len - MaxSample;`
* **596** `|` — If there is a loop, a small mess :-)
  <br>*es:* Si hay loop, pequeño lío :-)
  <br>`IF NOT f THEN BEGIN`
* **614** `|` — Comes here if it is a short sample (less than 65520 bytes)
  <br>*es:* Entra aquí si es un sample pequeño (menor de 65520 bytes)
  <br>`MOV     DI,WORD PTR Raw`
* **627** `>` — MOV TModRawChan([DI]).SplLimit1,AX
  <br>`@@1:`
* **789** `>` — PROCEDIMIENTO: ProcessNewNote
* **791** `>` — Work out and process the next note of the score.
  <br>*es:* Calcula y procesa la siguiente nota de la partitura.
* **1012** `>` — PROCEDIMIENTO: ProcessTick
* **1014** `>` — Process one tick of the music. Normally 50 ticks per second are used,
  <br>*es:* Procesa un tick de la música. Normalmente, se usan 50 ticks por segundo,
* **1015** `>` — pero puede cambiarse.
* **1186** `|` — (LONGINT(256)*13900) DIV Can^.RealPeriod,
  <br>`$FFFFFFFF,`
* **1204** `>` — PROCEDIMIENTO: ProcessTickEntry
* **1206** `>` — Entrada desde ensamblador de ProcessTick.
* **1480** `>` — WHILE DeviceIdling AND (NOT KbdKeyPressed) DO;
  <br>`WHILE DeviceIdling AND (NOT KbdKeyPressed) DO;`
* **1532** `>` — WHILE (NOT DeviceIdling) AND (NOT KbdKeyPressed) DO;
  <br>`WHILE (NOT DeviceIdling) AND (NOT KbdKeyPressed) DO;`


## `v1.39b/LIB/S3MLOADE.PAS`

* **24** `>` — Internal definitions. Format of the files.
  <br>`TYPE`
* **495** `|` — (Hdr.Magic1 <> S3mMagic1) OR
  <br>`IF`
* **522** `|` — Hdr.NPI1 + 1;
  <br>`Song.SequenceRepStart := 0;`
* **543** `>` — Processing of the patterns (the partiture)
  <br>`ProcessPatterns(Song, St, InstrFlags, PattOfs, Hdr.NPatts, TRUE, $FF);`
* **549** `>` — Processing of the instruments
  <br>`ProcessInstruments(Song, St, InstrFlags, InstrOfs, Hdr.NInstruments, TRUE, $FF);`


## `v1.39b/LIB/SONGELEM.PAS`

* **11** `>` — Definitions for handling the format of individual notes.
* **12** `>` — Notes are composed of four fields:
* **14** `>` — Period: A number in the range 0..2047 which states the period of
* **15** `>` — the note in units of 1/3584000 per sample. (this is a
* **16** `>` — somewhat empyric number. If anyone knows the exact Amiga
* **17** `>` — number, please, tell us). A zero means to keep using the
* **18** `>` — same period used before.
* **19** `>` — Instrument: A number in range 0..63 meaning the number of the instrument
* **20** `>` — which will be used for the note. A zero means use the same.
* **21** `>` — Command: A number (no real range) of the way the note should be
* **22** `>` — played (i.e. Vibrato) a change in the playing sequence (i.e.
* **23** `>` — pattern break) or a change in the general parameters of the
* **24** `>` — module player (i.e. set tempo). All the possible values are
* **25** `>` — defined in the TModCommand enumerated type below.
* **26** `>` — Parameter: A parameter for the command. Its meaning differs from one
  <br>`TYPE`
* **27** `>` — command to another. Sometimes each nibble is considered as a
  <br>`TYPE`
* **28** `>` — different parameter.
  <br>`TYPE`
* **33** `|` — Just play the note, without any special option.
  <br>`mcNone,       { 0 00 }`
* **35** `|` — Rotate through three notes rapidly.
  <br>`mcArpeggio,   { 0 xy }`
* **36** `|` — Tone Portamento Up: Gradual change of tone towards high frequencies.
  <br>`mcTPortUp,    { 1 xx }`
* **37** `|` — Tone Portamento Down: Gradual change of tone towards low frequencies.
  <br>`mcTPortDown,  { 2 xx }`
* **38** `|` — Note Portamento: Gradual change of tone towards a given note.
  <br>`mcNPortamento,{ 3 xy }`
* **39** `|` — Vibrato: Frequency changes around the note.
  <br>`mcVibrato,    { 4 xy }`
* **40** `|` — Tone Port. Up + Volume slide: Parameter means vol. slide.
  <br>`mcT_VSlide,   { 5 xy }`
* **41** `|` — Vibrato + Volume slide: Parameter means vol. slide.
  <br>`mcVib_VSlide, { 6 xy }`
* **42** `|` — Tremolo: I don't know for sure. Fast volume variations, I think.
  <br>`mcTremolo,    { 7 xy }`
* **43** `|` — Do Nothing (as far as I know).
  <br>`mcNPI1,       { 8 xx }`
* **44** `|` — Start the sample from the middle.
  <br>`mcSampleOffs, { 9 xx }`
* **45** `|` — Volume slide: Gradual change in volume.
  <br>`mcVolSlide,   { A xy }`
* **46** `|` — End pattern and continue from a different pattern sequence position.
  <br>`mcJumpPattern,{ B xx }`
* **47** `|` — Set the volume of the sound.
  <br>`mcSetVolume,  { C xx }`
* **48** `|` — Continue at the start of the next pattern.
  <br>`mcEndPattern, { D xx }`
* **49** `|` — Extended set of commands (ProTracker).
  <br>`mcExtended,   { E xy }`
* **50** `|` — Set the tempo of the music, in 1/50ths of a second.
  <br>`mcSetTempo,   { F xx }`
* **52** `|` — Set the output filter to the on or off value.
  <br>`mcSetFilter,  { E 0x }`
* **53** `|` — Like TPortUp, but slower.
  <br>`mcFinePortaUp,{ E 1x }`
* **54** `|` — Like TPortDown, but slower.
  <br>`mcFinePortaDn,{ E 2x }`
* **56** `|` — Set the vibrato waveform.
  <br>`mcVibCtrl,    { E 4x }`
* **57** `|` — Fine tune the frequency of the sound.
  <br>`mcFineTune,   { E 5x }`
* **58** `|` — Make a loop inside a pattern.
  <br>`mcJumpLoop,   { E 6x }`
* **59** `|` — Set the tremolo waveform (I think).
  <br>`mcTremCtrl,   { E 7x }`
* **62** `|` — Like VolSlide, but slower and towards high frequencies.
  <br>`mcVolFineUp,  { E Ax }`
* **63** `|` — Like VolSlide, but slower and towards low frequencies.
  <br>`mcVolFineDown,{ E Bx }`
* **65** `|` — Wait a little before starting note.
  <br>`mcNoteDelay,  { E Dx }`
* **67** `|` — No idea, but sounds funny.
  <br>`mcFunkIt,     { E Fx }`
* **69** `|` — Oktalizer arpeggio
  <br>`mcOktArp,     {      }`
* **70** `|` — Oktalizer arpeggio2
  <br>`mcOktArp2,    {      }`
* **107** `>` — Definitions for handling the instruments used in the module.
* **108** `>` — Instruments are fragments of sampled sound (long arrays of bytes which
* **109** `>` — describe the wave of the sound of the instrument). The samples used in
  <br>`CONST`
* **110** `>` — music modules have a default volume and also, they can have a loop (for
  <br>`CONST`
* **111** `>` — sustained instruments) and a fine tuning constant (not yet implemented).
  <br>`CONST`
* **122** `|` — Set if the instrument is played always at the same freq (not implemented).
  <br>`ipMonoFreq = $0001;`
* **123** `|` — Set if the instrument's sample is longer than 65520 bytes.
  <br>`ipLong     = $0002;`
* **129** `|` — Properties of the instrument.
  <br>`TIProperties = WORD;`
* **134** `|` — Length of the instrument's sampled image.
  <br>`Len,`
* **135** `|` — Starting offset of the repeated portion.
  <br>`Reps,`
* **136** `|` — Size of the repeated portion.
  <br>`Repl  : LONGINT;`
* **137** `|` — Default volume of the instrument (0..64)
  <br>`Vol   : BYTE;`
* **138** `|` — Fine tuning value for the instrument (not yet implemented).
  <br>`Ftune : BYTE;`
* **139** `|` — Numerator of note adjutment.
  <br>`NAdj  : WORD;`
* **140** `|` — Denominator of note adjutment.
  <br>`DAdj  : WORD;`
* **141** `|` — Pointer to the first 65520 bytes of the sample.
  <br>`Data  : ^TSample;`
* **142** `|` — Pointer to the second 65520 bytes of the sample (if there is such).
  <br>`Xtra  : ^TSample;`
* **143** `|` — Bit mapped properties value.
  <br>`Prop  : TIProperties;`
* **168** `>` — Definitions for handling the tracks of which patterns are built.
  <br>`TYPE`
* **169** `>` — Tracks are lists of notes and command values of which the empty leading
  <br>`TYPE`
* **170** `>` — and trailing blanks have been removed (obviated).
  <br>`TYPE`
* **231** `>` — Definitions for handling the format of the patterns.
* **232** `>` — Patterns are arrays of pointers to tracks (up to 12 tracks).
* **233** `>` — A music module can have up to 255 individual patterns, arranged in a
  <br>`CONST`
* **234** `>` — sequence of up to 255.
  <br>`CONST`
* **235** `>` — Empty patterns are not counted.
  <br>`CONST`
* **276** `>` — General definitions for the song.
  <br>`TYPE`
* **293** `>` — TInstrument object implementation.
  <br>`CONST`
* **479** `>` — TTrack object implementation.
  <br>`CONSTRUCTOR TTrack.Init;`
* **605** `>` — TPattern object implementation.
  <br>`CONSTRUCTOR TPattern.Init(Chans: WORD);`


## `v1.39b/LIB/SONGUNIT.PAS`

* **6** `>` — data types and different file formats of a song. Also, it
* **7** `>` — implements the base routines for loading the song from many
* **8** `>` — different file formats and (future) saving them to disk.
* **16** `>` — xx-Jun-1992 Lots of improvements (ditto O;-).
* **21** `>` — oriented interface. Name change from ModUnit.
  <br>`UNIT SongUnit;`
* **38** `>` — Song object definition.
  <br>`TYPE`
* **47** `|` — SoundTracker 15-instrument module.
  <br>`mffMod15        ,`
* **48** `|` — JMPlayer module.
  <br>`mffJMPlayer     ,`
* **49** `|` — 8 voices Oktalizer MOD. (.OKT)
  <br>`mffOktalizer    ,`
* **51** `|` — 8 voices Grave. (.WOW)
  <br>`mffWow8         ,`
* **52** `|` — 6 or 8 voices Triton FastTracker. (.MOD)
  <br>`mffFastTracker  ,`
* **54** `|` — ScreamTracker 3.0 (beta) (.S2M)
  <br>`mffS2m          ,`
* **60** `>` — Non fatal states
  <br>`msNotLoaded              ,    { Not yet loaded                                         }`
* **63** `|` — Everything was Ok.
  <br>`msOK                     ,`
* **64** `|` — End of file premature (lot's of modules have this).
  <br>`msFileTooShort           ,`
* **66** `>` — Fatal states
  <br>`msFileOpenError          ,    { Could not open the .MOD file.                          }`
* **68** `|` — Could not open the .MOD file.
  <br>`msFileOpenError          ,`
* **69** `|` — There is not enough memory left. :-( Shouldn't happen.
  <br>`msOutOfMemory            ,`
* **70** `|` — Syntax checking error on module file.
  <br>`msFileDamaged            ,`
* **71** `|` — JMPlayer or ScreamTracker, for example.
  <br>`msFileFormatNotSupported`
* **82** `>` — Desired data
  <br>`SongStart             : WORD;`
* **87** `>` — General song data
  <br>`Name                  : PString;`
* **102** `>` — Instrument data
  <br>`Instruments           : TCollection;`
* **106** `>` — Pattern sequence data
  <br>`SequenceLength        : WORD;`
* **115** `>` — Track data
  <br>`Tracks                : TCollection;`
* **119** `>` — State data
  <br>`Status                : TSongStatus;`
* **163** `>` — Header definition for the loaders.
  <br>`TYPE`
* **187** `>` — Loaders definition.
  <br>`TYPE`
* **212** `>` — TSong object.
  <br>`CONSTRUCTOR TSong.Init;`


## `v1.39b/LIB/SOUNDBLA.PAS`

* **6** `>` — Sound Blaster and Sound Blaster Pro cards and compatibles.
* **29** `>` — I/O Port offsets.
  <br>`CONST`
* **32** `|` — CM/S 1-6 Data port. Write Only.
  <br>`CMS1DataPortOffset = $00;`
* **33** `|` — CM/S 1-6 Address port. Write Only.
  <br>`CMS1AddrPortOffset = $01;`
* **34** `|` — CM/S 7-12 Data port. Write Only.
  <br>`CMS2DataPortOffset = $02;`
* **35** `|` — CM/S 7-12 Address port. Write Only.
  <br>`CMS2AddrPortOffset = $03;`
* **37** `|` — Mixer register port. Write Only.
  <br>`MixAddrPortOffset  = $04;`
* **38** `|` — Mixer data port. Read/Write.
  <br>`MixDataPortOffset  = $05;`
* **40** `|` — Mono FM Status port. Read Only.
  <br>`FMStatPortOffset   = $08;`
* **41** `|` — Mono FM Address port. Write Only.
  <br>`FMAddrPortOffset   = $08;`
* **42** `|` — Mono FM Data port. Write Only.
  <br>`FMDataPortOffset   = $09;`
* **44** `|` — Left FM Status port. Read Only.
  <br>`LFMStatPortOffset  = $00;`
* **45** `|` — Left FM Address port. Write Only.
  <br>`LFMAddrPortOffset  = $00;`
* **46** `|` — Left FM Data port. Write Only.
  <br>`LFMDataPortOffset  = $01;`
* **48** `|` — Right FM Status port. Read Only.
  <br>`RFMStatPortOffset  = $02;`
* **49** `|` — Right FM Address port. Write Only.
  <br>`RFMAddrPortOffset  = $02;`
* **50** `|` — Right FM Data port. Write Only.
  <br>`RFMDataPortOffset  = $03;`
* **52** `|` — DSP Reset port. Write Only.
  <br>`DSPResetPortOffset = $06;`
* **53** `|` — DSP Read data port. Read Only.
  <br>`DSPReadPortOffset  = $0A;`
* **55** `|` — DSP Write buffer status port. Write Only.
  <br>`DSPWStatPortOffset = $0C;`
* **56** `|` — DSP Write data port. Write Only.
  <br>`DSPWritePortOffset = $0C;`
* **57** `|` — DSP Read buffer status port. Read Only.
  <br>`DSPRStatPortOffset = $0E;`
* **58** `|` — 8 bit DMA IRQ Acknowledge port. Write Only.
  <br>`DSP8AckPortOffset  = $0E;`
* **59** `|` — 16 bit DMA IRQ Acknowledge port. Write Only.
  <br>`DSP16AckPortOffset = $0F;`
* **61** `|` — CD-ROM Data port. Read Only.
  <br>`CDDataPortOffset   = $10;`
* **62** `|` — CD-ROM Command port. Write Only.
  <br>`CDCmdPortOffset    = $10;`
* **63** `|` — CD-ROM Status port. Read Only.
  <br>`CDStatPortOffset   = $11;`
* **64** `|` — CD-ROM Reset port. Write Only.
  <br>`CDResetPortOffset  = $12;`
* **65** `|` — CD-ROM Enable port. Write Only.
  <br>`CDEnablePortOffset = $13;`
* **68** `>` — I/O Ports. Same as above.
  <br>`CONST`
* **110** `|` — Base port. $FFFF Means Autodetect.
  <br>`SbPort       : WORD    = $FFFF;`
* **111** `|` — DMA IRQ level.
  <br>`SbIrq        : WORD    = 7;`
* **112** `|` — DMA channel.
  <br>`SbDMAChan    : WORD    = 1;`
* **113** `|` — Default DSP timeout.
  <br>`SbDefTimeout : WORD    = 5000;`
* **114** `|` — User Desires HS DMA mode if TRUE.
  <br>`SbHiSpeed    : BOOLEAN = TRUE;`
* **115** `|` — Force TRUE the detection of the SB.
  <br>`SbForce      : BOOLEAN = FALSE;`
* **116** `|` — Force TRUE the detection of the Mixer.
  <br>`MixerForce   : BOOLEAN = FALSE;`
* **117** `|` — Force TRUE the detection of the SB Pro.
  <br>`SbProForce   : BOOLEAN = FALSE;`
* **118** `|` — Force TRUE the detection of the SB 16.
  <br>`Sb16Force    : BOOLEAN = FALSE;`
* **121** `>` — Card information.
  <br>`CONST`
* **135** `>` — Run-time information.
  <br>`CONST`
* **146** `|` — Set to FALSE if DSP timeouts.
  <br>`SbWorksOk         : BOOLEAN = TRUE;`
* **147** `|` — Set to the last hi-speed block size.
  <br>`HSBlockSpecified  : WORD    = 0;`
* **148** `|` — Set to the last Sb 16 block size.
  <br>`Sb16BlockSpecified: WORD    = 0;`
* **149** `|` — Stereo DMA mode if TRUE.
  <br>`SbStereo          : BOOLEAN = FALSE;`
* **150** `|` — SB Pro output filter ON if TRUE.
  <br>`SbFilter          : BOOLEAN = FALSE;`
* **152** `|` — Hi speed DMA mode if TRUE.
  <br>`DoHiSpeed         : BOOLEAN = FALSE;`
* **153** `|` — 16 bit output if TRUE.
  <br>`Sb16Bit           : BOOLEAN = FALSE;`
* **165** `>` — DSP Commands.
  <br>`CONST`
* **168** `|` — Send a sample to the DAC directly (mono mode only).
  <br>`sdcSendOneSample  = $10;`
* **169** `|` — Start a low-speed DMA transfer.
  <br>`sdcStartLSpeedDMA = $14;`
* **170** `|` — Set the time constant.
  <br>`sdcSetTimeConst   = $40;`
* **171** `|` — Set hi-speed DMA transfer length.
  <br>`sdcSetHSpeedSize  = $48;`
* **172** `|` — Start a hi-speed DMA transfer.
  <br>`sdcStartHSpeedDMA = $91;`
* **173** `|` — Turn on the SB speaker.
  <br>`sdcTurnOnSpeaker  = $D1;`
* **174** `|` — Turn off the SB speaker.
  <br>`sdcTurnOffSpeaker = $D3;`
* **175** `|` — Get the DSP version number.
  <br>`sdcGetDSPVersion  = $E1;`
* **176** `|` — Get the card copyright string.
  <br>`sdcGetCopyright   = $E3;`
* **179** `>` — Mixer registers.
  <br>`CONST`
* **193** `>` — Bit masks for the mixer registers.
  <br>`CONST`
* **284** `>` — Sound Blaster basic routines.
  <br>`FUNCTION SbReset : BOOLEAN;`
* **380** `>` — MOV DX,[DSPLifePort] IN AL,DX MOV AX,t PUSH AX CALL SbReadLoop
  <br>`MOV     DX,[DSPLifePort]`
* **395** `>` — Mixer basic routines.
  <br>`PROCEDURE SbWriteMixerReg(Reg, Val: BYTE); ASSEMBLER;`
* **428** `>` — Regular Sound Blaster generic routines.
  <br>`FUNCTION SbRegDetect : BOOLEAN;`
* **515** `|` — AND FALSE
  <br>`DoHiSpeed := (SbVersion > $200) AND SbHiSpeed`
* **551** `|` — Send command.
  <br>`SbWriteByte(SbDefTimeout, sdcGetDSPVersion);`
* **590** `|` — Send time constant command.
  <br>`SbWriteByte(SbDefTimeout, $D9)`
* **595** `|` — Send the time constant.
  <br>`SbWriteByte(SbDefTimeout*4, tc);`
* **596** `|` — Reset time constant to already changed.
  <br>`TimeConst := 0;`
* **614** `|` — Reset Hi-speed block specifier, just in case.
  <br>`HSBlockSpecified := 0;`
* **616** `|` — Start DMA low speed command.
  <br>`SbWriteByte(SbDefTimeout, sdcStartLSpeedDMA);`
* **617** `|` — Low & high bytes of size.
  <br>`SbWriteByte(SbDefTimeout, LO(Len));`
* **627** `|` — Set hi speed DMA block command.
  <br>`SbWriteByte(SbDefTimeout, sdcSetHSpeedSize);`
* **634** `|` — Start DMA in hi speed mode.
  <br>`SbWriteByte(SbDefTimeout, sdcStartHSpeedDMA);`
* **641** `|` — Too short -> Discard. It wouldn't sound anyway.
  <br>`IF Len < 10 THEN EXIT;`
* **643** `|` — Twice as big a buffer if stereo mode.
  <br>`IF SbStereo THEN INC(Len, Len);`
* **644** `|` — DMA sizes are always size - 1.
  <br>`DEC(Len);`
* **658** `>` — Mixer generic routines.
  <br>`FUNCTION MixerDetect : BOOLEAN;`
* **771** `>` — Sound Blaster Pro generic routines.
  <br>`FUNCTION SbProDetect : BOOLEAN;`
* **828** `>` — Sound Blaster 16 generic routines.
  <br>`FUNCTION Sb16Detect : BOOLEAN;`
* **867** `|` — Set 16 bit DMA transfer command.
  <br>`SbWriteByte(SbDefTimeout, $B6)`
* **869** `|` — Set 8 bit DMA transfer command.
  <br>`SbWriteByte(SbDefTimeout, $C6);`
* **871** `|` — Set stereo mode.
  <br>`SbWriteByte(SbDefTimeout, $20)`
* **873** `|` — Set mono mode.
  <br>`SbWriteByte(SbDefTimeout, $00);`
* **881** `|` — 16 bit DMA continue command.
  <br>`SbWriteByte(SbDefTimeout, $47)`
* **883** `|` — 8 bit DMA continue command.
  <br>`SbWriteByte(SbDefTimeout, $45);`


## `v1.39b/LIB/SOUNDDEV.PAS`

* **6** `>` — sampled audio devices possible on a PC, wether they work
* **7** `>` — with DMA or polling.
* **14** `>` — xx-Jun-1992 Development.
* **30** `>` — Device configuration definitions.
  <br>`TYPE`
* **34** `|` — Name/description of device.
  <br>`TDevName = STRING[50];`
* **35** `|` — Device identification string.
  <br>`TDevID   = STRING[20];`
* **41** `|` — Returns the real sampling freq. when Hz is selected.
  <br>`TGetRealFreqProc = FUNCTION  (Hz: WORD) : WORD;`
* **45** `|` — Device record for including in a linked list.
  <br>`PSoundDevice = ^TSoundDevice;`
* **47** `|` — Device ID string.
  <br>`DevID         : TDevID;`
* **48** `|` — TRUE if the device uses DMA output (shouldn't be needed).
  <br>`DMA           : BOOLEAN;`
* **56** `|` — Routine to be executed for active polling (hand made).
  <br>`PollRut         : TProc;`
* **59** `|` — Next record in the list.
  <br>`Next          : PSoundDevice;`
* **63** `|` — Count of the number of installed devices.
  <br>`NumDevices   : BYTE         = 0;`
* **64** `|` — Device being used right now.
  <br>`ActiveDevice : PSoundDevice = NIL;`
* **70** `>` — Device Stack.
  <br>`CONST`
* **81** `>` — Sample buffers definition.
  <br>`TYPE`
* **85** `|` — Data type of the samples.
  <br>`TDataType = (dtShortInt, dtInteger);`
* **87** `|` — Data types for big arrays.
  <br>`TIntBuff   = ARRAY[0..32760] OF INTEGER;`
* **95** `|` — TRUE while it's being used by the device.
  <br>`InUse    : BOOLEAN;`
* **96** `|` — Size of the buffer in samples.
  <br>`NSamples,`
* **97** `|` — Sampling frequency.
  <br>`RateHz   : WORD;`
* **98** `|` — 1 or 4, channels contained in the buffer.
  <br>`Channels : BYTE;`
* **100** `|` — Pointer to the buffer.
  <br>`dtInteger:  ( IData : PIntBuff );`
* **106** `|` — Buffer that is actually sounding (NON-DMA only).
  <br>`Sounding     : POINTER = NIL;`
* **107** `|` — Number of samples left in the buffer.
  <br>`SoundLeft    : WORD    = 0;`
* **108** `|` — Number of channels in the buffer.
  <br>`NumChannels  : WORD    = 1;`
* **109** `|` — Size of one sample in the buffer.
  <br>`ChannelIncr  : WORD    = 1;`
* **115** `>` — DMA buffers definition.
  <br>`CONST`
* **119** `|` — Size of the buffer.
  <br>`DMABufferSize = 4096;`
* **122** `|` — Pointers for the
  <br>`DMABufferPtr : POINTER;`
* **123** `|` — DMA buffer.
  <br>`DMABuffer    : POINTER;`
* **139** `>` — Hardware parameters.
  <br>`CONST`
* **143** `|` — Default sampling rate.
  <br>`DefaultHz                   = 16000;`
* **144** `|` — TRUE if there are no samples sounding.
  <br>`DeviceIdling      : BOOLEAN = TRUE;`
* **145** `|` — Clock frequency of the INT 8 timer.
  <br>`TimerHz           : WORD    = DefaultHz;`
* **146** `|` — Older INT 8 frequency (for detecting change).
  <br>`LastHz            : WORD    = 0;`
* **147** `|` — Sampling frequency of the sound.
  <br>`SoundHz           : WORD    = DefaultHz;`
* **148** `|` — Desired sampling frequency of the sound.
  <br>`DesiredHz         : WORD    = DefaultHz;`
* **149** `|` — Clock count for calling the original INT 8.
  <br>`SystemClockCount  : WORD    = 0;`
* **150** `|` — Increment for calling the original INT 8.
  <br>`SystemClockIncr   : WORD    = 0;`
* **151** `|` — Value given to the INT 8 timer.
  <br>`TimerVal          : WORD    = 0;`
* **152** `|` — TRUE if a device has already been initialized.
  <br>`DeviceInitialized : BOOLEAN = FALSE;`
* **153** `|` — Number of samples to discard in DMA transferences.
  <br>`DMAOffset         : WORD    = 1;`
* **156** `|` — Mono/stereo mixing algorithm.
  <br>`MixMethod         : BYTE    = 3;`
* **165** `|` — Number of ticks per second, 50 = Europe, 60 = USA.
  <br>`TicksPerSecond    : WORD    = 50;`
* **179** `>` — Periodic process.
  <br>`VAR`
* **183** `|` — Periodic process (normally a music interpreter).
  <br>`PeriodicProc  : TProc;`
* **186** `|` — Frequency for calling the periodic process.
  <br>`PeriodicHz    : BYTE = 0;`
* **187** `|` — Countdown starting point (NON-DMA only).
  <br>`PeriodicStart : WORD = 1;`
* **188** `|` — Countdown. (idem).
  <br>`PeriodicCount : WORD = 0;`
* **194** `>` — Buffer provider definitions.
  <br>`TYPE`
* **201** `|` — Pointer to the buffer provider.
  <br>`AskBufferProc  : TAskBufferProc;`
* **202** `|` — Buffer being used.
  <br>`ActualBuffer,`
* **203** `|` — Buffer that will be used next.
  <br>`NextBuffer     : PSampleBuffer;`
* **204** `|` — Set TRUE if there are no buffers available.
  <br>`PleaseFallback : WORD{BOOLEAN};`
* **210** `>` — Sound Blaster device variables.
  <br>`CONST`
* **217** `|` — $10 DSP Command timeout.
  <br>`SbCmdTimeout : WORD    = 100;`
* **218** `|` — $10 DSP Parameter timeout.
  <br>`SbSplTimeout : WORD    = 10;`
* **224** `>` — DAC device ports.
  <br>`CONST`
* **237** `>` — Functions in the ASM portion.
  <br>`CONST`
* **264** `>` — Functions to be used by devices only.
  <br>`FUNCTION  InitDevice   (Device: PSoundDevice) : WORD; { Used to declare a device.                   `
* **267** `|` — Used to declare a device.
  <br>`FUNCTION  InitDevice   (Device: PSoundDevice) : WORD;`
* **268** `|` — Used to manually poll the device, if it is required.
  <br>`PROCEDURE PollDevice;`
* **269** `|` — Used to calculate the different Hz variables.
  <br>`PROCEDURE CalcTimerData(Hz: WORD);`
* **270** `|` — Used as a default TChgHzProc.
  <br>`PROCEDURE DefaultChgHz (Hz: WORD);`
* **271** `|` — Used as a default TRealFreqProc.
  <br>`FUNCTION  GetRealFreq  (Hz: WORD)             : WORD;`
* **272** `|` — Used to reinitialise the timer after a freq. change.
  <br>`PROCEDURE InitTimer;`
* **273** `|` — Used to get the next buffer prepared.
  <br>`FUNCTION  DoGetBuffer                         : WORD;`
* **279** `>` — Functions to be used by the sound generators only.
  <br>`PROCEDURE SetDevice      (p: PSoundDevice);                             { Used to initialise a buffe`
* **282** `|` — Used to initialise a buffer for output.
  <br>`PROCEDURE SetDevice      (p: PSoundDevice);`
* **283** `|` — Used to index the devices.
  <br>`FUNCTION  IndexDevice    (i: WORD)                      : PSoundDevice;`
* **284** `|` — Used to find a given device.
  <br>`FUNCTION  LocateDevice   (ID: STRING)                   : PSoundDevice;`
* **285** `|` — Used to initialise the periodic process.
  <br>`PROCEDURE SetPeriodicProc(Proc: TProc; PerSecond: WORD);`
* **286** `|` — Used to initialise the buffer asker.
  <br>`PROCEDURE SetBufferAsker (Proc: TAskBufferProc);`
* **287** `|` — Used to start the sound output.
  <br>`PROCEDURE StartSampling;`
* **288** `|` — Used to end the sound output.
  <br>`PROCEDURE EndSampling;`
* **305** `>` — Internal data.
  <br>`CONST`
* **309** `|` — Linked list of all devices.
  <br>`DeviceList       : PSoundDevice = NIL;`
* **310** `|` — Pointer to the original INT 8.
  <br>`OldTimerHandler  : POINTER      = NIL;`
* **311** `|` — TRUE if the INT 8 handler is already installed.
  <br>`IntInstalled     : BOOLEAN      = FALSE;`
* **317** `>` — Null procedures used in the unit.
  <br>`PROCEDURE NullProcedure;                  FAR; ASSEMBLER; ASM END;`
* **337** `>` — Periodic process implementation.
  <br>`PROCEDURE InitPeriodic;`
* **373** `>` — Hardware and interrupt handling procedures.
  <br>`PROCEDURE OriginalHwTimer; ASSEMBLER;`
* **378** `|` — Select timer 0, sequential access and continuous mode.
  <br>*es:* Selct timer 0, secuential access and contínuous mode.
  <br>`MOV     AL,54`
* **380** `|` — Set the counter to 0 (65536).
  <br>`XOR     AL,AL`
* **381** `|` — Lower byte of the counter.
  <br>`OUT     40h,AL`
* **382** `|` — Higher byte.
  <br>`OUT     40h,AL`
* **427** `>` — Procedures exported for the sound generator.
  <br>`PROCEDURE StartSampling;`
* **447** `|` — AND (NOT DeviceInitialized)
  <br>`IF (ActiveDevice <> NIL)`
* **541** `>` — Implementation of some procedures exported to the device controllers.
  <br>`FUNCTION InitDevice(Device: PSoundDevice) : WORD;`
* **608** `|` — It must be already finished using.
  <br>`ActualBuffer^.InUse := FALSE;`
* **613** `|` — If there had not been next buffer before.
  <br>`IF ActualBuffer = NIL THEN BEGIN`
* **615** `|` — If there has just been one more buffer.
  <br>`IF ActualBuffer <> NIL THEN BEGIN`
* **621** `|` — If there is no buffer :-(
  <br>`BEGIN`
* **655** `|` — Get the buffer, if there is one.
  <br>`NextBuffer   := AskBufferProc;`
* **675** `>` — Unit initialisation.
  <br>`PROCEDURE InitSoundDevices;`
* **697** `>` — Calc. for the DMA buffers. This messes with the heap, but works.
  <br>`DMABuffer := HeapPtr;`
* **701** `|` — l = linear address.
  <br>`l := (LONGINT(SEG(DMABuffer^)) SHL 4) + OFS(DMABuffer^);`
* **706** `|` — If address doesn't match,
  <br>`IF LONGINT(WORD(l)) + DMABufferSize > 65536 THEN`
* **707** `|` — get an address that matches
  <br>`BEGIN`
* **708** `|` — by incrementing to a 64 Kb
  <br>`OffsFree := 65536 - LONGINT(WORD(l));`
* **717** `|` — Manually, allocate the
  <br>`HeapPtr      := Ptr((l + DMABufferSize + 16) SHR 4, 0);`
* **730** `|` — Clear the Heap Pointer contents.
  <br>`FillChar(HeapPtr^, 8, 0);`
* **732** `|` — Update the Heap by freeing
  <br>`IF OffsFree > 0 THEN`
* **733** `|` — manually the unused memory.
  <br>`FreeMem(PtrFree, OffsFree);`


## `v1.39b/LIB/STMLOADE.PAS`

* **23** `>` — Internal definitions. Format of the files.
  <br>`TYPE`
* **385** `>` — Processing of the instruments
  <br>`ProcessInstruments(Song, St, Hdr);`
* **391** `>` — Processing of the patterns (the partiture)
  <br>`ProcessPatterns(Song, St, Hdr.NPatterns);`
* **397** `>` — Processing of the samples
  <br>`ProcessSamples(Song, St);`


## `v1.39b/LIB/UNKLOADE.PAS`

* **19** `|` — JMPlayer Id string (at the start of the file).
  <br>`TModJMIdString  = ARRAY[1..6] OF CHAR;`


## `v1.39b/LIB/PLAYMOD.ASM`

* **49** `>` — DS:SI.BP = Src pos. -> DS:SI.BP
* **50** `>` — ES:DI = Dest pos. -> ES:DI
* **51** `>` — CH.DX = Src Incr. -> DX:mem
* **52** `>` — CL = Volume. -> CL
  <br>`DumpRaw:`
* **53** `>` — BX = Dest Incr. -> BX
  <br>`DumpRaw:`
* **54** `>` — AX = Loop Len. -> CH*8
  <br>`DumpRaw:`
* **84** `>` — MOV CX,1000
* **126** `>` — AX = Loop Len. -> CH*16
  <br>`EmptyRaw:`
* **187** `>` — Step: WORD; SrcLimit, Max, ChanAdd: WORD) : WORD;
  <br>`PUBLIC DumpInstrument`


## `v1.39b/LIB/SOUNDDEV.ASM`

* **101** `>` — │ MACRO: Saturate │
* **103** `>` — │ Macro that saturates a sample just after an addition. │
* **105** `>` — │ IN: Reg = Register to be saturated. │
  <br>`MACRO Saturate Reg`
* **142** `>` — │ ROUTINE: DMAFillBuffer │
* **144** `>` — │ This routine fills a portion of the DMA buffer with the whole buffer of │
* **145** `>` — │ samples pointed to by Sounding & SoundLeft. │
* **147** `>` — │ IN: nothing │
* **149** `>` — │ OUT: nothing │
* **151** `>` — │ MODIFIES: AX, BX, CX, DX, SI, DI, ES │
  <br>`DeviceIdCount   DB 0`
* **195** `>` — MOV AL,[CS:TickCnt]
  <br>`MOV     AX,SS`
* **196** `>` — XOR AL,255
  <br>`MOV     AX,SS`
* **197** `>` — MOV [CS:TickCnt],AL
  <br>`MOV     AX,SS`
* **198** `>` — MOV [ES:DI-1],AL
  <br>`MOV     AX,SS`
* **210** `>` — │ ROUTINE: DMADoGetBuff │
* **212** `>` — │ This is the main buffer-filling routine for DMA devices. First it calls │
* **213** `>` — │ the buffer grabber. Then, it checks to see if the DMA has advanced │
* **214** `>` — │ enough to leave space for this buffer. │
* **271** `>` — MOV [DevSS],SS
* **272** `>` — MOV [DevSP],SP
* **273** `>` — MOV DX,DS
* **274** `>` — MOV SS,DX
* **275** `>` — MOV SP,OFFSET DevStack + StackSize
* **277** `>` — MOV SS,[DevSS]
* **278** `>` — MOV SP,[DevSP]
* **285** `>` — │ ROUTINE: TimerHandler │
* **287** `>` — │ This is the big routine for non-DMA devices. It is called through │
  <br>`PUBLIC TimerHandler`
* **288** `>` — │ interrupts from a timer whose period is the sampling period. │
  <br>`PUBLIC TimerHandler`
* **295** `|` — Just for safety's sake.
  <br>`CLI`
* **300** `>` — │ - Save the registers in the local stack. │
  <br>`PUSH    AX`
* **301** `>` — │ - Set the data segment register. │
  <br>`PUSH    AX`
* **316** `>` — │ First, we jump to the device start code. │
  <br>`DevCall DeviceStartRut`
* **322** `>` — │ Check to see if there are samples to use. │
  <br>`MOV     AX,[SoundLeft]`
* **330** `>` — │ Decrement the number of samples left in the │
  <br>`DEC     AX`
* **331** `>` — │ buffer, do the device initialization if any, │
  <br>`DEC     AX`
* **332** `>` — │ and signal that the device is not idle. │
  <br>`DEC     AX`
* **344** `>` — │ Load the buffer pointer, do the │
  <br>`LDS     SI,[Sounding]`
* **345** `>` — │ mixing and output the sample. │
  <br>`LDS     SI,[Sounding]`
* **368** `>` — │ Restore the stack. │
  <br>`thAfterProcessingSample:`
* **374** `>` — │ Check if the old interrupt │
  <br>`MOV     AX,[SystemClockIncr]`
* **375** `>` — │ routine must be called. │
  <br>`MOV     AX,[SystemClockIncr]`
* **383** `>` — │ Else, signal the EOI to the PIC. │
  <br>`MOV     AL,20h`
* **402** `>` — │ Do the final stuff: Pop registers. │
  <br>`POP     DS`
* **421** `>` — │ Get a new sample buffer. If there is none, │
  <br>`MOV     AL,0`
* **422** `>` — │ signal that the device is in idle state. │
  <br>`MOV     AL,0`
* **455** `>` — │ See if the periodic process must be called. │
  <br>`MOV     AX,[PeriodicCount]`
* **466** `>` — │ Call the periodic process. │
  <br>`PUSH    ES`
* **482** `>` — │ ROUTINE: DMATimerHandler │
* **484** `>` — │ This is the big routine for DMA devices. It is called through │
  <br>`DMASema         DB 0`
* **485** `>` — │ interrupts from a timer whose period is a few Hertz (100 for example). │
  <br>`DMASema         DB 0`
* **499** `>` — │ - Save the registers. │
  <br>`PUSHA`
* **512** `>` — │ Check if the old interrupt routine must be called. │
  <br>`MOV     AX,[SystemClockIncr]`
* **520** `>` — │ If so, do it. │
  <br>`PUSHF`
* **539** `>` — │ First we check if the DMA operation is │
* **540** `>` — │ requested to stop. If so, we signal the │
  <br>`MOV     AL,[DMAStop]`
* **541** `>` — │ stopping of the DMA and jump to the old │
  <br>`MOV     AL,[DMAStop]`
* **542** `>` — │ IRQ-checking part. │
  <br>`MOV     AL,[DMAStop]`
* **548** `>` — MOV [DMAStopped],AL
  <br>`MOV    [DeviceIdling],AL`
* **553** `>` — │ Now, we check the IRQ watchdog, just in │
  <br>`MASM`
* **554** `>` — │ case we need to kick the card. │
  <br>`MASM`
* **563** `>` — CALL [DeviceKickRut]
  <br>`@@notwatch:`
* **566** `>` — │ If the device is said to be idle, reset │
  <br>`MOV     AL,[DeviceIdling]`
* **567** `>` — │ the timer. This is to protect the timer │
  <br>`MOV     AL,[DeviceIdling]`
* **568** `>` — │ period from being modified. │
  <br>`MOV     AL,[DeviceIdling]`
* **574** `>` — CALL InitTimer
  <br>`@@notidling:`
* **577** `>` — │ Signal that the device is not idling, │
  <br>`#`
* **578** `>` — │ and fill a bit more of the DMA buffer. │
  <br>`#`
* **615** `>` — │ Call the periodic process and exit. │
  <br>`STI`
* **627** `>` — JZ @@loop
  <br>`DEC     [CS:DMASema]`
* **633** `>` — │ Increment the watchdog, but don't let │
  <br>`MOV     AL,[DMAIrqWatch]`
* **634** `>` — │ it wrap around. │
  <br>`MOV     AL,[DMAIrqWatch]`
* **644** `>` — │ Do the final stuff: Pop registers, restore the │
  <br>`POP     DS`
* **645** `>` — │ stack, and exit. │
  <br>`POP     DS`
* **883** `>` — │ ROUTINE: NullDevRut │
* **885** `>` — │ Do-nothing routine for the unused device services. │
  <br>`NullDevRut:`


## `v1.39b/LIB/DEVSB.INC`

* **56** `>` — GeneralDev8MonoFillRut
  <br>`DevSbSterFillRut EQU GeneralDev8SterFillRut`
