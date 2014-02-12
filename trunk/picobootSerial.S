/* picoBoot - tiny bootloader for AVR MCUs
 * TTL serial version - 81N, 115.2kbps @8Mhz, 230.4kbps@16Mhz
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
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#ifndef PORTD
#define UART_Port PORTB
#else
#define UART_Port PORTD
#endif
#define UART_Rx 0
#define UART_Tx 0
#define TXSTART 21
; 3 * 20 - 1 = 62 cycles + 7 call/ret + 3 cycles = 69
#define RXDELAY 19
; 3 * 19 - 1 = 56 cycles + 7 call/ret + 6 loop = 69
#define RXSTART 31
#define tmp1	r16
#define data    r22
#define delayArg	r18

.text
.org 0x0000
    rjmp BootStart 

.org (FLASHEND - SPM_PAGESIZE -1)
VirtualReset:
    rjmp BootStart                  ; will be overwritten by programmer
; beginning of last page of memory
BootStart:
    in  tmp1, MCUSR
    sbrs tmp1, EXTRF                ; run bootloader on EXTRF 
    rjmp VirtualReset               ; jump to application code
    rcall RxByte
    cpi data, (SIGNATURE_1 ^ SIGNATURE_2)
    brne VirtualReset               ; start application if no match
    ; ACK to programmer with break
    sbi UART_Port-1, UART_Tx		; set Tx line to output
CommandLoop:

    rcall RxByte					; read low byte
    mov r0, data
    rcall RxByte					; read high byte
    mov r1, data
    rcall RxByte					; read SPM command
    cpse delayArg, data             ; delayArg = 0 after RxByte
    movw r0, ZL                     ; command 0 = set Z
; execute program memory command - 0 = nop
    out SPMCSR, data
    spm
    sbi UART_Port-2, UART_Tx		; toggle Tx break
    rjmp CommandLoop				; next command

; receive byte - save in data
RxByte:
    sbic UART_Port, UART_Rx			; wait for start edge
    rjmp RxByte
    ldi data, 0x80                  ; bit shift counter
    ldi delayArg, RXSTART           ; 1.5 bit delay
RxBit:
    ; 6 cycles + delay
    rcall Delay3Cycle
    ldi delayArg, RXDELAY
    in tmp1, UART_Port
    ror tmp1
    ror data
    brcc RxBit
    ; fall into delay for stop bit = 1 = idle state

; delay 3 cycles * delayArg + 4 cycles (ret instruction)
Delay3Cycle:
    dec delayArg
    brne Delay3Cycle
    ret
