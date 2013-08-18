# picoBoot - tiny bootloader for AVR MCUs - ATtiny85 and others
# @author: Ralph Doncaster
# @version: $Id$

# any AVR MCUs with USI should work
DEVICE = attiny85

CC = avr-gcc
CFLAGS = -Os -mmcu=$(DEVICE)

all: boot.bin boot.hex

boot.hex: boot.o
	avr-objcopy -j .text -j .data -O ihex $< $@

boot: boot.o
	$(CC) -o $@ $<

boot.bin: boot
	avr-objcopy -j .text -j .data -O binary $< $@

.S.o:
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

