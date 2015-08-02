# set DEVICE, ADDRESS, & FUSEFLAGS then run
# make; make flash

# same lfuse options for m168 & m328
FUSEFLAGS = -U lfuse:w:0xff:m

DEVICE = atmega328p
ADDRESS = 0x7E00 
FUSEFLAGS += -U hfuse:w:0xde:m

#DEVICE = atmega168p
#ADDRESS = 0x3F00 
#FUSEFLAGS += -U efuse:w:0x06:m

TARGET = picobootSTK500

LDFLAGS = -nostartfiles -Wl,-section-start=.bootloader=$(ADDRESS)

include ../avr.mk


