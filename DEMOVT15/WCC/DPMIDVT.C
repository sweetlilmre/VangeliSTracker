/* ------------------------ DPMIDVT.C --------------------------- */
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

#include <stdlib.h>
#include <i86.h>

#include "dpmidvt.h"

 // -------------------------------------------------------

   // Leave some real mode memory free. Just in case. :)
extern unsigned __near __minreal = 100*1024;


TDPMI_RealModeInfo  DPMI_rmi;

static union  REGS  rmregs;
static struct SREGS rmsregs;

static void DPMI_RealModeCall(void) {
    DPMI_rmi.SS = DPMI_rmi.SP = 0;    // DPMI host will provide its own stack.
    rmregs.h.bh  = 0;                 // Do not reset PIC or A20 gate.
    rmregs.w.cx  = 0;                 // 0 words of parameters on the stack.
    rmregs.x.edi = FP_OFF(&DPMI_rmi); // Real mode info.
    rmsregs.es   = FP_SEG(&DPMI_rmi);
    int386x(0x31, &rmregs, &rmregs, &rmsregs);
}

void DPMI_RealModeInt(int i) {
    rmregs.w.ax = 0x300;
    rmregs.h.bl = i;
    DPMI_RealModeCall();
}

void DPMI_RealModeProc(word seg, word off) {
/*
    rmregs.w.ax = 0x301;
    DPMI_rmi.CS = seg;
    DPMI_rmi.IP = off;
    DPMI_RealModeCall();

    ********************************************************
    WARNING: DOS4GW v1.8 bundled with WATCOM C++ 9.5 doesn't
    seem to suuport the above call (at least I didn't get it
    to work), so we used a wierd scheme to emulate it.
    JCAB - 2/94
    DOS4GW 1.95 doesn't work either. What's going on?
    Jare - 3/94
    ********************************************************
*/

    dword _far *vectable = (dword _far *)RealModeMem;
    dword oldvec4 = vectable[4];
    dword oldvec6 = vectable[6];
    dword oldvec7 = vectable[7];

       // None of these interrupts should occur during normal operation.
       // but the way to do would be to allocate Real Mode Memory and place
       // the call there. INT 4 still should be used. I hate this!
    vectable[4] = 6*4+1; // Address of INT6 vector.
    vectable[6] = (long)0x9A00 + ((long)off<<16);   // FAR CALL [seg:off] 
    vectable[7] = (long)seg    + ((long)0xCF<<16);  // + IRET
    DPMI_RealModeInt(4);

    vectable[4] = oldvec4;
    vectable[6] = oldvec6;
    vectable[7] = oldvec7;

}

void _far * DPMI_MapRealModeSegment(word rmseg) {

    rmregs.x.eax = 0x0002;
    rmregs.x.ebx = (dword)rmseg;
    int386(0x31, &rmregs, &rmregs);

//    if (rmregs.x.cflag & FLAGS_CARRY)
//        return NULL;
//    else
        return MK_FP(rmregs.w.ax, 0);
}

byte _far *DPMI_MapMemory(dword baseaddr, dword len) {
    word selector;

    rmregs.x.eax = 0x0000;          // Allocate descriptor.
    rmregs.x.ecx = 1;               // One descriptor.
    int386(0x31, &rmregs, &rmregs);
//    if (rmregs.x.cflag & FLAGS_CARRY)
//        return NULL;
    selector = rmregs.w.ax;

    rmregs.x.eax = 0x0007;          // Set selector base address.
    rmregs.x.ebx = (dword)selector;
    rmregs.x.edx = (dword)((word)baseaddr);
    rmregs.x.ecx = (dword)(baseaddr >> 16);
    int386(0x31, &rmregs, &rmregs);
//    if (!(rmregs.x.cflag & FLAGS_CARRY))
    {
        rmregs.x.eax = 0x0009;      // Set descriptor access rights.
        rmregs.x.ebx = (dword)selector;
        rmregs.x.ecx = 0xCF93;
        int386(0x31, &rmregs, &rmregs);
//        if (!(rmregs.x.cflag & FLAGS_CARRY))
        {
            rmregs.x.eax = 0x0008;      // Set segment limit.
            rmregs.x.ebx = (dword)selector;
            rmregs.x.edx = (dword)((word)len);
            rmregs.x.ecx = (dword)(len >> 16);
            int386(0x31, &rmregs, &rmregs);
            if (!(rmregs.x.cflag & FLAGS_CARRY))
                return (MK_FP(selector, 0));    // Everything OK.
            // puts("Error setting limit");
        }
//        else
            ;//puts("Error setting rights.");
    }
//    else
        ;//puts("Error setting base address.");

      // Something went wrong, so we free the selector.
    rmregs.x.eax = 0x0001;          // Free selector.
    rmregs.x.ebx = (dword)selector;
    int386(0x31, &rmregs, &rmregs);
      // We don't care about errors freeing the selector. Can't do
      // much about it I guess.
    return NULL;
}

 // -------------------------------------------------------

