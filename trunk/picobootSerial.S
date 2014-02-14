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
 *
 * Soft UART is used, even on parts with a hardware UART
 * PD0/PD1 are used for Rx/Tx, or PB0/PB1 for parts with no PORTD
 *
 * The protocol is a sequence of 4-byte frames:
 * data lo, data hi, command, FCS (continuous EOR)
 * data is copied to r0, r1, command is written to SPMCSR, followed
 * by the spm instruction.  If bit 6 of the command is set, r0 & r1
 * are copied to Z
 *
 * bootloader acks to programmer with a break signal before FCS 
 * which starts on even frames and ends on odd frames
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

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
    sbi PINB, 5
    ldi ZH, 30
DelayLoop:
    ; 5.9M cycles =~ .74s @ 8Mhz
    rcall Delay3Cycle               ; 256 * 3 cycles
    sbiw ZL, 1
    brne DelayLoop
    rjmp BlinkLED

.org (FLASHEND - 65)
VirtualReset:
    rjmp BlinkLED                   ; will be overwritten by programmer
BootStart:
    sbis UART_Port, UART_Rx         ; Rx high = start bootloader
    rjmp VirtualReset               ; jump to application code
    clr FCS
    sbi UART_Port-1, UART_Tx        ; set Tx line to output

    ; continuous loop for commands from programmer
    ; when upload is finished, programmer resets chip & starts app
    ; by transmitting a null byte during BootStart
CommandLoop:
    rcall RxByte                    ; read low byte
    mov r0, data
    rcall RxByte                    ; read high byte
    mov r1, data
    rcall RxByte                    ; read SPM command
    sbrs data, 6                    ; command bit 6 = set Z
    movw ZL, r0
    ; execute program memory command bit 0 unset = nop
    out SPMCSR, data
    spm
    sbi UART_Port-2, UART_Tx        ; toggle Tx break signal
    rcall RxByte                    ; read FCS
    cp  FCS, data
    breq CommandLoop                ; next command
    ; Halt on FCS error
    ; programmer will loose sync and report error
Halt:
    rjmp Halt                       ; jump to application code

; receive byte - save in data
RxByte:
    sbic UART_Port, UART_Rx         ; wait for start edge
    rjmp RxByte
    ldi data, 0x80                  ; bit shift counter
    ldi delayArg, RXSTART           ; 1.5 bit delay
RxBit:
    ; 6 cycles + delay
    rcall Delay3Cycle
    ldi delayArg, RXDELAY           ; delay and clear carry
    sbic UART_Port, UART_Rx
    sec
    ror data
    brcc RxBit
    eor FCS, data
    ; fall into delay for stop bit duration 

; delay 3 cycles * delayArg + 4 cycles (ret instruction)
; also clears carry (subi instead of dec)
Delay3Cycle:
    subi delayArg, 1
    brne Delay3Cycle
    ret
