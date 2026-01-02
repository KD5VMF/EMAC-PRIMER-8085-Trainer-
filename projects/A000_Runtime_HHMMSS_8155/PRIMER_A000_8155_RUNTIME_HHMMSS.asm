;===============================================================================
;  PRIMER_A000_8155_RUNTIME_HHMMSS.asm
;
;  EMAC PRIMER (8085) - Runtime HHMMSS counter on the 6-digit 7-seg display.
;  Uses the on-board Intel 8155 timer/counter (NOT the RTC).
;
;  HOW IT WORKS
;    - PRIMER's 8155 timer/counter can generate an interrupt on RST 7.5. 
;    - The 8155 hardware cannot directly make a 1-second period (its max interval
;      is ~53.3 ms), so we configure it for 100 Hz and divide by 100 in software.
;
;  LOAD/RUN
;    - Load this hex at A000h and run:  G A000
;
;  Notes
;    - We only touch the timer registers and timer command value used in the
;      PRIMER app manuals, to avoid disturbing MOS standard 8155 setup.
;===============================================================================

            ORG     0A000H

; -------------------- Constants --------------------

MOS_ENTRY    EQU     01000H         ; MOS service entry point (CALL 1000h)

; MOS services (from PRIMER MOS services listing)
SVC_DIGOUT   EQU     017H           ; 7-seg digit output
SVC_DECPNT   EQU     021H           ; decimal point control

; 8155 I/O port map used by PRIMER examples
P_8155_CMD   EQU     010H           ; 8155 command/control port
P_CNTLO      EQU     014H           ; timer/counter low byte
P_CNTHI      EQU     015H           ; timer/counter high byte (upper count + mode)

; Monitor/MOS vector for RST7.5 handler (used by PRIMER examples)
VEC7HLF      EQU     0FFE9H         ; holds address of RST7.5 ISR

; Timer setup for 100 Hz square-wave (PRIMER example values)
TMR_LO_100HZ EQU     000H
TMR_HI_100HZ EQU     04CH           ; mode=1 (square wave) + upper bits of 0C00h
TMR_CMD_GO   EQU     0CDH

; SIM masks: enable only RST7.5 (mask 5.5 & 6.5), reset RST7.5 FF, enable masks
SIM_EN_75    EQU     01BH           ; 00011011b
SIM_CLR_75   EQU     010H           ; 00010000b (reset RST7.5 FF only)

; -------------------- Entry --------------------

START:      DI
            LXI     SP,STACKTOP

            ; Clear runtime counters
            XRA     A
            STA     TICKS
            STA     SECS
            STA     MINS
            STA     HOURS
            STA     FLAGS

            ; Turn ALL decimal points OFF (bitmask=0)
            MVI     C,SVC_DECPNT
            MVI     D,00H
            CALL    MOS_ENTRY

            ; Display initial 00:00:00
            CALL    DISP_TIME

            ; Install RST7.5 interrupt handler via VEC7HLF vector
            LXI     H,ISR_75
            SHLD    VEC7HLF

            ; Configure 8155 timer for 100 Hz and start it
            MVI     A,TMR_LO_100HZ
            OUT     P_CNTLO
            MVI     A,TMR_HI_100HZ
            OUT     P_CNTHI
            MVI     A,TMR_CMD_GO
            OUT     P_8155_CMD

            ; Enable only RST7.5 interrupts and clear any pending 7.5
            MVI     A,SIM_EN_75
            SIM
            EI

MAIN:       ; Wait for "one second elapsed" flag set by ISR
            LDA     FLAGS
            ANI     01H
            JZ      MAIN

            ; Clear flag
            LDA     FLAGS
            ANI     0FEH
            STA     FLAGS

            ; Update display (safe to do outside ISR)
            CALL    DISP_TIME
            JMP     MAIN

;===============================================================================
;  RST 7.5 Interrupt Service Routine (called at 100 Hz)
;    - Counts 100 ticks -> 1 second
;    - Increments HH:MM:SS runtime (wraps at 24:00:00)
;===============================================================================

