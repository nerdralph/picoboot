/* tinyBoot - reset vector replacement code for ATtiny series
 * @author: Ralph Doncaster
 * @version: $Id: picoboot.S 30 2013-09-01 15:08:10Z ralphdoncaster@gmail.com $
 */

#define DATAPAGE (FLASHEND - 127 - SPM_PAGESIZE)

#define spmArg	r17

#define dataPageLo r18
#define dataPageHi r19
#define chipErased r22
#define appJumpLo r24
#define appJumpHi r25

; save application boot vector by writing to DATAPAGE
SaveAppStart:
	movw ZL, dataPageLo
	movw r0, appJumpLo 
	rcall DoSPM
	movw appJumpLo, r2				; zero appJump	
	rjmp WritePage
	
; write page buffer to flash - jumps to CommandLoop when done
WritePage:
	rcall ErasePage
	ldi spmArg, ((1<<PGWRT)|(1<<SPMEN)) 
	rcall DoSPM
	; check if AppJump needs to be written
	sbiw appJumpLo, 0
	brne CommandLoop
	rjmp SaveAppStart

ChipErase:
	ldi chipErased, (1<<PGERS)
	movw ZL, dataPageLo
; fall into ErasePage

; check Z pointer to see if it points to bootloader section
ErasePage:
	mov spmArg, chipErased
	;movw tmpWordLo, ZL
	; subtract bootloader start address
	;subi tmpWordLo, lo8(DATAPAGE)
	;sbci tmpWordHi, hi8(DATAPAGE)
	cpi ZL, hi8(DATAPAGE)		; 256 byte protection area
	brcs DoSPM
	ret								; block write to bootloader section

DoSafeSPM:
    sbiw ZL, 0
	brne DoSPM
	movw appJumpLo, r0				; save application starting opcode
	; now replace r0, r1 with current bootload vector
	lpm r0, Z+
	lpm r1, Z
	; fall through to DoSPM
DoSPM:
	ori spmArg, (1<<SPMEN) 
    out SPMCSR, spmArg
    spm
	ret

