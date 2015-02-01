/* picoBootSTK500 - arduino compatible bootloader
 *
 * TTL serial version - 81N, 115.2kbps
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * https://code.google.com/p/optiboot/
 * https://github.com/whitequark/vuxboot
 * 
 * This bootloader is an implementation of the Arduino bootloader,
 * a stripped-down STK500 protocol, in assembler.
 * Optiboot is the primary guide for this bootloader 
 * protocol trace from Bald Wisdom blog
 * http://baldwisdom.com/bootloading/ 
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#ifdef DEBUG
/* for simulavr debugging */
#   define debug_output_port 0x31
#   define debug_input_port 0x32
#endif

#define LEDPIN 5
#define LEDPORT PORTB

/* following defines are missing in avr-libc
 * see bug #42957  
 */
#ifndef SPMEN
#define SPMEN 0
#endif
#ifndef SIGRD
#define SIGRD 5
#endif

#include "stk500.h"

#define rCOMMAND r16
#define rTEMP r17
#define PgLen r18
#define MemType r19

/* defintions for soft UART */
#ifdef PORTD
#define UART_Port PORTD
#else
#define UART_Port PORTB
#endif
#define UART_Tx 1
#define UART_Rx 0
#define BAUD_RATE 115200

.section .bootloader,"ax",@progbits
; use -WL,--section-start=.bootloader=0xXf00

Boot:
    in rTEMP, MCUSR
	cpi rTEMP, (1<<EXTRF|1<<PORF)   ; run bootloader on external reset
    breq CommandLoop
    sbr rTEMP, PORF
    out MCUSR, rTEMP                ; ensure PORF set in case of dbl reset
	rjmp StartApp                   ; jump to application code

BootLoader:
    cbr rTEMP, PORF
    out MCUSR, rTEMP                ; clear PORF to show bootloader run 
    sbi LEDPORT, LEDPIN             ; light LED dimly during bootloader
CommandLoop:
    rcall RxPacket
	ldi r26, STK_INSYNC 
	rcall TxByte
    ld rCOMMAND, Y+
	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne Universal
    ld ZL, Y+
    ld ZH, Y+                       ; Z stores address for page load
    lsl ZL
    rol ZH                          ; convert from word to byte address

Universal:
	cpi rCOMMAND, STK_UNIVERSAL
	brne GetParam
    ; command ignored - return dummy 0x00
    clr r26
    rcall TxByte

GetParam:
	cpi rCOMMAND, STK_GET_PARAMETER
	brne ProgPage
    ; return 0x03 for all parameters - Optiboot comments say
    ; its enough to keep Avrdude happy
    ; also means 03 is reply to major and minor version
    ; looking at the Avrdude stk500 code I think it may be safe to return
    ; 0x00 and comine this response with the STK_UNIVERSAL response
    ; to save 2 instructions
    ldi r26, 0x03
    rcall TxByte

ProgPage:
    ; predictive load of PgLen for PROG_PAGE or READ_PAGE 
    ldd PgLen, Y+                   ; ignore Pg len Hi
    ldd PgLen, Y+
    ldd MemType, Y+

	cpi rCOMMAND, STK_PROG_PAGE
	brne ReadPage
    cpi MemType, 'F'
    brne ProgEEProm
PageFill:
    ld r0, Y+                       ; word low byte 
    ld r1, Y+                       ; word high byte 
    ldi rTEMP, (1<<SPMEN)           ; fill page buffer
	rcall DoSPM
	adiw ZL, 2                      ; increment Z pointer
	subi PgLen, 2
	brne PageFill
	subi ZL, SPM_PAGESIZE           ; reverse page pointer
    sbci ZH, 0
    ldi rTEMP, (1<<PGERS)|(1<<SPMEN)    ;erase page
	rcall DoSPM
    ldi rTEMP, (1<<PGWRT)|(1<<SPMEN)    ;write page
	rcall DoSPM
ProgEEProm:
    cpi MemType, 'E'
    brne Default                    ; ignore other MemType
WriteEE:
    rcall SetupEE
    ld r0, Y+
    out EEDR, r0 
    sbi EECR, EEMPE
    sbi EECR, EEPE                  ; write data to EEProm
	dec PgLen
	brne WriteEE

ReadPage:
	cpi rCOMMAND, STK_READ_PAGE
	brne ReadSig
    cpi MemType, 'F'
    brne ReadEEProm
