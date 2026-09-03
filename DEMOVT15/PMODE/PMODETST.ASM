; --------------------------- PMODETST.ASM ---------------------------
; DemoVT 1.51 interface for Tran's PMode 2.4, test program.
; Hacked into EX_PM0.ASM. Gives warnings.
; A simple program to print a message using DOS INT 21h AH=9.

        .386p

include pmodedvt.inc

public  _main

;±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±
; DATA
;±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±

m1              DB      'Waiting for DemoVT to start....$'
m2              DB      10, 13, 'GO!', 13, 10, 'Press a key to end .$'
m3              DB      10, 13, 'Have a nice DOS.$'
merr            DB      'DemoVT is not present!$'

;±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±
; CODE
;±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±

ShowMessage:
        add eax,_code32a        ; adjust to an absolute address
        shld ebx,eax,28         ; shift bits 4-31 of EAX into 0-28 of EBX
                                ;  though we only care for bits 4-19 of EAX
                                ;  that is the segment from the absolute addx
        and eax,0fh             ; and off the segment from EAX
                                ;  now BX:AX is the seg:off of the message
        mov v86r_ds,bx          ; put segment into virtual reg for real mode
        mov v86r_dx,ax          ; put offset into virtual reg for real mode
        mov v86r_ah,9           ; AH=9 for call to real mode INT 21h
        mov al,21h              ; interrupt number to call
        int 33h                 ; do real mode INT AL
        RET


;ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ
_main:
        sti

        CALL    InitMusic
        MOV     EAX,OFFSET merr
        OR      DL,DL
        JZ      Bye
        MOV     EAX,OFFSET m1
        CALL    ShowMessage
        CALL    VTConnectTimer
        CALL    VTBeginSync
        CALL    VTWaitForStart
        MOV     EAX,OFFSET m2
        CALL    ShowMessage
     do:
         ; Nifty Tran's way to kbhit().
        MOV     AX,GS:[41Ah]
        CMP     AX,GS:[41Ch]
        JZ      do

        mov v86r_ah,0                   ; wait for key with INT 16h AH=0
        mov al,16h
        int 33h

        MOV     EAX,OFFSET m3
    Bye:
        CALL    ShowMessage
        jmp _exit

code32  ends
        end

; --------------------------- PMODETST.ASM ---------------------------

