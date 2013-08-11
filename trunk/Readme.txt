Programming requires an SPI master that sends a binary command stream.
Protocol format starts with 1 byte for number of pages of code to download  Followed by binary stream of code consisting of 2 bytes of data followed by a 1-byte SPM command. Programmer must pause 9ms after each page to allow time for flash erase & write.  Bootloader writes a 1-byte signature (0x18), followed by echoing each byte received.

