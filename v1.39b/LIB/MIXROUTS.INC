



; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё MACROS: MonoMix, SterMix, MixoMixSoft & SterMixHard                      Ё
; Ё                                                                          Ё
; Ё Macros that the mono/stereo mixing.                                      Ё
; Ё                                                                          Ё
; Ё IN:  AX    = Mono 16 bit sample.                                         Ё
; Ё              Stereo left  channel 16 bit sample.                         Ё
; Ё      BX    = Stereo right channel 16 bit sample.                         Ё
; Ё                                                                          Ё
; Ё OUT: idem.                                                               Ё
; Ё                                                                          Ё
; Ё MODIFIES: AX, BX, CX, DX                                                 Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

MACRO MonoMix

                ADD     AX,BX
                Saturate AX

ENDM MonoMix

; ---------------------------------------------------------------------------

MACRO SterMix

                ADD     BX,BX
                Saturate BX
                ADD     AX,AX
                Saturate AX

ENDM SterMix

; ---------------------------------------------------------------------------

MACRO SterMixSoft
LOCAL @@nooverf, @@ovc

                MOV     DX,AX
                ADD     DX,BX
                JNO     SHORT @@nooverf
                 RCR    DX,1
                JMP     SHORT @@ovc
@@nooverf:       SAR    DX,1
@@ovc:
                ADD     AX,DX
                Saturate AX
                ADD     BX,DX
                Saturate BX

ENDM SterMixSoft

; ---------------------------------------------------------------------------

MACRO SterMixHard

                SAR     AX,1
                SAR     BX,1
                MOV     DX,AX
                ADD     DX,BX

                MOV     CX,DX
                SAR     DX,1

                ADD     DX,CX
                Saturate DX

                ADD     AX,DX
                Saturate AX
                ADD     BX,DX
                Saturate BX

ENDM SterMixHard




CalcNewMixData:

                ; зддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё First, calculate the jump from the number Ё
                ; Ё of channels in the buffer, and store the  Ё
                ; Ё increment fot rhe next sample in the BX   Ё
                ; Ё register.                                 Ё
                ; юддддддддддддддддддддддддддддддддддддддддддды

                MOV     CX,2 ;[NumChannels]
                MOV     DX,32
                SUB     DX,CX

                MOV     BX,DX
                ADD     DX,DX   ; OJO: Multiply by 3, which is the size of the
                ADD     DX,BX   ;      ADD rX,[DS:rI+n] instruction.

                ADD     CX,CX

                MOV     [BYTE PTR CS:MixJumpVal-1],DL
                MOV     [WORD PTR CS:MixAddVal -2],CX




                MOV     BX,DX
                SUB     BX,OFFSET Mono32MixD1 - OFFSET Mono32MixLoop
                MOV     [BYTE PTR CS:Mono32MixD1-1],BL

                MOV     BX,DX
                SUB     BX,OFFSET Ster32MixD1 - OFFSET Ster32MixLoop
                MOV     [BYTE PTR CS:Ster32MixD1-1],BL

                MOV     [WORD PTR CS:Mono32MixD2  ],CX
                MOV     [WORD PTR CS:Ster32MixD2  ],CX




                MOV     DL,[MixMethod]

                MOV     BX,OFFSET MixMono   - OFFSET MixMSJumpVal
                AND     DL,DL
                JZ      @@ya

                MOV     BX,OFFSET MixSter   - OFFSET MixMSJumpVal
                DEC     DL
                JZ      @@ya

                MOV     BX,OFFSET MixStMix1 - OFFSET MixMSJumpVal
                DEC     DL
                JZ      @@ya

                MOV     BX,OFFSET MixStMix2 - OFFSET MixMSJumpVal
@@ya:
                MOV     [WORD PTR CS:MixMSJumpVal-2],BX

                MOV     AH,0C3h
                MOV     AL,[DoBassPower]
                AND     AL,AL
                JZ      @@nobass
                 MOV    AH,90h
