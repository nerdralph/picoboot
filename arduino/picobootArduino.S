/* picobootArduino - arduino compatible bootloader
 * (c) Ralph Doncaster 2020 MIT license
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
 * 20200111 v3.00-b2 - size reduction to 256b and timing tweaks
 * 20200115 v3.00-rc1 improved noise immunity and portability
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
#define UART_PIN PIND

#include "stk500.h"

#define Command r16
#define Temp r17
#define RXEN_TXEN r18
#define pgLen r19
#define SpmArg r20
#define STK_OK_MSG r21
#define rxData r25
#define rxWord r24

; register definitions for mega8 & mega88/168/328 portability
; mega88/168/328 defines UCSR0A
#ifdef UCSR0A
  .equiv USART_BASE, UCSR0A
  ; define register displacements from USART_BASE
  .equiv UBRRL_d, (UBRR0L-USART_BASE)
  .equiv UCSRA_d, (UCSR0A-USART_BASE)
  .equiv UCSRB_d, (UCSR0B-USART_BASE)
  .equiv UDR_d, (UDR0-USART_BASE)
#endif
; mega8 defines UCSRA
#ifdef UCSRA
  .equiv USART_BASE, UBRRL
  ; define register displacements from USART_BASE
  .equiv UBRRL_d, (UBRRL-USART_BASE)
  .equiv UCSRA_d, (UCSRA-USART_BASE)
  .equiv UCSRB_d, (UCSRB-USART_BASE)
  .equiv UDR_d, (UDR-USART_BASE)
#endif
; USART bit values are the same for mega8 & mega88/168/328
.equiv U2XSpeed, (1<<1)
.equiv TXEnable, (1<<3)
.equiv RXEnable, (1<<4)
.equiv DREmpty, 5
.equiv RXComplete, 7

; same address for SPMCR/SPMCSR
.equiv SPMReg, 0x37

.section .version
.equiv picoboot_version, 256*3

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
    sbi UART_PIN+2, 0               ; pullup rx to improve noise immunity
    sbi UART_PIN+1, 1               ; pulldown tx

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
JStartApp:
    rjmp StartApp                   ; bootloader timout

    ; autobaud - times the 5 low bits in GET_SYNC 0x30 '0'
1:  adiw XL, 1                      ; count low time
    sbis UART_PIN, 0
    rjmp 1b
    lsr XH
    ror XL
    lsr XH
    ror XL
    lsr XH                          ; XH should be 0 now
    lsr XL
    adc XL, XH                      ; round up
    dec XL                          ; final UBRR value
    ; UBRR 0 means noise or rx baud rate too high
    breq JStartApp

    ; inialize UART IO base pointer
    ldi YL, lo8(USART_BASE)
    clr YH
    ; initialize UART
    ldi Temp, U2XSpeed
    std Y+UCSRA_d, Temp
    std Y+UBRRL_d, XL
    ldi RXEN_TXEN, RXEnable | TXEnable 


    ldi STK_OK_MSG, STK_OK

    ;rcall TxByte                    ; debug UBRR calc

; in a very noisy environment the bootloader could get stuck in WaitSync
; if a long enough low pulse is received to get past WaitStart
WaitSync:
    ;rcall RxByte                    ; read command
    ;cpi rxData, STK_GET_SYNC
    ;brne WaitSync

CommandLoop:
    ; turn off Rx to ignore the rest of STK500 message
    ldi Temp, TXEnable
    std Y+UCSRB_d, Temp
    ; longest msg is SET_DEVICE at 22 bytes; wait at least that long
    ; loop is 7 cycles, so 7 * 256 * (UBRR + 1)  is enough
    ldd XH, Y+UBRRL_d
    inc XH
1:  sbiw XL, 1                      ; 2 cycle add
    lpm                             ; 3 cycle delay
    brne 1b                         ; 2 cycle branch

    ; enable reading RWW section - ensures last spm completed before
    ; returning STK_OK
    ; for RWW info see ATmega88/168/328 datasheet 27.9.1
#ifdef RWWSRE
    ldi SpmArg, (1<<RWWSRE)|(1<<SPMEN)
    rcall DoSPM
#endif
    ; turn Rx back on
    std Y+UCSRB_d, RXEN_TXEN
    ; reply OK
    std Y+UDR_d, STK_OK_MSG

; start of new message from programmer
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
    ; command ignored - send dummy 0x00(XH) for Universal/Version Param
1:  std Y+UDR_d, XH

ReadSig:
    cpi Command, STK_READ_SIGN
    brne Quit
    ldi r26, SIGNATURE_0
    rcall TxByte
    ldi r26, SIGNATURE_1
    rcall TxByte
    ldi r26, SIGNATURE_2
    rcall TxByte

ProgPage:
    cpi Command, STK_PROG_PAGE
    brne ReadPage
    rcall GetPageParams
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
    ; erase then write page
    ldi SpmArg, (1<<PGERS)|(1<<SPMEN)
    rcall DoSPM
    ldi SpmArg, (1<<PGWRT)|(1<<SPMEN)
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
    rjmp CommandLoop

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
    in Temp, SPMReg
    sbrc Temp, SPMEN
    rjmp DoSPM                      ; wait for last SPM to complete
    out SPMReg, SpmArg
    spm
    ret


/* UART code */

; transmit byte contained in r26
TxByte:
#ifdef DEBUG
    out debug_output_port, r26
    ret    
#endif
    ldd Temp, Y+UCSRA_d
    sbrs Temp, DREmpty
    rjmp TxByte
    std Y+UDR_d, r26
    ret

; receive byte into rxData
RxByte:
#ifdef DEBUG
    in rxData, debug_input_port
    ret    
#endif
    ldd Temp, Y+UCSRA_d
    sbrs Temp, RXComplete
    rjmp RxByte
    ldd rxData, Y+UDR_d
    ret

Quit:
    cpi Command, STK_LEAVE_PROGMODE
    brne ProgPage
    ; reply OK
    std Y+UDR_d, STK_OK_MSG

    ; disable USART RX/TX then start app
    std Y+UCSRB_d, YH

StartApp:
    cbi UART_PIN+2, 0               ; turn off rx pullup
    cbi UART_PIN+1, 1               ; turn off Tx
    ; wrap-around to reset vector

