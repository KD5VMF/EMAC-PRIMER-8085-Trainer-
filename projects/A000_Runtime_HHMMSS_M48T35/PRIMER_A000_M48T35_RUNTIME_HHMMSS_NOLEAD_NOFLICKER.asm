;===============================================================================
;  PRIMER_A000_M48T35_RUNTIME_HHMMSS_NOLEAD_NOFLICKER.asm
;
;  EMAC PRIMER (8085)
;  ROM: 0000-7FFF
;  RAM: 8000-FFFF  (M48T35 TIMEKEEPER RAM+RTC mapped here)
;
;  Tick source: M48T35 seconds register at TOP of RAM (FFF8-FFFF region).
;    FFF8 = Control (W/R/cal)
;    FFF9 = Seconds (BCD; bit7 = STOP)
;
;  Display: runtime HHMMSS on the 6-digit 7-seg.
;    - Leading-zero blanking (LEFT side only)
;    - No flicker: only updates digits that changed
;
;  Seconds logic is intentionally conservative and proven:
;    - uses READ latch (R=1) briefly, then releases it (R=0)
;    - masks STOP bit in seconds
;    - converts packed BCD seconds to binary 0..59
;
;  Minutes roll 59->00, hours roll 23->00 (true HH:MM:SS runtime).
;
;  Load/Run:
;    Load at A000h and execute:  G A000
;===============================================================================

            ORG     0A000H

;---------------- MOS services --------------------------------------------------
MOS_ENTRY    EQU     01000H
SVC_LEDOUT   EQU     011H           ; raw segments output (use for BLANK)
SVC_DIGOUT   EQU     017H           ; digit 0..F output
SVC_DECPNT   EQU     021H           ; decimal point control

;---------------- M48T35 RTC mapped at top of RAM ------------------------------
RTC_CTRL     EQU     0FFF8H
RTC_SEC      EQU     0FFF9H
RTC_DAY      EQU     0FFFCH         ; clear FT/reserved bits for normal run

;---------------- Stack (keep well away from code/vars) ------------------------
STACKTOP     EQU     0BFFFH

;===============================================================================
; START
;===============================================================================

START:      DI
            LXI     SP,STACKTOP

            ; Decimal points OFF
            MVI     C,SVC_DECPNT
            MVI     D,00H
            CALL    MOS_ENTRY

            ; Clear runtime
            XRA     A
            STA     RUN_S
            STA     RUN_M
            STA     RUN_H
            STA     PREV_SEC

            ; Init prev display states to "invalid" so first draw always happens
            MVI     A,0FEH
            STA     PREV0
            STA     PREV1
            STA     PREV2
            STA     PREV3
            STA     PREV4
            STA     PREV5

            ; Ensure oscillator is running (clear STOP in seconds if set)
            CALL    RTC_START_OSC

            ; Verify seconds actually tick (else blink)
            CALL    RTC_VERIFY_TICK

            ; Seed previous second
            CALL    RTC_GET_SECONDS_BIN
            STA     PREV_SEC

            ; Initial display
            CALL    DISP_TIME

;===============================================================================
; MAIN LOOP: runtime ticks when RTC seconds change
;===============================================================================

MAIN:       CALL    RTC_GET_SECONDS_BIN      ; A=new (0..59)
            MOV     B,A                      ; B=new

            LDA     PREV_SEC                 ; A=last
            CMP     B
            JZ      POLL_DELAY_AND_REPEAT

            ; delta = (new - last) mod 60
            MOV     D,A                      ; D=last
            MOV     A,B                      ; A=new
            STA     PREV_SEC                 ; update last=new

            CMP     D
            JC      DELTA_WRAP

            SUB     D                        ; A=new-last
            MOV     B,A
            JMP     APPLY_DELTA

DELTA_WRAP: ADI     03CH                     ; +60
            SUB     D
            MOV     B,A