@@nobass:       MOV     [BYTE PTR CS:MixMonoBass],AH
                MOV     [BYTE PTR CS:MixSterBass],AH

                CALL    SetFilterValues

                RET




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: MixChannels                                                     Ё
; Ё                                                                          Ё
; Ё Mixes up to 32 channels of 16-bit, signed samples into stereo or mono,   Ё
; Ё and performs all the necessary operations (mixing, equalization,         Ё
; Ё saturation, etc.)                                                        Ё
; Ё                                                                          Ё
; Ё IN:  DS:SI = input buffer, where the samples are.                        Ё
; Ё      SS    = Must match the program's data segment.                      Ё
; Ё                                                                          Ё
; Ё OUT: AX    = Mono 16 bit sample.                                         Ё
; Ё              Stereo left  channel 16 bit sample.                         Ё
; Ё      CX    = Stereo right channel 16 bit sample.                         Ё
; Ё      SI    = Position in the buffer updated.                             Ё
; Ё                                                                          Ё
; Ё MODIFIES: AX, BX, CX, DX, SI                                             Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

PUBLIC MixChannels

MixChannels:

                ; здддддддддддддддддддддддддддддддддддддддд©
                ; Ё Now, do the mixing. A jump is used to  Ё
                ; Ё make faster mixing with less channels. Ё
                ; юдддддддддддддддддддддддддддддддддддддддды

                MOV     AX,[SI]
                XOR     BX,BX
                JMP     SHORT MixJumpVal
MixJumpVal:
                ADD     AX,[SI+62]
                ADD     BX,[SI+60]
                ADD     BX,[SI+58]
                ADD     AX,[SI+56]
                ADD     AX,[SI+54]
                ADD     BX,[SI+52]
                ADD     BX,[SI+50]
                ADD     AX,[SI+48]
                ADD     AX,[SI+46]
                ADD     BX,[SI+44]
                ADD     BX,[SI+42]
                ADD     AX,[SI+40]
                ADD     AX,[SI+38]
                ADD     BX,[SI+36]
                ADD     BX,[SI+34]
                ADD     AX,[SI+32]
                ADD     AX,[SI+30]
                ADD     BX,[SI+28]
                ADD     BX,[SI+26]
                ADD     AX,[SI+24]
                ADD     AX,[SI+22]
                ADD     BX,[SI+20]
                ADD     BX,[SI+18]
                ADD     AX,[SI+16]
                ADD     AX,[SI+14]
                ADD     BX,[SI+12]
                ADD     BX,[SI+10]
                ADD     AX,[SI+8]
                ADD     AX,[SI+6]
                ADD     BX,[SI+4]
                ADD     BX,[SI+2]

                ; здддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Add the increment to the sample pointer. Ё
                ; юдддддддддддддддддддддддддддддддддддддддддды

                ADD     SI,1234h
MixAddVal:

                ; здддддддддддддддддддддддддддддддддддд©
                ; Ё Finally, do the mono/stereo mixing Ё
                ; Ё and apply the bass-power filter.   Ё
                ; юдддддддддддддддддддддддддддддддддддды

                JMP     NEAR CS:0FFFFh
MixMSJumpVal:

MixMono:        MonoMix
MixMonoBass:    NOP
                JMP     BassPowerMono

MixSter:        SterMix
                JMP     SHORT MixStCommon

MixStMix1:      SterMixSoft
                JMP     SHORT MixStCommon

MixStMix2:      SterMixHard

MixStCommon:
MixSterBass:    NOP
                JMP     BassPowerStereo




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: DumpSamples                                                     Ё
; Ё                                                                          Ё
; Ё This routine fills a portion of buffer with samples.                     Ё
; Ё                                                                          Ё
; Ё IN:  DS:SI = Source multi-channel buffer.                                Ё
; Ё      ES:DI = Destination buffer.                                         Ё
; Ё      CX    = Number of samples.                                          Ё
; Ё      SS    = Must match the program's data segment.                      Ё
; Ё                                                                          Ё
; Ё OUT: SI    = Source      final position.                                 Ё
; Ё      DI    = Destination final position.                                 Ё
; Ё                                                                          Ё
; Ё MODIFIES: AX, BX, CX, DX, SI, DI                                         Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

Picos DB 0

GeneralDev8MonoFillRut:

Mono32MixRut:

