/* -------------------------- CDVT.H ---------------------------- */
/* C interface code to DemoVT v1.5 and higher.                    */
/* Written bye Jare of Iguana in 1994.                            */
/* -------------------------------------------------------------- */
/* Based on code written by Carlos Quintero.                      */
/* -------------------------------------------------------------- */
/* Tested under TC++ 3.0, MSC/C++ 7.0 and BC++ 3.1                */
/* -------------------------------------------------------------- */

#ifndef _CDVT_H_
#define _CDVT_H_

// ------------------------------------------------------------------------
// ---------- Portable definitions of machine types.

typedef unsigned char  byte;
typedef unsigned short word;
typedef unsigned long  dword;

// ------------------------------------------------------------------------
// ---------- And how we hate MSC for not supporting MK_FP. :-(

#ifndef MK_FP
#  define MK_FP(s,o) ((void _far *)((((dword)((word)(s)))<<16)+(word)(o)))
#endif

// ------------------------------------------------------------------------
// ---------- DemoVT. The real thing.

#ifdef __TURBOC__
    // Ain't this "Compiler war" stupid? Why not support the usual pack()?
#   pragma option -a-
#else
#   pragma pack(1)
#endif

typedef struct {
    word  period;             // Period of the playing note.
    byte  ins;                // Number of instrument, 1-31.
    byte  vol;                // Current volume, 0-63.
} TChanData;

typedef struct sDVT_info {    // DemoVT's info structure.
        // Written by DemoVT.
    byte  semaphores   [256]; // 256 semaphores used for synchronisation.
    byte  chansTrig    [32];  // Flags that indicate note triggered for
                              //  each channel. Useful for vu-meters.
    byte  numChannels;        // Number of channels of the current module.
    void  (_pascal _far *entryPoint)(word command);
                              // Far pointer to the servicing routine
                              //  that receives params thru the stack.
    dword tickCounter;        // 50 Hz counter. Increments 50 times per second.
    void  (_pascal _far *entryPointAX)(void);
                              // Far pointer to the servicing routine
                              //  that gets the parameter in AX. It's just
                              //  a PUSH AX; CALL FAR entryPointSeg:Off; RETF

    TChanData chansData[32];  // Info about all playing channels.

    byte  pos;                // Position of the current note in the pattern.
    byte  seq;                // Order number of playing pattern.

    byte  _reserved2   [81];

        // Read and written by DemoVT.
    byte  _reserved3   [3];
    byte  jumpNewPos,         // Boolean. 1 if song must jump.
          jumpPosSeq,         // Sequence and note values to jump to.
          jumpPosNote;     
    byte  soundVolume;        // Volume of the sound output.
    byte  abortDvt;           // Set to 1 to abort the demo.
    byte  _reserved4   [248];
} TDVTInfo;

#ifdef __TURBOC__
#   pragma option -a.
#else
#   pragma pack()
#endif

extern byte      _far *DVTAppIdFound;   // Pointer to the  DemoVT data.
extern TDVTInfo  _far *DVTInfo;         // Pointer to the info structure.
                                        // If DVT_Init fails, both of
                                        // these will be NULL.


   // DemoVT access functions.

extern int   DVT_Init(void);
  //         --------
  // Starts the interface variables, and returns if the DemoVT is present.
  // NOTE: check for DVTInfo != NULL even if the DemoVT is present.

extern void  DVT_CallDemoVT(word command);
  //         --------------
  // Calls DemoVT API entry point.

#define      DVT_CallMusic()       DVT_CallDemoVT(2)
  //         -------------

#define      DVT_ConnectTimer()    DVT_CallDemoVT(0)
  //         ----------------

#define      DVT_DisconnectTimer() DVT_CallDemoVT(1)
  //         -------------------

#define      DVT_BeginSync()       DVT_CallDemoVT(3)
  //         -------------

extern dword DVT_GetTickCounter(void);
  //         ------------------

extern void  DVT_WaitForStart(void);
  //         ----------------

extern void  DVT_JumpPos(byte pattern, byte note);
  //         -----------

extern byte  DVT_GetSemaphore(byte nsem);
  //         ----------------

extern void  DVT_SetSemaphore(byte nsem, byte value);
  //         ----------------

extern void  DVT_MiddleSync(byte nsem, byte pattern, byte note);
  //         --------------

extern byte  DVT_GetSoundVolume(void);
  //         ------------------

extern void  DVT_SetSoundVolume(byte vol);
  //         ------------------

#endif

/* -------------------------- CDVT.H ---------------------------- */

