/* picoBootSTK500 - arduino compatible bootloader
 *
 * TTL serial version - 81N, 115.2kbps @16Mhz, 57.6kbps@8Mhz
 * @author: Ralph Doncaster
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * https://code.google.com/p/optiboot/
 * https://github.com/whitequark/vuxboot
 * 
 * This bootloader is an implementation of the Arduino bootloader,
 * a stripped-down STK500 protocol, in assembler.
 * Optiboot is the main guide for this bootloader.
 * protocol trace from Bald Wisdom blog
 * http://baldwisdom.com/bootloading/ 
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

/* work-around for defines missing in avr-libc - bug #42957  
 */
#ifndef SPMEN
#define SPMEN 0
#endif

#ifdef DEBUG
/* for simulavr debugging */
#   define debug_output_port 0x31
#   define debug_input_port 0x32
#endif

#define LEDPIN 5
#define LEDPORT PORTB

#include "stk500.h"

#define TmpWord r12
#define Command r16
#define Temp r17
#define PgLen r18
#define MemType r19
#define Temp2 r20

.text
Blink:
    sbi PINB, LEDPIN
    ldi ZH, 60
DelayLoop:
    ; 11.8M cycles =~ .74s @ 16Mhz
    rcall Delay3Cycle               ; 256 * 3 cycles
    sbiw ZL, 1
    brne DelayLoop
    rjmp Blink

; delay 3 cycles * r24 + 4 cycles (ret instruction)
; also clears carry (subi instead of dec)
Delay3Cycle:
    subi r24, 1
    brne Delay3Cycle
    ret

.section .bootloader,"ax",@progbits
; use -WL,--section-start=.bootloader=0xXf00

Boot:
    in Temp, MCUSR
    sbrs Temp, EXTRF
JmpStart:
    rjmp StartApp                  ; jump to application code
    eor r15, Temp                  ; toggle r15 to signal bootloader run
    breq JmpStart

BootLoader:
    mov r15, Temp                  ; flag bootloader run
    sbi LEDPORT, LEDPIN            ; light LED dimly during bootloader

    ; inialize UART IO base pointer
    ldi YL, lo8(UCSR0A)
    clr YH
    ; initialize UART
    ldi Temp, (1<<U2X0)
    st Y, Temp
    ldi Temp, 16                    ; 115200kbps @16Mhz
    std Y+(UBRR0L - UCSR0A), Temp
    ldi Temp, (1<<RXEN0 | 1<<TXEN0)
    std Y+(UCSR0B - UCSR0A), Temp

CommandLoop:
    rcall RxByte                    ; read command
    mov Command, r24
    ldi r26, STK_INSYNC 
    rcall TxByte                    ; all responses start with INSYNC

    cpi Command, STK_LOAD_ADDRESS
    brne Universal
    rcall RxByte
    mov ZL, r24
    rcall RxByte
    mov ZH, r24                     ; Z stores address for page load
    lsl ZL
    rol ZH                          ; convert from word to byte address

Universal:
    cpi Command, STK_UNIVERSAL
    brne GetParam
    ; command ignored - return dummy 0x00
    clr r26
    rcall TxByte

GetParam:
    cpi Command, STK_GET_PARAMETER
    brne ReadSig
    ; return 0x03 for all parameters - Optiboot comments say
    ; its enough to keep Avrdude happy
    ; also means 03 is reply to major and minor version
    ; looking at the Avrdude stk500 code I think it may be safe to return
    ; 0x00 and comine this response with the STK_UNIVERSAL response
    ; to save 2 instructions
    ldi r26, 0x03
    rcall TxByte

ReadSig:
    cpi Command, STK_READ_SIGN
    brne Quit
    ldi r26, SIGNATURE_0
    rcall TxByte
    ldi r26, SIGNATURE_1
    rcall TxByte
    ldi r26, SIGNATURE_2
    rcall TxByte

Quit:
    cpi Command, STK_LEAVE_PROGMODE
    brne ProgPage
    ldi r26, STK_OK
    rcall TxByte                    ; reply OK
    ; enable reading RWW section before starting application
    ; see ATmega88/168/328 datasheet 27.9.1
    ldi Temp, (1<<RWWSRE)|(1<<SPMEN)
    rcall DoSPM
    rjmp StartApp

ProgPage:
    ; faster to erase first, read, then write?
    cpi Command, STK_PROG_PAGE
    brne ReadPage
    rcall GetPageParams
    cpi r24, 'F'                    ; check for memtype flash
    brne Default                    ; only flash supported
    movw TmpWord, ZL                ; save Z
PageFill:
    rcall RxByte
    mov r0, r24                     ; word low byte 
    rcall RxByte
    mov r1, r24                     ; word high byte 
    ldi Temp, (1<<SPMEN)            ; fill page buffer
    rcall DoSPM
    adiw ZL, 2                      ; increment Z pointer
    subi PgLen, 2
    brne PageFill
    movw ZL, TmpWord                ; restore Z
    ldi Temp, (1<<PGERS)|(1<<SPMEN) ;erase page
    rcall DoSPM
    ldi Temp, (1<<PGWRT)|(1<<SPMEN) ;write page
    rcall DoSPM

ReadPage:
    cpi Command, STK_READ_PAGE
    brne Default 
    rcall GetPageParams
    ; read both flash and EE, but only send memtype that was requested
    ; reduces code to one loop instead of two 
ReadByte:
    lpm r26, Z+
ReadEEPROM:
    cpi r24, 'E'                    ; check for memtype EEPROM
    brne SendByte
ReadEEByte:
    out EEARL, ZL
    out EEARH, ZH
    sbi EECR, EERE
    in r26, EEDR
SendByte:
    rcall TxByte
    dec PgLen
    brne ReadEEByte

Default:
    ; read to EOP
    rcall RxByte
    cpi r24, CRC_EOP
    brne Default                    ; read until EOP
    ldi r26, STK_OK
    rcall TxByte                    ; reply OK
    rjmp CommandLoop

; get length and flash type for write or read page
GetPageParams:
    rcall RxByte                    ; ignore block size hi byte
    rcall RxByte
    mov PgLen, r24                  ; block size
    rcall RxByte                    ; memory type
    ret


DoSPM:
    in Temp2, SPMCSR
    sbrc Temp2, SPMEN
    rjmp DoSPM                      ; wait for last SPM to complete
    out SPMCSR, Temp
    spm
    ret

/* UART code */

; transmit byte contained in r26
TxByte:
#ifdef DEBUG
    out debug_output_port, r26
    ret    
#endif
    ld Temp, Y
    sbrs Temp, UDRE0
    rjmp TxByte
    std Y+(UDR0 - UCSR0A), r26
    ret

; receive byte into r24
RxByte:
#ifdef DEBUG
    in r24, debug_input_port
    ret    
#endif
    ld Temp, Y
    sbrs Temp, RXC0
    rjmp RxByte
    ldd r24, Y+(UDR0 - UCSR0A)
    ret

; set registers to reset state then start app
StartApp:
    clr r15                         ; flag bootloader not run
    ; reset UART
    std Y+(UCSR0B - UCSR0A), r15
    ; reset USART
    cbi LEDPORT, LEDPIN             ; turn off LED
; slide into reset vector at address 0x0000
