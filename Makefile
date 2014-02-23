# picoBoot - tiny bootloader for AVR MCUs
# @author: Ralph Doncaster
# @version: $Id$

# tested with avr-gcc version 4.3.2

#DEVICE = attiny88
#DEVICE = attiny85
DEVICE = attiny84
#DEVICE = attiny2313
# calculate bootloader address
ADDRESS:=$(shell echo $(DEVICE)|cut -c7| awk '{ print $$1 * 1024 -66 }')

CC = avr-gcc
LD = avr-ld
CFLAGS = -mmcu=$(DEVICE)
#CFLAGS += -O
CFLAGS += -nostdlib

all: picobootSerial.hex

.elf.hex:
	avr-objcopy -O ihex $< $@
#	avr-objcopy -j .text -j .data -O ihex $< $@

picobootSerial.hex: picobootSerial.o

picobootSerial.hex: picobootSerial.elf
	avr-objcopy -O ihex $< $@

picoboot.bin: picoboot.o
	$(CC) $(CFLAGS) -o $@ $<

picobootSerial.elf: picobootSerial.o
	$(CC) $(CFLAGS) -Wl,-section-start=.bootloader=$(ADDRESS) -o $@ $<

picoboot.bin: picoboot
	avr-objcopy -j .text -j .data -O binary $< $@

.S.o:
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

clean:
	rm *.o *.elf