APPLY_DELTA:
            ; Apply B seconds to runtime
APLP:       MOV     A,B
            ORA     A
            JZ      UPDATE_DISP
            CALL    INC_RUNTIME_1S
            DCR     B
            JMP     APLP

UPDATE_DISP:
            CALL    DISP_TIME
            JMP     MAIN

POLL_DELAY_AND_REPEAT:
            CALL    SMALL_DELAY
            JMP     MAIN

;===============================================================================
; RTC_START_OSC
;   If STOP bit (D7) in seconds is 1, clear it safely.
;===============================================================================

RTC_START_OSC:
            LDA     RTC_SEC
            ANI     080H
            JZ      RTSO_DONE

            ; base = CTRL with W/R cleared (preserve calibration/sign)
            LDA     RTC_CTRL
            ANI     03FH
            MOV     B,A                      ; B=base

            ; Set WRITE (W=1)
            MOV     A,B
            ORI     080H
            STA     RTC_CTRL

            ; Clear STOP bit in seconds
            LDA     RTC_SEC
            ANI     07FH
            STA     RTC_SEC

            ; Clear FT/reserved bits in DAY reg (keep dow bits)
            LDA     RTC_DAY
            ANI     037H
            STA     RTC_DAY

            ; Release WRITE (W=0, R=0)
            MOV     A,B
            STA     RTC_CTRL

            ; Give oscillator time to start
            CALL    BIG_DELAY

RTSO_DONE:  RET

;===============================================================================
; RTC_GET_SECONDS_BIN
;   Reads seconds (BCD) from RTC_SEC with READ latch for consistency.
;   OUT: A = 0..59 (binary)
;===============================================================================

RTC_GET_SECONDS_BIN:
            ; base = CTRL with W/R cleared (preserve calibration/sign)
            LDA     RTC_CTRL
            ANI     03FH
            MOV     B,A

            ; Set READ (R=1) to freeze updates during read
            MOV     A,B
            ORI     040H
            STA     RTC_CTRL

            ; Read seconds, mask STOP
            LDA     RTC_SEC
            ANI     07FH
            MOV     E,A                      ; E=BCD seconds

            ; Clear READ (R=0)
            MOV     A,B
            STA     RTC_CTRL

            ; Convert packed BCD in E -> binary in A
            MOV     A,E
            CALL    BCD_SEC_TO_BIN
            RET

;===============================================================================
; RTC_VERIFY_TICK
;   Confirms seconds change. If not, blink 888888 forever.
;===============================================================================

RTC_VERIFY_TICK:
            CALL    RTC_GET_SECONDS_BIN
            STA     SEC_A

            MVI     A,200
            STA     RETRY

VTLP:       CALL    SMALL_DELAY
            CALL    RTC_GET_SECONDS_BIN
            MOV     B,A
            LDA     SEC_A
            CMP     B
            JNZ     VT_OK

            LDA     RETRY
            DCR     A
            STA     RETRY
            JNZ     VTLP

            ; FAIL -> blink 888888 forever
VT_FAIL:    MVI     A,08H
            CALL    SHOW_ALL_DIG
            CALL    BIG_DELAY
            CALL    SHOW_ALL_BLANK
            CALL    BIG_DELAY
            JMP     VT_FAIL

VT_OK:      RET

;===============================================================================
; BCD_SEC_TO_BIN
;   IN : A = packed BCD (00-59)
;   OUT: A = binary 0..59
;===============================================================================

BCD_SEC_TO_BIN:
            MOV     E,A                      ; save BCD

            ; tens in B
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     B,A

            ; ones in C
            MOV     A,E
            ANI     00FH
            MOV     C,A

            ; clamp if bogus
            MOV     A,B
            CPI     06H
            JNC     BCD_BAD
            MOV     A,C
            CPI     0AH
            JNC     BCD_BAD

            ; tens*10 = tens*8 + tens*2
            MOV     A,B
            ADD     A                        ; *2
            MOV     D,A
            MOV     A,B
            ADD     A                        ; *2
            ADD     A                        ; *4
            ADD     A                        ; *8
            ADD     D                        ; *10
            ADD     C                        ; +ones
            RET

