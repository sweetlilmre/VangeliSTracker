UNIT VTStrConst;

INTERFACE

USES Objects;




CONST
  StrPosition       = $1000;
  StrPattern        = $1001;
  StrNote           = $1002;
  StrTempo          = $1003;

  StrModule         = $1100;
  StrFilename       = $1101;
  StrMemoryLeft     = $1102;
  StrSampleRate     = $1103;
  StrVolume         = $1104;

  StrMenu1          = $1201;
  StrMenu2          = $1202;
  StrMenu3          = $1203;
  StrMenu4          = $1204;
  StrMenu5          = $1205;
  StrMenu6          = $1206;
  StrMenu7          = $1207;
  StrMenu8          = $1208;
  StrMenu9          = $1209;
  StrMenu0          = $120A;

  StrOscilloscView  = $1300;
  StrGUSOscillosc   = $1310;

  StrChannel        = $1400;

  StrCreditsTitle   = $14FF;

  StrDedicat        = $1500;
  StrCredits        = $1520;

  StrUsageTop       = $2000;
  StrUsage01        = $2001;
  StrUsageBottom    = $200D;
  StrUsageEmpty     = $200E;
  StrUsagePressAKey = $200F;

  StrUsage1Beg      = $2020;
  StrUsage2Beg      = $2040;
  StrUsage3Beg      = $2060;
  StrUsage4Beg      = $2080;

  StrInitializing   = $2200;




PROCEDURE VTAddSpanishMsg(VAR List: TStrListMaker);
PROCEDURE VTAddEnglishMsg(VAR List: TStrListMaker);




IMPLEMENTATION




