/* ------------------------ DPMITST.C --------------------------- */
/* DPMI interface to DemoVT v1.5 and higher; test program.        */
/* Written bye Jare of Iguana in 1994.                            */
/* -------------------------------------------------------------- */

#include <stdio.h>
#include <string.h>
#include <i86.h>
#include <conio.h>

#include "dpmidvt.h"

int main() {
    char buf[300];

    if (!DVT_Init()) {
        puts("DemoVT is not present.");
        return 1;
    }
    if (DVTInfo == NULL) {
        puts("DemoVT is present, but DPMI gave an error allocating memory.");
        return 1;
    }
    printf("There it is!!!! Info available at address %X:%08X\n"
           "                API entry point at %04X:%04X\n",
           FP_SEG(DVTInfo), FP_OFF(DVTInfo),
           DVTInfo->entryPointAXSeg, DVTInfo->entryPointAXOff);

    _fmemcpy(buf, RealModeMem + DVTAppIdFound + 1, RealModeMem[DVTAppIdFound]);
    buf[RealModeMem[DVTAppIdFound]] = '\0';
    printf("DemoVT version string is: >>%s<<\n", buf);
    DVT_BeginSync();
    DVT_SetSoundVolume(255);
//    DVT_ConnectTimer();
    DVT_WaitForStart();
    puts("GO!");
    while (!kbhit()) {
        DVT_CallMusic();
        printf("\rTicks: %5ld  Pos: %2d/%02d", DVT_GetTickCounter(),
               DVTInfo->seq, DVTInfo->pos);
    }
    getch();

    return 0;
}

/* ------------------------ DPMITST.C --------------------------- */