BCD_BAD:    XRA     A
            RET

;===============================================================================
; INC_RUNTIME_1S  (minutes 0..59, hours 0..23)
;===============================================================================

INC_RUNTIME_1S:
            ; seconds++
            LDA     RUN_S
            INR     A
            CPI     03CH                     ; 60
            JC      IRS_OK
            XRA     A
            STA     RUN_S
            JMP     MIN_INC

IRS_OK:     STA     RUN_S
            RET

MIN_INC:
            ; minutes++
            LDA     RUN_M
            INR     A
            CPI     03CH                     ; 60
            JC      IRM_OK
            XRA     A
            STA     RUN_M
            JMP     HOUR_INC

IRM_OK:     STA     RUN_M
            RET

HOUR_INC:
            ; hours++
            LDA     RUN_H
            INR     A
            CPI     018H                     ; 24
            JC      IRH_OK
            XRA     A
            STA     RUN_H
            RET

IRH_OK:     STA     RUN_H
            RET

;===============================================================================
; DISPLAY (leading-zero blanking + change-only updates)
;   Positions: 5 4 3 2 1 0  = Ht Ho Mt Mo St So
;===============================================================================

DISP_TIME:
            ; seconds -> pos1,pos0
            LDA     RUN_S
            CALL    TO_TENS_ONES
            LDA     LAST_ONES
            STA     DIGBUF0                  ; pos0 (sec ones)
            MOV     A,B
            STA     DIGBUF1                  ; pos1 (sec tens)

            ; minutes -> pos3,pos2
            LDA     RUN_M
            CALL    TO_TENS_ONES
            LDA     LAST_ONES
            STA     DIGBUF2                  ; pos2 (min ones)
            MOV     A,B
            STA     DIGBUF3                  ; pos3 (min tens)

            ; hours -> pos5,pos4
            LDA     RUN_H
            CALL    TO_TENS_ONES
            LDA     LAST_ONES
            STA     DIGBUF4                  ; pos4 (hour ones)
            MOV     A,B
            STA     DIGBUF5                  ; pos5 (hour tens)

            ; Blank leading zeros from pos5 down to pos1 (pos0 always shown)
            XRA     A
            STA     FOUNDNZ                  ; 0 = none seen yet

            ; pos5
            LDA     FOUNDNZ
            ORA     A
            JNZ     BLK_P4
            LDA     DIGBUF5
            ORA     A
            JNZ     SET_NZ5
            MVI     A,0FFH
            STA     DIGBUF5
            JMP     BLK_P4
SET_NZ5:    MVI     A,01H
            STA     FOUNDNZ

BLK_P4:     LDA     FOUNDNZ
            ORA     A
            JNZ     BLK_P3
            LDA     DIGBUF4
            ORA     A
            JNZ     SET_NZ4
            MVI     A,0FFH
            STA     DIGBUF4
            JMP     BLK_P3
SET_NZ4:    MVI     A,01H
            STA     FOUNDNZ

BLK_P3:     LDA     FOUNDNZ
            ORA     A
            JNZ     BLK_P2
            LDA     DIGBUF3
            ORA     A
            JNZ     SET_NZ3
            MVI     A,0FFH
            STA     DIGBUF3
            JMP     BLK_P2
SET_NZ3:    MVI     A,01H
            STA     FOUNDNZ

BLK_P2:     LDA     FOUNDNZ
            ORA     A
            JNZ     BLK_P1
            LDA     DIGBUF2
            ORA     A
            JNZ     SET_NZ2
            MVI     A,0FFH
            STA     DIGBUF2
            JMP     BLK_P1
SET_NZ2:    MVI     A,01H
            STA     FOUNDNZ

