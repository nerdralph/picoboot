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
	rcall RxByte					; read command
	mov rCOMMAND, r24
	rcall RxByte          ; get next byte
	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne Universal
	mov ZH, r24
	rcall RxByte
	mov ZL, r24					; Z stores address for page load
  lsl ZL
  rol ZH              ; convert from word to byte address
Universal:
	cpi rCOMMAND, STK_UNIVERSAL
	brne ProgPage
  rcall ReadEOP
  ; 0x00 dummy reply
	rjmp TxOK
ProgPage:
	cpi rCOMMAND, STK_PROG_PAGE
	brne ReadPage
	rcall GetPageParams
PageFill:
	mov r1, r24
	rcall RxByte
	mov r0, r24
	rcall DoSPM
	adiw ZL, 2						          ; increment Z pointer
	subi rTEMP, 2
	brne PageFill
	subi ZL, SPM_PAGESIZE			      ; reverse page pointer
  sbci ZH, 0
  ldi rTEMP, (1<<PGERS)|(0x01)    ;erase page
	rcall DoSPM
  ldi rTEMP, (1<<PGWRT)|(0x01)    ;write page
	rcall DoSPM
ReadPage:
	cpi rCOMMAND, STK_READ_PAGE
	brne ReadSig
	rcall GetPageParams
  rcall ReadEOP
ReadByte:
	lpm r26, Z+
	rcall TxByte
	dec rTEMP
	brne ReadByte
  rjmp DoneCMD
ReadSig:
	cpi rCOMMAND, STK_READ_SIGN
	brne GetParam
  rcall ReadEOP
  ldi r26, SIGNATURE_0
	rcall TxByte
  ldi r26, SIGNATURE_1
	rcall TxByte
  ldi r26, SIGNATURE_2
	rjmp TxOK
GetParam:
	cpi rCOMMAND, STK_GET_PARAMETER
	brne Quit
  rcall ReadEOP                   ; ignore parameter
  ; 0x00 dummy reply
	rjmp TxOK
Quit:
	cpi rCOMMAND, STK_LEAVE_PROGMODE
	breq StartApp
Default:
  rcall ReadEOP
  rjmp DoneCMD
TxOK:
; transmit reply byte + OK
  rcall TxByte
DoneCMD:
; reply OK
	ldi r26, STK_OK
	rcall TxByte
  rjmp CommandLoop

; read to EOP and respond with INSYNC 
NextByte:
  rcall RxByte
ReadEOP:
  cpi r24, CRC_EOP
  brne RxByte
	ldi r26, STK_INSYNC 
	rcall TxByte
  ret

; get length and flash type for write or read page
; length stored in rTemp
GetPageParams:
	; ignore block size hi byte already read
	rcall RxByte
	mov rTEMP, r24				; block size
	rcall RxByte					; ignore memory type - only flash support
  ret

DoSPM:
  out SPMCSR, rTEMP
  spm
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
