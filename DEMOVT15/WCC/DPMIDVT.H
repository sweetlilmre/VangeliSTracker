/* ------------------------ DPMIDVT.H --------------------------- */
/* DPMI interface code to DemoVT v1.5 and higher.                 */
/* Written bye Jare of Iguana in 1994.                            */
/* -------------------------------------------------------------- */
/* Thanks to Yann for supplying all those specs, and also to Tran */
/* of nothing for getting me into this wonderful world of PMode.  */
/* -------------------------------------------------------------- */
/* This code will compile under Watcom C++ 9.5. I think it should */
/* work also with other versions and under other 32 bit compilers */
/* but I haven't bothered to test.                                */
/* -------------------------------------------------------------- */
/* You will find some general purpose DPMI code here. Use it!     */
/* Especially that RealModeMem variable.                          */
/* That variable is not necessary under DOS4GW, because the first */
/* megabyte is directly accesible using the default data seg. But */
/* I have included it to make this code fully portable to other,  */
/* more hostile environments.                                     */
/* You might need to translate it to assembly, but that should be */
/* easy. After all, it's your job! :)                             */
/* -------------------------------------------------------------- */

#ifndef _DPMIDVT_H_
#define _DPMIDVT_H_

// ------------------------------------------------------------------------
// ---------- Portable definitions of machine types.

typedef unsigned char  byte;
typedef unsigned short word;
typedef unsigned long  dword;

// ------------------------------------------------------------------------
// ---------- DPMI interface routines.

typedef struct SDPMI_rminfo {       // Real mode registers for the DPMI
    dword EDI;                      // translation API.
    dword ESI;
    dword EBP;
    dword _reserved;
    dword EBX;
    dword EDX;
    dword ECX;
    dword EAX;
    word  flags;
    word  ES, DS, FS, GS;
    word  IP, CS, SP, SS;
} TDPMI_RealModeInfo;

#define FLAGS_CARRY  0x0001         // To check flags above.
#define FLAGS_PARITY 0x0004
#define FLAGS_AUX    0x0010
#define FLAGS_ZERO   0x0040
#define FLAGS_SIGN   0x0080

extern TDPMI_RealModeInfo DPMI_rmi; // Place real mode register values
                                    // here when calling the next two
                                    // functions.


extern void         DPMI_RealModeInt(int i);
  //                ----------------
  // Calls a real mode interrupt. For example, DOS' INT 2Fh.


extern void         DPMI_RealModeProc(word seg, word off);
  //                -----------------
  // Calls a real mode procedure. For example, DemoVT's entry point.


extern void _far * DPMI_MapRealModeSegment(word rmseg);
  //               -----------------------
  // Maps a real mode segment (under 1 Meg) into a far pointer. Do
  // not use, MapMemory() is preferred because it is more flexible.


extern byte _far * DPMI_MapMemory(dword baseaddr, dword len);
  //               --------------
  // Maps a linear memory area into a far pointer. Remember that these
  // two use up the descriptors that the DPMI host provides, so you
  // should plan carefully when to call this functions,, and most of
  // the time you will rather mess wiith the pointers (and selectors)
  // obtained here.


// ------------------------------------------------------------------------
// ---------- DemoVT. The real thing.

#pragma pack(1)

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
    word  entryPointOff,      // Far pointer to the servicing routine
          entryPointSeg;      //  that receives params thru the stack.
    dword tickCounter;        // 50 Hz counter. Increments 50 times per second.
    word  entryPointAXOff,    // Far pointer to the servicing routine
          entryPointAXSeg;    //  that gets the parameter in AX. It's just
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

#pragma pack()

extern byte      _far *RealModeMem;     // This gives access to the 1st. Meg.
extern dword           DVTAppIdFound;   // Offset into RealModeMem of the
                                        // DemoVT data returned.
extern TDVTInfo  _far *DVTInfo;         // Pointer to the info structure.
                                        // If DVT_Init fails, all these
                                        // will be 0/NULL.


   // DemoVT access functions.

extern int   DVT_Init(void);
  //         --------
  // Starts the interface variables, and returns if the DemoVT is present.
  // NOTE: check for DVTInfo != NULL even if the DemoVT is present, the
  // DPMI interface might fail (nobody's perfect).

extern void  DVT_CallDemoVT(int command);
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

/* ------------------------ DPMIDVT.H --------------------------- */

