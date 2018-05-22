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
 *
 * 20150601 v1 release - includes EEPROM read
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
#define UART_PIN PIND

#include "stk500.h"

#define Command r16
#define Temp r17
#define PgLen r18
#define MemType r19
#define SpmArg r20

.text
; this will be address 0x0000 which is the reset vector
; user application will over-write blink code
; dimly lights LED (using internal pullup) with a 1.5 s cycle time
ResetVector:
    clr r1                          ; avr-libc does this when app is flashed
    sbi PINB, LEDPIN
    sbi DDRB, LEDPIN
    ldi ZH, 60
DelayLoop:
    ; 11.8M cycles =~ .74s @ 16Mhz
    rcall Delay3Cycle               ; 256 * 3 cycles
    sbiw ZL, 1
    brne DelayLoop
    rjmp ResetVector

; delay 3 cycles * r24 + 4 cycles (ret instruction)
Delay3Cycle:
    dec r24
    brne Delay3Cycle
    ret


.section .bootloader,"ax",@progbits
; use -WL,--section-start=.bootloader=0xXX00

BootLoader:
    ;sbi LEDPORT, LEDPIN             ; light LED dimly during bootloader
    tst r1                          ; was app running before reset?
    brne 1f
    in r1, MCUSR
    sbrs r1, EXTRF
1:  rjmp StartApp                   ; jump to application code

    ; inialize UART IO base pointer
    ldi YL, lo8(UCSR0A)
    clr YH
    ;sbi UART_PIN+2, 1              ; pullup tx
    sbi UART_PIN+1, 1               ; pulldown tx
    ; autobaud - times the 5 low bits in GET_SYNC 0x30 '0'
    clr XL
    clr XH
1:  sbic UART_PIN, 0                ; wait for start bit
    rjmp 1b
1:  adiw XL, 1                      ; count low time
    sbis UART_PIN, 0
    rjmp 1b
    lsr XH
    ror XL
    lsr XH
    ror XL
    lsr XL
    dec XL                          ; final UBRR value

    ; initialize UART
    ldi Temp, (1<<U2X0)
    st Y, Temp
    std Y+(UBRR0L - UCSR0A), XL
    ldi Temp, (1<<RXEN0 | 1<<TXEN0)
    std Y+(UCSR0B - UCSR0A), Temp

    ;rcall TxByte                    ; debug UBRR calc

CommandLoop:
    rcall RxByte                    ; read command
1:  mov Command, r24
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
    breq 1f                         ; dummy reply
GetParam:
    cpi Command, STK_GET_PARAMETER
    brne ReadSig
    ; command ignored - return dummy 0x00 for Universal/Version Param
1:  clr r26
    rcall TxByte

ReadSig:
    cpi Command, STK_READ_SIGN
    brne ProgPage
    ldi r26, SIGNATURE_0
    rcall TxByte
    ldi r26, SIGNATURE_1
    rcall TxByte
    ldi r26, SIGNATURE_2
    rcall TxByte

;Quit:
    ; Ignored - user must reset AVR after programming
    ;cpi Command, STK_LEAVE_PROGMODE
    ;brne ProgPage
    ;ldi r26, STK_OK
    ;rcall TxByte                    ; reply OK
    ; wait for tx to complete before shutting off uart
;1:  adiw XL, 1
    ;brne 1b
    ; set registers to reset state then start app
    ; reset UART - YH is zero
    ;std Y+(UCSR0B - UCSR0A), YH
    ;std Y+(UBRR0L - UCSR0A), YH
    ;st Y, YH

ProgPage:
    ; faster to erase first, read, then write?
    cpi Command, STK_PROG_PAGE
    brne ReadPage
    rcall GetPageParams
    cpi r24, 'F'                    ; check for memtype flash
    brne Default                    ; only flash supported
PageFill:
    rcall RxByte
    mov r0, r24                     ; word low byte 
    rcall RxByte
    mov r1, r24                     ; word high byte 
    ldi SpmArg, (1<<SPMEN)          ; fill page buffer
    rcall DoSPM
    adiw ZL, 2                      ; increment Z pointer
    subi PgLen, 2
    brne PageFill
    sbiw ZL, 2                      ; roll Z back
    ldi SpmArg, (1<<PGERS)|(1<<SPMEN)
    rcall DoSPM
    ldi SpmArg, (1<<PGWRT)|(1<<SPMEN) ;write page
    rcall DoSPM
    ; if in RWW section, page write will continue asynchronously
    ; while bootloader runs

ReadPage:
    cpi Command, STK_READ_PAGE
    brne Default 
    rcall GetPageParams
    ; read both flash and EE, but only send memtype that was requested
    ; reduces code to one loop instead of two 
ReadByte:
    out EEARL, ZL
    out EEARH, ZH
    lpm r26, Z+
ReadEEPROM:
    cpi r24, 'E'                    ; check for memtype EEPROM
    brne SendByte
ReadEEByte:
    sbi EECR, EERE
    in r26, EEDR
SendByte:
    rcall TxByte
    dec PgLen
    brne ReadByte

Default:
    rcall RxByte
    cpi r24, CRC_EOP
    brne Default                    ; read until EOP
    ; enable reading RWW section - ensures last spm completed before
    ; returning STK_OK
    ; for RWW info see ATmega88/168/328 datasheet 27.9.1
    ldi SpmArg, (1<<RWWSRE)|(1<<SPMEN)
    rcall DoSPM
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
    in Temp, SPMCSR
    sbrc Temp, SPMEN
    rjmp DoSPM                      ; wait for last SPM to complete
    out SPMCSR, SpmArg
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

StartApp:
    ;cbi LEDPORT, LEDPIN             ; turn off LED
    ; slide into reset vector
    ;rjmp ResetVector                ; jump to application code
