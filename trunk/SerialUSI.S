/* USI half-duplex serial uart implementation
 * hard-coded for 81N, 115.2kbps @8Mhz = 69.4 cycles/bit
 * @16Mhz = 139 cycles/bit
 * @author: Ralph Doncaster
 * @version: $Id$
 */

; transmit byte in USIDR - 8 instructions
; need to init USICR |= (1<<USIWM0) for 3-wire mode
; does MSB first - need to reverse bits for UART LSB first
TxByte:
    ldi bitcnt, 9                   ; 8 bit + 1 stop (USIDR = 1 after 8 bits)
    cbi UART_Port, UART_Tx          ; transmit a 0 (START)
    sbi USICR, USIWM0
TxLoop:
    rcall Delay1Bit ; 17 * 3 cycle
    ; 4 cycle loop
    sbi USICR, USICLK ; shift data
TxDone:
    dec bitcnt
    brne TxLoop
; stop bit = 1 = idle
    ret

;AVR 305 tx loop: 8 cycles + delay
;USI-assisted code: 5 cycles + delay

; receive byte into rDEST - 10 instructions
RxByte:
    sbic UART_Port, UART_Rx         ; wait for start edge
    rjmp RxByte
    ldi bitcnt, 8
    ldi delayArg, 8                 ; half bit delay
    rcall Delay3Cycle               ; get to middle of start bit
RxBit:
    rcall Delay1Bit
    ; 4 cycle loop
    sbi USICR, USICLK ; shift data
    dec bitcnt
    brne RxBit
    ; ignore stop bit
    ret

;reverse bits in r24, store in r25 - 4 instructions
BitReverse:
    ldi r25, 1
BitLoop:
    ror r24
    rol r25
    brcc BitLoop
    ret