byte     _far *RealModeMem   = NULL;
dword          DVTAppIdFound = 0;
TDVTInfo _far *DVTInfo       = NULL;


int DVT_Init(void) {
    int present;
    byte _far *p;

    if (DVTInfo != NULL)        // Already initialized?
        return 1;
    DPMI_rmi.EAX = 0x5654;      // DemoVT magic numbers.
    DPMI_rmi.EBX = 0x5472;
    DPMI_rmi.ECX = 0x6163;
    DPMI_rmi.EDI = 0;
    DPMI_rmi.ES  = 0;
    DPMI_RealModeInt(0x2F);     // Perform call.

    present = (   (word)DPMI_rmi.EAX == 0       // Complex check.
               && (word)DPMI_rmi.EBX == 0x3F17
               && (word)DPMI_rmi.ECX == 0x1343);
    if (present) {                              // Allocate far pointer.
        p = DPMI_MapMemory(0, 1024*1024-1);
        if (p != NULL) {
            word _far *g;
            RealModeMem = p;
            DVTAppIdFound = (dword)((DPMI_rmi.ES << 4)
                            + (word)(DPMI_rmi.EDI));
            g = (word _far *) (p + DVTAppIdFound - 4);
            DVTInfo = (TDVTInfo _far *)(p + g[0] + (g[1] << 4));
        }
    }
    return present;
}

void DVT_CallDemoVT(int command) {
    if (DVTInfo == NULL                 // Not initialized?
        || command < 0 || command > 3)  // or invalid parameter?
        return;
    DPMI_rmi.EAX = command;
    DPMI_RealModeProc(DVTInfo->entryPointAXSeg, DVTInfo->entryPointAXOff);
}

dword DVT_GetTickCounter(void) {
    if (DVTInfo == NULL)    // Not initialized?
        return 0;
    return DVTInfo->tickCounter;
}

void DVT_WaitForStart(void) {
    if (DVTInfo == NULL)    // Not initialized?
        return;
    DVTInfo->tickCounter = 0;
    while (DVTInfo->tickCounter < 25)
        DVT_CallMusic();
    DVTInfo->tickCounter = 0;
}

void DVT_JumpPos(byte pattern, byte note) {
    if (DVTInfo == NULL)    // Not initialized?
        return;
    DVTInfo->jumpPosSeq  = pattern;
    DVTInfo->jumpPosNote = note;
    DVTInfo->jumpNewPos  = 1;
}

byte DVT_GetSemaphore(byte nsem) {
    if (DVTInfo == NULL)    // Not initialized?
        return 0;
    return DVTInfo->semaphores[nsem];
}

void DVT_SetSemaphore(byte nsem, byte value) {
    if (DVTInfo == NULL)    // Not initialized?
        return;
    DVTInfo->semaphores[nsem] = value;
}

void DVT_MiddleSync(byte nsem, byte pattern, byte note) {
    if (DVTInfo == NULL || nsem > 254)    // Not initialized or error?
        return;
    if (DVT_GetSemaphore(nsem) == 0)
        DVT_JumpPos(pattern, note);
    while (DVT_GetSemaphore(nsem+1) == 0);
}

byte DVT_GetSoundVolume(void) {
    if (DVTInfo == NULL)    // Not initialized?
        return 255;
    return DVTInfo->soundVolume;
}

void DVT_SetSoundVolume(byte vol) {
    if (DVTInfo == NULL)    // Not initialized?
        return;
    DVTInfo->soundVolume = vol;
}

/* ------------------------ DPMIDVT.C --------------------------- */

