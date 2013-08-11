Programming requires an SPI master that sends a binary command stream.
Protocol format starts with 1 byte for number of pages of code to download  Followed by binary stream of code consisting of 2 bytes of data followed by a 1-byte command. Programmer must pause 9ms after each page to allow time for flash erase & write.  Bootloader writes a 1-byte signature (0x18), followed by echoing each byte received.

command bits:
0 = Store Program Memory Enable
1 = Page Erase  - SPMCSR settings
2 = Page Write /
3-5: must be 0
6 = load pointer after SPM
7 = increment word pointer after SPM

each page typically consists of the following sequence:
low byte, high byte, command 0b10000001 - buffer write, pointer += 2
at the end of the page:
2 bytes page pointer, command 0b01000011 - page erase
 the page pointer is to setup for subsequent page write
wait 4.5ms for page erase
2 bytes pointer, command 0b01000101 - page write
 the page pointer is to setup for subsequent page write
wait 4.5ms for page write

