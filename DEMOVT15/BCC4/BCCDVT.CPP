/*

   BCCDVT.CPP -- BC++ (4.0) interface to DEMOVT.EXE  //  ARM 4/94
   (based on PASDVT.PAS)

   To use BCCDVT.CPP simply #include it in your source (there's just not
   enough non-inline executable code to bother making seperate .H/.OBJ, but
   you can easily do so if you want to).

   NOTE WELL: Any "portable" code herein is wholly unintentional };-)

*/

/*
==========================================================================

                         f u n c t i o n s

  BOOL VT_Init()      : Initializes DEMOVT, returns 1 if successful.

+ void VT_Poll()      : Call this function at least 50 times a second when
                        in manual mode (see VT_AutoOff).

+ void VT_AutoOn()    : Polls automatically thru timer interrupt.

+ void VT_AutoOff()   : Disconnects timer from DEMOVT, you must poll manually
                        with VT_Poll().

+ DWORD VT_Timer()    : Returns timer count (1/50ths sec. from music start)

+ void VT_Start()     : Prepare to play music.

  void VT_SyncStart() : VT_Start and waits for 1/2 second, returns at the
                        same time the music starts sounding.

  void VT_GoTo( BYTE pattern, BYTE note ) :
                        Jumps to specified pattern/note.

+ BYTE VT_GetSem( BYTE sem ) :
                        Returns the value of semaphore number "sem".

+ void VT_SetSem( BYTE sem, BYTE value ) :
                        Sets semaphore "sem" to value "value".

  void VT_Resync( BYTE sem, BYTE pattern, BYTE note ) :
                        This one's awkward, see "MiddleSync" in DEMOVT
                        docs O:-)

+ void VT_SetVolume( BYTE level ) :
                        Sets volume level, 0 (silence)..255 (loudest).

+ BYTE VT_GetVolume() : Returns current volume level setting.

  void VT_Delay( unsigned int hundredths ) :
                        Waits for specified number of 1/100ths of a second
                        while calling VT_Poll. Delay is precise only to
                        about 1/50th second.

+ BOOL VT_QueryCh( BYTE ChanNo ) :
                        Returns 1 if a not has been played to the specified
                        channel since the last call to VT_QueryCh(ChanNo),
                        else 0.

  void VT_ChStatus( BYTE ChanNo, WORD& per, BYTE& inst, BYTE& volu ) :
                        Returns the specified channel's current status: per
                        = period of the note being played, inst = number of
                        the instrument being played, volu = volume of note
                        being played. Note that period and volume are those
                        specified in the musical score, not the actual tone
                        and volume of the sample.

+ BYTE VT_ChannelCount() :
                        Returns the number of channels the present music
                        uses (e.g. 4, 8, etc.).

+ void VT_CurrentPos( int& pat, int& not ) :
                        Returns the current pattern/note being played
                        within the score.

+ void VT_Abort() :     Tells DEMOVT to quit as soon as this program
                        exists.

  void VT_IDstring( char* buffer ) :
                        Copies DEMOVT's version ID string ("DEMOVT v?.?")
                        to buffer as an ASCIIZ string.

("+" denotes inline functions)

*/


// ------------------------------------------------------------------

// define fundamental asm types (16-bit compiler):

typedef unsigned char     BYTE;    // 8 bits
typedef unsigned int      WORD;    // 16 bits
typedef unsigned long int DWORD;   // 32 bits

typedef int BOOL;                  // language's natural boolean type


// handy macro for inserting labels in asm{}

#ifndef _L
#define _L(x) } _L##x: asm {
#endif


// --- structures

#pragma option -a-     // align to byte (else compiler will wreck our structs)

struct TChanData
{
   WORD period;        // period
   BYTE instrument;    // instrument number (1..31)
   BYTE volume;        // volume (0..63)
};

   // *VT_Info

struct
{
   // out

   volatile BYTE  semaphores [256];
   volatile BYTE  ChansTrig   [32];
            BYTE  NumChannels;

            void (far pascal * CtrlEntryPoint)( WORD command );
   volatile DWORD TickCounter;
            void (far _fastcall * RegEntryPoint)( WORD command );

   volatile TChanData ChansData [32];

   volatile BYTE Note;
   volatile BYTE Pattern;

            BYTE _reserved2 [81];

   // in

            BYTE _reserved3 [3];

            BYTE DoJump;
            BYTE JumpToPattern;
            BYTE JumpToNote;

            BYTE Volume;
            BYTE Abort;

            BYTE _reserved4 [248];

} far * VT_Info = 0;

#pragma option -a.            // restore previous alignment

BOOL VTOK = 0;

// in a .H/.OBJ setup these two wouldn't be exported:

BYTE far * VTAppIDFound = 0;  // points to a Pascal string w/ "DemoVT v1.5"
void (far _fastcall * VTControl)( WORD command ) = 0;


// - prototypes for non-inline functions --------------------------------

