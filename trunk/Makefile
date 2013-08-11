# picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
# @author: Ralph Doncaster
# @version: $Id$

# any AVR MCUs with USI should work
CC = avr-gcc
DEVICE = attiny85
CFLAGS = -Os -mmcu=$(DEVICE)

all: boot.bin

boot.bin: boot.o
	avr-objcopy -j .text -j .data $< $@

#boot.o:
#	avr-gcc $(CFLAGS) -c -o boot.o boot.S

.S.o:
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

