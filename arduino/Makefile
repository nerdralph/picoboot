# set DEVICE, ADDRESS, & FUSEFLAGS then run
# make; make flash

# same lfuse options for m88/m168/m328
FUSEFLAGS = -U lfuse:w:0xFF:m
# F7 = full-swing oscillator option
FUSEFLAGS = -U lfuse:w:0xF7:m

#DEVICE = atmega328p
#ADDRESS = 0x7E00
#FUSEFLAGS += -U hfuse:w:0xde:m

#DEVICE = atmega168p
#ADDRESS = 0x3F00
#FUSEFLAGS += -U efuse:w:0x06:m

DEVICE = atmega8
ADDRESS = 0x1F00
FUSEFLAGS += -U efuse:w:0x06:m
FUSEFLAGS += -U hfuse:w:0xdf:m

TARGET = picobootArduino

LDFLAGS = -nostartfiles -Wl,-section-start=.bootloader=$(ADDRESS)

include ../avr.mk
