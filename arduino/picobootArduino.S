/* picoBootSTK500 - arduino compatible bootloader
 * Ralph Doncaster 2018 GPLv3 license
 *
 * TTL serial version with autobaud 19,200 to 115,200
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * https://code.google.com/p/optiboot/
 * https://github.com/whitequark/vuxboot
 * 
 * This is an implementation of the Arduino bootloader in asm
 * Optiboot is the main guide for this bootloader.
 * protocol trace from Bald Wisdom blog
 * http://baldwisdom.com/bootloading/ 
 *
 * 20150601 v1 release - includes EEPROM read
 * 20180525 v2 release with autobaud - 250 bytes
 * 20200104 v2.01 reduce size
 * 20200106 v3.00-beta - bootloader timeout instead of mode toggle
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

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
#define rxCount r18
#define pgLen r19
#define SpmArg r20
#define rxData r25
#define rxWord r24

.section .version
.equ picoboot_version, 256*3

.text
; this will be address 0x0000 which is the reset vector
; user application will over-write 20-byte blink code
; dimly lights LED (using internal pullup) with a 1.5 s cycle time
ResetVector:
    clr r1                          ; avr-libc does this when app is flashed
    sbi PINB, LEDPIN
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

.section .bootloader,"ax"
; use -WL,--section-start=.bootloader=0xXX00
BootLoader:
    sbi LEDPORT, LEDPIN             ; light LED dimly during bootloader
    in r2, MCUSR
    sbrs r2, EXTRF
    rjmp StartApp                   ; jump to application code

    ;sbi UART_PIN+1, 1               ; pulldown tx
    clr XL
    clr XH
    
    ; wait for start bit of first message
    ldi YL, 100                     ; 100 =~ 2.5s @16Mhz
WaitStart:
    adiw ZL, 1
    sbis UART_PIN, 0
    rjmp 1f                         ; got start bit
    brne WaitStart
    dec YL
    brne WaitStart
    rjmp StartApp                   ; bootloader timout


    ; autobaud - times the 5 low bits in GET_SYNC 0x30 '0'
1:  adiw XL, 1                      ; count low time
    sbis UART_PIN, 0
    rjmp 1b
    lsr XH
    ror XL
    lsr XH
    ror XL
    lsr XL
    dec XL                          ; final UBRR value

    ; inialize UART IO base pointer
    ldi YL, lo8(UCSR0A)
    clr YH
    ; initialize UART
    ldi Temp, (1<<U2X0)
    st Y, Temp
    std Y+(UBRR0L - UCSR0A), XL

    ; delay to enable UART after GET_SYNC message is over
1:  adiw XL, 1
    brne 1b
    ldi Temp, (1<<RXEN0 | 1<<TXEN0)
    std Y+(UCSR0B - UCSR0A), Temp

    rcall TxByte                    ; debug UBRR calc

WaitSync:
    rcall RxByte                    ; read command
    cpi rxData, STK_GET_SYNC
    brne WaitSync
    rjmp Default                    ; wait for CRC_EOP

CommandLoop:
    rcall RxByte                    ; read command
1:  mov Command, rxData
    ldi r26, STK_INSYNC 
    rcall TxByte                    ; all responses start with INSYNC

    cpi Command, STK_LOAD_ADDRESS
    brne Universal
    rcall ReadWord
    movw ZL, rxWord                 ; Z stores address for page load
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
    brne SetDevice
    ldi r26, SIGNATURE_0
    rcall TxByte
    ldi r26, SIGNATURE_1
    rcall TxByte
    ldi r26, SIGNATURE_2
    rcall TxByte

SetDevice:
    cpi Command, STK_SET_DEVICE
    brne Quit
    ldi rxCount, 20                 ; skip next 20 bytes
    rcall RxBytes

Quit:
    cpi Command, STK_LEAVE_PROGMODE
    brne ProgPage
    ldi r26, STK_OK
    rcall TxByte                    ; reply OK

    ; disable USART RX/TX then start app
    std Y+(UCSR0B - UCSR0A), YH

StartApp:
    ;cbi UART_PIN+1, 1               ; turn off Tx
    cbi LEDPORT, LEDPIN             ; turn off LED
    rjmp ResetVector

ProgPage:
    cpi Command, STK_PROG_PAGE
    brne ReadPage
    rcall GetPageParams
    mov pgLen, rxWord
    cpi rxData, 'F'                 ; check for memtype flash
    brne Default                    ; only flash supported
PageFill:
    rcall ReadWord
    movw r0, rxWord                 ; data in r1:r0
    ldi SpmArg, (1<<SPMEN)          ; fill page buffer
    rcall DoSPM
    adiw ZL, 2                      ; increment Z pointer
    subi pgLen, 2
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
    mov pgLen, rxWord
    ; read both flash and EE, but only send memtype that was requested
    ; reduces code to one loop instead of two 
ReadByte:
    out EEARL, ZL
    out EEARH, ZH
    lpm r26, Z+
ReadEEPROM:
    cpi rxData, 'E'                 ; check for memtype EEPROM
    brne SendByte
ReadEEByte:
    sbi EECR, EERE
    in r26, EEDR
SendByte:
    rcall TxByte
    dec pgLen
    brne ReadByte

Default:
    rcall RxByte
    cpi rxData, CRC_EOP
    brne Default                    ; read until EOP
    ; enable reading RWW section - ensures last spm completed before
    ; returning STK_OK
    ; for RWW info see ATmega88/168/328 datasheet 27.9.1
#ifdef RWWSRE
    ldi SpmArg, (1<<RWWSRE)|(1<<SPMEN)
    rcall DoSPM
#endif
    ldi r26, STK_OK
    rcall TxByte                    ; reply OK
    rjmp CommandLoop

; skip n=rxCount bytes
RxBytes:
    rcall RxByte
    dec rxCount
    brne RxBytes
    ret

; get length and flash type for write or read page
GetPageParams:
    rcall RxByte                    ; ignore block size hi byte
    rcall ReadWord
    mov pgLen, rxWord               ; block size
    ret

ReadWord:                           ; read word into rxWord
    rcall RxByte
    mov rxWord, rxData              ; rxWord lo
    rjmp RxByte                     ; rxWord hi

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

; receive byte into rxData
RxByte:
#ifdef DEBUG
    in rxData, debug_input_port
    ret    
#endif
    ld Temp, Y
    sbrs Temp, RXC0
    rjmp RxByte
    ldd rxData, Y+(UDR0 - UCSR0A)
    ret
