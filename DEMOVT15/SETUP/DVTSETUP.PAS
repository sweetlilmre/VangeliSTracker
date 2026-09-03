{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,R-,S-,V-,X+}
{$M 4096,0,655360}

   (* Copyright by Jare/Iguana in 1993, but given to the public domain. *)
   (* Want more comments? Write'em!                                     *)

   (*   Main program. Does too many things not taken to separate units, *)
   (* but anyway it works.                                              *)

USES
   DOS,
   Devices, Menus, Output, Detections, Gfx, HexConversions, Reader;

VAR
   cfg : TCfg;

CONST
   rateit : ARRAY [1..13] OF TMenuIt = (
         (Text: ' 8000   386SX or Trident VGA'; Val: 8000),
         (Text: '10000          ú          '  ; Val:10000),
         (Text: '12000          ú          '  ; Val:12000),
         (Text: '14000          ú          '  ; Val:14000),
         (Text: '16000   Our 386/25+ET-4000'  ; Val:16000),
         (Text: '18000          ú          '  ; Val:18000),
         (Text: '20000          ú          '  ; Val:20000),
         (Text: '22000          ú          '  ; Val:22000),
         (Text: '26000          ú          '  ; Val:26000),
         (Text: '32000          ú          '  ; Val:32000),
         (Text: '38000          ú          '  ; Val:38000),
         (Text: '44000   486 or higher.    '  ; Val:44000),
         (Text: 'Accept previous selection'   ; Val:$FFFF)
   );
PROCEDURE ChooseRate;
  VAR
     ch : WORD;
     i  : INTEGER;
  BEGIN
     IF (cfg.SoundDevice = NONE) OR (cfg.SoundDevice = GUS) THEN
        EXIT;
     ClearArea;
     ClearMenu(mm^);
     FOR i := 1 TO 13 DO
        AddItem(mm^, rateit[i], TRUE);
     ch := DoMenu(mm^, cfg.ReplayRate);
     IF ch <> $FFFF THEN
        cfg.ReplayRate := ch;
     ClearArea
  END;


CONST
   devit : ARRAY [1..9] OF TMenuIt = (
        (Text:'Stereo SoundBlaster 16 ASP'; Val:ORD(S_SB16ASP)),
        (Text:'Mono SoundBlaster 16 ASP'  ; Val:ORD(M_SB16ASP)),
        (Text:'Stereo SoundBlaster Pro'   ; Val:ORD(S_SBPRO)),
        (Text:'Mono SoundBlaster Pro'     ; Val:ORD(M_SBPRO)),
        (Text:'Plain SoundBlaster'        ; Val:ORD(SB)),
        (Text:'Gravis Ultrasound'         ; Val:ORD(GUS)),
        (Text:'PAS (SB emulation, sorry)' ; Val:ORD(PAS)),
        (Text:'No Sound'                  ; Val:ORD(NONE)),
        (Text: 'Accept previous selection'; Val:$FFFF)
   );
PROCEDURE SelectDevice;
  CONST
     compareDevices: ARRAY [TDevices] OF BYTE = (
        0, 0, 0, 0, 0,
        1,
        0,
        2,
        255);
  VAR
     ch : WORD;
     i  : INTEGER;
  BEGIN
     ClearArea;
     ClearMenu(mm^);
     FOR i := 1 TO 9 DO
        AddItem(mm^, devit[i], TRUE);
     ch := DoMenu(mm^, ORD(cfg.SoundDevice));
     IF ch <> $FFFF THEN BEGIN
        IF (cfg.SoundDevice >= DEV_INVALID) OR
           (compareDevices[TDevices(ch)] <> compareDevices[cfg.SoundDevice]) THEN BEGIN
           cfg.SoundDevice := TDevices(ch);
           CASE compareDevices[TDevices(ch)] OF
              0: BEGIN
                    cfg.Port := $220;
                    cfg.IRQ  := 7;
                    cfg.DMA  := 1;
                    DetectSoundEnvironment(cfg)
                 END;
              1: BEGIN
                    cfg.Port := $240;
                    cfg.IRQ  := 11;
                    DetectSoundEnvironment(cfg)
                 END;
              2: BEGIN
                    cfg.Port := $3F8;
                    cfg.IRQ  := 4
                 END
           END
        END;
        cfg.SoundDevice := TDevices(ch);
     END;
     ClearArea
  END;


PROCEDURE SetPort;
  CONST
     silencePorts: ARRAY [1..4] OF TMenuIt = (
        (Text:'3F8h (Serial Port COM1)'; Val:$3F8),
        (Text:'2F8h (Serial Port COM2)'; Val:$2F8),
        (Text:'3E8h (Serial Port COM3)'; Val:$3E8),
        (Text:'2E8h (Serial Port COM4)'; Val:$2E8)
     );
  VAR
     portit: TMenuIt;
     ch : WORD;
     i  : INTEGER;
  BEGIN
     IF cfg.SoundDevice > NONE THEN
        EXIT;
     ClearArea;
     ClearMenu(mm^);
     IF cfg.SoundDevice = NONE THEN BEGIN
        FOR i := 1 TO 4 DO
           AddItem(mm^, silencePorts[i], TRUE);
        AddItem(mm^, rateit[13], TRUE)
     END ELSE BEGIN
        FOR i := 1 TO 12 DO BEGIN
           portit.Text := 'Port number 2'+HexByte((i-1)*16)+'h';
           portit.Val  := (i-1)*16 + $200;
           AddItem(mm^, portit, TRUE);
        END;
        AddItem(mm^, rateit[13], TRUE)
     END;
     ch := DoMenu(mm^, cfg.Port);
     IF ch <> $FFFF THEN BEGIN
        cfg.Port := ch;
        IF cfg.SoundDevice = NONE THEN
           IF cfg.Port = $3F8 THEN
              cfg.IRQ := 4
           ELSE IF cfg.Port = $2F8 THEN
              cfg.IRQ := 3
     END;
     ClearArea;
  END;


PROCEDURE SetIRQ;
  VAR
     irqit : TMenuIt;
     ch    : WORD;
     i     : INTEGER;
     s     : STRING;
  BEGIN
     IF cfg.SoundDevice > NONE THEN
        EXIT;
     ClearArea;
     ClearMenu(mm^);
     FOR i := 2 TO 15 DO
        IF (i <> 6) AND (i <> 9) THEN BEGIN
           Str(i : 2, s);
           irqit.Text := 'IRQ number '+s;
           irqit.Val  := i;
           AddItem(mm^, irqit, TRUE)
        END;
     AddItem(mm^, rateit[13], TRUE);
     ch := DoMenu(mm^, cfg.IRQ);
     IF ch <> $FFFF THEN
        cfg.IRQ := ch;
     ClearArea;
  END;

PROCEDURE SetDMA;
  VAR
     dmait : TMenuIt;
     ch    : WORD;
     i     : INTEGER;
     s     : STRING;
  BEGIN
     IF (cfg.SoundDevice >= NONE) OR (cfg.SoundDevice = GUS) THEN
        EXIT;
     ClearArea;
     ClearMenu(mm^);
     FOR i := 0 TO 7 DO
        IF (i <> 2) AND (i <> 4) THEN BEGIN
           Str(i : 2, s);
           dmait.Text := 'DMA channel '+s;
           dmait.Val  := i;
           AddItem(mm^, dmait, TRUE)
        END;
     AddItem(mm^, rateit[13], TRUE);
     ch := DoMenu(mm^, cfg.DMA);
     IF ch <> $FFFF THEN
        cfg.DMA := ch;
     ClearArea;
  END;



FUNCTION Cfg2Text: STRING;
  VAR
     s1, s2 : STRING;
  BEGIN
     s1 := 'Device: '+devit[ORD(cfg.SoundDevice)+1].Text;
     IF cfg.SoundDevice <> NONE THEN BEGIN
        s1 := s1;
        IF cfg.SoundDevice <> GUS THEN BEGIN
           Str(cfg.ReplayRate, s2);
           s1 := s1 + ', Rate = ' + s2
        END;
        s1 := s1 + ', Port ' + HexWord(cfg.Port) + 'h, IRQ ';
        Str(cfg.IRQ, s2);
        s1 := s1 + s2;
        IF cfg.SoundDevice <> GUS THEN BEGIN
           Str(cfg.DMA, s2);
           s1 := s1 + ', DMA ' + s2
        END
     END ELSE BEGIN
        IF (cfg.Port = $3F8) AND (cfg.IRQ = 4) THEN
           s1 := s1 + ' (COM1)'
        ELSE IF (cfg.Port = $3F8) AND (cfg.IRQ = 4) THEN
           s1 := s1 + ' (COM1)'
        ELSE IF (cfg.Port = $2F8) AND (cfg.IRQ = 3) THEN
           s1 := s1 + ' (COM2)'
        ELSE IF (cfg.Port = $3E8) AND (cfg.IRQ = 4) THEN
           s1 := s1 + ' (COM3)'
        ELSE IF (cfg.Port = $2E8) AND (cfg.IRQ = 3) THEN
           s1 := s1 + ' (COM4)'
        ELSE BEGIN
           s1 := s1 + ', Serial Port ' + HexWord(cfg.Port) + 'h, IRQ ';
           Str(cfg.IRQ, s2);
           s1 := s1 + s2
        END
     END;
     Cfg2Text := s1
  END;


CONST
   mainit : ARRAY [1..8] OF TMenuIt = (
         (Text:'Run the demo'; Val:0),
         (Text:'Select sound device'; Val:1),
         (Text:'Choose sampling rate'; Val:2),
         (Text:'Set port number'; Val:3),
         (Text:'Set IRQ'; Val:4),
         (Text:'Set DMA channel'; Val:5),
         (Text:'Notes of interest'; Val:6),
         (Text:'Exit to DOS'; Val:$FFFF)
   );
PROCEDURE MainMenu;
  VAR
     ch : WORD;
     i  : INTEGER;
     uopts : ARRAY [1..8] OF BOOLEAN;
  BEGIN
     ch := 0;
     FOR i := 1 TO 8 DO
       uopts[i] := TRUE;
     IF cfg.SoundDevice = DEV_INVALID THEN BEGIN
        cfg.SoundDevice := NONE;
        SelectDevice;
        IF cfg.SoundDevice <> NONE THEN BEGIN
           IF cfg.SoundDevice = GUS THEN BEGIN
              cfg.DMA  :=    5;  {Not used}
              cfg.IRQ  :=   11;
              cfg.Port := $240;
              cfg.ReplayRate := 44000; {WOW!}
           END ELSE BEGIN
              cfg.DMA  :=    1;  {Not used}
              cfg.IRQ  :=    7;
              cfg.Port := $220;
              cfg.ReplayRate := 16000; {WOW!}
           END;
           ChooseRate;
           SetPort;
           SetIRQ;
           SetDMA
        END
     END;
     REPEAT
        DumpDevice(CFG2Text);
        ClearMenu(mm^);
        uopts[3] := NOT((cfg.SoundDevice = NONE) OR (cfg.SoundDevice = GUS));
        {uopts[4] := NOT(cfg.SoundDevice = NONE);}
        {uopts[5] := NOT(cfg.SoundDevice = NONE);}
        uopts[6] := NOT((cfg.SoundDevice = NONE) OR (cfg.SoundDevice = GUS));
        FOR i := 1 TO 8 DO
           AddItem(mm^, mainit[i], uopts[i]);
        ch := DoMenu(mm^, ch);
        CASE ch OF
           1 : SelectDevice;
           2 : ChooseRate;
           3 : SetPort;
           4 : SetIRQ;
           5 : SetDMA;
           6 : ReadText;
           $FFFF : BEGIN EndScreen; HALT(1); END;
        END;
     UNTIL ch = 0;
  END;


PROCEDURE Usage;
   BEGIN
      WriteLn(#13#10'     This demo detects the soundcard settings via the environment variables',
              #13#10'BLASTER and ULTRASND. If that fails, it will ask you.');

      WriteLn(#13#10'     After first running this  demo,  a  file called DVT.CFG will contain',
              #13#10'the sound settings. Then you can execute the demo again, passing  something',
              #13#10'as a parameter, and the demo will run without going thru the setup process.',
              #13#10'This is useful in a slideshow, for example.');

      WriteLn(#13#10'     Arbitrary greetings JMP to: N‚stor Matas, Carlos Fernandez Sanz, Patxi',
              #13#10'O''larte ;-D, Mario Elkati, Juananton  Roque, Manuel Petit, Oscar G., Javier',
              #13#10'Olmo, Alejandro Lopez, Antonio Ropero, Phil Carlisle, Jeff Lawson  and  all',
              #13#10'other  people  that  has  helped in the development of the VangeliSTracker.',
              #13#10'Modplaying greetings  JMP  to  the  creators  of  the  great Visual Player.',
              #13#10'Looking forward to see a GUS version of VP3... :)');

      Write  (#13#10'     Group greetings to: <odeNation, Capt.Bit/?, Reset, Dust, Gore and  all',
              #13#10'at Future Crew, Triton, Silents PC, all (SO many) at Surprise! Productions,',
              #13#10'Renaissance, Tran, W.Shadow, Edge/UXP, Type One, The Incredibly Long-Haired',
              #13#10'Avatar,  all at  Xography, Cascada,  Pallbearer,  EMF,  Avalanche,  Pelusa,',
              #13#10'Irresistible Works, ImpCDA, Mental Design, Extreme, Epical, Darkzone, Gregg',
              #13#10'and  Phantom,  Gollum,  Five and then Some (!), Majic-12, the InertiaPlayer',
              #13#10'team, etc. If you''re not in this list, feel free to add yourself.');

      HALT(1);
   END;


VAR
   fcfg : FILE OF TCfg;
   fvto : TEXT;
   i, j : INTEGER;
   s    : STRING;

CONST
   VTDevs : ARRAY [TDevices] OF STRING = (
         'DMA-SB-Stereo',
         'DMA-SB-Mono',
         'DMA-SB-Stereo',
         'DMA-SB-Mono',
         'DMA-SB-Mono',
         'GUS',
         'DMA-SB-Mono',
         'Silence',
         'Silence'    (* If you don't know which card, then no card. *)
   );

CONST
   ThereIsCfg : BOOLEAN = FALSE;


BEGIN

     (* Place your own banner here. *)
   WriteLn('DemoVT Setup program (C) 1993-94 by Iguana/VangeliSTeam'#13#10,
           '   Use SETUP /? to see the help text.'#13#10);

   IF ParamCount > 0 THEN
      FOR j := 1 TO ParamCount DO BEGIN
         s := ParamStr(j);
         FOR i := 1 TO Length(s) DO
            IF (s[i] = '?') OR (UpCase(s[i]) = 'H') THEN
               Usage
      END;

   CheckFilesOK;

   Assign(fcfg, 'DVT.CFG');
   Reset(fcfg);
   IF IOResult = 0 THEN BEGIN
      ThereIsCfg := TRUE;
      Read(fcfg, cfg);
      Close(fcfg)
   END ELSE BEGIN
      cfg.SoundDevice := DEV_INVALID;
      cfg.ReplayRate  := 16000;
      cfg.IRQ  := 7;  (* Something to use as default values. *)
      cfg.DMA  := 1;
      cfg.Port := $220;
      DetectSoundEnvironment(cfg)
   END;

   Assign(fvto, 'DVT.VTO');
   ReWrite(fvto);
   WriteLn(fvto, '; This file is generated by the DemoVT setup program.');
   WriteLn(fvto);
   Close(fvto);
   IF IOResult <> 0 THEN BEGIN
      Erase(fvto);
      WriteLn;
      WriteLn('I need at least 2 clusters of disk space to run the demo.');
      WriteLn('Reboot during the demo if you feel curious why, but give me that space.');
      HALT(1);
   END;
   Erase(fvto);

   IF (ParamCount < 1) OR NOT ThereIsCfg THEN BEGIN
      IF NOT IsVGA THEN BEGIN
         WriteLn(#13'                                              ');
         WriteLn('I think you don''t have the required VGA card.');
         Write(' Continue anyway? (y/N) ');
         IF UpCase(CHAR(GetKey)) <> 'Y' THEN BEGIN
            WriteLn;
            WriteLn('Go buy a cool ET-4000 or something like that.');
            HALT(1)
         END
      END;

      IF NOT Is386 THEN BEGIN
         WriteLn(#13'                                              ');
         WriteLn('I can''t find a 386SX or higher in your machine. I need one.');
         Write(' Continue anyway? (y/N) ');
         IF UpCase(CHAR(GetKey)) <> 'Y' THEN BEGIN
            WriteLn;
            WriteLn('Have a sad DOS (without a 386 it sure will be).');
            HALT(1)
         END
      END;

      ASM
        MOV  AX,3
        INT  10h
      END;

      InitScreen;
      SplitIn;

      MainMenu;

      SplitOut;
      EndScreen;

      Assign(fcfg, 'DVT.CFG');
      ReWrite(fcfg);
      IF IOResult = 0 THEN BEGIN
         Write(fcfg, cfg);
         Close(fcfg)
      END;

      IF ((cfg.SoundDevice = NONE) AND HasMouse) OR IsProtMode THEN BEGIN
         IF IsProtMode THEN BEGIN
            WriteLn('You are running in protected mode (EMM386, QEMM, Windows, OS/2, DesqView).'#13#10,
                    'If the demo runs slow or flickers, try booting with a clean MSDOS.'#13#10);
         END;
         IF (cfg.SoundDevice = NONE) AND HasMouse THEN BEGIN
            WriteLn('You have selected silent mode, but your mouse driver may cause conflicts.');
            WriteLn('If you experience any problems, try changing the COM port and IRQ.');
         END;
         Write(' Press any key to continue');
         GetKey;
         WriteLn(#13'                                              ');
      END;
   END;

   Assign(fvto, 'DVT.VTO');
   ReWrite(fvto);
   WriteLn(fvto, '; This file is generated by the DemoVT setup program.');
   WriteLn(fvto);

     (* First we set the sound options for DemoVT.   *)

   WriteLn(fvto, '/d:', VTDevs[cfg.SoundDevice]);
   WriteLn(fvto, '/port:', cfg.Port);
   WriteLn(fvto, '/irq:', cfg.IRQ);
   IF NOT (cfg.SoundDevice IN [NONE, GUS]) THEN BEGIN
      WriteLn(fvto, '/dma:', cfg.DMA);
      WriteLn(fvto, '/f:', cfg.ReplayRate);
   END;
   WriteLn(fvto);

     (* Then we place each MOD and the program that runs under it. *)
     (* Set up this as appropiate for your program.                *)

   WriteLn(fvto, '/nobf');
   WriteLn(fvto, '/v:80');
   WriteLn(fvto, '  DEMODEMO.MOD /sh:EXAMPLE.EXE');
   Close(fvto)
END.

