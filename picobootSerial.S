/* picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
 * TTL serial version - 81N, 115.2kbps @8Mhz
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * http://symlink.dk/electro/m163boot/
 * http://github.com/baerwolf/USBaspLoader
 * AVR305 half-duplex serial uart
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#define BOOTPIN	PINB0
#define UART_Port PORTB
#define UART_Tx PINB1
#define UART_Rx PINB2
#define tmp1	r16
#define bitcnt	r17
#define delayArg	r18

#define LOWBYTE(word) (word & 0xff)

.text
.org 0x0000
IntVectors:
	rjmp BootStart 

; .org _VECTORS_SIZE
;.org (FLASHEND - SPM_PAGESIZE - 1)
AppStart:
	rjmp 0							; dummy vector to be overwritten
; .org (FLASHEND - SPM_PAGESIZE + 1)
; beginning of last page of memory
BootStart:
	sbis PINB, BOOTPIN 				; run bootloader if BOOTPIN high
	rjmp AppStart					; jump to application code
	sbi DDRB, DDB1					; set Tx line to output

; Z pointer starts at program address 0
CommandLoop:
    rcall SPIxfer					; read low byte
    mov r0, tmp1
    rcall SPIxfer					; read high byte
	mov r1, tmp1

    rcall DoSPM
	sbrc tmp1, 6					; command bit 6 = increment
    adiw ZL, 2						; inc Z pointer by one word
	sbrc tmp1, 7					; command bit 7 = set Z 
	movw ZL, r0						; set Z pointer
	tst tmp1
    brne CommandLoop				; not done
	; done programming - bootloader falls into SPIxfer forever loop

; transmit byte contained in r3 
TxByte:
	ldi bitcnt, 10					; 1 start + 8 bit + 1 stop
	ldi delayArg, 18				; delay
	com r3
	sec
TxLoop:
	brcc tx1
	cbi UART_Port, UART_Tx 			; transmit a 0
	rjmp TxDone
tx1:
	sbi UART_Port, UART_Tx 			; transmit a 1
	nop
TxDone:
	rcall delay3Cycle				; delay 54 + 7 cycles
	lsr r3
	dec bitcnt
	brne TxLoop
Return:
	ret

; receive byte into r3 
RxByte:
	sbic UART_Port, UART_Rx			; wait for start edge
	rjmp RxByte
	ldi delayArg, 8					; half bit delay
	rcall delay3Cycle				; get to middle of start bit
	ldi delayArg, 18				; 1 bit delay
RxBit:
	rcall delay3Cycle				; wait 1 bit period
	clc
	sbic UART_Port, UART_Rx
	sec
	dec bitcnt
	breq Return
	ror r3
	rjmp RxBit

; execute program memory command 
DoSPM:
	rcall SPIxfer 
    out SPMCSR, tmp1
    spm
    ret

; delay 3 cycles * delayArg + 4 cycles (ret instruction)
Delay3Cycle:
	mov tmp1, delayArg
delayLoop:
	dec tmp1
	brne delayLoop
	ret
