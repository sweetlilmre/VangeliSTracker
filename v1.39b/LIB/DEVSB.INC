
                DATASEG

EXTRN DSPWritePort : WORD
EXTRN DSP8AckPort  : WORD
EXTRN DSPLifePort  : WORD
EXTRN SbSplTimeout : WORD
EXTRN SbCmdTimeout : WORD

                CODESEG



MACRO  SBLoop Tout
LOCAL @@tst, @@cnt

                MOV     DX,[DSPWritePort]
                MOV     BX,Tout
@@tst:
                 DEC    BX
                 JZ     SHORT @@cnt
                 IN     AL,DX
                 TEST   AL,80h
                 JNZ    SHORT @@tst
@@cnt:

ENDM  SBLoop





DevSbStartRut EQU DeviceStartRutRet

DevSbRut1:
                SBLoop  [SbCmdTimeout]
                MOV     AL,10h
                OUT     DX,AL
                JMP     DeviceRut1Ret

DevSbRut2:
                XOR     AH,80h
                SBLoop  [SbSplTimeout]
                MOV     AL,AH
                OUT     DX,AL
                JMP     DeviceRut2Ret

DevSbKickRut:
                MOV     DX,[DSP8AckPort]
                IN      AL,DX
                MOV     DX,[DSPLifePort]
                IN      AL,DX
                RET

DevSbMonoFillRut EQU GeneralDev8MonoFillRut
;GeneralDev8MonoFillRut

DevSbSterFillRut EQU GeneralDev8SterFillRut




PUBLIC DevInitSbNonDMA

PROC DevInitSbNonDMA FAR Ster: BYTE, Bits: BYTE

                MOV     AX,OFFSET DevSbMonoFillRut

                JMP     SHORT DevSbGeneralInit

ENDP


PUBLIC DevInitSbDMA

PROC DevInitSbDMA FAR Ster: BYTE, Bits: BYTE

                MOV     AL,[Ster]
                AND     AL,AL
                JNZ     SHORT @@ster
                 MOV    AX,OFFSET DevSbMonoFillRut
                JMP     SHORT DevSbGeneralInit
@@ster:          MOV    AX,OFFSET DevSbSterFillRut
                JMP     SHORT DevSbGeneralInit

DevSbGeneralInit:
                MOV     [DeviceFillRut],AX

                MOV     AX,OFFSET DevSbStartRut
                MOV     [DeviceStartRut],AX

                MOV     AX,OFFSET DevSbRut1
                MOV     [DeviceRut1],AX

                MOV     AX,OFFSET DevSbRut2
                MOV     [DeviceRut2],AX

                MOV     AX,OFFSET DevSbKickRut
                MOV     [DeviceKickRut],AX

                RET

ENDP
   
