picobootArduino release notes

Autobaud works best with baud rates within 1% of USART supported rates.
For example, with a 16Mhz oscillator and a UBRR value of 16, the actual baud
rate is 117,650bps.  The next closest baud rate to 115,200 is with a UBRR
value of 17, generating a baud rate of 111,111bps.  If the autobaud picks
17, that can result in errors with some USB-TTL adapters.  The recommended
baud rate is 250kbps, which is reliable at 16Mhz, 12Mhz, and with the internal
8Mhz oscillator.  While the CH340 and CP2102 support 250 and 500kbps under
Windows, most PL2303HX do not support this speed.  Linux does support custom
buad rates with the PL2303.

The default timeout is about 2.5 seconds, after which the application code
will run if there is no communication received from avrdude.  During the
timeout period, the Tx line (PD1) will stay low, which will light the Rx LED
on the USB-TTL adapter.

