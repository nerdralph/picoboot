/* test program for bootloader - blinks LED at ~1Hz */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

#define LEDPIN 5

.text
    sbi DDRB, LEDPIN
Blink:
    sbi PINB, LEDPIN
    ldi ZH, 40
DelayLoop:
    ; 7.8M cycles =~ .5s @ 16Mhz
    rcall Delay3Cycle               ; 256 * 3 cycles
    sbiw ZL, 1
    brne DelayLoop
    rjmp Blink

; delay 3 cycles * r24 + 4 cycles (ret instruction)
; also clears carry (subi instead of dec)
Delay3Cycle:
    subi r24, 1
    brne Delay3Cycle
    ret

