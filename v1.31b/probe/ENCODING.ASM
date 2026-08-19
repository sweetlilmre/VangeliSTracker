; The ENCODING probe -- the assembler half of demovt/probe/PROBE.PAS.
;
; Turbo Pascal's inline assembler and TASM disagree on the direction bit for
; same-register arithmetic, and 1a17 contains BOTH: 0746..10c3 is TASM's and
; GetPlayPos's asm block is TP's. This file is what settled that. Assemble it
; with the image's own TASM and read the listing:
;
;     C:\TASM\BIN\TASM.EXE /la /m2 ENCODING.ASM
;
; measured with TASM 4.1, against the original's bytes:
;
;     SUB BX,AX     2B D8      original 29 C3 at 0713   (TP inline asm: 29 C3)
;     SUB AX,BX     2B C3
;     AND AL,AL     22 C0      original 22 C0 at 1014   (TP inline asm: 20 C0)
;     XOR AL,AL     32 C0      original 32 C0 at 102e   (TP inline asm: 30 C0)
;     ADD AX,AX     03 C0      original 03 C0 at 0a84   (TP inline asm: 01 C0)
;     RETF 4        CA 0004    original CA 04 00 at 10c1 (TP cannot express it)
;
; IDEAL / MODEL TPascal / LOCALS @@ are the release's own directives, taken
; from VangeliSTracker/LIB/SOUNDDEV.ASM.

                IDEAL
                MODEL  TPascal
                LOCALS @@
                P286

                DATASEG
GLOBAL DMABufferSize : WORD

                CODESEG
PUBLIC ProbeTasm
ProbeTasm:
                SUB     BX,AX
                SUB     AX,BX
                AND     AL,AL
                XOR     AL,AL
                ADD     AX,AX
                MOV     BX,[DMABufferSize]
                RETF    4
                END
