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
;.org (FLASHEND - SPM_PAGESIZE - 1)
AppStart:
	rjmp 0							; dummy vector to be overwritten
; .org (FLASHEND - SPM_PAGESIZE + 1)
; beginning of last page of memory
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
CheckProgPage:
	cpi rCOMMAND, STK_PROG_PAGE
	brne Default
	rcall RxByte					; ignore block size hi byte
	rcall RxByte
	mov rTEMP, rDEST				; block size
	rcall RxByte					; ignore memory type - only flash support
PageFill:
	rcall RxByte
	mov r1, rDEST
	rcall RxByte
	mov r0, rDEST
	rcall DoSPM
	subi rTEMP, 2
	brne PageFill
Default:
	rcall RxByte					; read EOP
	ldi rSOURCE, STK_INSYNC 
	rcall TxByte
	ldi rSOURCE, STK_OK 
	rcall TxByte
    brne CommandLoop				; not done
	; done programming - bootloader falls into SPIxfer forever loop

; execute program memory command 
DoSPM:
    out SPMCSR, 0x01
    spm
    ret

/* TxByte(rSOURCE) and rDEST RxByte */
#include "AVR305.S"

