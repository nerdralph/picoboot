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

#define codeWords r18
#define pgCnt	r19

.text
    cli
SPIinit:
; set SPI slave
    ldi tmp1,(1<<USIWM0)|(1<<USICS1)
    out USICR, tmp1

; store from page 0 so no need to init zl & zh
;    ldi zl, 0
;    ldi zh, 0
    rcall SPIxfer
    mov pgCnt, r1
RxPage:
    ldi wrdCnt, SPM_PAGESIZE/2
RxWord:
    rcall SPIxfer
    mov r0, r1
    rcall SPIxfer
    
    ldi tmp1, 0b00000001             ; write to flash buffer
    rcall DoSPM
    adiw ZL, 2
    dec wrdCnt
    brne RxWord
    
    ldi tmp1, 0b00000011             ; page erase
    rcall DoSPM
    ldi tmp1, 0b00000101             ; page write
    rcall DoSPM
    dec pgCnt
    brne RxPage

; SPIxfer subroutine for slave
; stores received data in r1
SPIxfer:
;    out USIDR, tmp
SPIwait:
    sbis USISR, USIOIF
    rjmp SPIwait
    sbi USISR, USIOIF               ; clear USIOIF 
    in  r1, USIBR
    ret

; execute program memory command
DoSPM:
    out SPMCSR, tmp1
    spm
    ret

