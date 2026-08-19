
                DATASEG

EXTRN DacPort  : WORD
EXTRN LDacPort : WORD
EXTRN RDacPort : WORD

                CODESEG

DevDacStartRut EQU DeviceStartRutRet

DevDacRut1 EQU DeviceRut1Ret

DevDacRut2Mono:
;                JMP     DeviceRut2Ret
                XOR     AH,80h
                MOV     AL,AH

                MOV     DX,[DacPort]
                OUT     DX,AL

                JMP     DeviceRut2Ret

DevDacRut2Stereo:
;                JMP     DeviceRut2Ret
                XOR     AH,80h
                XOR     CH,80h

                MOV     DX,[LDacPort]
                MOV     AL,AH
                OUT     DX,AL

                MOV     DX,[RDacPort]
                MOV     AL,CH
                OUT     DX,AL

                JMP     DeviceRut2Ret




PUBLIC DevInitDac

PROC DevInitDac FAR Ster: BYTE, Bits: BYTE

                MOV     AL,[Ster]
                AND     AL,AL
                JZ      @@mono
                 MOV    AX,OFFSET DevDacRut2Stereo
                JMP     @@stereo
@@mono:          MOV    AX,OFFSET DevDacRut2Mono
@@stereo:
                MOV     [DeviceRut2],AX

                MOV     AX,OFFSET DevDacStartRut
                MOV     [DeviceStartRut],AX

                MOV     AX,OFFSET DevDacRut1
                MOV     [DeviceRut1],AX

                RET

ENDP