BLK_P1:     LDA     FOUNDNZ
            ORA     A
            JNZ     DO_UPDATES
            LDA     DIGBUF1
            ORA     A
            JNZ     DO_UPDATES
            MVI     A,0FFH
            STA     DIGBUF1

DO_UPDATES:
            ; Update pos0..pos5 only if changed
            ; pos0
            MVI     D,00H
            LDA     DIGBUF0
            MOV     B,A
            LDA     PREV0
            CMP     B
            JZ      UP1
            MOV     A,B
            STA     PREV0
            CALL    OUT_DIG_OR_BLANK

UP1:        MVI     D,01H
            LDA     DIGBUF1
            MOV     B,A
            LDA     PREV1
            CMP     B
            JZ      UP2
            MOV     A,B
            STA     PREV1
            CALL    OUT_DIG_OR_BLANK

UP2:        MVI     D,02H
            LDA     DIGBUF2
            MOV     B,A
            LDA     PREV2
            CMP     B
            JZ      UP3
            MOV     A,B
            STA     PREV2
            CALL    OUT_DIG_OR_BLANK

UP3:        MVI     D,03H
            LDA     DIGBUF3
            MOV     B,A
            LDA     PREV3
            CMP     B
            JZ      UP4
            MOV     A,B
            STA     PREV3
            CALL    OUT_DIG_OR_BLANK

UP4:        MVI     D,04H
            LDA     DIGBUF4
            MOV     B,A
            LDA     PREV4
            CMP     B
            JZ      UP5
            MOV     A,B
            STA     PREV4
            CALL    OUT_DIG_OR_BLANK

UP5:        MVI     D,05H
            LDA     DIGBUF5
            MOV     B,A
            LDA     PREV5
            CMP     B
            JZ      DRET
            MOV     A,B
            STA     PREV5
            CALL    OUT_DIG_OR_BLANK

DRET:       RET

; OUT_DIG_OR_BLANK
;   IN: D = position (0..5)
;       A = value 0..9 OR FFh for blank
OUT_DIG_OR_BLANK:
            CPI     0FFH
            JZ      OUT_BLANK
            MOV     E,A
            MVI     C,SVC_DIGOUT
            CALL    MOS_ENTRY
            RET

OUT_BLANK:
            MVI     E,00H                    ; all segments off
            MVI     C,SVC_LEDOUT
            CALL    MOS_ENTRY
            RET

;===============================================================================
; Helpers
;===============================================================================

TO_TENS_ONES:
            ; IN : A (0..99)
            ; OUT: B=tens, LAST_ONES=ones
            MVI     B,00H
TTO:        CPI     00AH
            JC      TTD
            SUI     00AH
            INR     B
            JMP     TTO
TTD:        STA     LAST_ONES
            RET

SHOW_ALL_DIG:
            ; IN: A=digit 0..9
            MOV     E,A
            MVI     C,SVC_DIGOUT
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

SHOW_ALL_BLANK:
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

;===============================================================================
; Delays
;===============================================================================

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

;===============================================================================
; Variables
;===============================================================================

RUN_S:      DB      00H
RUN_M:      DB      00H
RUN_H:      DB      00H

PREV_SEC:   DB      00H
SEC_A:      DB      00H
RETRY:      DB      00H

LAST_ONES:  DB      00H

; Display buffers (index == display position)
DIGBUF0:    DB      00H
DIGBUF1:    DB      00H
DIGBUF2:    DB      00H
DIGBUF3:    DB      00H
DIGBUF4:    DB      00H
DIGBUF5:    DB      00H

FOUNDNZ:    DB      00H

; Previous displayed state per digit (0..9 or FF=blank)
PREV0:      DB      0FEH
PREV1:      DB      0FEH
PREV2:      DB      0FEH
PREV3:      DB      0FEH
PREV4:      DB      0FEH
PREV5:      DB      0FEH

            END
