;
;===============================================================================
;  PRIMER_A000_M48T35_CLOCK_BIGASCII_PERSIST.asm
;
;  EMAC PRIMER (8085) + M48T35 Timekeeper (mapped at FFF8-FFFF)
;
;  FEATURES
;  --------
;  1) One-time SET: If the user already set the clock once (saved flag stored in
;     battery-backed RAM), the program will NOT prompt again on next run.
;     - Press 'S' anytime to re-set time/date.
;     - Press 'C' at the live display to clear the saved flag (forces prompt next run).
;     - Press 'Q' to redraw UI.
;
;  2) Big ASCII "7-seg" clock in the terminal (DEC display):
;       HH:MM:SS shown large (3-row digits).
;     Date shown normal: 20YY-MM-DD
;
;  3) 6-digit 7-seg hardware display shows HH MM SS as HEX BYTES:
;       hour (00-17h), minute (00-3Bh), second (00-3Bh)
;     Example: 23:59:59 -> 17 3B 3B on the 7-seg display.
;
;  LOAD/RUN
;  --------
;   - Assemble with             ORG     09000H
;   - Download Intel HEX to RAM at 9000h
;   - Run:  G 9000
;
;  HARDWARE ASSUMPTIONS (your known-good setup)
;  --------------------------------------------
;   - ROM: 0000-7FFF
;   - RAM: 8000-FFFF (battery-backed)
;   - M48T35 mapped at:
;        FFF8 Control
;        FFF9 Seconds
;        FFFA Minutes
;        FFFB Hours
;        FFFC Day-of-week
;        FFFD Date
;        FFFE Month
;        FFFF Year
;   - UART 8251A: data=80h, status=81h (monitor already init'd UART)
;   - 7-seg via EMOS services at 1000h:
;        DIGOUT  C=17h  D=0..5  E=0..15 (hex digit)
;        DECPNT  C=21h  D=bitmask (00h forces all off)
;
;  PERSISTENT "CLOCK SET" FLAG
;  ---------------------------
;   Stored at PERSIST_BASE = FEF0h (battery-backed RAM).
;   Signature: 'C''L''K''S''E''T''1'  (7 bytes) + 00
;   Also stores last set values (BCD) so you can inspect later if desired.
;
;===============================================================================

                        ORG     09000H
            JMP     START

; ----------------- CONSTANTS -----------------

MOS         EQU     1000H

; EMOS services
SVC_DIGOUT  EQU     17H
SVC_DECPNT  EQU     21H

; UART (8251A)
UART_DATA   EQU     80H
UART_STAT   EQU     81H

; 8155 PPI ports (I/O mapped)
PPI_PA      EQU     10H
PPI_PB      EQU     11H
PPI_PC      EQU     12H
PPI_CMD     EQU     13H

; UART status bits (8251A)
ST_TXRDY    EQU     01H
ST_RXRDY    EQU     02H

; M48T35 registers (memory-mapped at top of RAM)
RTC_CTRL    EQU     0FFF8H
RTC_SEC     EQU     0FFF9H
RTC_MIN     EQU     0FFFAH
RTC_HOUR    EQU     0FFFBH
RTC_DOW     EQU     0FFFCH
RTC_DATE    EQU     0FFFDH
RTC_MON     EQU     0FFFEH
RTC_YEAR    EQU     0FFFFH

CTRL_W      EQU     80H            ; write enable

; Persistent storage location in battery-backed RAM (safe away from FFF8-FFFF)
PERSIST_BASE EQU    0FEF0H         ; 16 bytes reserved

; Screen layout (ANSI 1-based)
ROW_TITLE   EQU     1
ROW_LINE    EQU     3
ROW_DATE    EQU     5
ROW_BIG     EQU     7              ; big time starts here (3 rows: 7..9)
ROW_HEX     EQU     11
ROW_HINT    EQU     13

COL_LABEL   EQU     1
COL_VALUE   EQU     14
COL_BIG     EQU     14
; ----------------- STARTUP -----------------


;  VARIABLES (fixed RAM addresses to avoid forward-reference issues)
;===============================================================================

VAR_BASE        EQU 0FD00H         ; safe RAM area below stack (stack at FE00h)

PREV_SEC        EQU VAR_BASE+0
BCD_SEC         EQU VAR_BASE+1
BCD_MIN         EQU VAR_BASE+2
BCD_HOUR        EQU VAR_BASE+3
BCD_DATE        EQU VAR_BASE+4
BCD_MON         EQU VAR_BASE+5
BCD_YEAR        EQU VAR_BASE+6

BIN_SEC         EQU VAR_BASE+7
BIN_MIN         EQU VAR_BASE+8
BIN_HOUR        EQU VAR_BASE+9

SEG_MODE        EQU VAR_BASE+10     ; 0=HEX bytes, 1=DEC HHMMSS

BCD_SEC_SET     EQU VAR_BASE+11
BCD_MIN_SET     EQU VAR_BASE+12
BCD_HOUR_SET    EQU VAR_BASE+13
BCD_DATE_SET    EQU VAR_BASE+14
BCD_MON_SET     EQU VAR_BASE+15
BCD_YEAR_SET    EQU VAR_BASE+16
DOW_SET         EQU VAR_BASE+17

D0              EQU VAR_BASE+18
D1              EQU VAR_BASE+19
D2              EQU VAR_BASE+20
D3              EQU VAR_BASE+21
D4              EQU VAR_BASE+22
D5              EQU VAR_BASE+23
;===============================================================================
;  STRINGS (0-terminated)
;===============================================================================


BIGFONT:
            ; Each digit is 3 rows, each row is 3 characters (total 9 bytes per digit)

            ; 0
            DB ' ','_',' ','|',' ','|','|','_','|'
            ; 1
            DB ' ',' ',' ',' ',' ','|',' ',' ','|'
            ; 2
            DB ' ','_',' ',' ','_','|','|','_',' '
            ; 3
            DB ' ','_',' ',' ','_','|',' ','_','|'
            ; 4
            DB ' ',' ',' ','|','_','|',' ',' ','|'
            ; 5
            DB ' ','_',' ','|','_',' ',' ','_','|'
            ; 6
            DB ' ','_',' ','|','_',' ','|','_','|'
            ; 7
            DB ' ','_',' ',' ',' ','|',' ',' ','|'
            ; 8
            DB ' ','_',' ','|','_','|','|','_','|'
            ; 9
            DB ' ','_',' ','|','_','|',' ','_','|'
;===============================================================================

STR_CLR:        DB  1BH,'[','2','J',1BH,'[','H',0
STR_GREEN:      DB  1BH,'[','9','2','m',0
STR_WHITE:      DB  1BH,'[','0','m',0
STR_HIDE_CURSOR: DB  1BH,'[','?','2','5','l',0
STR_SHOW_CURSOR: DB  1BH,'[','?','2','5','h',0
STR_EOL:        DB  1BH,'[','K',0

STR_BANNER:
            DB  13,10
            DB  'EMAC PRIMER 8085 + M48T35 Timekeeper Clock',13,10
            DB  'Big ASCII terminal clock (DEC) + 7-seg HEX bytes + persistent SET flag',13,10
            DB  'Load at 9000h and run: G 9000',13,10,13,10,0

STR_LINE:        DB  '------------------------------------------------------------',0
STR_DATE_LBL:    DB  'DATE (DEC):  ',0
STR_TIME_LBL:    DB  'TIME (DEC):  (big)',0
STR_HEX_LBL:     DB  'SEG:         (press T to toggle HEX/DEC)',0

STR_HINT:
            DB  'Keys:  S=set clock   T=toggle seg   C=clear flag   Q=redraw   E=exit',0

STR_CLEARED:
            DB  'Saved flag cleared. Next run will prompt to set the clock.      ',0

STR_MODE_HEX:   DB  'MODE:HEX',0
STR_MODE_DEC:   DB  'MODE:DEC',0

STR_SET1:
            DB  'SET CLOCK (DEC). Press ENTER after each value.',13,10
            DB  'Tip: If you ever want to force this prompt next time, press C in live mode.',13,10,13,10,0

STR_P_YR:        DB  'Year (00-99): ',0
STR_P_MON:       DB  'Month (1-12): ',0
STR_P_DATE:      DB  'Day (1-31):   ',0
STR_P_DOW:       DB  'DOW (1-7, 1=Sun): ',0
STR_P_HR:        DB  'Hour (0-23):  ',0
STR_P_MIN:       DB  'Minute (0-59):',0
STR_P_SEC:       DB  'Second (0-59):',0

STR_EXIT:
            DB  13,10,'Exiting... terminal color restored. Returning to monitor.',13,10,0

STR_SET_DONE:
            DB  13,10,'Clock updated. Press any key to start live display...',13,10,0


START:      DI
            LXI     SP,0FE00H      ; keep stack away from RTC and persistent bytes

            ; default 7-seg mode = HEX bytes
            XRA     A
            STA     SEG_MODE

            ; turn off all decimal points on hardware 7-seg
            MVI     C,SVC_DECPNT
            MVI     D,00H
            CALL    MOS

            ; clear 7-seg digits to 0
            CALL    SEG_CLEAR

            ; clear terminal, set GREEN, and show banner
            CALL    TERM_CLEAR
            CALL    TERM_GREEN
            CALL    SHOW_BANNER

            ; if not set before, force set UI
            CALL    PERSIST_CHECK
            ORA     A
            JNZ     HAVE_SAVED

            ; Not saved -> force set
            CALL    SET_CLOCK_UI
            CALL    PERSIST_WRITE   ; mark as set

HAVE_SAVED:
            ; draw the live UI frame
            CALL    DRAW_UI

            ; force first update
            MVI     A,0FFH
            STA     PREV_SEC

MAIN_LOOP:  CALL    RTC_READ_STABLE

            ; update on second change only (no flicker)
            LDA     BCD_SEC
            MOV     B,A
            LDA     PREV_SEC
            CMP     B
            JZ      POLL_KEY

            MOV     A,B
            STA     PREV_SEC

            ; update binary values used by HEX + 7-seg
            CALL    COMPUTE_BIN_FROM_BCD

            ; show DEC seconds (BCD) on the 8 LEDs (active-low)
            CALL    LED_SHOW_SEC

            ; update hardware 7-seg (HEX bytes OR DEC HHMMSS)
            CALL    SEG_SHOW_MODED

            ; update terminal (date + big time + hex bytes line)
            CALL    TERM_UPDATE

POLL_KEY:   CALL    KEY_POLL
            ORA     A
            JZ      MAIN_LOOP

            CPI     'S'
            JZ      DO_SET
            CPI     'Q'
            JZ      DO_REDRAW
            CPI     'C'
            JZ      DO_CLEARFLAG
            CPI     'T'
            JZ      DO_TOGGLESEG
            CPI     'E'
            JZ      DO_EXIT
            CPI     'X'
            JZ      DO_EXIT

            JMP     MAIN_LOOP

DO_SET:     CALL    SET_CLOCK_UI
            CALL    PERSIST_WRITE
            JMP     DO_REDRAW

DO_CLEARFLAG:
            CALL    PERSIST_CLEAR
            CALL    TERM_STATUS_CLEARED
            JMP     MAIN_LOOP

DO_TOGGLESEG:
            ; flip SEG_MODE and force immediate redraw of seg + terminal
            LDA     SEG_MODE
            XRI     01H
            STA     SEG_MODE
            ; force immediate refresh
            MVI     A,0FFH
            STA     PREV_SEC
            JMP     DO_REDRAW

DO_EXIT:    CALL    TERM_SHOW_CURSOR
            CALL    TERM_WHITE
            CALL    TERM_CLEAR
            LXI     H,STR_EXIT
            CALL    PUTS
            JMP     0000H           ; return to monitor (soft restart)

DO_REDRAW:  CALL    DRAW_UI
            MVI     A,0FFH
            STA     PREV_SEC
            JMP     MAIN_LOOP

;===============================================================================
;  BANNER / UI
;===============================================================================

SHOW_BANNER:
            ; Big ASCII title
            LXI     H,STR_BANNER
            CALL    PUTS
            RET

DRAW_UI:    CALL    TERM_CLEAR
            CALL    TERM_GREEN
            CALL    TERM_HIDE_CURSOR
            CALL    SHOW_BANNER

            ; divider line
            MVI     B,ROW_LINE
            MVI     C,COL_LABEL
            CALL    ANSI_GOTO_BC
            LXI     H,STR_LINE
            CALL    PUTS
            LXI     H,STR_EOL
            CALL    PUTS

            ; date label + placeholder
            MVI     B,ROW_DATE
            MVI     C,COL_LABEL
            CALL    ANSI_GOTO_BC
            LXI     H,STR_DATE_LBL
            CALL    PUTS
            LXI     H,STR_EOL
            CALL    PUTS

            ; big time area label
            MVI     B,ROW_BIG-1
            MVI     C,COL_LABEL
            CALL    ANSI_GOTO_BC
            LXI     H,STR_TIME_LBL
            CALL    PUTS
            LXI     H,STR_EOL
            CALL    PUTS

            ; HEX line label
            MVI     B,ROW_HEX
            MVI     C,COL_LABEL
            CALL    ANSI_GOTO_BC
            LXI     H,STR_HEX_LBL
            CALL    PUTS
            LXI     H,STR_EOL
            CALL    PUTS

            ; hints
            MVI     B,ROW_HINT
            MVI     C,COL_LABEL
            CALL    ANSI_GOTO_BC
            LXI     H,STR_HINT
            CALL    PUTS
            LXI     H,STR_EOL
            CALL    PUTS

            RET

;===============================================================================
;  TERMINAL UPDATE (no scrolling)
;===============================================================================

TERM_UPDATE:
            ; DATE: 20YY-MM-DD (DEC) at ROW_DATE, COL_VALUE
            MVI     B,ROW_DATE
            MVI     C,COL_VALUE
            CALL    ANSI_GOTO_BC

            ; "20"
            MVI     A,'2'
            CALL    PUTCH
            MVI     A,'0'
            CALL    PUTCH

            LDA     BCD_YEAR
            CALL    PRT_BCD2
            MVI     A,'-'
            CALL    PUTCH
            LDA     BCD_MON
            CALL    PRT_BCD2
            MVI     A,'-'
            CALL    PUTCH
            LDA     BCD_DATE
            CALL    PRT_BCD2

            ; BIG TIME: draw 3 rows starting at ROW_BIG, COL_BIG
            CALL    TERM_BIG_TIME

            ; SEG line at ROW_HEX, COL_VALUE
            MVI     B,ROW_HEX
            MVI     C,COL_VALUE
            CALL    ANSI_GOTO_BC

            ; Print mode
            LDA     SEG_MODE
            ORA     A
            JZ      TU_HEX
            LXI     H,STR_MODE_DEC
            CALL    PUTS
            JMP     TU_MODE_DONE
TU_HEX:     LXI     H,STR_MODE_HEX
            CALL    PUTS
TU_MODE_DONE:
            ; spacing
            MVI     A,' '
            CALL    PUTCH
            MVI     A,' '
            CALL    PUTCH

            ; Now print values
            LDA     SEG_MODE
            ORA     A
            JZ      TU_PRINT_HEX

            ; DEC mode: print HH:MM:SS in DEC (always 2 digits)
            LDA     BCD_HOUR
            CALL    PRT_BCD2
            MVI     A,':'
            CALL    PUTCH
            LDA     BCD_MIN
            CALL    PRT_BCD2
            MVI     A,':'
            CALL    PUTCH
            LDA     BCD_SEC
            CALL    PRT_BCD2
            JMP     TU_DONE

TU_PRINT_HEX:
            ; HEX mode: print HH MM SS as hex bytes
            LDA     BIN_HOUR
            CALL    PRT_HEX8
            MVI     A,' '
            CALL    PUTCH
            LDA     BIN_MIN
            CALL    PRT_HEX8
            MVI     A,' '
            CALL    PUTCH
            LDA     BIN_SEC
            CALL    PRT_HEX8

TU_DONE:    RET

; Draw large HH:MM:SS using 3-row 7-seg ASCII digits.
; Uses BCD_HOUR / BCD_MIN / BCD_SEC (BCD).
TERM_BIG_TIME:
            ; extract digit nibbles to TEMP digits
            LDA     BCD_HOUR
            CALL    SPLIT_BCD
            STA     D0              ; tens
            MOV     A,B
            STA     D1              ; ones

            LDA     BCD_MIN
            CALL    SPLIT_BCD
            STA     D2
            MOV     A,B
            STA     D3

            LDA     BCD_SEC
            CALL    SPLIT_BCD
            STA     D4
            MOV     A,B
            STA     D5

            ; for each row 0..2
            MVI     E,0
BT_ROW_LOOP:
            ; goto row = ROW_BIG + E
            MOV     A,E
            ADI     ROW_BIG
            MOV     B,A
            MVI     C,COL_BIG
            CALL    ANSI_GOTO_BC

            ; print digits with colon separators
            LDA     D0
            MOV     D,A
            MOV     A,E
            CALL    BIGDIG_PRINT     ; digit D, row A

            MVI     A,' '
            CALL    PUTCH

            LDA     D1
            MOV     D,A
            MOV     A,E
            CALL    BIGDIG_PRINT

            MVI     A,' '
            CALL    PUTCH

            ; colon
            MOV     A,E
            CALL    BIGCOLON_PRINT

            MVI     A,' '
            CALL    PUTCH

            LDA     D2
            MOV     D,A
            MOV     A,E
            CALL    BIGDIG_PRINT

            MVI     A,' '
            CALL    PUTCH

            LDA     D3
            MOV     D,A
            MOV     A,E
            CALL    BIGDIG_PRINT

            MVI     A,' '
            CALL    PUTCH

            ; colon
            MOV     A,E
            CALL    BIGCOLON_PRINT

            MVI     A,' '
            CALL    PUTCH

            LDA     D4
            MOV     D,A
            MOV     A,E
            CALL    BIGDIG_PRINT

            MVI     A,' '
            CALL    PUTCH

            LDA     D5
            MOV     D,A
            MOV     A,E
            CALL    BIGDIG_PRINT

            ; next row
            INR     E
            MOV     A,E
            CPI     3
            JC      BT_ROW_LOOP

            RET

; Print colon for row A (0..2)
; Row 0: "   "
; Row 1: " . "
; Row 2: " . "
BIGCOLON_PRINT:
            CPI     1
            JZ      BC_DOT
            CPI     2
            JZ      BC_DOT
            ; row0
            MVI     A,' '
            CALL    PUTCH
            MVI     A,' '
            CALL    PUTCH
            MVI     A,' '
            CALL    PUTCH
            RET
BC_DOT:     MVI     A,' '
            CALL    PUTCH
            MVI     A,'.'
            CALL    PUTCH
            MVI     A,' '
            CALL    PUTCH
            RET

; Print one big digit.
; IN: D = digit 0..9
;     A = row 0..2
; Uses BIGFONT table: 10 digits * 3 rows each, fixed 3 chars per row.
BIGDIG_PRINT:
            PUSH    PSW
            PUSH    B
            PUSH    D
            PUSH    H

            MOV     B,A            ; B=row (0..2)

            ; A = digit*9
            MOV     A,D            ; digit
            MOV     C,A            ; C=digit
            ADD     A              ; *2
            ADD     A              ; *4
            ADD     A              ; *8
            ADD     C              ; *9

            ; A = digit*9 + row*3
            MOV     C,A            ; C = digit*9
            MOV     A,B            ; row
            ADD     A              ; row*2
            ADD     B              ; row*3
            ADD     C              ; total offset 0..89
            MOV     E,A
            MVI     D,0

            LXI     H,BIGFONT
            DAD     D

            ; print 3 chars
            MOV     A,M
            CALL    PUTCH
            INX     H
            MOV     A,M
            CALL    PUTCH
            INX     H
            MOV     A,M
            CALL    PUTCH

            POP     H
            POP     D
            POP     B
            POP     PSW
            RET

;===============================================================================
;  PERSISTENT FLAG (battery-backed RAM)
;===============================================================================

; Return A=1 if signature matches, else A=0.
PERSIST_CHECK:
            LXI     H,PERSIST_BASE
            MOV     A,M
            CPI     'C'
            JNZ     PC_NO
            INX     H
            MOV     A,M
            CPI     'L'
            JNZ     PC_NO
            INX     H
            MOV     A,M
            CPI     'K'
            JNZ     PC_NO
            INX     H
            MOV     A,M
            CPI     'S'
            JNZ     PC_NO
            INX     H
            MOV     A,M
            CPI     'E'
            JNZ     PC_NO
            INX     H
            MOV     A,M
            CPI     'T'
            JNZ     PC_NO
            INX     H
            MOV     A,M
            CPI     '1'
            JNZ     PC_NO
            MVI     A,1
            RET
PC_NO:      XRA     A
            RET

PERSIST_WRITE:
            ; write signature and last set values (BCD)
            LXI     H,PERSIST_BASE
            MVI     A,'C'  ; 0
            MOV     M,A
            INX     H
            MVI     A,'L'  ; 1
            MOV     M,A
            INX     H
            MVI     A,'K'  ; 2
            MOV     M,A
            INX     H
            MVI     A,'S'  ; 3
            MOV     M,A
            INX     H
            MVI     A,'E'  ; 4
            MOV     M,A
            INX     H
            MVI     A,'T'  ; 5
            MOV     M,A
            INX     H
            MVI     A,'1'  ; 6
            MOV     M,A
            INX     H
            XRA     A       ; 7
            MOV     M,A

            ; bytes 8..13 store last set values (BCD)
            INX     H       ; 8
            LDA     BCD_YEAR_SET
            MOV     M,A
            INX     H       ; 9
            LDA     BCD_MON_SET
            MOV     M,A
            INX     H       ; 10
            LDA     BCD_DATE_SET
            MOV     M,A
            INX     H       ; 11
            LDA     BCD_HOUR_SET
            MOV     M,A
            INX     H       ; 12
            LDA     BCD_MIN_SET
            MOV     M,A
            INX     H       ; 13
            LDA     BCD_SEC_SET
            MOV     M,A
            RET

PERSIST_CLEAR:
            LXI     H,PERSIST_BASE
            XRA     A
            MOV     M,A
            RET

TERM_STATUS_CLEARED:
            ; small message on hint row (no redraw)
            MVI     B,ROW_HINT+3
            MVI     C,COL_LABEL
            CALL    ANSI_GOTO_BC
            LXI     H,STR_CLEARED
            CALL    PUTS
            LXI     H,STR_EOL
            CALL    PUTS
            RET

;===============================================================================
;  SET CLOCK UI
;===============================================================================

SET_CLOCK_UI:
            CALL    TERM_CLEAR
            CALL    TERM_GREEN
            CALL    TERM_SHOW_CURSOR
            CALL    SHOW_BANNER

            MVI     B,4
            MVI     C,1
            CALL    ANSI_GOTO_BC
            LXI     H,STR_SET1
            CALL    PUTS

            ; Year (00-99)
GET_YEAR:   LXI     H,STR_P_YR
            CALL    PUTS
            CALL    READ_DEC
            CPI     100
            JNC     GET_YEAR
            CALL    BIN2BCD
            STA     BCD_YEAR_SET

            ; Month (1-12)
GET_MON:    LXI     H,STR_P_MON
            CALL    PUTS
            CALL    READ_DEC
            CPI     1
            JC      GET_MON
            CPI     13
            JNC     GET_MON
            CALL    BIN2BCD
            STA     BCD_MON_SET

            ; Date (1-31)
GET_DATE:   LXI     H,STR_P_DATE
            CALL    PUTS
            CALL    READ_DEC
            CPI     1
            JC      GET_DATE
            CPI     32
            JNC     GET_DATE
            CALL    BIN2BCD
            STA     BCD_DATE_SET

            ; Day-of-week (1-7)
GET_DOW:    LXI     H,STR_P_DOW
            CALL    PUTS
            CALL    READ_DEC
            CPI     1
            JC      GET_DOW
            CPI     8
            JNC     GET_DOW
            STA     DOW_SET

            ; Hour (0-23)
GET_HR:     LXI     H,STR_P_HR
            CALL    PUTS
            CALL    READ_DEC
            CPI     24
            JNC     GET_HR
            CALL    BIN2BCD
            STA     BCD_HOUR_SET

            ; Minute (0-59)
GET_MIN:    LXI     H,STR_P_MIN
            CALL    PUTS
            CALL    READ_DEC
            CPI     60
            JNC     GET_MIN
            CALL    BIN2BCD
            STA     BCD_MIN_SET

            ; Second (0-59)
GET_SEC:    LXI     H,STR_P_SEC
            CALL    PUTS
            CALL    READ_DEC
            CPI     60
            JNC     GET_SEC
            CALL    BIN2BCD
            STA     BCD_SEC_SET

            ; write to RTC
            CALL    RTC_WRITE_FROM_SET

            LXI     H,STR_SET_DONE
            CALL    PUTS
            CALL    GETCH
            RET

;===============================================================================
;  RTC READ/WRITE
;===============================================================================

; Stable read: retry if seconds changed during read.
RTC_READ_STABLE:
RR1:        LDA     RTC_SEC
            ANI     7FH
            STA     BCD_SEC

            LDA     RTC_MIN
            ANI     7FH
            STA     BCD_MIN

            LDA     RTC_HOUR
            ANI     3FH
            STA     BCD_HOUR

            LDA     RTC_DATE
            ANI     3FH
            STA     BCD_DATE

            LDA     RTC_MON
            ANI     1FH
            STA     BCD_MON

            LDA     RTC_YEAR
            STA     BCD_YEAR

            LDA     RTC_SEC
            ANI     7FH
            MOV     B,A
            LDA     BCD_SEC
            CMP     B
            JNZ     RR1
            RET

COMPUTE_BIN_FROM_BCD:
            LDA     BCD_SEC
            CALL    BCD2BIN
            STA     BIN_SEC

            LDA     BCD_MIN
            CALL    BCD2BIN
            STA     BIN_MIN

            LDA     BCD_HOUR
            CALL    BCD2BIN
            STA     BIN_HOUR
            RET

RTC_WRITE_FROM_SET:
            ; enable write mode
            MVI     A,CTRL_W
            STA     RTC_CTRL

            ; seconds (ensure STOP bit cleared)
            LDA     BCD_SEC_SET
            ANI     7FH
            STA     RTC_SEC

            LDA     BCD_MIN_SET
            ANI     7FH
            STA     RTC_MIN

            LDA     BCD_HOUR_SET
            ANI     3FH
            STA     RTC_HOUR

            ; DOW low bits only
            LDA     DOW_SET
            ANI     07H
            STA     RTC_DOW

            LDA     BCD_DATE_SET
            ANI     3FH
            STA     RTC_DATE

            LDA     BCD_MON_SET
            ANI     1FH
            STA     RTC_MON

            LDA     BCD_YEAR_SET
            STA     RTC_YEAR

            ; exit write mode
            XRA     A
            STA     RTC_CTRL
            RET

;===============================================================================
;  7-SEG HARDWARE DISPLAY (HEX HH MM SS)
;===============================================================================

SEG_CLEAR:
            MVI     E,0
            MVI     D,0
            CALL    SEG_ONE
            MVI     D,1
            CALL    SEG_ONE
            MVI     D,2
            CALL    SEG_ONE
            MVI     D,3
            CALL    SEG_ONE
            MVI     D,4
            CALL    SEG_ONE
            MVI     D,5
            CALL    SEG_ONE
            RET

SEG_SHOW_HEX_HHMMSS:
            ; Hour -> digits 5,4
            LDA     BIN_HOUR
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     E,A
            MVI     D,5
            CALL    SEG_ONE

            MOV     A,B
            ANI     0FH
            MOV     E,A
            MVI     D,4
            CALL    SEG_ONE

            ; Min -> digits 3,2
            LDA     BIN_MIN
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     E,A
            MVI     D,3
            CALL    SEG_ONE

            MOV     A,B
            ANI     0FH
            MOV     E,A
            MVI     D,2
            CALL    SEG_ONE

            ; Sec -> digits 1,0
            LDA     BIN_SEC
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     E,A
            MVI     D,1
            CALL    SEG_ONE

            MOV     A,B
            ANI     0FH
            MOV     E,A
            MVI     D,0
            CALL    SEG_ONE
            RET



; Show either HEX bytes (default) or DEC HHMMSS depending on SEG_MODE
SEG_SHOW_MODED:
            LDA     SEG_MODE
            ORA     A
            JZ      SSM_HEX
            JMP     SEG_SHOW_DEC_HHMMSS
SSM_HEX:    JMP     SEG_SHOW_HEX_HHMMSS

; DEC mode: show HHMMSS as decimal digits (6 digits)
; Uses BCD_HOUR / BCD_MIN / BCD_SEC (BCD values 00-59 / 00-23).
SEG_SHOW_DEC_HHMMSS:
            ; Hours
            LDA     BCD_HOUR
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     E,A
            MVI     D,5
            CALL    SEG_ONE
            MOV     A,B
            ANI     0FH
            MOV     E,A
            MVI     D,4
            CALL    SEG_ONE

            ; Minutes
            LDA     BCD_MIN
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     E,A
            MVI     D,3
            CALL    SEG_ONE
            MOV     A,B
            ANI     0FH
            MOV     E,A
            MVI     D,2
            CALL    SEG_ONE

            ; Seconds
            LDA     BCD_SEC
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     E,A
            MVI     D,1
            CALL    SEG_ONE
            MOV     A,B
            ANI     0FH
            MOV     E,A
            MVI     D,0
            CALL    SEG_ONE
            RET

;===============================================================================
;  8 LEDs: show seconds in DEC (BCD) as an 8-bit value (active-low LEDs)
;  - Upper nibble = tens, lower nibble = ones (00..59)
;===============================================================================
LED_SHOW_SEC:
            LDA     BCD_SEC        ; already masked to 7Fh in RTC_READ_STABLE
            CMA                     ; LEDs are active-low: 0=ON, 1=OFF
            OUT     PPI_PB
            RET

SEG_ONE:
            PUSH    PSW
            PUSH    B
            PUSH    H
            MVI     C,SVC_DIGOUT
            CALL    MOS
            POP     H
            POP     B
            POP     PSW
            RET

;===============================================================================
;  UART / ANSI TERMINAL
;===============================================================================

TERM_CLEAR:
            LXI     H,STR_CLR
            CALL    PUTS
            RET

TERM_GREEN:
            LXI     H,STR_GREEN
            CALL    PUTS
            RET

TERM_WHITE:
            LXI     H,STR_WHITE
            CALL    PUTS
            RET

TERM_HIDE_CURSOR:
            LXI     H,STR_HIDE_CURSOR
            CALL    PUTS
            RET

TERM_SHOW_CURSOR:
            LXI     H,STR_SHOW_CURSOR
            CALL    PUTS
            RET

ANSI_GOTO_BC:
            PUSH    PSW
            PUSH    B
            PUSH    D
            PUSH    H

            ; ESC [
            MVI     A,1BH
            CALL    PUTCH
            MVI     A,'['
            CALL    PUTCH

            ; row (B)
            MOV     A,B
            CALL    PRT_DEC_NOLZ
            MVI     A,';'
            CALL    PUTCH

            ; col (C)
            MOV     A,C
            CALL    PRT_DEC_NOLZ

            MVI     A,'H'
            CALL    PUTCH

            POP     H
            POP     D
            POP     B
            POP     PSW
            RET

KEY_POLL:
            IN      UART_STAT
            ANI     ST_RXRDY
            JZ      KP_NONE
            IN      UART_DATA
            ANI     0DFH            ; uppercase
            RET
KP_NONE:    XRA     A
            RET

GETCH:
            IN      UART_STAT
            ANI     ST_RXRDY
            JZ      GETCH
            IN      UART_DATA
            RET

PUTCH:
            PUSH    PSW
PT1:        IN      UART_STAT
            ANI     ST_TXRDY
            JZ      PT1
            POP     PSW
            OUT     UART_DATA
            RET

PUTS:
            MOV     A,M
            ORA     A
            RZ
            CALL    PUTCH
            INX     H
            JMP     PUTS

READ_DEC:
            MVI     B,0
RD1:        CALL    GETCH
            CPI     0DH
            JZ      RD_DONE
            CPI     0AH
            JZ      RD1

            CPI     '0'
            JC      RD1
            CPI     '9'+1
            JNC     RD1

            CALL    PUTCH          ; echo
            SUI     '0'
            MOV     E,A

            ; B = B*10 + E
            MOV     A,B
            ADD     A
            MOV     D,A            ;*2
            MOV     A,B
            ADD     A
            ADD     A
            ADD     A              ;*8
            ADD     D              ;*10
            ADD     E
            MOV     B,A
            JMP     RD1

RD_DONE:    MVI     A,0DH
            CALL    PUTCH
            MVI     A,0AH
            CALL    PUTCH
            MOV     A,B
            RET

;===============================================================================
;  FORMATTING / CONVERSIONS
;===============================================================================

PRT_BCD2:
            PUSH    PSW
            PUSH    B

            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            ADI     '0'
            CALL    PUTCH

            MOV     A,B
            ANI     0FH
            ADI     '0'
            CALL    PUTCH

            POP     B
            POP     PSW
            RET

PRT_HEX8:
            PUSH    PSW
            PUSH    B
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            CALL    NIB_TO_HEX
            CALL    PUTCH

            MOV     A,B
            ANI     0FH
            CALL    NIB_TO_HEX
            CALL    PUTCH
            POP     B
            POP     PSW
            RET

NIB_TO_HEX:
            CPI     10
            JC      NTH_DEC
            ADI     ('A' - 10)
            RET
NTH_DEC:    ADI     '0'
            RET

PRT_DEC_NOLZ:
            PUSH    PSW
            PUSH    B
            PUSH    D

            MOV     D,A

            MVI     B,0
PDH1:       MOV     A,D
            CPI     100
            JC      PDH2
            SUI     100
            MOV     D,A
            INR     B
            JMP     PDH1
PDH2:       MVI     C,0
PDT1:       MOV     A,D
            CPI     10
            JC      PDT2
            SUI     10
            MOV     D,A
            INR     C
            JMP     PDT1
PDT2:
            MOV     A,B
            ORA     A
            JZ      PDX_TENS
            ADI     '0'
            CALL    PUTCH
            MOV     A,C
            ADI     '0'
            CALL    PUTCH
            JMP     PDX_ONES

PDX_TENS:   MOV     A,C
            ORA     A
            JZ      PDX_ONES0
            ADI     '0'
            CALL    PUTCH
            JMP     PDX_ONES

PDX_ONES0:  MOV     A,D
            ORA     A
            JNZ     PDX_ONES
            MVI     A,'0'
            CALL    PUTCH
            JMP     PDX_DONE

PDX_ONES:   MOV     A,D
            ADI     '0'
            CALL    PUTCH

PDX_DONE:   POP     D
            POP     B
            POP     PSW
            RET

; Split BCD in A into:
;   A = tens digit (0..9)
;   B = ones digit (0..9)
SPLIT_BCD:
            MOV     B,A
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     C,A            ; tens
            MOV     A,B
            ANI     0FH
            MOV     B,A            ; ones
            MOV     A,C            ; return tens in A
            RET

BIN2BCD:
            PUSH    B
            MOV     B,A
            MVI     C,0
B2B1:       MOV     A,B
            CPI     10
            JC      B2B2
            SUI     10
            MOV     B,A
            INR     C
            JMP     B2B1
B2B2:       MOV     A,C
            RLC
            RLC
            RLC
            RLC
            ORA     B
            POP     B
            RET

BCD2BIN:
            PUSH    B
            PUSH    D

            MOV     B,A
            ANI     0FH
            MOV     E,A            ; ones
            MOV     A,B
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            MOV     D,A            ; tens

            MOV     A,D
            ADD     A
            MOV     C,A            ; *2
            MOV     A,D
            ADD     A
            ADD     A
            ADD     A              ; *8
            ADD     C              ; *10
            ADD     E
            POP     D
            POP     B
            RET

;===============================================================================
;  BIG FONT TABLE (10 digits * 3 rows, 3 chars each)  = 90 bytes
;===============================================================================

            END
