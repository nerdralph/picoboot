/* picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
 * TTL serial version - 81N, 115.2kbps @8Mhz
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * AVR305 half-duplex serial uart
 * https://code.google.com/p/optiboot/
 * 
 * This bootloader is an implementation of the Arduino bootloader,
 * a stripped-down STK500 protocol, in assembler.
 * Optiboot is the primary guide for this bootloader 
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#include "stk500.h"

#define rCOMMAND r16
#define rTEMP r18

.section .bootloader,"ax",@progbits
; use -WL,--section-start=.bootloader=0xXf00

rjmp Boot

/* TxByte(r24) and r24 RxByte */
#include "BBUart.S"

Boot:
	sbis UART_Port, UART_Rx 		; run bootloader if serial connected
	rjmp StartApp					; jump to application code
  ; check MCUSR for EXTRF too?

; Z pointer starts at program address 0
CommandLoop:
	rcall RxByte					; read command
	mov rCOMMAND, r24
	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne ProgPage
	rcall RxByte
	mov ZH, r24
	rcall RxByte
	mov ZL, r24					; Z stores address for page load
ProgPage:
	cpi rCOMMAND, STK_PROG_PAGE
	brne ReadPage
	rcall GetPageParams
PageFill:
	rcall RxByte
	mov r1, r24
	rcall RxByte
	mov r0, r24
	rcall DoSPM
	adiw ZL, 2						; increment Z pointer
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
ReadByte:
	lpm r24, Z+
	rcall TxByte
	dec rTEMP
	brne ReadPage
ReadSig:
	cpi rCOMMAND, STK_READ_SIGN
	brne GetParam
  ldi r24, SIGNATURE_0
	rcall TxByte
  ldi r24, SIGNATURE_1
	rcall TxByte
  ldi r24, SIGNATURE_2
	rcall TxByte
GetParam:
	cpi rCOMMAND, STK_GET_PARAMETER
	brne Quit
  rcall RxByte                    ; ignore parameter
  ldi r24, 0x03                   ; generic 0x03 reply
	rcall TxByte
Quit:
	cpi rCOMMAND, STK_LEAVE_PROGMODE
	breq StartApp
Default:
; read to EOP and respond with INSYNC
	rcall RxByte
  cpi r24, CRC_OK
  brne Default
	ldi r24, STK_INSYNC 
	rcall TxByte
	ldi r24, STK_OK
	rcall TxByte
  rjmp CommandLoop

; get length and flash type for write or read page
; length stored in rTemp
GetPageParams:
	rcall RxByte					; ignore block size hi byte
	rcall RxByte
	mov rTEMP, r24				; block size
	rcall RxByte					; ignore memory type - only flash support
  ret

DoSPM:
  out SPMCSR, rTEMP
  spm
  ret

; set registers to reset state then start app
StartApp:
  ldi rTEMP, 0
  out UART_Port-1, rTEMP
  out UART_Port, rTEMP
; slide into reset vector at address 0x0000
