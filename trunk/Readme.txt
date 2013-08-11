Programming requires an SPI master that sends a binary command stream.
Protocol format starts with 1 byte for number of pages of code to download  Followed by binary stream of code consisting of 2 bytes of data followed by a 1-byte SPM command. Programmer must pause 9ms after each page to allow time for flash erase & write.  Bootloader writes a 1-byte signature (0x18), followed by echoing each byte received.

each page consists of the following sequence:
low byte, high byte, command 0b00000001 - word write
at the end of the page:
2 dummy bytes, command 0b00000011 - page erase
wait 4.5ms for page erase
2 dummy bytes, command 0b00000101 - page write
wait 4.5ms for page write

