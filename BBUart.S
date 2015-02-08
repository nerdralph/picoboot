/* optimized half-duplex serial uart implementation - 26 instructions
 * bit-bang RxByte based on AVR305, TxByte original code
 * hard-coded for 81N, 115.2kbps @8Mhz = 69.4 cycles/bit
 * @16Mhz = 139 cycles/bit
 * @author: Ralph Doncaster 2014
 * @version: $Id$
 * macro definition help from Joey Morin
 */

#define UART_Port PORTB
#define UART_Tx 0
#define UART_Rx 1
#define BAUD_RATE 115200
#define F_CPU 8000000

#define DIVIDE_ROUNDED(NUMERATOR, DIVISOR) ((((2*(NUMERATOR))/(DIVISOR))+1)/2)

; txbit takes 3*RXDELAY + 14 cycles
#define delayArg r22
;define TXDELAY 18
#define BIT_CYCLES DIVIDE_ROUNDED(F_CPU,BAUD_RATE) 
#define TXDELAY DIVIDE_ROUNDED(BIT_CYCLES - 14, 3)

; rxbit takes 3*RXDELAY + 12 cycles
#define RXSTART_CYCLES DIVIDE_ROUNDED(3*F_CPU,2*BAUD_RATE) 
#define RXSTART DIVIDE_ROUNDED(RXSTART_CYCLES - 12, 3)
#define RXDELAY DIVIDE_ROUNDED(BIT_CYCLES - 12, 3)

; transmit byte contained in r24 - 12 instructions
; AVR305 has 1 cycle of jitter per bit, this has none
TxByte:
	sbi UART_Port-1, UART_Tx		; set Tx line to output
	cbi UART_Port, UART_Tx			; start bit
	in r0, UART_Port
	ldi r25, 3						; stop bit & idle state
TxLoop:
	; 8 cycle loop + delay
	ldi delayArg, TXDELAY
	rcall Delay3Cycle				; delay + 3 cycles for rcall
	bst r24, 0						; store lsb in T
	bld r0, UART_Tx
	lsr r25
	ror r24							; 2-byte shift register
	out UART_Port, r0
	brne TxLoop
	ret

; receive byte into r24 - 11 instructions
RxByte:
	ldi r24, 0x80					; bit shift counter
WaitStart:
	sbic UART_Port-2, UART_Rx		; wait for start edge
	rjmp WaitStart
	ldi delayArg, RXSTART			; 1.5 bit delay
RxBit:
	rcall Delay3Cycle				; delay and clear carry
	; 6 cycle loop
	ldi delayArg, RXDELAY 
	sbic UART_Port-2, UART_Rx
	sec
	ror r24
	brcc RxBit
	; fall into delay for stop bit

; delay (3 cycle * delayArg) -1 + 4 cycles (ret instruction)
; also clears carry (subi instead of dec) to save 1 instr in RxBit
Delay3Cycle:
	subi delayArg, 1
	brne Delay3Cycle
	ret
