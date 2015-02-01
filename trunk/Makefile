# picoBoot - tiny bootloader for AVR MCUs
# @author: Ralph Doncaster
# @version: $Id$

# tested with avr-gcc version 4.3.2 and 4.8.1

#DEVICE = attiny88
#DEVICE = attiny85
#DEVICE = attiny84
#DEVICE = attiny2313
DEVICE = atmega328
CPU_SPEED = 16000000
#CPU_SPEED = 8000000
# calculate picoboot bootloader address
ADDRESS:=$(shell echo $(DEVICE)|cut -c7| awk '{ printf("0x%x", $$1 * 1024 -66) }')

CC = avr-gcc
LD = avr-ld
CFLAGS = -mmcu=$(DEVICE) -DF_CPU=$(CPU_SPEED)
#CFLAGS += -O
CFLAGS += -nostdlib

%.hex: %
	avr-objcopy -O ihex $< $@
#	avr-objcopy -j .text -j .data -O ihex $< $@

all: picobootSerial.hex

.elf.hex:
	avr-objcopy -O ihex $< $@
#	avr-objcopy -j .text -j .data -O ihex $< $@

picobootSerial.hex: picobootSerial.o

picobootSerial.hex: picobootSerial.elf
	avr-objcopy -O ihex $< $@

picobootSTK500.hex: picobootSTK500.elf
	avr-objcopy -O ihex $< $@

picoboot.bin: picoboot.o
	$(CC) $(CFLAGS) -o $@ $<

picobootSerial.elf: picobootSerial.o
	$(CC) $(CFLAGS) -Wl,-section-start=.bootloader=$(ADDRESS) -o $@ $<

picobootSTK500.elf: picobootSTK500.o
	$(CC) $(CFLAGS) -Wl,-section-start=.bootloader=0x7E00 -o $@ $<

picoboot.bin: picoboot
	avr-objcopy -j .text -j .data -O binary $< $@

.S.o:
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

clean:
	rm *.o *.elf

