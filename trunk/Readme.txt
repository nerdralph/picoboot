Programming requires an SPI master that sends a binary command stream.
Protocol format starts with 1 byte for number of pages of code to download  Followed by binary stream of code consisting of 2 bytes of data followed by a 1-byte command. Programmer must pause 9ms after each page to allow time for flash erase & write.  Bootloader transmits 1-byte data from lpm each command cycle.  i.e. the 1st 3 bytes transmitted are 0, then the contents of memory address 0 (boot vector) 

last word of page before bootloader stores application start vector

command bits:
0 = Store Program Memory Enable
1 = Page Erase  - SPMCSR settings
2 = Page Write /
3-5: must be 0
6 = increment word pointer after SPM
7 = load pointer after SPM

each page typically consists of the following sequence:
low byte, high byte, command 0b01000001 - buffer write, pointer += 2

for last word in page, don't increment Z:
low byte, high byte, command 0b00000001 - buffer write

at the end of the page:
2 bytes page pointer, command 0b10000011 - page erase
 the page pointer is to setup for subsequent page write
wait 4.5ms for page erase
2 bytes pointer, command 0b01000101 - page write
 the page pointer is to setup for subsequent buffer write
wait 4.5ms for page write

To read memory, send the set pointer command (0b10000000).
Data comes after next command (i.e. 1 command cycle latency)

3 zero bytes received signify end of programming

