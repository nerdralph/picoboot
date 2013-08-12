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

#define BOOTPIN	PINB3
#define tmp1	r16
#define blank	r18

#define LOWBYTE(word) (word & 0xff)

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

.org _VECTORS_SIZE
AppStart:

.org (FLASHEND - SPM_PAGESIZE + 1)
BootStart:
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code
; set SPI slave
    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
    out USICR, tmp1
	sbi DDRB, DDB1					; set BP1 to output
    out USIDR, tmp1					; signature byte = 0x18

; flash the full memory space
;    ldi pgCnt, (FLASHEND / SPM_PAGESIZE)

; Z pointer starts at program address 0

CommandLoop:
    rcall SPIxfer					; read low byte
    mov r0, tmp1
    rcall SPIxfer					; read high byte
	mov r1, tmp1

    rcall DoSPM
	sbrc tmp1, 7					; bit 7 = set Z 
	movw ZL, r0						; set Z pointer
	sbrc tmp1, 6					; bit 6 = increment
    adiw ZL, 2						; inc Z pointer by one word
	tst tmp1
    brne CommandLoop				; not done

; SPIxfer subroutine for slave
; stores received data in r1
SPIwait:
SPIxfer:
    sbis USISR, USIOIF
    rjmp SPIxfer
    sbi USISR, USIOIF               ; clear USIOIF 
    in  tmp1, USIBR
    ret

; execute program memory command stored in register tmp1
DoSPM:
	rcall SPIxfer 
    out SPMCSR, tmp1
    spm
    ret