ISR_75:     PUSH    PSW
            PUSH    B
            PUSH    D
            PUSH    H

            ; Clear the RST7.5 flip-flop so interrupts keep coming
            MVI     A,SIM_CLR_75
            SIM

            ; ticks++
            LDA     TICKS
            INR     A
            CPI     064H             ; 100 decimal
            JC      ISR_SAVE_TICKS

            ; reached 100 -> reset ticks and advance time by 1 second
            XRA     A
            STA     TICKS

            ; SECS++
            LDA     SECS
            INR     A
            CPI     03CH             ; 60
            JC      ISR_STORE_SECS
            XRA     A
            STA     SECS

            ; MINS++
            LDA     MINS
            INR     A
            CPI     03CH             ; 60
            JC      ISR_STORE_MINS
            XRA     A
            STA     MINS

            ; HOURS++
            LDA     HOURS
            INR     A
            CPI     018H             ; 24
            JC      ISR_STORE_HOURS
            XRA     A
            STA     HOURS
            JMP     ISR_SET_FLAG

ISR_STORE_HOURS:
            STA     HOURS
            JMP     ISR_SET_FLAG

ISR_STORE_MINS:
            STA     MINS
            JMP     ISR_SET_FLAG

ISR_STORE_SECS:
            STA     SECS

ISR_SET_FLAG:
            ; set FLAGS bit0 = 1
            LDA     FLAGS
            ORI     01H
            STA     FLAGS
            JMP     ISR_DONE

ISR_SAVE_TICKS:
            STA     TICKS

ISR_DONE:   POP     H
            POP     D
            POP     B
            POP     PSW
            EI
            RET

;===============================================================================
;  DISP_TIME
;    Writes HHMMSS to 6-digit 7-seg via MOS SVC_DIGOUT.
;    Digit positions:
;      D=5 leftmost ... D=0 rightmost
;      [5]=H tens, [4]=H ones, [3]=M tens, [2]=M ones, [1]=S tens, [0]=S ones
;===============================================================================

DISP_TIME:
            ; --- Hours (pos 5,4) ---
            LDA     HOURS
            CALL    TO_TENS_ONES     ; B=tens, A=ones
            MOV     A,B
            MVI     D,05H
            CALL    PUTDIG
            LDA     LAST_ONES
            MVI     D,04H
            CALL    PUTDIG

            ; --- Minutes (pos 3,2) ---
            LDA     MINS
            CALL    TO_TENS_ONES
            MOV     A,B
            MVI     D,03H
            CALL    PUTDIG
            LDA     LAST_ONES
            MVI     D,02H
            CALL    PUTDIG

            ; --- Seconds (pos 1,0) ---
            LDA     SECS
            CALL    TO_TENS_ONES
            MOV     A,B
            MVI     D,01H
            CALL    PUTDIG
            LDA     LAST_ONES
            MVI     D,00H
            CALL    PUTDIG

            RET

;===============================================================================
;  PUTDIG
;    IN:  A = digit (0..9)
;         D = position (0..5)
;===============================================================================

PUTDIG:     MOV     E,A
            MVI     C,SVC_DIGOUT
            CALL    MOS_ENTRY
            RET

;===============================================================================
;  TO_TENS_ONES
;    IN:  A = value (0..99)
;    OUT: B = tens (0..9)
;         LAST_ONES memory = ones digit (0..9)
;         A is clobbered
;===============================================================================

TO_TENS_ONES:
            MVI     B,00H
TTLOOP:     CPI     00AH
            JC      TTDONE
            SUI     00AH
            INR     B
            JMP     TTLOOP
TTDONE:     STA     LAST_ONES
            RET

; -------------------- Variables --------------------

TICKS:      DB      00H             ; 0..99 (100 Hz ticks)
SECS:       DB      00H             ; 0..59
MINS:       DB      00H             ; 0..59
HOURS:      DB      00H             ; 0..23
FLAGS:      DB      00H             ; bit0 = 1 when a second elapsed
LAST_ONES:  DB      00H             ; helper storage for ones digit

; -------------------- Stack --------------------
            ; Keep stack above our variables and code area in A000 page.
STACKTOP    EQU     0A2FFH
