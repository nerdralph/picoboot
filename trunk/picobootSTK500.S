/* picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
 * TTL serial version - 81N, 115.2kbps @8Mhz
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * http://symlink.dk/electro/m163boot/
 * http://github.com/baerwolf/USBaspLoader
 * AVR305 half-duplex serial uart
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#include "stk500.h"

#define BOOTPIN	PINB0
#define UART_Port PORTB
#define UART_Tx PINB1
#define UART_Rx PINB2

#define rCOMMAND r16
#define rTEMP r18

/* defines for AVR305.S */
#define rSOURCE r25
#define rDEST r25

#define LOWBYTE(word) (word & 0xff)

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

; .org _VECTORS_SIZE
.org (FLASHEND - SPM_PAGESIZE - 1)
AppStart:
	rjmp 0							; dummy vector to be overwritten
; beginning of last page of memory
; include virtual boot vector code
#include "tinyBoot.S" 

BootStart:
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code
	sbi DDRB, DDB1					; set Tx line to output

; Z pointer starts at program address 0
CommandLoop:
	rcall RxByte					; read command
	mov rCOMMAND, rDEST
	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne CheckProgPage
	rcall RxByte
	mov ZH, rDEST
	rcall RxByte
	mov ZL, rDEST					; Z stores address for page load
	rcall HandleEOP
CheckProgPage:
	cpi rCOMMAND, STK_PROG_PAGE
	brne Default
	rcall GetPageParams
PageFill:
	rcall RxByte
	mov r1, rDEST
	rcall RxByte
	mov r0, rDEST
	rcall DoSPM
	adiw ZL, 2						; increment Z pointer
	subi rTEMP, 2
	brne PageFill
CheckRead:
	cpi rCOMMAND, STK_READ_PAGE
	brne Default
	rcall GetPageParams
ReadPage:
	lpm rSOURCE, Z+
	rcall TxByte
	dec rTEMP
	brne ReadPage
Default:
	ldi rSOURCE, STK_OK 
	rcall TxByte
    rjmp CommandLoop
	; done programming

; get length and flash type for write or read page
; length stored in rTemp
; fall into HandleEOP
GetPageParams:
	rcall RxByte					; ignore block size hi byte
	rcall RxByte
	mov rTEMP, rDEST				; block size
	rcall RxByte					; ignore memory type - only flash support

; read EOP and respond with INSYNC
HandleEOP:
	rcall RxByte					; read EOP
	ldi rSOURCE, STK_INSYNC 
	rcall TxByte
	ret

/* TxByte(rSOURCE) and rDEST RxByte */
#include "AVR305.S"

