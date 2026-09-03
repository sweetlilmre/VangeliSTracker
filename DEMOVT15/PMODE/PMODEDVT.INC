; ------------------------------ PMODEDVT.INC --------------------------------
; ASM library file for accessing the DemoVT. For Watcom C and/or Tran's PMode.
; (C) Copyright 1993-1994 by Iguana-VangeliSTeam. However, it is made
; public domain for non-commercial use.

IFNDEF _PMODEDVT_H_
       _PMODEDVT_H_ = 1

        .386p
code32  segment para public use32
        assume cs:code32, ds:code32

INCLUDE PMODE.INC

ENDS

; -------------------------------------------------------------
; This is the structure that holds the DemoVT variables.
; We will get its address to check semaphores, modify volume, and
; all that.                                  

TChanData STRUC
      Period DW ?
      Ins    DB ?
      Vol    DB ?
ENDS

VTRunInfo STRUC
  ; These are modified by DemoVT, and you can read them.
      Semaphores     DB 256 DUP(?)      ; Array of semaphores. You can read or
                                        ; modify them (usually cleaning them).


      ChansTrig      DB  32 DUP(?)      ; == 1 -> channel retriggered a note.
      NumChannels    DB ?               ; Number of channels in the MOD.

      CtrlEntryPoint DD ?               ; Address of ther DemoVT service proc.
      TickCounter    DD ?               ; This one provides some form for you
                                        ; to do timing, incremented at 50Hz.
      RegEntryPoint  DD ?               ; DVT Service taking parm in AX.
      ChansData      TChanData 32 DUP (<>) ; Per-channel info.
      Pos            DB ?               ; Note in the current pattern.
      Seq            DB ?               ; Number of playing pattern.

                     DB 81 DUP(?)      ; Reserved.

  ; These are supposed to be modified by you to tell DemoVT your intentions. :)
                     DB  ?              ; Reserved.
                     DW  ?              ; Reserved.

      JumpNewPos     DB  ?              ; Indicates that you want to jump to
                                        ; another position inside the MOD.
      JumpPosSeq     DB  ?              ; Sequence position to jump to.
      JumpPosNote    DB  ?              ; Note inside the pattern to jump to.

      SoundVolume    DB  ?              ; Put your favourite volume here.
                                        ; You can perform fades and the like.
                                        ; 0-255.
      Abort          DB ?               ; Set to 1 to force DVT to exit after
                                        ; your program exits.

                     DB 248 DUP(?)      ; Reserved.

ENDS

code32  segment para public use32
        assume cs:code32, ds:code32


DMA_Channel_EDX EQU (DMA_Channel PTR EDX)

; ---------------------------------------------------------------

GLOBAL AppIDFound   : DWORD     ; Address of the DemoVT (C) string.
GLOBAL DVTRunInfo   : DWORD     ; Address of the VTRunInfo declared above.

; ========================== FUNCTIONS ==========================
; You can count these modify ALL registers except EBX, ESI, EDI.

GLOBAL InitMusic         : NEAR
GLOBAL CallMusic         : NEAR
GLOBAL VTConnectTimer    : NEAR
GLOBAL VTDisconnectTimer : NEAR
GLOBAL VTGetTickCounter  : NEAR
GLOBAL VTBeginSync       : NEAR
GLOBAL VTWaitForStart    : NEAR
GLOBAL VTJumpPos         : NEAR
GLOBAL VTCheckSemaphore  : NEAR
GLOBAL VTSetSemaphore    : NEAR
GLOBAL VTMiddleSync      : NEAR
GLOBAL VTSetSoundVolume  : NEAR
GLOBAL VTGetSoundVolume  : NEAR

ENDIF

; -------------------------- End of PMODEDVT.INC --------------------------
