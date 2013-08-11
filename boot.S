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

#define tmp1	r16
#define wrdCnt	r17
#define pgCnt	r18

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

.org _VECTORS_SIZE
AppStart:

.org (FLASHEND - SPM_PAGESIZE + 1)
BootStart:
; set SPI slave
    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
    out USICR, tmp1
	sbi DDRB, DDB1
    out USIDR, tmp1					; signature byte = 0x18

; flash the full memory space
;    ldi pgCnt, (FLASHEND / SPM_PAGESIZE)
; read number of pages to flash
    rcall SPIxfer
	mov pgCnt, R1

; first word of first page is reset vector program stream should point to it

RxPage:
    ldi wrdCnt, SPM_PAGESIZE/2
RxWord:
    rcall SPIxfer
    mov r0, r1
    rcall SPIxfer

    ldi tmp1, 0b00000001            ; write to flash buffer
    rcall DoSPM
    adiw ZL, 2						; inc Z pointer by one word
    dec wrdCnt
    brne RxWord
    
    ldi tmp1, 0b00000011            ; page erase
    rcall DoSPM
    ldi tmp1, 0b00000101            ; page write
    rcall DoSPM
    dec pgCnt
    brne RxPage

; SPIxfer subroutine for slave
; stores received data in r1
SPIxfer:
;    out USIDR, tmp1
SPIwait:
	adiw XL, 1
	brne NoTimeout
; timeout after 7 cycles (SPIwait loop) * 65536 = ~50ms @ 8Mhz
	rjmp AppStart
NoTimeout:
    sbis USISR, USIOIF
    rjmp SPIwait
    sbi USISR, USIOIF               ; clear USIOIF 
    in  r1, USIBR
    ret

; execute program memory command stored in register tmp1
DoSPM:
    out SPMCSR, tmp1
    spm
    ret

