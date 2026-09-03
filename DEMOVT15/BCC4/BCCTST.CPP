/*

    Example routine for BCCDVT.CPP  //  ARM 4/94

*/

#include <stdio.h>
#include <conio.h>
#include "bccdvt.cpp"

void PressAnyKey( char* what )
{
    printf( "Press any key %s...\n\n", what );
    while (kbhit()) getch();
    while (!kbhit()) ;
    while(kbhit()) getch();
}


// -- pattern/note display ------------------------------------------

void Demo_PatternNote()
{
   BOOL fullvolume = 1;

   puts("Music will play for 10 seconds...");
   VT_SetVolume(255);
   VT_AutoOn();
   VT_SyncStart();
   puts("  Starts sounding now!");

   do
   {
     int patt, note;
     DWORD timer;

     VT_CurrentPos( patt, note );
     timer = VT_Timer();

     printf( "\r  Seconds*100: %4li, Pattern: %3u, Note: %3u",
             timer<<1, patt, note);

     // 1/2 second before time's up we put the volume down (since
    //  the change will take 1/2 second to reach the speakers).

     if (fullvolume && ( timer > 10*50-25 ))
     {
        fullvolume = 0;
        VT_SetVolume(0);
     }

   }
   while (VT_Timer()<=10*50);

   puts("\n");

   VT_Delay(15);  // allow some time for DEMOVT to fill DMA buffer...
   VT_AutoOff();  // stop updating music

  // (on DMA devices, there's a chunk of music still playing at volume 0)

}


// -- fading volume in and out --------------------------------------

void Demo_Fading()
{
   int i,j;

   puts("Fading in and out two times...");

   VT_AutoOn();     // start updating again

   // raise and lower volume two times

   for ( i=0; i<2; i++ )
   {
     for ( j=15; j<=255; j+=2 )
     {
        VT_SetVolume(j);
        VT_Delay(2);
     }
     for ( j=255; j>=15; j-=2 )
     {
        VT_SetVolume(j);
        VT_Delay(2);
     }
   }

   // kill volume, and wait at least 1/2 sec for it to take efect:

   VT_SetVolume(0);
   VT_Delay(60);
   VT_AutoOff();

   puts("\n");
}


// -- "grand finale" ------------------------------------------------

struct TPixel {
   int  x;
   long int  y;
   int vx;
   long int vy;
   int color;
};

void Demo_Finale( int NoDots )
{
   typedef BYTE TVGA [200][320];
   TVGA far * VGA;
   VGA = (TVGA far *) 0xa0000000;

   BYTE vmode;

   // set vga 13h display mode

   asm {
    mov ah, 0fh
    int 10h
    mov [vmode], al   // store video mode, before changing it
    mov ax,13h
    int 10h           // good ol' 320x200x256
   }

   // setup array

   TPixel* Dots = new TPixel [ NoDots ];

   {
     for (int i=0; i<NoDots; i++) Dots[i].color = 0;
   }

   // start sound

   VT_AutoOn();
   VT_Delay(50);
   VT_GoTo( 1,1 );
   VT_SetVolume( 255 );
// VT_Delay( 50 );

   // play till key pressed

   int NumChans = VT_ChannelCount();

   int DotPtr = 0;
   do
   {
       int i;

       // add dots

       for ( i = 1; i<=NumChans; i++ )
       {
          if ( VT_QueryCh(i) )
          {
             WORD period;
             BYTE instrument, volume;

             VT_ChStatus( i, period, instrument, volume );

             period <<=2 ;
             if (period<(190<<4))
             {
                if ((instrument&1)==0)
                {
                    Dots[ DotPtr ].x = 0;
                    Dots[ DotPtr ].vx= 1;
                }
                else
                {
                    Dots[ DotPtr ].x = 319;
                    Dots[ DotPtr ].vx= -1;
                }
                Dots[ DotPtr ].y = period;
                Dots[ DotPtr ].vy= 0;

                if ((instrument = 16-instrument)==0) instrument = 15;
                Dots[ DotPtr ].color=instrument;

                DotPtr++;
                if (DotPtr==NoDots) DotPtr = 0;
             }
          }
       }

       // update and draw dots

       for ( i = 0; i<NoDots; i++)
       {
          if (Dots[i].color!=0)
          {
             TPixel Dot = Dots[i];

             (*VGA)[ Dot.y>>4 ][ Dot.x ] = 0;

             Dot.x += Dot.vx;
             Dot.y += Dot.vy;

             if ( (Dot.x>=319) || (Dot.x<0) )
                Dot.color = 0;
             else
             {
                if ( (Dot.y>(199<<4)) )
                {
                   Dot.vy = -Dot.vy*15/16;
                   Dot.y += 2*Dot.vy;
                }

                Dot.vy++;

                (*VGA)[ Dot.y>>4 ][ Dot.x ] = Dot.color;
             }

             Dots[i] = Dot;
          }
       }
   }
   while (!kbhit());
   while (kbhit()) getch();

   // dispose dots

   delete[] Dots;

   // restore video

   asm {
     xor ah,ah
     mov al,[vmode]
     int 10h
   }
}

int main()
{
    char DemoVTver [32];

    puts("\nDEMOVT / BC++ interface demo.\n");

    if (! VT_Init() )
    {
      puts( "Can't find DemoVT!!" );
      return 1;
    }

    VT_IDstring( DemoVTver );
    printf( "DemoVT found. Version string is \"%s\".\n"
            "Number of channels: %i.\n"
            "VT_Info points to: %Fp.\n\n",
           DemoVTver, VT_ChannelCount(), VT_Info );

      PressAnyKey( "to play showing pattern/note" );
    Demo_PatternNote();
      PressAnyKey( "to fade volume to and fro");
    Demo_Fading();
      PressAnyKey( "for grand finale" );
    Demo_Finale( 320*6 );

    VT_Abort();

    puts("\n");
    return 0;
}

