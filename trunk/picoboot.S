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

#define LOWBYTE(word) (word & 0xff)
#define HIBYTE(word) ((word & 0xff00) >> 8) 

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

; save application boot vector
SaveAppStart:
	movw ZL, dataPageLo

; check Z pointer to see if it points to bootloader section
ErasePage:
	mov spmArg, chipErased
	movw tmpWordLo, ZL
	; subtract bootloader start address
	subi tmpWordLo, LOWBYTE(DATAPAGE)
	sbci tmpWordHi, HIBYTE(DATAPAGE)
	brcc DoSPM
	ret								; block write to bootloader section
	
WritePage:
	rcall ErasePage
	ldi spmArg, ((1<<PGWRT)|(1<<SPMEN)) 
	rcall DoSPM
	; check if AppJump needs to be written
	sbiw appJumpLo, 0
	brne CommandLoop
	rjmp SaveAppStart

DoSafeSPM:
    sbiw ZL, 0
	brne DoSPM
	movw appJumpLo, r0				; save application starting opcode
	; now replace r0, r1 with current bootload vector
	lpm r0, Z+
	lpm r1, Z
	; bit 0 of Z is ignored for spm so no need to clear it
	; clr ZL							; reset Z to 0
DoSPM:
	ori spmArg, (1<<SPMEN) 
    out SPMCSR, spmArg
    spm
	ret

ChipErase:
	ldi chipErased, (1<<PGERS)
	movw ZL, dataPageLo
	rcall ErasePage
	ret

BootStart:
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code

	ldi dataPageLo, LOWBYTE(DATAPAGE)
	ldi dataPageHi, HIBYTE(DATAPAGE)

; set SPI slave mode
    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
    out USICR, tmp1
	; no need to set DO pin as output in USI slave mode
	; see datasheet on DO pin override
	;sbi DDRB, DDB1					; set BP1 to output
; USIDR wrapps - bytes will echo back to programmer

; implements Serial Programming Instruction per ATtinyx5 datasheet
; 4 byte format starting with a 1-byte instruction

;   return point for load memory page low byte
LoadL:
	mov r0, tmp1					; load low byte
CommandLoop:
	rcall SPIxfer					; read instruction
	out	GPIOR0, tmp1				; save command
	bst tmp1, 3						; bit 3 set for read hi byte 
	rcall SPIxfer
	sbis USIBR, 7					; chip erase command
	rcall ChipErase
	;rcall ReadZ
	bld ZL, 0						; set bit 0 for hi byte
	lpm tmp1, Z						; lpm even when we don't need to
	out USIDR, tmp1
	rcall SPIxfer 
	sbis GPIOR0, 3					; do we need to do SPM?
	rjmp LoadL
	mov r1, tmp1					; load hi byte
	ldi spmArg, (1<<SPMEN) 
	sbic GPIOR0, 2					; bit 2 set for page write
	rjmp WritePage					; WritePage jumps to CommandLoop
	rcall DoSafeSPM
	rjmp CommandLoop

; SPIxfer subroutine for slave
; received data in USIBR copied to tmp1
; min 4 cycles + return (4) = 8 cycles
SPIxfer:
    sbis USISR, USIOIF
    rjmp SPIxfer
    sbi USISR, USIOIF               ; clear USIOIF 
    in  tmp1, USIBR
    ret

; read low & high byte into Z register
ReadZ:
    rcall SPIxfer					; read low byte
	rol tmp1						; word to byte addr
    mov ZL, tmp1
    rcall SPIxfer					; read high byte
	rol tmp1						; word to byte addr
	mov ZH, tmp1
	ret

