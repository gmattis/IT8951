# cython: language_level=3
# cython: profile=True

import time

from libbcm2835._bcm2835 import *


class SPI:

    # Reference them from there instead of the constants
    # Remove them from constants.py as well
    def __init__(self, HRDY=24, CS=8, RESET=17):
        init_rtn = bcm2835_init()
        if init_rtn != 1:
            raise RuntimeError("Error in bcm2835_init")

        self.HRDY = HRDY
        self.CS = CS
        self.RESET = RESET

        bcm2835_spi_begin()
        bcm2835_spi_setBitOrder(BCM2835_SPI_BIT_ORDER_MSBFIRST)
        bcm2835_spi_setDataMode(BCM2835_SPI_MODE0)
        bcm2835_spi_setClockDivider(BCM2835_SPI_CLOCK_DIVIDER_32)

        if self.CS is not None:
            bcm2835_gpio_fsel(self.CS, BCM2835_GPIO_FSEL_OUTP)

        if self.RESET is not None:
            bcm2835_gpio_fsel(self.RESET, BCM2835_GPIO_FSEL_OUTP)

        if self.HRDY is not None:
            bcm2835_gpio_fsel(self.HRDY, BCM2835_GPIO_FSEL_INPT)
            bcm2835_gpio_set_pud(self.HRDY, BCM2835_GPIO_PUD_DOWN)

        self._write_cs(False)

    def __del__(self):
        bcm2835_spi_end()
        bcm2835_close()

    def reset(self):
        assert self.RESET is not None
        self._write_cs(True)
        time.sleep(0.1)
        self._write_cs(False)

    def _write_cs(self, should_listen):
        '''
        Signal the SPI it should listen / not listen.
        Done via self.CS here
        '''
        assert self.CS is not None
        value_to_write = LOW if should_listen else HIGH
        bcm2835_gpio_write(self.CS, value_to_write)

    def wait_ready(self):
        '''
        Wait for the device's ready pin to be set
        '''
        # TODO: should we sleep just a tiny bit here?
        assert self.HRDY is not None
        while not bcm2835_gpio_lev(self.HRDY):
            pass

    def read(self, preamble, count):
        '''
        Send preamble, and return a buffer of 16-bit unsigned ints of length count
        containing the data received
        '''

        # allocate the array we will return
        # initializing it is unnecessary here, but read() is not called
        # with large arrays so this should not be a performance problem

        self.wait_ready()

        self._write_cs(True)

        bcm2835_spi_transfer(preamble >> 8)
        bcm2835_spi_transfer(preamble)

        self.wait_ready()

        # spec says to read two dummy bytes
        bcm2835_spi_transfer(0)
        bcm2835_spi_transfer(0)

        self.wait_ready()

        rtn = [0 for _ in range(count)]

        for i in range(count):
            rtn[i] = bcm2835_spi_transfer(0x00) << 8
            rtn[i] |= bcm2835_spi_transfer(0x00)

        self._write_cs(False)

        return rtn

    def write(self, preamble, ary):
        '''
        Send preamble, and then write the data in ary (16-bit unsigned ints) over SPI
        '''

        self.wait_ready()

        self._write_cs(True)

        bcm2835_spi_transfer(preamble >> 8)
        bcm2835_spi_transfer(preamble)

        self.wait_ready()

        # TODO: what's the best way to do this in cython?
        for i in range(len(ary)):
            bcm2835_spi_transfer(ary[i] >> 8)
            bcm2835_spi_transfer(ary[i])

        self._write_cs(False)

    def write_pixels(self, pixbuf):
        '''
        Write the pixels in pixbuf to the device. Pixbuf should be an array of
	    16-bit ints, containing packed pixel information.
        '''
        print("Write pixels")
        t = time.time()
        preamble = 0x0000

        # we inline the wait_ready here for speed
        self.wait_ready()

        self._write_cs(True)

        bcm2835_spi_transfer(preamble >> 8)
        bcm2835_spi_transfer(preamble)

        self.wait_ready()

        bcm2835_spi_transfern(pixbuf, len(pixbuf))

        self._write_cs(False)
        print("Took", time.time() - t)

    # the following functions are higher-level for writing and reading
    # various types of data to and from the device

    def write_cmd(self, cmd, *args):
        '''
        Send the device a command code

        Parameters
        ----------

        cmd : int (from constants.Commands)
            The command to send

        args : list(int), optional
            Arguments for the command
        '''
        self.write(0x6000, [cmd])  # 0x6000 is preamble
        for arg in args:
            self.write_data([arg])

    def write_data(self, ary):
        '''
        Send the device an array of data

        Parameters
        ----------

        ary : array-like
            The data
        '''
        self.write(0x0000, ary)

    def read_data(self, n):
        '''
        Read n 16-bit words of data from the device

        Parameters
        ----------

        n : int
            The number of 2-byte words to read
        '''
        return self.read(0x1000, n)

    def read_int(self):
        '''
        Read a single 16 bit int from the device
        '''
        return self.read_data(1)[0]
