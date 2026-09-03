{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,R-,S-,V-,X+}
UNIT Devices;

   (* Copyright by Jare/Iguana in 1993, but given to the public domain. *)
   (* Want more comments? Write'em!                                     *)

   (*    Sound device detection and configuration file various.         *)

INTERFACE

TYPE
   TDevices = (S_SB16ASP, M_SB16ASP, S_SBPRO, M_SBPRO, SB,
               GUS,
               PAS,
               NONE,
               DEV_INVALID);   (* == No idea of the configuration. *)

   TCfg = RECORD
      SoundDevice : TDevices;
      ReplayRate  : WORD;
      Port        : WORD;
      IRQ         : WORD;
      DMA         : WORD;
   END;


PROCEDURE DetectSoundEnvironment(VAR cfg : TCfg);


   (* ========================================= *)

IMPLEMENTATION

USES Dos;

PROCEDURE DetectSoundEnvironment(VAR cfg : TCfg);
  VAR
     v : STRING;
     i : INTEGER;

  PROCEDURE DoUltraSnd;
    BEGIN
       cfg.SoundDevice := GUS;
       i := 1;
       cfg.Port := 0;
       cfg.IRQ  := 0;
       WHILE (i <= Length(v)) AND (v[i] <> ',') DO BEGIN
          cfg.Port := cfg.Port*16 + ORD(v[i]) - ORD('0');
          INC(i)
       END;
       IF i < Length(v) THEN
          INC(i);

       WHILE (i <= Length(v)) AND (v[i] <> ',') DO BEGIN
          cfg.DMA := cfg.DMA*10 + ORD(v[i]) - ORD('0');
          INC(i)
       END;
       IF i < Length(v) THEN
          INC(i);

       WHILE (i <= Length(v)) AND (v[i] <> ',') DO
          INC(i);
       IF i < Length(v) THEN
          INC(i);

       WHILE (i <= Length(v)) AND (v[i] <> ',') DO BEGIN
          cfg.IRQ := cfg.IRQ*10 + ORD(v[i]) - ORD('0');
          INC(i)
       END;
    END;

  PROCEDURE DoSBlaster;
    VAR
      p     : ^WORD;
      dummy : WORD;
      base  : WORD;
    BEGIN
       cfg.SoundDevice := SB;
       i := 1;
       cfg.Port := 0;
       cfg.IRQ  := 0;
       cfg.DMA  := 0;
       WHILE (i <= Length(v)) DO BEGIN
          CASE v[i] OF
             'A' : BEGIN
                      p := @cfg.Port;
                      base := 16
                   END;
             'D' : BEGIN
                      p := @cfg.DMA;
                      base := 10
                   END;
             'I' : BEGIN
                      p := @cfg.IRQ;
                      base := 10
             END ELSE BEGIN
                p := @dummy;
                base := 0
             END
          END;
          INC(i);
          WHILE (i <= Length(v)) AND (v[i] <> ' ') DO BEGIN
             p^ := p^*base + ORD(v[i]) - ORD('0');
             INC(i)
          END;
          IF i < Length(v) THEN
            INC(i)
       END
    END;

  BEGIN
    v := GetEnv('ULTRASND');
    IF (v <> '') AND (cfg.SoundDevice IN [GUS, DEV_INVALID]) THEN
       DoUltraSnd
    ELSE BEGIN
       v := GetEnv('BLASTER');
       IF (v <> '') AND NOT (cfg.SoundDevice IN [GUS, DEV_INVALID]) THEN
          DoSBlaster
       ELSE BEGIN
          cfg.IRQ  := 4;
          cfg.DMA  := 1;
          cfg.Port := $3F8
       END
    END
  END;

END.
