/* AVR305 half-duplex serial uart implementation in 28 instructions
 * hard-coded for 81N, 115.2kbps @8Mhz = 69.4 cycles/bit
 * @16Mhz = 139 cycles/bit
 * @author: Ralph Doncaster
 * @version: $Id$
 */

#define bitcnt r19
#define delayArg r24

; transmit byte contained in rSOURCE - 12 instructions
TxByte:
	sbi UART_DDR, UART_Tx			; set Tx line to output
	ldi bitcnt, 10					; 1 start + 8 bit + 1 stop
	com rSOURCE						; invert and set carry
TxLoop:
	; 9 cycle loop
	brcc tx1
	cbi UART_Port, UART_Tx 			; transmit a 0
tx1:
	brcs TxDone
	sbi UART_Port, UART_Tx 			; transmit a 1
TxDone:
	ldi delayArg, 18				; 3 * 18 - 1 = 53 cycles
	; ldi delayArg, 41 for 16Mhz
	rcall Delay3Cycle
	lsr rSOURCE
	dec bitcnt
	brne TxLoop
	; fall into delay for stop bit = 1 = idle state

; delay (3 cycle * delayArg) -1 + 4 cycles (ret instruction)
; also clears carry (subi instead of dec) to save 1 instr in RxBit
Delay3Cycle:
	subi delayArg, 1
	brne delay3Cycle
	ret

; receive byte into rDEST - 11 instructions
RxByte:
	ldi rDEST, 0x80					; bit shift counter
WaitStart:
	sbic UART_Port, UART_Rx			; wait for start edge
	rjmp WaitStart
	ldi delayArg, 32				; 1.5 bit delay
	;ldi delayArg, 67 for 16Mhz
RxBit:
	rcall Delay3Cycle				; delay and clear carry
	; 6 cycle loop
	; adiw delayArg, 19 clears carry 
	ldi delayArg, 19				; 3 * 19 - 1 = 56 cycles
	;ldi delayArg, 40 for 16Mhz
	sbic UART_Port, UART_Rx
	sec
	ror rDEST
	brcc RxBit
	; fall into UartInit

UartInit:
	sbi UART_Port, UART_Tx			; set Tx line to idle state (high)
	ret
