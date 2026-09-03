(* ------------------------ PASTST.PAS ---------------------- *)
(* DemoVT 1.5 Pascal example bye Jare/Iguana.                 *)

(* This thing shows how to create volume bars with DemoVT 1.5 *)
(* You have three types: by channels, instruments or notes.   *)

(* Channel bars are launched when DemoVT tells. ChansTrig[].  *)
(* Inst. and note bars are launched when any channel triggers *)
(* that instrument or note. Notes range from $14 to $6B0, but *)
(* most will do in the range shown here.                      *)

(* CARE: notes are logarithmic, they're really 1/frequency.   *)

{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,R-,S-,V-,X+}

USES PasDVT, Crt;

TYPE
   TScrB = ARRAY [0..24,0..79,0..1] OF BYTE;
   TScrW = ARRAY [0..24,0..79] OF WORD;
VAR
   ScrB : TScrB ABSOLUTE $B800:0000;
   ScrW : TScrW ABSOLUTE $B800:0000;

CONST
   MAXCHANS =  8;
   MAXBARCH = 32;

   NUMSAMPS = 31;
   MAXBARSA = 24;

   NUMFREQS = 64;
   MINFREQ  = $14;
   MAXFREQ  = $3B0;
   MAXBARFR = 24;

   MAXVOL   = 64;

VAR
   Chans     : ARRAY [1..MAXCHANS] OF INTEGER;
   Samps     : ARRAY [1..NUMSAMPS] OF INTEGER;
   Freqs     : ARRAY [1..NUMFREQS] OF INTEGER;
   OFreqs    : ARRAY [1..NUMFREQS] OF INTEGER;
   SampsChan : ARRAY [1..NUMSAMPS] OF BYTE;
   FreqsChan : ARRAY [1..NUMFREQS] OF BYTE;

   OldVMode : BYTE;

   NumChans : INTEGER;


PROCEDURE InitScr;
   CONST
      BOXATTR = $300;
   VAR
      i : INTEGER;
   BEGIN
      ASM
         MOV   AH,0Fh
         INT   10h
         MOV   [OldVMode],AL
         MOV   AX,3
         INT   10h
      END;

      FOR i := 0 TO 63 DO BEGIN
         ScrW[11,i] := WORD(BYTE('Ä') + BOXATTR);
         ScrW[13,i] := WORD(BYTE('Ä') + BOXATTR);

         ScrW[ 0,i] := $220;
         ScrW[ 1,i] := $220;
         ScrW[ 2,i] := $220;
         ScrW[ 3,i] := $220;
         ScrW[ 4,i] := $A20;
         ScrW[ 5,i] := $A20;
         ScrW[ 6,i] := $A20;
         ScrW[ 7,i] := $A20;
         ScrW[ 8,i] := $C20;
         ScrW[ 9,i] := $C20;
         ScrW[10,i] := $420;
         ScrW[14,i] := $420;
         ScrW[15,i] := $C20;
         ScrW[16,i] := $C20;
         ScrW[17,i] := $A20;
         ScrW[18,i] := $A20;
         ScrW[19,i] := $A20;
         ScrW[20,i] := $A20;
         ScrW[21,i] := $220;
         ScrW[22,i] := $220;
         ScrW[23,i] := $220;
         ScrW[24,i] := $220;
      END;

      FOR i := 0 TO 24 DO BEGIN
         ScrW[i,64] := WORD(BYTE('³') + BOXATTR);

         ScrW[i,65] := $420;
         ScrW[i,66] := $420;
         ScrW[i,67] := $C20;
         ScrW[i,68] := $C20;
         ScrW[i,69] := $C20;
         ScrW[i,70] := $A20;
         ScrW[i,71] := $A20;
         ScrW[i,72] := $A20;
         ScrW[i,73] := $A20;
         ScrW[i,74] := $A20;
         ScrW[i,75] := $220;
         ScrW[i,76] := $220;
         ScrW[i,77] := $220;
         ScrW[i,78] := $220;
         ScrW[i,79] := $220;
      END;

      ScrW[11,0] := WORD(BYTE('Ú') + BOXATTR);
      ScrW[12,0] := WORD(BYTE('³') + BOXATTR);
      ScrW[13,0] := WORD(BYTE('À') + BOXATTR);

      ScrW[11,64] := WORD(BYTE('´') + BOXATTR);
      ScrW[13,64] := WORD(BYTE('´') + BOXATTR);

      FOR i := 1 TO AppIdFound^[0] DO
         ScrW[12,i] := AppIdFound^[i] + $1E00;

      ScrB[0,0,1] := 0        { Hide cursor at (0,0). }
   END;


PROCEDURE UpdateScr;
   VAR
      i, j, k, l, h: INTEGER;
      Patt, Note : byte;
      PattStr, NoteStr : STRING[2];
   BEGIN

      VT_CurrentPos( Patt, Note );
      STR( Patt : 2, PattStr);
      STR( Note : 2, NoteStr);

      IF NoteStr[1] = ' ' THEN NoteStr[1] := '0';

      j := 59;
      FOR i := 1 TO Length(PattStr) DO
         BEGIN
            ScrW[12,j] := BYTE(PattStr[i]) + $1F00;
            INC(j);
         END;
      ScrW[12,j] := BYTE('/') + $1F00;
      INC(j);
      FOR i := 1 TO Length(NoteStr) DO
         BEGIN
            ScrW[12,j] := BYTE(NoteStr[i]) + $1F00;
            INC(j);
         END;



      h := 25 DIV NumChans;   { NOTE: h = 0 if NumChans > 12. }
                              { This results in missing bars. }

      FOR i := 1 TO NumChans DO BEGIN
         l := Chans[i] DIV 2;
         FOR j := 0 TO l-1 DO
            FOR k := 1 TO h-1 DO
               ScrB[h*i-h+k, 79-j, 0] := BYTE('Û');
         IF l <= 14 THEN
            IF (Chans[i] MOD 2) = 1 THEN
               FOR k := 1 TO h-1 DO
                  ScrB[h*i-h+k, 79-l, 0] := BYTE('Þ')
            ELSE
               FOR k := 1 TO h-1 DO
                  ScrB[h*i-h+k, 79-l, 0] := BYTE(' ');
         FOR j := l+1 TO 14 DO
            FOR k := 1 TO h-1 DO
               ScrB[h*i-h+k, 79-j, 0] := BYTE(' ')
      END;

      FOR i := 1 TO NUMSAMPS DO BEGIN
         l := Samps[i] DIV 2;
         FOR j := 0 TO l-1 DO
            ScrB[j, 2*i, 0] := BYTE('Û');
         IF l <= 10 THEN
            IF (Samps[i] MOD 2) = 1 THEN
               ScrB[l, 2*i, 0] := BYTE('ß')
            ELSE
               ScrB[l, 2*i, 0] := BYTE(' ');
         FOR j := l+1 TO 10 DO
            ScrB[j, 2*i, 0] := BYTE(' ')
      END;

      FOR i := 1 TO NUMFREQS DO BEGIN
         l := Freqs[i] DIV 2;
         FOR j := 0 TO l-1 DO
            ScrB[24-j, i-1, 0] := BYTE('Û');
         IF l <= 10 THEN
            IF (Freqs[i] MOD 2) = 1 THEN
               ScrB[24-l, i-1, 0] := BYTE('Ü')
            ELSE
               ScrB[24-l, i-1, 0] := BYTE(' ');
         FOR j := l+1 TO 10 DO
            ScrB[24-j, i-1, 0] := BYTE(' ')
      END
   END;

VAR
   i, j, v, p : INTEGER;
   fading, faded : BOOLEAN;
   fadevol : INTEGER;
   ticksToGo : LONGINT;

   period : word;
   instrument, volume : byte;
   triggered : boolean;

BEGIN
   WriteLn('PASTST: DemoVT''s Pascal interface example.');

   IF NOT VT_Init THEN BEGIN                    { Init DEMOVT           }
     WriteLn('DEMOVT not detected!');           { check if DEMOVT a-ok  }
     HALT(1);
   END;

   NumChans := VT_ChannelCount;

   FOR i := 1 TO NumChans DO
       Chans[i] := 0;
   FOR i := 1 TO NUMSAMPS DO BEGIN
       Samps[i] := 0;
       SampsChan[i] := 0
   END;
   FOR i := 1 TO NUMFREQS DO BEGIN
       Freqs[i] := 0;
       FreqsChan[i] := 0
   END;

   VT_GoTo(1, 1);
   VT_AutoOn;                                        { turn on timer control }
VT_AutoOff;
   VT_SetVolume(255);
   Write('Waiting for music to start sounding... ');
   VT_SyncStart;             { start playing music and delay for 1/2 second  }
   fadevol := 255;
   fading := FALSE;
   faded  := FALSE;
   InitScr;


   REPEAT
      VT_Delay(2);

      FOR i := 1 TO NumChans DO BEGIN

         VT_ChStatus( i, period, instrument, volume );
         triggered := VT_QueryCh( i );

         IF period < MINFREQ THEN
            p := 1
         ELSE IF period >= MAXFREQ THEN
            p := NUMFREQS
         ELSE
            p := 1+LONGINT(NUMFREQS)*(period - MINFREQ)
                   DIV (MAXFREQ-MINFREQ);

         p := NUMFREQS+1-p;

         IF (OFreqs[i] <> p) OR triggered THEN
            BEGIN
               v := MAXBARFR*INTEGER(volume) DIV MAXVOL;
               INC(Freqs[p], v);
               IF p > 1 THEN
                  INC(Freqs[p-1], v DIV 2);
               IF p > 2 THEN
                  INC(Freqs[p-2], v DIV 4);
               IF p < NUMFREQS THEN
                  INC(Freqs[p+1], v DIV 2);
               IF p < NUMFREQS-1 THEN
                  INC(Freqs[p+2], v DIV 4);
            END;
         OFreqs[i] := p;

         FOR j := p-2 TO p+2 DO
            IF (j >= 1) AND (j <= NUMFREQS) THEN
               IF Freqs[j] > MAXBARFR THEN
                  Freqs[j] := MAXBARFR;


(*
         IF (instrument > 0)
             AND (instrument <= NUMSAMPS)
             AND (SampsChan[instrument] <> i) THEN BEGIN
            Samps[instrument]     :=
               MAXBARSA*INTEGER(volume) DIV MAXVOL;
            SampsChan[instrument] := i
         END;

         IF FreqsChan[p] <> i THEN BEGIN
            Freqs[p]     := MAXBARFR*INTEGER(volume)
                            DIV MAXVOL;
            FreqsChan[p] := i
         END;
*)
         IF triggered THEN BEGIN
            Chans[i] := MAXBARCH*INTEGER(volume)
                        DIV MAXVOL;

            IF (instrument > 0)
                AND (instrument <= NUMSAMPS) THEN BEGIN
               Samps[instrument] :=
                  MAXBARSA*INTEGER(volume) DIV MAXVOL;
               SampsChan[instrument] := i;
            END;

{
            Freqs[p]     := MAXBARFR*INTEGER(volume)
                            DIV MAXVOL;
            FreqsChan[p] := i;
}

         END ELSE BEGIN
            IF Chans[i] > 0 THEN
               DEC (Chans[i]);
         END;
      END;

      FOR i := 1 TO NUMFREQS DO
         IF Freqs[i] > 0 THEN
            DEC(Freqs[i]);

      FOR i := 1 TO NUMSAMPS DO
         IF Samps[i] > 0 THEN
            DEC(Samps[i]);

      UpdateScr;

      IF KeyPressed THEN BEGIN
         ReadKey;
         fading := TRUE
      END;
      IF fading THEN BEGIN
         IF fadevol <= 0 THEN
            faded := (ticksToGo + 50) <= VT_Timer
         ELSE BEGIN
            VT_SetVolume(fadevol);
            DEC(fadevol,2);
            IF fadevol <= 0 THEN
               ticksToGo := VT_Timer
         END
      END
   UNTIL faded;

   VT_AutoOff;

   ASM
      MOV   AL,[OldVMode]
      XOR   AH,AH
      INT   10h
   END;

   VT_Abort;
END.


(* ------------------------ PASTST.PAS ---------------------- *)
