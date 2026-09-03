/* -------------------------- CTST.C ---------------------------- */
/* C interface to DemoVT v1.5 and higher; test program.           */
/* Written bye Jare of Iguana in 1994.                            */
/* -------------------------------------------------------------- */

#include <stdio.h>
#include <string.h>
#include <conio.h>
#include <dos.h>

#include "cdvt.h"

int main() {
    char buf[300];

    if (!DVT_Init()) {
        puts("DemoVT is not present.");
        return 1;
    }
    if (DVTInfo == NULL) {
        puts("DemoVT is present, but there was some obscure error.");
        return 1;
    }
    printf("There it is!!!! Info available at address %04X:%04X\n"
           "                API entry point at %04X:%04X\n",
           FP_SEG(DVTInfo), FP_OFF(DVTInfo),
           FP_SEG(DVTInfo->entryPoint), FP_OFF(DVTInfo->entryPoint));

    _fmemcpy(buf, DVTAppIdFound + 1, DVTAppIdFound[0]);
    buf[DVTAppIdFound[0]] = '\0';
    printf("DemoVT version string is: >>%s<<\n", buf);

    puts("Beginning....");
    DVT_BeginSync();
    DVT_SetSoundVolume(255);
//    DVT_ConnectTimer();
    DVT_WaitForStart();
    puts("GO!");
    while (!kbhit()) {
        DVT_CallMusic();
        printf("\rTicks: %6.6ld  Pos: %2d/%02d", DVT_GetTickCounter(),
               DVTInfo->seq, DVTInfo->pos);
    }
    getch();
    puts("");

    return 0;
}

/* -------------------------- CTST.C ---------------------------- */

