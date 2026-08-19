
                CODESEG
                       
SpkrTabla DB 40h, 40h, 40h, 40h, 40h, 40h, 40h, 40h, 40h, 40h, 3Fh, 3Fh, 3Fh, 3Fh, 3Fh, 3Fh
          DB 3Fh, 3Fh, 3Fh, 3Fh, 3Fh, 3Fh, 3Eh, 3Eh, 3Eh, 3Eh, 3Eh, 3Eh, 3Eh, 3Eh, 3Eh, 3Eh
          DB 3Dh, 3Dh, 3Dh, 3Dh, 3Dh, 3Dh, 3Dh, 3Dh, 3Dh, 3Ch, 3Ch, 3Ch, 3Ch, 3Ch, 3Ch, 3Ch
          DB 3Ch, 3Ch, 3Ch, 3Bh, 3Bh, 3Bh, 3Bh, 3Bh, 3Bh, 3Bh, 3Bh, 3Bh, 3Bh, 3Ah, 3Ah, 3Ah
          DB 3Ah, 3Ah, 3Ah, 3Ah, 3Ah, 3Ah, 3Ah, 39h, 39h, 39h, 39h, 39h, 39h, 39h, 39h, 39h
          DB 39h, 38h, 38h, 38h, 38h, 38h, 38h, 38h, 38h, 37h, 37h, 37h, 37h, 37h, 36h, 36h
          DB 36h, 36h, 35h, 35h, 35h, 35h, 34h, 34h, 34h, 33h, 33h, 32h, 32h, 31h, 31h, 30h
          DB 30h, 2Fh, 2Eh, 2Dh, 2Ch, 2Bh, 2Ah, 29h, 28h, 27h, 26h, 25h, 24h, 23h, 22h, 21h
          DB 20h, 1Fh, 1Eh, 1Dh, 1Ch, 1Bh, 1Ah, 19h, 18h, 17h, 16h, 15h, 14h, 13h, 12h, 11h
          DB 11h, 10h, 10h, 0Fh, 0Fh, 0Eh, 0Eh, 0Dh, 0Dh, 0Dh, 0Ch, 0Ch, 0Ch, 0Ch, 0Bh, 0Bh
          DB 0Bh, 0Bh, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 09h, 09h, 09h, 09h, 09h, 09h, 09h, 09h, 09h
          DB 08h, 08h, 08h, 08h, 08h, 08h, 08h, 08h, 08h, 08h, 08h, 08h, 07h, 07h, 07h, 07h
          DB 07h, 07h, 07h, 06h, 06h, 06h, 06h, 06h, 06h, 06h, 06h, 06h, 06h, 06h, 05h, 05h
          DB 05h, 05h, 05h, 05h, 05h, 05h, 05h, 05h, 04h, 04h, 04h, 04h, 04h, 04h, 04h, 04h
          DB 04h, 04h, 03h, 03h, 03h, 03h, 03h, 03h, 03h, 03h, 03h, 03h, 02h, 02h, 02h, 02h
          DB 02h, 02h, 02h, 02h, 02h, 01h, 01h, 01h, 01h, 01h, 01h, 01h, 01h, 01h, 01h, 01h



DevSpkrStartRut:
                MOV     AL,0
SpkrData1:
                OUT     42h,AL
                JMP     DeviceStartRutRet

DevSpkrRut1 EQU DeviceRut1Ret

DevSpkrRut2:
                XOR     AH,80h
                MOV     AL,AH
                MOV     BX,OFFSET SpkrTabla

                DB 2Eh                          ; CS:
                XLAT
                MOV     [BYTE PTR CS:SpkrData1-1],AL

                JMP     DeviceRut2Ret




PUBLIC DevInitSpkr

PROC DevInitSpkr FAR Ster: BYTE, Bits: BYTE

                MOV     AX,OFFSET DevSpkrStartRut
                MOV     [DeviceStartRut],AX

                MOV     AX,OFFSET DevSpkrRut1
                MOV     [DeviceRut1],AX

                MOV     AX,OFFSET DevSpkrRut2
                MOV     [DeviceRut2],AX

                RET

ENDP

