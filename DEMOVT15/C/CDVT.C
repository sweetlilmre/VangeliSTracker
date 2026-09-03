/* -------------------------- CDVT.C ---------------------------- */
/* C interface code to DemoVT v1.5 and higher.                    */
/* Written bye Jare of Iguana in 1994.                            */
/* -------------------------------------------------------------- */
/* Based on code written by Carlos Quintero.                      */
/* -------------------------------------------------------------- */
/* Tested under TC++ 3.0, MSC/C++ 7.0 and BC++ 3.1                */
/* -------------------------------------------------------------- */

#include <stdlib.h>
#include <dos.h>

#include "cdvt.h"

 // -------------------------------------------------------

byte     _far *DVTAppIdFound = NULL;
TDVTInfo _far *DVTInfo       = NULL;


int DVT_Init(void) {
    union  REGS  regs;
    struct SREGS sregs;
    int present;

    if (DVTInfo != NULL)        // Already initialized?
        return 1;
    regs.x.ax = 0x5654;         // DemoVT magic numbers.
    regs.x.bx = 0x5472;
    regs.x.cx = 0x6163;
    regs.x.di = 0;
    sregs.es  = 0;
    int86x(0x2F, &regs, &regs, &sregs);

    present = (   regs.x.ax == 0       // Complex check.
               && regs.x.bx == 0x3F17
               && regs.x.cx == 0x1343);
    if (present) {                              // Allocate far pointer.
        word _far *g;
        DVTAppIdFound = MK_FP(sregs.es, regs.x.di);
        g = (word _far *) (DVTAppIdFound - 4);
        DVTInfo = (TDVTInfo _far *)(MK_FP(g[1], g[0]));
    }
    return present;
}

void DVT_CallDemoVT(word command) {
    if (DVTInfo == NULL                 // Not initialized?
        || command > 3)  // or invalid parameter?
        return;
    DVTInfo->entryPoint(command);
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
    while (DVT_GetSemaphore((byte)((int)nsem+1)) == 0);
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

/* -------------------------- CDVT.C ---------------------------- */

