/* picoBootSTK500 - arduino compatible bootloader
 *
 * TTL serial version - 81N, 115.2kbps
 * @author: Ralph Doncaster
 * @version: $Id$
 * code ideas from:
 * http://jtxp.org/tech/tinysafeboot_en.htm
 * https://code.google.com/p/optiboot/
 * https://github.com/whitequark/vuxboot
 * 
 * This bootloader is an implementation of the Arduino bootloader,
 * a stripped-down STK500 protocol, in assembler.
 * Optiboot is the primary guide for this bootloader 
 * protocol trace from Bald Wisdom blog
 * http://baldwisdom.com/bootloading/ 
 */

/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0 

/* AVR CPU definitions based on -mmcu flag */
#include <avr/io.h>

/* work-around for defines missing in avr-libc - bug #42957  
 */
#ifndef SPMEN
#define SPMEN 0
#endif

#ifdef DEBUG
/* for simulavr debugging */
#   define debug_output_port 0x31
#   define debug_input_port 0x32
#endif

#define LEDPIN 5
#define LEDPORT PORTB

#include "stk500.h"

#define TmpWord r14
#define rCOMMAND r16
#define rTEMP r17
#define PgLen r18
#define MemType r19

.text
Blink:
    sbi PINB, LEDPIN
    ldi ZH, 60
DelayLoop:
    ; 11.8M cycles =~ .74s @ 16Mhz
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

.section .bootloader,"ax",@progbits
; use -WL,--section-start=.bootloader=0xXf00

Boot:
    in rTEMP, MCUSR
	cpi rTEMP, (1<<EXTRF|1<<PORF)   ; run bootloader on external reset
    breq CommandLoop
    sbr rTEMP, PORF
    out MCUSR, rTEMP                ; ensure PORF set in case of dbl reset
	rjmp StartApp                   ; jump to application code

BootLoader:
    cbr rTEMP, PORF
    out MCUSR, rTEMP                ; clear PORF to show bootloader run 
    sbi LEDPORT, LEDPIN             ; light LED dimly during bootloader

    ; inialize UART IO base pointer
    ldi YL, lo8(UCSR0A)
    clr YH
    ; initialize UART
    ldi rTEMP, (1<<U2X0)
    st Y, rTEMP
    ldi rTEMP, 16                   ; 115200kbps @16Mhz
    std Y+(UBRR0L - UCSR0A), rTEMP
    ldi rTEMP, (1<<RXEN0) | (1<<TXEN0)
    std Y+(UCSR0B - UCSR0A), rTEMP

CommandLoop:
	rcall RxByte					; read command
	mov rCOMMAND, r24
	ldi r26, STK_INSYNC 
	rcall TxByte                    ; all responses start with INSYNC

	cpi rCOMMAND, STK_LOAD_ADDRESS
	brne Universal
	rcall RxByte
	mov ZL, r24
	rcall RxByte
	mov ZH, r24                     ; Z stores address for page load
    lsl ZL
    rol ZH                          ; convert from word to byte address

Universal:
	cpi rCOMMAND, STK_UNIVERSAL
	brne GetParam
    ; command ignored - return dummy 0x00
    clr r26
    rcall TxByte

GetParam:
	cpi rCOMMAND, STK_GET_PARAMETER
	brne ReadSig
    ; return 0x03 for all parameters - Optiboot comments say
    ; its enough to keep Avrdude happy
    ; also means 03 is reply to major and minor version
    ; looking at the Avrdude stk500 code I think it may be safe to return
    ; 0x00 and comine this response with the STK_UNIVERSAL response
    ; to save 2 instructions
    ldi r26, 0x03
    rcall TxByte

ReadSig:
	cpi rCOMMAND, STK_READ_SIGN
	brne Quit
    ldi r26, SIGNATURE_0
    rcall TxByte
    ldi r26, SIGNATURE_1
    rcall TxByte
    ldi r26, SIGNATURE_2
    rcall TxByte

Quit:
	cpi rCOMMAND, STK_LEAVE_PROGMODE
	brne ProgPage
	rjmp StartApp

ProgPage:
	cpi rCOMMAND, STK_PROG_PAGE
	brne ReadPage
    rcall GetPageParams
    brne Default                    ; only flash supported
    movw TmpWord, ZL                ; save Z
PageFill:
	rcall RxByte
	mov r0, r24                     ; word low byte 
	rcall RxByte
	mov r1, r24                     ; word high byte 
    ldi rTEMP, (1<<SPMEN)           ; fill page buffer
	rcall DoSPM
	adiw ZL, 2                      ; increment Z pointer
	subi PgLen, 2
	brne PageFill
    movw ZL, TmpWord                ; restore Z
    ldi rTEMP, (1<<PGERS)|(1<<SPMEN)    ;erase page
	rcall DoSPM
    ldi rTEMP, (1<<PGWRT)|(1<<SPMEN)    ;write page
	rcall DoSPM

ReadPage:
	cpi rCOMMAND, STK_READ_PAGE
    brne Default 
    rcall GetPageParams
    brne Default                    ; only flash supported
ReadFlashByte:
	lpm r26, Z+
	rcall TxByte
	dec PgLen
	brne ReadFlashByte

Default:
    ; read to EOP
	rcall RxByte
    cpi r24, CRC_EOP
    brne Default					; read until EOP
	ldi r26, STK_OK
	rcall TxByte                    ; reply OK
    rjmp CommandLoop

; get length and flash type for write or read page
GetPageParams:
	rcall RxByte                    ; ignore block size hi byte
	rcall RxByte
	mov PgLen, r24                  ; block size
	rcall RxByte					; memory type
    cpi r24, 'F'                    ; check for memtype flash
    ret


DoSPM:
  out SPMCSR, rTEMP
  spm
  ret

/* UART code */

; transmit byte contained in r26
TxByte:
#ifdef DEBUG
    out debug_output_port, r26
    ret    
#endif
    ld rTEMP, Y
    sbrs rTEMP, UDRE0
    rjmp TxByte
    std Y+(UDR0 - UCSR0A), r26
	ret

; receive byte into r24
RxByte:
#ifdef DEBUG
    in r24, debug_input_port
    ret    
#endif
    ld rTEMP, Y
    sbrs rTEMP, RXC0
    rjmp RxByte
    ldd r24, Y+(UDR0 - UCSR0A)
    ret

; set registers to reset state then start app
StartApp:
    ; reset USART
    sbi LEDPORT, LEDPIN             ; turn off LED
; slide into reset vector at address 0x0000
