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
 * Tx pin requires external pullup resistor (10K recommended)
 *
 * The protocol is pairs of 4-byte frames:
 * data lo, data hi, FCS (EOR), command
 * data from the first frame is copied r0, r1.  For the next frame,
 * data is copied to Z, command is written to SPMCSR, followed
 * by the spm instruction. The command for the first fame must be 0.
 *
 * bootloader acks to programmer with 0xC0 after each byte
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#define LEDPIN 2
# PB2 = CK0(pin5) on t84, SCK (pin7) on t85, SS(pin16) on t88

#ifndef PORTD
#define UART_Port PORTB
#else
#define UART_Port PORTD
#endif
#define UART_Rx 0
#define UART_Tx 1
# 7 * 3 = 21 + 6 + 8 = 35 cycles = 1 bit-time
#define RXDELAY 7
# 13 * 3 = 39 + 6 + 6.5 = 51.5 cycles = 1.5 bit-times
#define RXSTART 13
#define tmp1	r16
#define FCS	    r17
#define data    r22
#define delayArg	r18

.text
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

.section .bootloader,"ax",@progbits
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
Halt:
    rjmp Halt                       ; Halt on FCS error
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
    ; 8 cycles + delay
    rcall Delay3Cycle               ; delay and clear carry
    sbi UART_Port-1, UART_Tx        ; output mode, low 
    ldi delayArg, RXDELAY
    sbic UART_Port-2, UART_Rx
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
