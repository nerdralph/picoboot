# set DEVICE, ADDRESS, & FUSEFLAGS then run
# make; make flash

# same lfuse options for m168 & m328
FUSEFLAGS = -U lfuse:w:0xff:m

DEVICE = atmega328p
ADDRESS = 0x7E00 
FUSEFLAGS += -U hfuse:w:0xde:m

# for an atmega168p masquerading as a m328p, set DEVICE = atmega328p, 
# and use the ADDRESS and FUSEFLAGS for the 168p
# this allows you to use Uno as the target in the Arduino IDE for both
# m168p and m328p devices (as long as the code fits in 16128 bytes)
#DEVICE = atmega168p
#ADDRESS = 0x3F00 
#FUSEFLAGS += -U efuse:w:0x06:m

TARGET = picobootSTK500

LDFLAGS = -nostartfiles -Wl,-section-start=.bootloader=$(ADDRESS)

include ../avr.mk


