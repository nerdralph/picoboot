/* picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
 * TTL serial version - 81N, 115.2kbps @8Mhz
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * http://symlink.dk/electro/m163boot/
 * http://github.com/baerwolf/USBaspLoader
 * AVR305 half-duplex serial uart
 * https://code.google.com/p/optiboot/
 * 
 * This bootloader is an implementation of the Arduino bootloader,
 * a stripped-down STK500 protocol, in assembler.
 * Optiboot is the primary guide for this bootloader 
 *** this is pre-alpha non-functioning code ***
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#include "stk500.h"

#define rCOMMAND r16
#define rTEMP r18

/* code size in bytes rounded up to page size */
#define CODESIZE 256

.section .vectors
.org 0x0000
IntVectors:
	rjmp BootInit 

.text
; .org _VECTORS_SIZE
;.org (FLASHEND - SPM_PAGESIZE - 1)
; use -WL,--section-start=.text=0x1f00 for t85
AppStart:
	rjmp 0							; dummy vector to be overwritten
; beginning of last page of memory
; include virtual boot vector code
#include "tinyBoot.S" 

/* TxByte(r24) and r24 RxByte */
#include "BBUart.S"

Boot:
	sbis UART_Port, UART_Rx 		; run bootloader if serial connected
	rjmp StartApp					; jump to application code

; Z pointer starts at program address 0
CommandLoop:
	rcall RxByte					; read command
	mov rCOMMAND, r24
	cpi rCOMMAND, 0x0d				; CR = start app
	breq AppStart
	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne CheckProgPage
	rcall RxByte
	mov ZH, r24
	rcall RxByte
	mov ZL, r24					; Z stores address for page load
	rcall HandleEOP
CheckProgPage:
	cpi rCOMMAND, STK_PROG_PAGE
	brne CheckRead
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
CheckRead:
	cpi rCOMMAND, STK_READ_PAGE
	brne Default
	rcall GetPageParams
ReadPage:
	; check if this is a read of the reset vector
	tst ZH
	brne ReadByte
	cpi ZL, 1
	brne CheckAddr0
	ldi ZL, lo8(FLASHEND - CODESIZE)
	ldi ZH, hi8(FLASHEND - CODESIZE)
CheckAddr0:
	brcc ReadByte
	dec ZL
ReadByte:
	lpm r24, Z+
	rcall TxByte
	dec rTEMP
	brne ReadPage
Default:
	ldi r24, STK_OK 
	rcall TxByte
    rjmp CommandLoop

; get length and flash type for write or read page
; length stored in rTemp
; fall into HandleEOP
GetPageParams:
	rcall RxByte					; ignore block size hi byte
	rcall RxByte
	mov rTEMP, r24				; block size
	rcall RxByte					; ignore memory type - only flash support

; read EOP and respond with INSYNC
HandleEOP:
	rcall RxByte					; read EOP
	ldi r24, STK_INSYNC 
	rcall TxByte
	ret

