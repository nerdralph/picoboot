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
#define dataOut	r17
#define word0Save r24

/* bit 6 set for SPM instructions */
#define SPMbit	3

#define LOWBYTE(word) (word & 0xff)

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

; .org _VECTORS_SIZE
.org (FLASHEND - (SPM_PAGESIZE * 2) - 1)
AppStart:
	rjmp 0							; dummy vector to be overwritten
; .org (FLASHEND - SPM_PAGESIZE + 1)
; beginning of last page of memory
BootStart:
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code
; set SPI slave
;    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
;    out USICR, tmp1
	sbi DDRB, DDB1					; set BP1 to output
; USIDR wrapps - bytes will echo back to programmer

; implements Serial Programming Instruction per ATtinyx5 datasheet
; 4 byte format starting with a 1-byte instruction

;   return point for load memory page low byte
LoadL:
	mov r0, tmp1	
CommandLoop:
	rcall SPIxfer					; read instruction
	out	GPIOR0, tmp1				; save command
	rcall ReadZ
	lpm dataOut, Z					; lpm even when we don't need to
	out USIDR, dataOut
	rcall SPIxfer 
	sbis GPIOR0, SPMbit				; check if this is a SPM command
	rjmp LoadL
	mov r1, tmp1	
	ldi tmp1, (1<<SPMEN) 
	sbic GPIOR0, 2					; bit 2 set for page write
	rjmp LoopEnd					; fill page buffer
	ldi tmp1, ((1<<PGERS)|(1<<SPMEN)) 
	rcall DoSPM
	ldi tmp1, ((1<<PGWRT)|(1<<SPMEN)) 
LoopEnd:
	rcall DoSPM
	rjmp CommandLoop

; SPIxfer subroutine for slave
; stores received data in tmp1 
SPIxfer:
    sbis USISR, USIOIF
    rjmp SPIxfer
    sbi USISR, USIOIF               ; clear USIOIF 
;    out USIDR, dataOut				; data out
    in  tmp1, USIBR
    ret

; read low & high byte into Z register
ReadZ:
    rcall SPIxfer					; read low byte
    mov ZL, tmp1
    rcall SPIxfer					; read high byte
	mov ZH, tmp1
	ret

;   could we save cycles by ori SPMEN with flags passed 
DoSPM:
    ; protect bootloader vector
    sbiw ZL, 0
	brne NotBootVect
	movw word0Save, r0
	lpm

NotBootVect:
    out SPMCSR, tmp1
    spm
	ret