;  SetBorder 0, 0, 0

;PUSH DX
;MOV DL,[CS:Picos]

                INC     CX
                JMP     SHORT Mono32MixStartLp

Mono32MixLoop:
                ADD     AX,[SI+62]
                ADD     BX,[SI+60]
                ADD     BX,[SI+58]
                ADD     AX,[SI+56]
                ADD     AX,[SI+54]
                ADD     BX,[SI+52]
                ADD     BX,[SI+50]
                ADD     AX,[SI+48]
                ADD     AX,[SI+46]
                ADD     BX,[SI+44]
                ADD     BX,[SI+42]
                ADD     AX,[SI+40]
                ADD     AX,[SI+38]
                ADD     BX,[SI+36]
                ADD     BX,[SI+34]
                ADD     AX,[SI+32]
                ADD     AX,[SI+30]
                ADD     BX,[SI+28]
                ADD     BX,[SI+26]
                ADD     AX,[SI+24]
                ADD     AX,[SI+22]
                ADD     BX,[SI+20]
                ADD     BX,[SI+18]
                ADD     AX,[SI+16]
                ADD     AX,[SI+14]
                ADD     BX,[SI+12]
                ADD     BX,[SI+10]
                ADD     AX,[SI+8]
                ADD     AX,[SI+6]
                ADD     BX,[SI+4]

                ADD     SI,1234h         ; 4*2
Mono32MixD2 = $-2

;ADD SI,2*2

                ADD     AX,BX
                JO      SHORT Mono32MixSatur

Mono32MixCont:   XOR     AH,80h
;                STOSW
MOV   [BYTE PTR ES:DI],AH
INC   DI

;INC DL

Mono32MixStartLp:
                MOV     AX,[SI]
                MOV     BX,[SI+2]

                LOOP    SHORT Mono32MixLoop
Mono32MixD1 = $

;  SetBorder 0, 63, 63

;MOV [CS:Picos],DL
;POP DX

                RET


Mono32MixSatur: JNS     SHORT @@c1
                 MOV    AX,32767
                JMP     SHORT Mono32MixCont
@@c1:            MOV    AX,-32767
                JMP     SHORT Mono32MixCont











GeneralDev16MonoFillRut:
GeneralDev16SterFillRut:
GeneralDev8SterFillRut:

Ster32MixRut:

;  SetBorder 0, 0, 0

                INC     CX
                JMP     SHORT Ster32MixStartLp

Ster32MixLoop:
                ADD     AX,[SI+62]
                ADD     BX,[SI+60]
                ADD     BX,[SI+58]
                ADD     AX,[SI+56]
                ADD     AX,[SI+54]
                ADD     BX,[SI+52]
                ADD     BX,[SI+50]
                ADD     AX,[SI+48]
                ADD     AX,[SI+46]
                ADD     BX,[SI+44]
                ADD     BX,[SI+42]
                ADD     AX,[SI+40]
                ADD     AX,[SI+38]
                ADD     BX,[SI+36]
                ADD     BX,[SI+34]
                ADD     AX,[SI+32]
                ADD     AX,[SI+30]
                ADD     BX,[SI+28]
                ADD     BX,[SI+26]
                ADD     AX,[SI+24]
                ADD     AX,[SI+22]
                ADD     BX,[SI+20]
                ADD     BX,[SI+18]
                ADD     AX,[SI+16]
                ADD     AX,[SI+14]
                ADD     BX,[SI+12]
                ADD     BX,[SI+10]
                ADD     AX,[SI+8]
                ADD     AX,[SI+6]
                ADD     BX,[SI+4]

                ADD     SI,1234h         ; 4*2
Ster32MixD2 = $-2

Ster32MixCont:   XOR    AH,80h
                 XOR    BH,80h
;                STOSW
;                MOV    AX,BX
;                STOSW
MOV   AL,AH
MOV   AH,BH
MOV   [ES:DI],AX
INC   DI
INC   DI

Ster32MixStartLp:
                MOV     AX,[SI]
                MOV     BX,[SI+2]

                LOOP    SHORT Ster32MixLoop
Ster32MixD1 = $

;  SetBorder 0, 63, 63

                RET


