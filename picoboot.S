/* picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * http://symlink.dk/electro/m163boot/
 * http://github.com/baerwolf/USBaspLoader
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

/* PINB5 = Reset on ATtinyx5 */
#define BOOTPIN	PINB5
#define tmp1	r16
#define spmArg	r17
#define dataPageLo r18
#define dataPageHi r19
#define tmpWordLo r20
#define tmpWordHi r21
#define chipErased r22
#define appJumpLo r24
#define appJumpHi r25

#define DATAPAGE (FLASHEND - 127 - SPM_PAGESIZE)
#define LASTPAGE (FLASHEND - (SPM_PAGESIZE) +1 )

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

; .org _VECTORS_SIZE

.org (FLASHEND - 129)
; rjmp to start of application goes in last 2 bytes of page before bootloader
AppStart:
	rjmp IntVectors					; to be overwritten app address 0
; page starts here	
	rjmp IntVectors + 2

; save application boot vector by writing to DATAPAGE
SaveAppStart:
	movw ZL, dataPageLo
	movw r0, appJumpLo 
	rcall DoSPM
	movw appJumpLo, r2				; zero appJump	
	rjmp WritePage
	
; write page buffer to flash - jumps to CommandLoop when done
WritePage:
	rcall ErasePage
	ldi spmArg, ((1<<PGWRT)|(1<<SPMEN)) 
	rcall DoSPM
	; check if AppJump needs to be written
	sbiw appJumpLo, 0
	brne CommandLoop
	rjmp SaveAppStart

ChipErase:
	ldi chipErased, (1<<PGERS)
	movw ZL, dataPageLo
; fall into ErasePage

; check Z pointer to see if it points to bootloader section
ErasePage:
	mov spmArg, chipErased
	;movw tmpWordLo, ZL
	; subtract bootloader start address
	;subi tmpWordLo, lo8(DATAPAGE)
	;sbci tmpWordHi, hi8(DATAPAGE)
	cpi ZL, hi8(DATAPAGE)		; 256 byte protection area
	brcs DoSPM
	ret								; block write to bootloader section

DoSafeSPM:
    sbiw ZL, 0
	brne DoSPM
	movw appJumpLo, r0				; save application starting opcode
	; now replace r0, r1 with current bootload vector
	lpm r0, Z+
	lpm r1, Z
	; fall through to DoSPM
DoSPM:
	ori spmArg, (1<<SPMEN) 
    out SPMCSR, spmArg
    spm
	ret

BootStart:
	; sbi PORTB, BOOTPIN 				; enable pullup
	sbic PINB, BOOTPIN 				; run bootloader if BOOTPIN low
	rjmp AppStart					; jump to application code

	ldi dataPageLo, LOWBYTE(DATAPAGE)
	ldi dataPageHi, HIBYTE(DATAPAGE)

; set SPI slave mode
    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
    out USICR, tmp1
	; no need to set DO pin as output in USI slave mode
	; see datasheet on DO pin override
	;sbi DDRB, DDB1					; set BP1 to output

; implements Serial Programming Instruction per ATtinyx5 datasheet
; 4 byte format starting with a 1-byte instruction

;   return point for load memory page low byte
LoadL:
	mov r0, r1					; load low byte
CommandLoop:
	rcall SPIxfer					; read instruction
	out	GPIOR0, r1					; save command
	bst tmp1, 3						; bit 3 set for read hi byte 
	rcall SPIxfer
	sbrs r1, 7						; chip erase command
	rcall ChipErase
	rcall ReadZ
	bld ZL, 0						; set bit 0 for hi byte
	lpm tmp1, Z						; lpm even when we don't need to
	out USIDR, tmp1
	rcall SPIxfer 					; read hi byte into r1
	sbis GPIOR0, 6					; do we need to do SPM?
	rjmp LoadL						; ! load pg buf or write pg cmd
	ldi spmArg, (1<<SPMEN) 
	sbic GPIOR0, 2					; bit 2 set for page write
	rjmp WritePage					; WritePage jumps to CommandLoop
	rcall DoSafeSPM					; write page buffer
	rjmp CommandLoop

; SPIxfer subroutine for slave
; received data copied to r1
; min 4 cycles + return (4) = 8 cycles
SPIxfer:
    sbis USISR, USIOIF
    rjmp SPIxfer
    sbi USISR, USIOIF               ; clear USIOIF 
    in  r1, USIDR
    ret

; put low & high byte into Z register
; load low into tmp1 before calling
ReadZ:
	lsl r1							; word to byte addr
    mov ZL, r1
    rcall SPIxfer					; read high byte
	rol r1							; word to byte addr
    mov ZH, r1
	ret

