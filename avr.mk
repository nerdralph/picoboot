# avr.mk avr common makefile

# define the following, then include avr.mk
# DEVICE = atmega328p
# CPU_SPEED = 16000000
# PROGRAMMER = usbasp -B 4
PROGRAMMER ?= usbasp -B 4

# or export DEVICE=atxxxx in shell 
# export TARGET=app

CC = avr-gcc -mmcu=$(DEVICE) -DF_CPU=$(CPU_SPEED) $(CCFLAGS)

CFLAGS += -ffunction-sections -Wl,--gc-sections
CFLAGS += -Os -Wall
CFLAGS += -Wno-main
CFLAGS += --std=gnu99

LDFLAGS += -mrelax
LDFLAGS += -flto
LDFLAGS += -mpmem-wrap-around

all: $(TARGET) $(TARGET).hex

%.hex: %
	avr-objcopy -O ihex $< $@

flash:  $(TARGET).hex
	avrdude -C /etc/avrdude.conf -p $(DEVICE) -c $(PROGRAMMER) -U flash:w:$(TARGET).hex $(FUSEFLAGS)

# lfuse 0xe2 = 8Mhz internal RC, ckdiv1, 64ms SUT
# for t84 & t88 - not for all AVRs
fuses8mrc:
	avrdude -C /etc/avrdude.conf -p $(DEVICE) -c $(PROGRAMMER) -U lfuse:w:0xe2:m

clean:
	rm *.o $(TARGET) $(TARGET).hex
