# picoBoot - tiny bootloader for AVR MCUs
# @author: Ralph Doncaster
# @version: $Id$

# tested with avr-gcc version 4.3.3

#DEVICE = attiny88
DEVICE = attiny85
#DEVICE = attiny2313

CC = avr-gcc
LD = avr-ld
CFLAGS = -mmcu=$(DEVICE)
#CFLAGS += -O
CFLAGS += -nostdlib

all: picobootSerial.bin

picoboot.hex: picoboot.bin
	avr-objcopy -j .text -j .data -O ihex $< $@

picoboot.bin: picoboot.o
	$(CC) $(CFLAGS) -o $@ $<

picobootSerial.bin: picobootSerial.o
	$(CC) $(CFLAGS) -o $@ $<

picoboot.bin: picoboot
	avr-objcopy -j .text -j .data -O binary $< $@

.S.o:
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

clean:
	rm picoboot.o picoboot