ReadFlashByte:
	lpm r26, Z+
	rcall TxByte
	dec PgLen
	brne ReadFlashByte
ReadEEProm:
    rcall SetupEE
    sbi EECR, EERE
    in r26, EEDR
    rcall TxByte
	dec PgLen
	brne ReadEEProm

ReadSig:
	cpi rCOMMAND, STK_READ_SIGN
	brne Quit
    clr ZL
    clr ZH
    ldi rTEMP, (1<<SIGRD)|(1<<SPMEN)
SigLoop:
    out SPMCSR, rTEMP
    lpm r26, Z
	rcall TxByte                    ; send sig byte
    adiw ZL, 2
    cpi ZL, 6                       ; 3 signature bytes
    brne SigLoop

Quit:
	cpi rCOMMAND, STK_LEAVE_PROGMODE
	breq StartApp

Default:
    ; reply OK
	ldi r26, STK_OK
	rcall TxByte
    rjmp CommandLoop


DoSPM:
  out SPMCSR, rTEMP
  spm
  ret

SetupEE:
    sbic EECR, EEPE                 ; wait for previous IO to finish
    rjmp SetupEE
    out EEARL, ZL
    out EEARH, ZH
	adiw ZL, 1                      ; increment Z pointer
    ret

RxPacket:
    rcall ResetPacketPtr
NextByte:
    rcall RxByte
    st Y+, r24
    cpi r24, CRC_EOP
    brne NextByte
ResetPacketPtr:
    ; inialize packet buffer pointer
    ldi YL, lo8(RAMSTART)
    ldi YH, hi8(RAMSTART)
    ret

/* soft UART code */
#define DIVIDE_ROUNDED(NUMERATOR, DIVISOR) ((((2*(NUMERATOR))/(DIVISOR))+1)/2)

; txbit takes 3*RXDELAY + 14 cycles
#define delayArg r22
#define BIT_CYCLES DIVIDE_ROUNDED(F_CPU,BAUD_RATE) 
#define TXDELAY DIVIDE_ROUNDED(BIT_CYCLES - 14, 3)

; rxbit takes 3*RXDELAY + 12 cycles
#define RXSTART_CYCLES DIVIDE_ROUNDED(3*F_CPU,2*BAUD_RATE) 
#define RXSTART DIVIDE_ROUNDED(RXSTART_CYCLES - 12, 3)
#define RXDELAY DIVIDE_ROUNDED(BIT_CYCLES - 12, 3)

; transmit byte contained in r26 - 12 instructions
TxByte:
#ifdef DEBUG
    out debug_output_port, r26
    ret    
#endif
	sbi UART_Port-1, UART_Tx		; set Tx line to output
	cbi UART_Port, UART_Tx			; start bit
	in r0, UART_Port
	ldi r27, 7						; stop bit & idle state
TxLoop:
	; 8 cycle loop + delay
	ldi delayArg, TXDELAY
	rcall Delay3Cycle				; delay + 3 cycles for rcall
	bst r26, 0						; store lsb in T
	bld r0, UART_Tx
	lsr r27
	ror r26							; 2-byte shift register
	out UART_Port, r0
	brne TxLoop
	ret

; receive byte into r24 - 11 instructions
RxByte:
#ifdef DEBUG
    in r24, debug_input_port
    ret    
#endif
	ldi r24, 0x80               ; bit shift counter
	ldi delayArg, RXSTART       ; 1.5 bit delay
WaitStart:
	sbic UART_Port-2, UART_Rx		; wait for start edge
	rjmp WaitStart
RxBit:
	rcall Delay3Cycle           ; delay and clear carry
	; 6 cycle loop
	ldi delayArg, RXDELAY 
	ror r24
	sbic UART_Port-2, UART_Rx
	ori r24, 0x80
	brcc RxBit
	; fall into delay for stop bit

; delay (3 cycle * delayArg) -1 + 4 cycles (ret instruction)
Delay3Cycle:
	dec delayArg
	brne Delay3Cycle
	ret

; set registers to reset state then start app
StartApp:
    cbi UART_Port-1, UART_Tx
    cbi UART_Port, UART_Tx
    sbi LEDPORT, LEDPIN             ; turn off LED
; slide into reset vector at address 0x0000
