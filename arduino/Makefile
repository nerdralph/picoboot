# set DEVICE, ADDRESS, & FUSEFLAGS then run
# make; make flash

# same lfuse options for m168 & m328
FUSEFLAGS = -U lfuse:w:0xff:m
# F7 = full-swing oscillator option
#FUSEFLAGS = -U lfuse:w:0xf7:m

DEVICE = atmega328p
ADDRESS = 0x7E00 
FUSEFLAGS += -U hfuse:w:0xde:m

#DEVICE = atmega168p
#ADDRESS = 0x3F00 
#FUSEFLAGS += -U efuse:w:0x06:m

TARGET = picobootArduino

LDFLAGS = -nostartfiles -Wl,-section-start=.bootloader=$(ADDRESS)

include ../avr.mk
