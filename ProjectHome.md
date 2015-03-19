Picoboot is the smallest available bootloader for 8-bit <a href='http://www.atmel.com/products/microcontrollers/avr/tinyavr.aspx'>tinyAVR microcontrollers</a>.  A virtual reset vector implementation means picoboot does not require hardware bootloader support.  The bootloader communicates via TTL serial at 230.4kbps using a software UART implemented in  hand-coded assembler.  Less than two seconds are required to upload and write 5KB to flash.  Flash reads are unsupported, so picoboot verifies every 3 bytes received with a 1-byte check sequence.

The bootloader is started when a serial idle signal is detected on the Rx pin (PB0 on the ATtiny84 and ATtiny85, PD0 on the ATtiny88).  The bootloader will signal it is active on the Tx pin (PB1), which will turn on the Rx LED on <a href='http://nerdralph.blogspot.ca/2013/09/clone-pl-2303hx-usb-to-ttl-serial.html'>TTL serial adapters</a>.  Picoboot will then wait for avrdude to start.  Once the flash has been written, the Rx pin can be disconnected and the AVR reset to cause it to run the newly-flashed code.

Picoboot requires no SRAM, and supports parts with up to 8KB of flash.

2014/02/26:
Beta-1 release of picoboot and <a href='https://code.google.com/p/picoboot-avrdude/'>avrdude fork supporting picoboot</a>.
8Mhz builds for attiny84/85 and attiny88 are provided.  They should also work on 16Mhz parts provided the baud rate in avrdude.conf is changed from 230400 to 460800.

2014/02/19:
Alpha release of picoboot and <a href='https://code.google.com/p/picoboot-avrdude/'>avrdude fork supporting picoboot</a>.  Builds for attiny84/85 and attiny88 as well avrdude with picoboot support are available here:
http://162.248.164.251/files/

2014/02/08:
After rewriting the AVR305 soft UART, I've developed an AVR software UART that takes just 13 instructions.  With a simplified download protocol, I have written a serial bootloader that fits exactly in 32 words.  I could not implement an existing protocol in 32 words, so it will require an update to avrdude.  I plan to have that completed (including support for my <a href='http://nerdralph.blogspot.ca/2014/02/zero-wire-serial-auto-reset-for-arduino.html'>zero-wire auto-reset hardware</a>) soon.

2013/08/28:
I've changed the design of picoboot to be a transparent bootloader.  That means it uses the Serial Programming Instruction Set as documented in the AVR datasheet.  Although more code space is required (128 bytes), it will with existing programmers. And just like the hardware SPI programming interface, it is fast.

2013/08/11:
The smallest possible bootloader for the ATtiny85.  The flash page size is 32 words, so that is the smallest feasible bootloader size.
The (now obsolete) prototype uses SPI slave mode with a simple binary stream protocol for code downloading.

Version 0.1 alpha release: https://sites.google.com/site/ralphdoncaster/home/files/picoboot-0.1.tgz
This version compiles to only 54 bytes and is intended only as a proof-of-concept and a template for small bootloaders.