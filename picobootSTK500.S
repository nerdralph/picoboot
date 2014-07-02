/* picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
 * TTL serial version - 81N, 115.2kbps @8Mhz
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

#include "stk500.h"

#define rCOMMAND r16
#define rTEMP r18
#define PgLen r18
/* defintions for soft UART */
#define UART_Port PORTB
#define UART_Tx PINB0
#define UART_Rx PINB1
#define BAUD_RATE 115200
#define F_CPU 8000000

.section .bootloader,"ax",@progbits
; use -WL,--section-start=.bootloader=0xXf00

Boot:
	sbis UART_Port, UART_Rx 		; run bootloader if serial connected
	rjmp StartApp					; jump to application code
  ; check MCUSR for EXTRF too?

CommandLoop:
    rcall RxPacket
    ld rCOMMAND, Y+
	ldi r26, STK_INSYNC 
	rcall TxByte
	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne Universal
    ld ZH, Y+
    ld ZL, Y+                       ; Z stores address for page load
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
	cpi rCOMMAND, STK_PROG_PAGE
	brne ReadPage
    ldd PgLen, Y+1                  ; ignore Pg len Hi
    ; skip block size & type - 3 bytes
    adiw YL, 3
PageFill:
    ld r1, Y+                       ; word high byte 
    ld r0, Y+                       ; word low byte 
    ldi rTEMP, (0x01)               ; fill page buffer
	rcall DoSPM
	adiw ZL, 2                      ; increment Z pointer
	subi PgLen, 2
	brne PageFill
	subi ZL, SPM_PAGESIZE           ; reverse page pointer
    sbci ZH, 0
    ldi rTEMP, (1<<PGERS)|(0x01)    ;erase page
	rcall DoSPM
    ldi rTEMP, (1<<PGWRT)|(0x01)    ;write page
	rcall DoSPM
ReadPage:
	cpi rCOMMAND, STK_READ_PAGE
	brne ReadSig
    ldd PgLen, Y+1                  ; ignore Pg len Hi
ReadByte:
	lpm r26, Z+
	rcall TxByte
	dec PgLen
	brne ReadByte
ReadSig:
	cpi rCOMMAND, STK_READ_SIGN
	brne Quit
    ldi r26, SIGNATURE_0
	rcall TxByte
    ldi r26, SIGNATURE_1
	rcall TxByte
    ldi r26, SIGNATURE_2
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
;define TXDELAY 18
#define BIT_CYCLES DIVIDE_ROUNDED(F_CPU,BAUD_RATE) 
#define TXDELAY DIVIDE_ROUNDED(BIT_CYCLES - 14, 3)

; rxbit takes 3*RXDELAY + 12 cycles
#define RXSTART_CYCLES DIVIDE_ROUNDED(3*F_CPU,2*BAUD_RATE) 
#define RXSTART DIVIDE_ROUNDED(RXSTART_CYCLES - 12, 3)
#define RXDELAY DIVIDE_ROUNDED(BIT_CYCLES - 12, 3)

; transmit byte contained in r26 - 12 instructions
TxByte:
	sbi UART_Port-1, UART_Tx		; set Tx line to output
	cbi UART_Port, UART_Tx			; start bit
	in r0, UART_Port
	ldi r27, 3						; stop bit & idle state
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
; slide into reset vector at address 0x0000
