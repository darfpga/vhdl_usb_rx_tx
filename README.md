**DE10_lite Tiny USB Full speed interface by Dar**  (darfpga@net-c.fr) (27/12/2021)

http://darfpga.blogspot.fr  
http://sourceforge.net/projects/darfpga  
http://github.com/darfpga  

---

**Educational use only.
Use at your own risk.
Beware voltage translation or protection are required**

---

**Main features** : Tiny USB interface for Full Speed USB devices (12Mbit/s)

**usb_rx.vhd** directly decodes D+/D- signal in order to produce real time signals below :

- usb_sleep    : no bus activity
- usb_eop      : end of packet
- usb_pid      : last PID received
- usb_adr      : last ADDRESS reveived
- usb_ep       : last END POINT received
- usb_frame    : last FRAME value (SOF) received
- usb_data     : last DATA value (byte) received
- usb_new_data : a new byte is received (last ~1bit)
- usb_crc_ok   : crc of last packet is ok

As a demo **usb_tx.vhd** performs the folowing action :

- Generate a few SOF packets to 'wake up' devices (constant frame 000)
- Request for device descriptor and read reply
- Set device address to 3
- Set configuration 1
- Periodicaly request for data from EP1

All messages are built-in and CRCs are already computed.
This tiny demo allow to get data from keyboard, mouse, joystick

**usb_to_jtag_uart.vhd** uses usb_rx signals in order to display USB captured frames
  on nios2-terminal thru Jtag uart interface.

Jtag-uart is used to display data and send user commands to decoder/filter.
It contains a 8ko fifo data buffer which seems to be enough for small devices (keyboard, joystick, mouse).
Jtag-uart avalon bus is accessed directly by real time hardware signals (no nios processor are used).
Usb_to_jtag_uart is used as a debug mean.It can be removed for final design.

**usb_rx_tx_de10_lite.vhd** is the top level design file for DE10_lite board.
It contains usb_rx, usb_tx and usb_to_jtag_uart components. It also contains a
commented section to directly displays USB data on DE10 board HEX 7segments instead of usb_to_jtag_uart.

**DE10_lite board commands**

Reset decoder  : key(0)  
Reinit USB bus : key(1) will restart device enumeration

**DE10_lite board display** (with usb_to_jtag_uart)

    HEX 1-0 : Last key (cmd) entered in nios2-terminal  
    HEX 3-2 : USB SOF frame counter (7 MSB only)  
    HEX   4 : Max capture lines  
    HEX   5 :  
        segment 0 : token packet filter on/off  
        segment 1 : sof   packet filter on/off  
        segment 2 : data  packet filter on/off  
        segment 3 : setup packet filter on/off  

**Commands** (via nios2-terminal)

key '1' : toggle token packet filter  
key '2' : toggle sof   packet filter  
key '3' : toggle data  packet filter  
key '4' : toggle setup packet filter  
key '6' : trigger/restart acquistion after stop (single shot)  
key '7' : +32 lines to max capture buffer (wrap to 0 after 15, 0 = continous)  
key '8' : -32 lines to max capture buffer (wrap to 15 after 0, 0 = continous)  
key 'space' : toggle all active filters on/off  

---

**Using nios2-terminal**

Nios2-terminal is available in quartus/bin64 folder. Launch nios2-terminal **after** DE10_lite board
fpga programmation then used reset/restart DE10_lite board and/or terminal commands. Use Ctrl-C to quit
terminal. Nios2-terminal **have to be shutdown** to allow fpga programmation.

---

**Screen shots**

![nios2-terminal display](/screen_shots/nios2-terminal_display.png)
 screen_shots/nios2-terminal_display.png

![signal tap 1](/screen_shots/signal_tap_1.png)
 screen_shots/signal_tap_1.png

![signal tap 2](/screen_shots/signal_tap_2.png)
 screen_shots/signal_tap_2.png

---

**Signal tap waveform record**
 
Signal tap sample record file **usb_first_exchange.stp** is available in de10_lite folder. It contains
most of the relevant signals for this design.
 

---

**Hardware wiring**

Operating as a spy tool USB power supply ** *must NOT* ** be connected to DE10 board.
Only D+ and D- have to be connected to the DE10 board gpio.

If the USB port to be spyied is connected on the same computer as the display
computer (nios2terminal via Jtag-uart on USB BLASTER port there is no need
to connect the USB ground wire to the DE10 board GND.

In other cases make sure that there is **NO current flowing** between the display 
machine and the USB to be spyied before connected the DE10 ground to the USB
ground. You might have to use isolation transformers for human and hardware
safety.

On DE10_LITE (only)

 **D+** : green wire to gpio(0) pin #1 thru voltage translation/protection  
 **D-** : white wire to gpio(2) pin #3 thru voltage translation/protection  

Operating as a standalone USB port device power supply may be supplied by
the DE10 board 5V and GND available on gpio.

```
 Voltage protection with Schottky diodes BAT54S or BAT42:

    BAT54S  (A2) o--|>{--o--|>{--O (K1)
                         |
                      (K2-A1)

 Use 2 x BAT54S or 4 x BAT42
   + 2 x 47 Ohms
                              --------
   gpio(0) pin #1  o-------o--| 47 Ohms|---o D+ USB to spy (green)
                           |   --------
                           |
       gnd pin #30 o--|>{--o  BAT54S
                           |
     +3.3V pin #29 o--}<|---

                              --------
   gpio(2) pin #3  o-------o--| 47 Ohms|---o D- USB to spy (white)
                           |   --------
                           |
       gnd pin #30 o--|>{--o
                           |
     +3.3V pin #29 o--}<|---
```
---
Jtag-uart component can be rebuilt with Qsys from scracth :

- Launch Qsys
- Remove Clock source component
- Add Jtag uart component from IP_catalog Interface_Protocols\serial
- Choose Wite FIFO buffer depth
- Double-click on each 4 lines of column 'Export' (lines : Clk, reset, 
  avalon_jtag_slave, irq)
- Click on Generate HDL
- Select HDL design files for synthesis => VHDL
- Uncheck Create block symbol file (.bsf)
- Set Ouput_directory
- Click on Generate, Give name jtag_uart_8kw.qsys
- Wait generation completed and close box when done
- Click on Finish in Qsys main windows

- Insert qsys/jtag_uart_8kw/synthesis/jtag_uart_8kw.qip in Quartus project

- Modify jtag_uart_8kw.vhd in Quartus to simplify names for entity and component declaration.
First replace any **jtag_uart_0_avalon_jtag_** with **av_**,
then remove any remaining **jtag_uart_0_**

---