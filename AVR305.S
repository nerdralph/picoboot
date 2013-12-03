/* AVR305 half-duplex serial uart implementation
 * hard-coded for 81N, 115.2kbps @8Mhz
 * @author: Ralph Doncaster
 * @version: $Id$
 */

#define tmp1 r18
#define bitcnt r19
#define delayArg r24

; transmit byte contained in rSOURCE
TxByte:
	ldi bitcnt, 10					; 1 start + 8 bit + 1 stop
	ldi delayArg, 18				; delay
	com rSOURCE
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
	lsr rSOURCE
	dec bitcnt
	brne TxLoop
Return:
	ret

; receive byte into rDEST
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
	ror rDEST
	rjmp RxBit

; delay 3 cycles * delayArg + 4 cycles (ret instruction)
Delay3Cycle:
	mov tmp1, delayArg
delayLoop:
	dec tmp1
	brne delayLoop
	ret
