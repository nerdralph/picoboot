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

#define BOOTPIN	PINB0
#define tmp1	r16
#define dataOut	r17

#define LOWBYTE(word) (word & 0xff)

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

; .org _VECTORS_SIZE
.org (FLASHEND - SPM_PAGESIZE - 1)
AppStart:
	rjmp 0							; dummy vector to be overwritten
; .org (FLASHEND - SPM_PAGESIZE + 1)
; beginning of last page of memory
BootStart:
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code
; set SPI slave
    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
    out USICR, tmp1
	sbi DDRB, DDB1					; set BP1 to output
; USIDR wrapps - bytes will echo back to programmer
;    out USIDR, tmp1					; signature byte = 0x18

; flash the full memory space
;    ldi pgCnt, (FLASHEND / SPM_PAGESIZE)

; Z pointer starts at program address 0

CommandLoop:
    rcall SPIxfer					; read low byte
    mov r0, tmp1
    rcall SPIxfer					; read high byte
	mov r1, tmp1

    rcall DoSPM
	sbrc tmp1, 6					; command bit 6 = increment
    adiw ZL, 2						; inc Z pointer by one word
	sbrc tmp1, 7					; command bit 7 = set Z 
	movw ZL, r0						; set Z pointer
	tst tmp1
    brne CommandLoop				; not done
	; done programming - bootloader falls into SPIxfer forever loop

; SPIxfer subroutine for slave
; stores received data in r1
SPIxfer:
    sbis USISR, USIOIF
    rjmp SPIxfer
    sbi USISR, USIOIF               ; clear USIOIF 
    out USIDR, dataOut				; data out
    in  tmp1, USIBR
    ret

; execute program memory command stored in register tmp1
DoSPM:
	lpm dataOut, Z					; lpm even when we don't need to
	rcall SPIxfer 
    out SPMCSR, tmp1
    spm
    ret

