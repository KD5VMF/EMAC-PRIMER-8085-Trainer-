;===============================================================================
;  PRIMER_A000_M48T35_RTC_SECONDS_TEST.asm
;
;  Simple sanity test for the M48T35 Timekeeper (8000-FFFF mapped):
;    - Ensures oscillator running (clears STOP bit if needed)
;    - Reads seconds from FFF9
;    - Displays SS on the two rightmost 7-seg digits (pos1 pos0)
;      (other digits blank)
;
;  Load/Run:
;    Load at A000h and execute:  G A000
;===============================================================================

            ORG     0A000H

MOS_ENTRY    EQU     01000H
SVC_LEDOUT   EQU     011H           ; blank via raw segments
SVC_DIGOUT   EQU     017H
SVC_DECPNT   EQU     021H

RTC_CTRL     EQU     0FFF8H
RTC_SEC      EQU     0FFF9H
RTC_DAY      EQU     0FFFCH

STACKTOP     EQU     0BFFFH

START:      DI
            LXI     SP,STACKTOP

            ; DPs off
            MVI     C,SVC_DECPNT
            MVI     D,00H
            CALL    MOS_ENTRY

            ; blank all digits
            CALL    BLANK_ALL

            ; start oscillator if needed
            CALL    RTC_START_OSC

MAIN:       CALL    RTC_GET_SECONDS_BIN      ; A=0..59
            CALL    TO_TENS_ONES             ; B=tens, LAST_ONES=ones

            ; tens at pos1, ones at pos0
            MOV     A,B
            MVI     D,01H
            CALL    PUTDIG

            LDA     LAST_ONES
            MVI     D,00H
            CALL    PUTDIG

            CALL    SMALL_DELAY
            JMP     MAIN

;---------------- RTC helpers ----------------

RTC_START_OSC:
            LDA     RTC_SEC
            ANI     080H
            JZ      RTSO_DONE

            LDA     RTC_CTRL
            ANI     03FH
            MOV     B,A

            MOV     A,B
            ORI     080H
            STA     RTC_CTRL

            LDA     RTC_SEC
            ANI     07FH
            STA     RTC_SEC

            LDA     RTC_DAY
            ANI     037H
            STA     RTC_DAY

            MOV     A,B
            STA     RTC_CTRL

            CALL    BIG_DELAY
RTSO_DONE:  RET

RTC_GET_SECONDS_BIN:
            LDA     RTC_CTRL
            ANI     03FH
            MOV     B,A

            MOV     A,B
            ORI     040H
            STA     RTC_CTRL

            LDA     RTC_SEC
            ANI     07FH
            MOV     E,A

            MOV     A,B
            STA     RTC_CTRL

            MOV     A,E
            CALL    BCD_SEC_TO_BIN
            RET

BCD_SEC_TO_BIN:
            MOV     E,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     B,A
            MOV     A,E
            ANI     00FH
            MOV     C,A

            MOV     A,B
            CPI     06H
            JNC     BCD_BAD
            MOV     A,C
            CPI     0AH
            JNC     BCD_BAD

            MOV     A,B
            ADD     A
            MOV     D,A
            MOV     A,B
            ADD     A
            ADD     A
            ADD     A
            ADD     D
            ADD     C
            RET
BCD_BAD:    XRA     A
            RET

;---------------- display helpers ----------------

PUTDIG:     MOV     E,A
            MVI     C,SVC_DIGOUT
            CALL    MOS_ENTRY
            RET

BLANK_ALL:
            MVI     C,SVC_LEDOUT
            MVI     E,00H
            MVI     D,00H
            CALL    MOS_ENTRY
            MVI     D,01H
            CALL    MOS_ENTRY
            MVI     D,02H
            CALL    MOS_ENTRY
            MVI     D,03H
            CALL    MOS_ENTRY
            MVI     D,04H
            CALL    MOS_ENTRY
            MVI     D,05H
            CALL    MOS_ENTRY
            RET

TO_TENS_ONES:
            MVI     B,00H
TTO:        CPI     00AH
            JC      TTD
            SUI     00AH
            INR     B
            JMP     TTO
TTD:        STA     LAST_ONES
            RET

;---------------- delays ----------------

SMALL_DELAY:
            LXI     H,1200H
SD1:        DCX     H
            MOV     A,H
            ORA     L
            JNZ     SD1
            RET

BIG_DELAY:
            LXI     H,7000H
BD1:        DCX     H
            MOV     A,H
            ORA     L
            JNZ     BD1
            RET

LAST_ONES:  DB      00H

            END