BOOL VT_Init      ();
void VT_SyncStart ();
void VT_GoTo      ( BYTE pattern, BYTE note );
void VT_Resync    ( BYTE sem, BYTE pattern, BYTE note );
void VT_Delay     ( unsigned int hundredths );
void VT_ChStatus  ( BYTE ChanNo, WORD& per, BYTE& inst, BYTE& volu );
void VT_IDstring  ( char* buffer );


// - inline function definitions ----------------------------------------

inline void VT_Start()     { if (VTOK) VTControl( 3 ); }
inline void VT_Poll()      { if (VTOK) VTControl( 2 ); }
inline void VT_AutoOff()   { if (VTOK) VTControl( 1 ); }
inline void VT_AutoOn()    { if (VTOK) VTControl( 0 ); }

inline void VT_Abort()     { if (VTOK) VT_Info -> Abort = 1; }

inline void VT_SetVolume( BYTE level ) { if (VTOK) VT_Info -> Volume = level; }

inline BYTE VT_ChannelCount()
  { if (VTOK)  return VT_Info -> NumChannels; else  return 0; }

inline DWORD VT_Timer()
  { if (VTOK)  return VT_Info -> TickCounter; else  return 0; }

inline BYTE VT_GetSem( BYTE sem )
  { if (VTOK)  return VT_Info -> semaphores[ sem ]; else  return 0; }

inline void VT_SetSem( BYTE sem, BYTE value )
  { if (VTOK) VT_Info -> semaphores[ sem ] = value; }

inline BYTE VT_GetVolume()
  { if (VTOK)  return VT_Info -> Volume; else  return 0; }

inline BOOL VT_QueryCh( BYTE ChanNo )
{
  if ( (VTOK) && (VT_Info -> ChansTrig[ ChanNo ]) )
    { VT_Info -> ChansTrig[ ChanNo ] = 0; return 1; }
  else return 0;
}

// VT_CurrentPos

inline void VT_CurrentPos( int& pat, int& not )
{
    if (VTOK)
    {
        pat = (int) VT_Info -> Pattern;
        not = (int) VT_Info -> Note;
    }
    else
      pat = not = 0;
}


// - non-inline function definitions ------------------------------------

// VT_Init

// ...some temporary defines for tidyness...

#define MagicAX    'VT'
#define MagicBX    'Tr'
#define MagicCX    'ac'
#define MagicXorBX 'ke'
#define MagicXorCX 'r '

BOOL VT_Init()
{
    asm {
      mov ax, MagicAX
      mov bx, MagicBX
      mov cx, MagicCX
      xor di, di
      mov es, di
      int 2fh
      xor dx, dx
      and ax, ax
      jnz _Lno
      cmp bx, MagicBX xor MagicXorBX
      jne _Lno
      cmp cx, MagicCX xor MagicXorCX
      jne _Lno

      inc dl                              // DEMOVT detected!
      mov [word ptr VTAppIDFound+2], es
      mov [word ptr VTAppIDFound  ], di  // DemoVT's ID string

      les di,[es:di-4]
      mov [word ptr VT_Info+2], es
      mov [word ptr VT_Info], di
    }
_Lno:
    VTOK = (BOOL)_DX;
    if (VTOK)
    {
       VTControl = VT_Info -> RegEntryPoint;
       VT_Info -> Pattern = VT_Info -> Note = 0;
    }
    return VTOK;
}

#undef MagicAX
#undef MagicBX
#undef MagicCX
#undef MagicXorBX
#undef MagicXorCX


// VT_SyncStart

void VT_SyncStart()
{
    if (VTOK)
    {
       VTControl( 3 );
       VT_Info -> TickCounter = 0;
       do VT_Poll(); while (VT_Timer()<25);  // 25/50ths = 1/2 second
       VT_Info -> TickCounter = 0;
    }
}


// VT_GoTo

void VT_GoTo( BYTE pattern, BYTE note )
{
    if (VTOK)
    {
       VT_Info -> JumpToPattern = pattern;
       VT_Info -> JumpToNote    = note;
       VT_Info -> DoJump        = 1;
    }
}


// VT_Resync

void VT_Resync( BYTE sem, BYTE pattern, BYTE note )
{
    if (VTOK)
    {
        if (!VT_GetSem(sem)) VT_GoTo( pattern, note );
        sem++;
        do VT_Poll(); while (!VT_GetSem( sem ));
    }
}


// VT_Delay

void VT_Delay( unsigned int hundredths )
{
    if (VTOK)
    {
      DWORD L = VT_Timer() + (hundredths >> 1);
      do VT_Poll(); while (VT_Timer() < L);
    }
}


// VT_ChStatus

void VT_ChStatus( BYTE ChanNo, WORD& per, BYTE& inst, BYTE& volu )
{
   if (VTOK)
   {
      TChanData temp = VT_Info -> ChansData[ ChanNo ];
      per  = temp.period;
      inst = temp.instrument;
      volu = temp.volume;
   }
   else
      per = inst = volu = 0;
}


// VT_IDstring

void VT_IDstring( char* buffer )
{
   char far * P = (BYTE far *) VTAppIDFound;
   int count = (int) *P++;
   for (int i = 0; i < count; i++) *buffer++ = *P++;
   *buffer = '\0';
}

