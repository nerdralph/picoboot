# picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
# @author: Ralph Doncaster
# @version: $Id$

# tested with avr-gcc version 4.3.3

# any AVR MCUs with USI should work
DEVICE = attiny85

CC = avr-gcc
LD = avr-ld
CFLAGS = -Os -mmcu=$(DEVICE)
#CFLAGS +=

all: boot.bin boot.hex

boot.hex: boot.o
	avr-objcopy -j .text -j .data -O ihex $< $@

boot: boot.o
	$(LD) -o $@ $<

boot.bin: boot
	avr-objcopy -j .text -j .data -O binary $< $@

.S.o:
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

clean:
	rm boot.o boot