PROCEDURE VTAddSpanishMsg(VAR List: TStrListMaker);
  BEGIN
    List.Put(StrPosition               , 'Posici¢n:  ');
    List.Put(StrPattern                , 'Patr¢n:    ');
    List.Put(StrNote                   , 'Nota:      ');
    List.Put(StrTempo                  , 'Tempo:     ');

    List.Put(StrModule                 , 'M¢dulo:    ');
    List.Put(StrFilename               , 'Fichero:   ');
    List.Put(StrMemoryLeft             , 'Mem. libre:');
    List.Put(StrSampleRate             , 'Frecuencia:');
    List.Put(StrVolume                 , 'Volumen:');

    List.Put(StrMenu1                  , 'PAr/Ab Otro patr¢n     ');
    List.Put(StrMenu2                  , 'In/Fin Idem (principio)');
    List.Put(StrMenu3                  , '1-8    Apagar canal    ');
    List.Put(StrMenu4                  , 'F5-F9  Varias ventanas ');
    List.Put(StrMenu5                  , 'Iz/Dch.Desplaza canales');
    List.Put(StrMenu6                  , 'R/T    Frec. de salida ');
    List.Put(StrMenu7                  , '+/-    Volumen         ');
    List.Put(StrMenu8                  , 'D      Shell al DOS    ');
    List.Put(StrMenu9                  , 'N/S    Sig. canci¢n    ');
    List.Put(StrMenu0                  , 'ESC    Parar           ');

    List.Put(StrOscilloscView          , 'Osciloscopio');
    List.Put(StrGUSOscillosc           , '               El osciloscopio no est  disponible cuando se usa la GUS');

    List.Put(StrChannel                , 'Canal    ');

    List.Put(StrCreditsTitle           , '                               Cr‚ditos');

    List.Put(StrCredits                , '     - Juan Carlos Ar‚valo  ú ³ Originador de todo el tinglado.');
    List.Put(StrCredits+ 1             , '                              ³ Cuerpo del programa. Estructura');
    List.Put(StrCredits+ 2             , '                              ³ general. Primeras versiones.');
    List.Put(StrCredits+ 3             , '');
    List.Put(StrCredits+ 4             , '     - Luis Crespo  úúúúúúúúú ³ Antecesor del programa (JAMP).');
    List.Put(StrCredits+ 5             , '                              ³ Rutinas de DMA. Informaci¢n sobre');
    List.Put(StrCredits+ 6             , '                              ³ Sound Blaster.');
    List.Put(StrCredits+ 7             , '');
    List.Put(StrCredits+ 8             , '     - F‚lix Sanz  úúúúúúúúúú ³ Creaci¢n de los DOCs de usuario.');
    List.Put(StrCredits+ 9             , '');
    List.Put(StrCredits+10             , '     - Alejandro L¢pez  úúúúú ³ Idea original de la mezcla de');
    List.Put(StrCredits+11             , '                              ³ canales en est‚reo.');
    List.Put(StrCredits+12             , '');
    List.Put(StrCredits+13             , '     - H‚ctor Mart¡nez  úúúúú ³ Rutinas FFT. (no introducidas');
    List.Put(StrCredits+14             , '                              ³ todav¡a).');
    List.Put(StrCredits+11             , '                              ³ Idea original del sistema de');
    List.Put(StrCredits+16             , '                              ³ manejo de los 4 canales.');
    List.Put(StrCredits+17             , '');
    List.Put(StrCredits+18             , '     - David L¢pez  úúúúúúúúú ³ Informaci¢n sobre SB-Pro est‚reo.');
    List.Put(StrCredits+19             , '');
    List.Put(StrCredits+20             , '     - Angel Trigo  úúúúúúúúú ³ Informaci¢n sobre SB-Pro est‚reo.');
    List.Put(StrCredits+21             , '');
    List.Put(StrCredits+22             , '     - Carlos Fern ndez  úúúú ³ Realizada una modificaci¢n en');
    List.Put(StrCredits+23             , '                              ³ el swapping, para que funcione');
    List.Put(StrCredits+24             , '                              ³ con CD-ROMS.');
    List.Put(StrCredits+25             , '');
    List.Put(StrCredits+26             , '     - N‚stor Matas  úúúúúúúú ³ Traducci¢n del manual al Ingl‚s.');
    List.Put(StrCredits+27             , '');
    List.Put(StrCredits+28             , 'NOTA: Esta versi¢n de VT no soporta ninguna tarjeta aparte de la GUS.');
    List.Put(StrCredits+29             , '      Otras tarjetas ser n soportadas de nuevo en futuras versiones de VT.');
    List.Put(StrCredits+30             , '');
    List.Put(StrCredits+31             , #0);

    List.Put(StrDedicat                , '         Esta versi¢n est  dedicada a Gore/FC y a John Smith.');
    List.Put(StrDedicat+1              , '           Ambos han contribu¡do de una forma muy especial.');
    List.Put(StrDedicat+2              , #0);

    List.Put(StrUsageTop               ,' ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
    List.Put(StrUsage01                ,' ³ VT  <fichero>[.MOD|.OKT|.S3M|.STM|.669| etc] [<opciones>] [@<fichero.VTO>] ³');
    List.Put(StrUsageBottom            ,' ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ');
    List.Put(StrUsageEmpty             ,' ³                                                                            ³');
    List.Put(StrUsagePressAKey         ,'                      ---===ğğğ Pulsa  una tecla ğğğ===---');

    List.Put(StrUsage1Beg              ,' ³ <fichero> acepta comodines (wildards). Se pueden especificar varios.       ³');
    List.Put(StrUsage1Beg+1            ,' ³           Tambi‚n se puede especificar la canci¢n que est  dentro de una   ³');
    List.Put(StrUsage1Beg+2            ,' ³           demo (‚sta sin comodines) mediante la barra "/" (ver ejemplos).  ³');
    List.Put(StrUsage1Beg+3            ,'');
    List.Put(StrUsage1Beg+4            ,' ³ <fichero.VTO> es un fichero ASCII con l¡neas de par metros. Se pueden      ³');
    List.Put(StrUsage1Beg+5            ,' ³               especificar varios, cada uno con su arroba (@). Los ficheros ³');
    List.Put(StrUsage1Beg+6            ,' ³               pueden llevar comentarios, precedidos por un s¡mbolo de ";". ³');
    List.Put(StrUsage1Beg+7            ,' ³               Tambi‚n se pueden anidar todo lo que se quiera.              ³');
    List.Put(StrUsage1Beg+8            ,#0);

    List.Put(StrUsage2Beg              ,' ³ <opciones> es una lista de opciones, precedidas cada una por una barra "/" ³');
    List.Put(StrUsage2Beg+ 1           ,' ³            o por un gui¢n "-". Las opciones deben estar separadas por, al  ³');
    List.Put(StrUsage2Beg+ 2           ,' ³            menos, un espacio. Algunas pociones pueden llevar un par metro, ³');
    List.Put(StrUsage2Beg+ 3           ,' ³            que se puede especificar a continuaci¢n, separado por un        ³');
    List.Put(StrUsage2Beg+ 4           ,' ³            espacio o por dos puntos ":". Posibles opciones son:            ³');
    List.Put(StrUsage2Beg+ 5           ,'');
    List.Put(StrUsage2Beg+ 6           ,' ³   / ¢ -        interpreta lo que se haya especificado, y despu‚s contin£a. ³');
    List.Put(StrUsage2Beg+ 7           ,' ³   /v:<vol.>    volumen del sonido.                                         ³');
    List.Put(StrUsage2Beg+ 8           ,' ³   /sh:<cmd.>   programa y par metros que se ejecutan al hacer un shell.    ³');
    List.Put(StrUsage2Beg+ 9           ,' ³   /ss:<pos.>   posici¢n de comienzo de la canci¢n.                         ³');
    List.Put(StrUsage2Beg+10           ,' ³   /sr:<pos.>   posici¢n de comienzo del bucle de la canci¢n.               ³');
    List.Put(StrUsage2Beg+11           ,' ³   /sl:<pos.>   posici¢n de finalizaci¢n de la canci¢n.                     ³');
    List.Put(StrUsage2Beg+12           ,' ³   /lq          "Low Quality", ocupa menos memoria, pero suena peor.        ³');
    List.Put(StrUsage2Beg+13           ,' ³   /hq          "Hi  Quality", desactiva el anterior.                       ³');
    List.Put(StrUsage2Beg+14           ,' ³   /flp         equivale a poner "ForceLoopMod = S¡" en el VT.CFG.          ³');
    List.Put(StrUsage2Beg+15           ,' ³   /nofl        equivale a poner "ForceLoopMod = No" en el VT.CFG.          ³');
    List.Put(StrUsage2Beg+16           ,' ³   /loop        equivale a poner "LoopMod = S¡" en el VT.CFG.               ³');
    List.Put(StrUsage2Beg+17           ,' ³   /nolp        equivale a poner "LoopMod = No" en el VT.CFG.               ³');
    List.Put(StrUsage2Beg+18           ,' ³   /off:<pos.>  posici¢n de comienzo de la canci¢n dentro del fichero.      ³');
    List.Put(StrUsage2Beg+19           ,' ³   /port:<n>    puerto de E/S de la tarjeta de sonido.                      ³');
    List.Put(StrUsage2Beg+20           ,' ³   /irq:<n>     IRQ de la tarjeta de sonido.                                ³');
    List.Put(StrUsage2Beg+21           ,' ³   /frst:<file> no suena ninguna canci¢n hasta que no se encuentra esta.    ³');

    List.Put(StrUsage2Beg+22           ,#0);

    List.Put(StrUsage3Beg              ,' ³ <disp.> puede ser:                                                         ³');
    List.Put(StrUsage3Beg+ 1           ,' ³                                                                            ³');
    List.Put(StrUsage3Beg+ 2           ,' ³     Lo siento. Esta versi¢n de VT s¢lo soporta GUS.                        ³');
    List.Put(StrUsage3Beg+ 3           ,' ³                                                                            ³');
    List.Put(StrUsage3Beg+ 4           ,#0);

    List.Put(StrUsage4Beg              ,' ³ Ejemplos: El int‚rprete de l¡nes de comando es demasiado flexible para     ³');
    List.Put(StrUsage4Beg+ 1           ,' ³           explicarlo aqu¡ entero, as¡ que para hacerse una idea de c¢mo    ³');
    List.Put(StrUsage4Beg+ 2           ,' ³           funciona, examine los ejemplos y los ficheros .VTO inclu¡dos.    ³');
    List.Put(StrUsage4Beg+ 3           ,'');
    List.Put(StrUsage4Beg+ 4           ,' ³   Este hace sonar la melod¡a "Axel F." por la GUS que est  en el puerto    ³');
    List.Put(StrUsage4Beg+ 5           ,' ³   240, IRQ 11 con un volumen de 64:                                        ³');
    List.Put(StrUsage4Beg+ 6           ,'');
    List.Put(StrUsage4Beg+ 7           ,' ³       VT /v:64 D:\MODS\AXEL_F.MOD /port $240 /IRQ:11                       ³');
    List.Put(StrUsage4Beg+ 8           ,'');
    List.Put(StrUsage4Beg+ 9           ,' ³   Este hace sonar la m£sica de la demo Unreal, de Future Crew, seg£n el    ³');
    List.Put(StrUsage4Beg+10           ,' ³   fichero .VTO. Al salir al shell, edita el fichero VT.PAS en el editor:   ³');
    List.Put(StrUsage4Beg+11           ,'');
    List.Put(StrUsage4Beg+12           ,' ³       VT @UNREAL.VTO /sh:C:\BIN\Q.EXE VT.PAS                               ³');
    List.Put(StrUsage4Beg+13           ,'');
    List.Put(StrUsage4Beg+14           ,' ³   Este toca las canciones 1 y 2 (cualquiera que sea su formato):           ³');
    List.Put(StrUsage4Beg+15           ,'');
    List.Put(StrUsage4Beg+16           ,' ³       VT 1 2                                                               ³');
    List.Put(StrUsage4Beg+17           ,'');
    List.Put(StrUsage4Beg+18           ,' ³   Este toca la canci¢n 1 a un volumen de 64 y la canci¢n 2 a 128:          ³');
    List.Put(StrUsage4Beg+19           ,'');
    List.Put(StrUsage4Beg+20           ,' ³       VT 1 /v:64 / /v 128 2                                                ³');
    List.Put(StrUsage4Beg+21           ,'');
    List.Put(StrUsage4Beg+22           ,#0);

    List.Put(StrInitializing           ,'    Inicializando... ');

  END;


PROCEDURE VTAddEnglishMsg(VAR List: TStrListMaker);
  BEGIN
    List.Put(StrPosition               , 'Position:  ');
    List.Put(StrPattern                , 'Pattern:   ');
    List.Put(StrNote                   , 'Note:      ');
    List.Put(StrTempo                  , 'Tempo:     ');

    List.Put(StrModule                 , 'Module:    ');
    List.Put(StrFilename               , 'Filename:  ');
    List.Put(StrMemoryLeft             , 'Free mem.: ');
    List.Put(StrSampleRate             , 'Frequency: ');
    List.Put(StrVolume                 , 'Volume: ');

    List.Put(StrMenu1                  , 'PUp/Dn Next pattern    ');
    List.Put(StrMenu2                  , 'Bg/End Idem (from beg) ');
    List.Put(StrMenu3                  , '1-8    Turn off channel');
    List.Put(StrMenu4                  , 'F5-F9  Change windows  ');
    List.Put(StrMenu5                  , 'Lt/Rt  Shift channels  ');
    List.Put(StrMenu6                  , 'R/T    Output freq.    ');
    List.Put(StrMenu7                  , '+/-    Volume          ');
    List.Put(StrMenu8                  , 'D      DOS Shell       ');
    List.Put(StrMenu9                  , 'N/S    Next song       ');
    List.Put(StrMenu0                  , 'ESC    Quit            ');

    List.Put(StrOscilloscView          , 'Oscilloscope');
    List.Put(StrGUSOscillosc           , '                    The oscilloscope is not available with GUS sound');

    List.Put(StrChannel                , 'Channel  ');

    List.Put(StrCreditsTitle           , '                          Credits');

    List.Put(StrCredits                , '     - Juan Carlos Ar‚valo  ú ³ Originator of all this mess.');
    List.Put(StrCredits+ 1             , '                              ³ Program body, General structure.');
    List.Put(StrCredits+ 2             , '                              ³ First versions.');
    List.Put(StrCredits+ 3             , '');
    List.Put(StrCredits+ 4             , '     - Luis Crespo  úúúúúúúúú ³ Programs antecesor (JAMP).');
    List.Put(StrCredits+ 5             , '                              ³ DMA routines. Sound Blaster');
    List.Put(StrCredits+ 6             , '                              ³ Info.');
    List.Put(StrCredits+ 7             , '');
    List.Put(StrCredits+ 8             , '     - F‚lix Sanz  úúúúúúúúúú ³ Creation of the user DOCs.');
    List.Put(StrCredits+ 9             , '');
    List.Put(StrCredits+10             , '     - Alejandro L¢pez  úúúúú ³ Original system of stereo');
    List.Put(StrCredits+11             , '                              ³ channels mixing.');
    List.Put(StrCredits+12             , '');
    List.Put(StrCredits+13             , '     - H‚ctor Mart¡nez  úúúúú ³ FFT routines. (not yet');
    List.Put(StrCredits+14             , '                              ³ introduced).');
    List.Put(StrCredits+11             , '                              ³ Original idea of the 4 channel');
    List.Put(StrCredits+16             , '                              ³ handling system.');
    List.Put(StrCredits+17             , '');
    List.Put(StrCredits+18             , '     - David L¢pez  úúúúúúúúú ³ SB-Pro stereo info.');
    List.Put(StrCredits+19             , '');
    List.Put(StrCredits+20             , '     - Angel Trigo  úúúúúúúúú ³ SB-Pro stereo info.');
    List.Put(StrCredits+21             , '');
    List.Put(StrCredits+22             , '     - Carlos Fern ndez  úúúú ³ Made a modification in the');
    List.Put(StrCredits+23             , '                              ³ swapping system, to make it work');
    List.Put(StrCredits+24             , '                              ³ on CD-ROMS.');
    List.Put(StrCredits+25             , '');
    List.Put(StrCredits+26             , '     - N‚stor Matas  úúúúúúúú ³ Translation of this manual into');
    List.Put(StrCredits+27             , '                              ³ English.');
    List.Put(StrCredits+28             , '');
    List.Put(StrCredits+29             , '  NOTE: This version of VT currently doesn''t support other than GUS.');
    List.Put(StrCredits+30             , '        Future versions of VT will support other cards again.');
    List.Put(StrCredits+31             , #0);

    List.Put(StrDedicat                , '         This version is dedicated to Gore/FC and John Smith.');
    List.Put(StrDedicat+1              , '           They both have contributed in a very special way.');
    List.Put(StrDedicat+2              , #0);

    List.Put(StrUsageTop               ,' ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
    List.Put(StrUsage01                ,' ³ VT  <file.MOD|.OKT|.S3M|.STM|.669| etc] [<options>] [@<file.VTO>]          ³');
    List.Put(StrUsageBottom            ,' ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ');
    List.Put(StrUsageEmpty             ,' ³                                                                            ³');
    List.Put(StrUsagePressAKey         ,'                       ---===ğğğ Press any key ğğğ===---');

    List.Put(StrUsage1Beg              ,' ³ <file> accepts wildards. You can also specify more than one. Also, you can ³');
    List.Put(StrUsage1Beg+ 1           ,' ³        specify the songs inside a demo (this time without wildcards)       ³');
    List.Put(StrUsage1Beg+ 2           ,' ³        using the bar "/". (See the examples).                              ³');
    List.Put(StrUsage1Beg+ 3           ,'');
    List.Put(StrUsage1Beg+ 4           ,' ³ <file.VTO> is an ASCII file with mor parameter lines. You can specify as   ³');
    List.Put(StrUsage1Beg+ 5           ,' ³            many as you want, each one with it''s at-sign "@". These files   ³');
    List.Put(StrUsage1Beg+ 2           ,' ³        using the bar "/". (See the examples).                              ³');
    List.Put(StrUsage1Beg+ 3           ,'');
    List.Put(StrUsage1Beg+ 4           ,' ³ <file.VTO> is an ASCII file with mor parameter lines. You can specify as   ³');
    List.Put(StrUsage1Beg+ 5           ,' ³            many as you want, each one with it''s at-sign "@". These files   ³');
    List.Put(StrUsage1Beg+ 6           ,' ³            can have comments, beginning with a semicolon ";". They can     ³');
    List.Put(StrUsage1Beg+ 7           ,' ³            also be nested to any level (memory permitting).                ³');
    List.Put(StrUsage1Beg+ 8           ,#0);

    List.Put(StrUsage2Beg              ,' ³ <options> is a list of switches, preceded each one with a slash "/" or a   ³');
    List.Put(StrUsage2Beg+ 1           ,' ³           hyphen "-". All options must be separated by, at least, a space. ³');
    List.Put(StrUsage2Beg+ 2           ,' ³           Some options must have a parameter, which must be separated by a ³');
    List.Put(StrUsage2Beg+ 3           ,' ³           space or a colon ":". Possible options are:                      ³');
    List.Put(StrUsage2Beg+ 4           ,'');
    List.Put(StrUsage2Beg+ 5           ,' ³   / or -       do all the options and songs specified, and then continue.  ³');
    List.Put(StrUsage2Beg+ 6           ,' ³   /v:<vol.>    sound volume.                                               ³');
    List.Put(StrUsage2Beg+ 7           ,' ³   /sh:<cmd.>   program and parameters to be executed when shelling.        ³');
    List.Put(StrUsage2Beg+ 8           ,' ³   /ss:<pos.>   song start position.                                        ³');
    List.Put(StrUsage2Beg+ 9           ,' ³   /sr:<pos.>   song loop start position.                                   ³');
    List.Put(StrUsage2Beg+10           ,' ³   /sl:<pos.>   song last position.                                         ³');
    List.Put(StrUsage2Beg+11           ,' ³   /lq          "Low Quality", spends less memory, but sounds worse         ³');
    List.Put(StrUsage2Beg+12           ,' ³   /hq          "Hi  Quality", deactivates the /lq.                         ³');
    List.Put(StrUsage2Beg+13           ,' ³   /flp         equals to "ForceLoopMod = Yes" in the VT.CFG.               ³');
    List.Put(StrUsage2Beg+14           ,' ³   /nofl        equals to "ForceLoopMod = No"  in the VT.CFG.               ³');
    List.Put(StrUsage2Beg+15           ,' ³   /loop        equals to "LoopMod = Yes" in the VT.CFG.                    ³');
    List.Put(StrUsage2Beg+16           ,' ³   /nolp        equals to "LoopMod = No"  in the VT.CFG.                    ³');
    List.Put(StrUsage2Beg+17           ,' ³   /off:<pos.>  offset where the song begins inside the file.               ³');
    List.Put(StrUsage2Beg+18           ,' ³   /port:<n>    I/O port of the sound card.                                 ³');
    List.Put(StrUsage2Beg+19           ,' ³   /irq:<n>     IRQ of the sound card.                                      ³');
    List.Put(StrUsage2Beg+20           ,' ³   /frst:<file> this is the first song that will be played.                 ³');
    List.Put(StrUsage2Beg+21           ,#0);
    
    List.Put(StrUsage3Beg              ,' ³ <device> can be:                                                           ³');
    List.Put(StrUsage3Beg+ 1           ,' ³                                                                            ³');
    List.Put(StrUsage3Beg+ 2           ,' ³     Only GUS is supported in this version of VT. Sorry.                    ³');
    List.Put(StrUsage3Beg+ 3           ,' ³                                                                            ³');
    List.Put(StrUsage3Beg+ 4           ,#0);

    List.Put(StrUsage4Beg              ,' ³ Examples: The command line interpreter is too flexible to explain every    ³');
    List.Put(StrUsage4Beg+ 1           ,' ³           little aspect of it, so to have an idea, just look below, and    ³');
    List.Put(StrUsage4Beg+ 2           ,' ³           examine the example .VTO files.                                  ³');
    List.Put(StrUsage4Beg+ 3           ,'');
    List.Put(StrUsage4Beg+ 4           ,' ³   This plays the song "Axel F." through the GUS at 240/11 with a volume of ³');
    List.Put(StrUsage4Beg+ 5           ,' ³   64:                                                                      ³');
    List.Put(StrUsage4Beg+ 6           ,'');
    List.Put(StrUsage4Beg+ 7           ,' ³       VT /v:64 D:\MODS\AXEL_F.MOD /port $240 /IRQ:11                       ³');
    List.Put(StrUsage4Beg+ 8           ,'');
    List.Put(StrUsage4Beg+ 9           ,' ³   This plays the music of the Unreal demo, by Future Crew, as given in the ³');
    List.Put(StrUsage4Beg+10           ,' ³   example .VTO file. Shells to the ASCII editor, editing the VT.PAS file:  ³');
    List.Put(StrUsage4Beg+11           ,'');
    List.Put(StrUsage4Beg+12           ,' ³       VT @UNREAL.VTO /sh:C:\BIN\Q.EXE VT.PAS                               ³');
    List.Put(StrUsage4Beg+13           ,'');
    List.Put(StrUsage4Beg+14           ,' ³   This plays the songs 1 and 2 (whichever format they are):                ³');
    List.Put(StrUsage4Beg+15           ,'');
    List.Put(StrUsage4Beg+16           ,' ³       VT 1 2                                                               ³');
    List.Put(StrUsage4Beg+17           ,'');
    List.Put(StrUsage4Beg+18           ,' ³   This plays the song 1 at 64 of volume and the song 2 at 128:             ³');
    List.Put(StrUsage4Beg+19           ,'');
    List.Put(StrUsage4Beg+20           ,' ³       VT 1 /v:64 / /v 128 2                                                ³');
    List.Put(StrUsage4Beg+21           ,'');
    List.Put(StrUsage4Beg+22           ,#0);

    List.Put(StrInitializing           ,'    Initializing... ');

  END;




END.
