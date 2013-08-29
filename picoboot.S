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
#define bootAddrLo r18
#define bootAddrHi r19
#define tmpWordLo r20
#define tmpWordHi r21

#define LOWBYTE(word) (word & 0xff)
#define HIBYTE(word) ((word & 0xff00) >> 8) 

#define APPEND	(FLASHEND - (SPM_PAGESIZE * 2))
#define LASTPAGE	(FLASHEND - (SPM_PAGESIZE) +1 )

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

; .org _VECTORS_SIZE

; bootloader needs 128 bytes (rounded up to page size)
.org (FLASHEND - 127)
; check Z pointer to see if it points to bootloader section
; Carry clear if OK
DoCheckSPM:
	movw tmpWordLo, ZL
	; subtract bootloader start address
	subi tmpWordLo, LOWBYTE(APPEND)
	sbci tmpWordHi, HIBYTE(APPEND)
	brcc DoSPM
	ret								; block write to bootloader section
DoSafeSPM:
    sbiw ZL, 0
	brne DoSPM
	movw tmpWordLo, r0
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

BootStart:
; prep last page of memory to store application boot vector
	ldi ZL, LOWBYTE(LASTPAGE)
	ldi ZH, HIBYTE(LASTPAGE)
CopyPage:							; 9 opcodes - 18 bytes
	lpm r0, Z+
	lpm	r1, Z+
	rcall DoSPM 
	cpi ZL, 0xfc		 			; application vector storage
	brcs CopyPage
	ldi tmp1, ((1<<PGERS)|(1<<SPMEN)) 
	rcall DoSPM						; erase page
	ldi tmp1, ((1<<PGWRT)|(1<<SPMEN)) 
	rcall DoSPM						; write page
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code
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
	rcall ReadZ
	bld ZL, 0						; set bit 0 for hi byte
	lpm tmp1, Z						; lpm even when we don't need to
	out USIDR, tmp1
	rcall SPIxfer 
	sbis GPIOR0, 3					; do we need to do SPM?
	rjmp LoadL
	mov r1, tmp1					; load hi byte
	ldi spmArg, (1<<SPMEN) 
	sbic GPIOR0, 2					; bit 2 set for page write
	rjmp LoopEnd					; write to page buffer
	ldi spmArg, ((1<<PGERS)|(1<<SPMEN)) 
	rcall DoCheckSPM				; make sure we dont erase bootloader
	;brcs CommandLoop				; skip write
	; OK to fall through loop since page write w/o page erase does nothing
	ldi spmArg, ((1<<PGWRT)|(1<<SPMEN)) 
LoopEnd:
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

.org (FLASHEND - 3)
AppStart:
	rjmp IntVectors					; to be overwritten app address 0
	rjmp IntVectors + 2

