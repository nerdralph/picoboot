/* picoBoot - tiny bootloader for AVR MCUs
 * TTL serial version - 81N, 115.2kbps @8Mhz, 230.4kbps@16Mhz
 * ideal bit timing @115.2kbps/8Mhz is 69.444 cycles/bit
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * http://symlink.dk/electro/m163boot/
 * http://github.com/baerwolf/USBaspLoader
 * http://code.google.com/p/optiboot/
 * AVR305 half-duplex serial uart
 * Thanks for suggestions from avrfreaks members and code
 * submissions by Joey Morin.
 *
 * Soft UART is used, even on parts with a hardware UART
 * PD0/PD1 are used for Rx/Tx, or PB0/PB1 for parts with no PORTD
 *
 * The protocol is pairs of 4-byte frames:
 * data lo, data hi, FCS (EOR), command
 * data from the first frame is copied r0, r1.  For the next frame,
 * data is copied to Z, command is written to SPMCSR, followed
 * by the spm instruction. The command for the first fame must be 0.
 *
 * bootloader acks to programmer with 0x80 after each byte
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#define PICOBOOT_MIN_PAGE_ALIGN 64

#if (SPM_PAGESIZE > PICOBOOT_MIN_PAGE_ALIGN)
#define VIRTUAL_RESET_ORG (FLASHEND - SPM_PAGESIZE) - 1)
#else
#define VIRTUAL_RESET_ORG (FLASHEND - PICOBOOT_MIN_PAGE_ALIGN - 1)
#endif 

#define LEDPIN 5

#ifndef PORTD
#define UART_Port PORTB
#else
#define UART_Port PORTD
#endif
#define UART_Rx 0
#define UART_Tx 1
#define RXDELAY 19
; 3 * 19 -1 = 56 cycles + 7 call/ret + 6 loop = 69
; 69/69.444 = 0.6% fast bit timing
#define RXSTART 31
#define tmp1	r16
#define FCS	    r17
#define data    r22
#define delayArg	r18

.text
.org 0x0000
    rjmp BootStart 
BlinkLED:
    sbi DDRB, LEDPIN
Blink:
    sbi PINB, LEDPIN
    ldi ZH, 30
DelayLoop:
    ; 5.9M cycles =~ .74s @ 8Mhz
    rcall Delay3Cycle               ; 256 * 3 cycles
    sbiw ZL, 1
    brne DelayLoop
    rjmp Blink

.org VIRTUAL_RESET_ORG
VirtualReset:
    rjmp BlinkLED                   ; will be overwritten by programmer
BootStart:
    sbis UART_Port-2, UART_Rx       ; Rx high = start bootloader
    rjmp VirtualReset               ; jump to application code
    clr FCS

    ; continuous loop for commands from programmer
    ; when upload is finished, programmer resets chip & starts app
    ; by transmitting a null byte during BootStart
CommandLoop:
    rcall RxByte                    ; read low byte
    mov ZL, data
    rcall RxByte                    ; read high byte
    mov ZH, data
    rcall RxByte                    ; read FCS
    rcall RxByte                    ; read SPM command
    cpse FCS, delayArg              ; no error if FCS == 0
    ; execute program memory command bit 0 unset = nop
    out SPMCSR, data
    spm
    movw r0, ZL
    rjmp CommandLoop                ; next command

; receive byte - save in data
RxByte:
    sbic UART_Port-2, UART_Rx       ; wait for start edge
    rjmp RxByte
    ldi data, 0x80                  ; bit shift counter
    ldi delayArg, RXSTART           ; 1.5 bit delay
RxBit:
    ; 6 cycles + delay
    rcall Delay3Cycle
    sbi UART_Port-1, UART_Tx        ; start Tx ACK
    ldi delayArg, RXDELAY           ; delay and clear carry
    sbic UART_Port, UART_Rx
    sec
    ror data
    brcc RxBit
    eor FCS, data
    cbi UART_Port-1, UART_Tx        ; stop Tx ACK
    ; fall into delay for stop bit duration 

; delay 3 cycles * delayArg + 4 cycles (ret instruction)
; also clears carry (subi instead of dec)
Delay3Cycle:
    subi delayArg, 1
    brne Delay3Cycle
    ret
