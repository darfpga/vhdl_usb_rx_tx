---------------------------------------------------------------------------------
-- DE10_lite Tiny USB Full speed interface by Dar (darfpga@net-c.fr) (27/12/2021)
-- http://darfpga.blogspot.fr
---------------------------------------------------------------------------------
-- Educational use only
-- Use at your own risk. Beware voltage translation or protection are required
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
-- Main features : Tiny USB decoder for Full Speed USB devices (12Mbit/s)
--
--  usb_rx analyse and decode D+/D- signal in order to produce real time signals
--  below :
--
--    usb_sleep    : no bus activity
--    usb_eop      : end of packet
--    usb_pid      : last PID received
--    usb_adr      : last ADDRESS reveived
--    usb_ep       : last END POINT received
--    usb_frame    : last FRAME value (SOF) received
--    usb_data     : last DATA value (byte) received
--    usb_new_data : a new byte is received (last ~1bit)
--    usb_crc_ok   : crc of last packet is ok
--
--  As a demo usb_tx performs the folowing action :
--
--   - Generate a few SOF packets to 'wake up' devices (constant frame 000)
--   - Request for device descriptor and read reply
--   - Set device address to 3
--   - Set configuration 1
--   - Periodicaly request for data from EP1
--
--  All messages are built-in and CRCs are already computed
--  This tiny demo allow to get data from keyboard, mouse, joysitck
--
--  usb_to_jtag_uart uses usb_rx signals in order to display USB captured frames
--  on nios2-terminal thru Jtag uart interface.
--
-- It contains a 8ko fifo data buffer which seems to be enough for small devices
-- (keyboard, joystick, mouse). Jtag-uart avalon bus is accessed directly by 
-- real time hardware signals (no nios processor are used). Usb_to_jtag_uart is
-- used as a debug mean.It can be removed for final design.
--
--  DE10_lite board commands 
--
--  Reset decoder  : key(0)
--  Reinit USB bus : key(1) will restart device enumeration
--
--  DE10_lite board display
--
--    HEX 1-0 : Last key (cmd) entered in nios2-terminal
--    HEX 3-2 : USB SOF frame counter (7 MSB only)
--    HEX   4 : Max capture lines
--	   HEX   5 :
--       segment 0 : token packet filter on/off
--       segment 1 : sof   packet filter on/off
--       segment 2 : data  packet filter on/off
--       segment 3 : setup packet filter on/off
--
--  Commands (via nios2-terminal)
--	key '1' : toggle token packet filter 
--	key '2' : toggle sof   packet filter 
--	key '3' : toggle data  packet filter 
--	key '4' : toggle setup packet filter 
--
--	key 'space' : toggle all active filters on/off
--
--	key '6' : trigger/restart acquistion after stop (single shot)
--	key '7' : +32 lines to max capture buffer (wrap to 0 after 15, 0 = continous)
--	key '8' : -32 lines to max capture buffer (wrap to 15 after 0, 0 = continous)
--
---------------------------------------------------------------------------------
-- Using nios2-terminal
---------------------------------------------------------------------------------
-- Nios2-terminal is available in quartus/bin64 folder. Launch nios2-terminal
-- **after** DE10_lite board fpga programmation then used reset/restart DE10_lite
-- board and/or terminal commands. Use Ctrl-C to quit terminal. Nios2-terminal
-- **have to be shutdown** to allow fpga programmation.
--
---------------------------------------------------------------------------------
-- Hardware wiring
---------------------------------------------------------------------------------
--  Operating as a spy tool USB power supply *must NOT* be connected to DE10 board.
--  Only D+ and D- have to be connected to the DE10 board gpio.
--
--  If the USB port to be spyied is connected on the same computer as the display
--  computer (nios2terminal via Jtag-uart on USB BLASTER port there is no need
--  to connect the USB ground wire to the DE10 board GND.
--
--  In other cases make sure that there *NO current flowing* between the display 
--  machine and the USB to be spyied before connected the DE10 ground to the USB
--  ground. You might have to use isolation transformers for human and hardware
--  safety.
--
--  On DE10_LITE (only)
--
--    D+ : green wire to gpio(0) pin #1 thru voltage translation/protection
--    D- : white wire to gpio(2) pin #3 thru voltage translation/protection
--
--  Operating as a standalone USB port device power supply may be supplied by
--  the DE10 board 5V and GND available on gpio.
--
---------------------------------------------------------------------------------
-- Voltage protection with Schottky diodes BAT54S or BAT42
--
--    BAT54S  (A2) o--|>{--o--|>{--O (K1)
--                         |
--                      (K2-A1)
--
--  use 2 x BAT54S or 4 x BAT42
--    + 2 x 47 Ohms
---------------------------------------------------------------------------------
--                              --------
--   gpio(0) pin #1  o-------o--| 47 Ohms|---o D+ USB to spy (green)
--                           |   --------
--                           |
--       gnd pin #30 o--|>{--o  BAT54S
--                           |
--     +3.3V pin #29 o--}<|---
--
--                              --------
--   gpio(2) pin #3  o-------o--| 47 Ohms|---o D- USB to spy (white)
--                           |   --------
--                           |
--       gnd pin #30 o--|>{--o
--                           |
--     +3.3V pin #29 o--}<|---
--

---------------------------------------------------------------------------------
-- Known bugs
---------------------------------------------------------------------------------
--  Carriage return / line feed missing after some packets due to early ot late 
--  end-of-packet Se0. 
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity usb_rx_tx_de10_lite is
port(
 max10_clk1_50  : in std_logic;
-- max10_clk2_50  : in std_logic;
-- adc_clk_10     : in std_logic;
 ledr           : out std_logic_vector(9 downto 0);
 key            : in std_logic_vector(1 downto 0);
 sw             : in std_logic_vector(9 downto 0);

-- dram_ba    : out std_logic_vector(1 downto 0);
-- dram_ldqm  : out std_logic;
-- dram_udqm  : out std_logic;
-- dram_ras_n : out std_logic;
-- dram_cas_n : out std_logic;
-- dram_cke   : out std_logic;
-- dram_clk   : out std_logic;
-- dram_we_n  : out std_logic;
-- dram_cs_n  : out std_logic;
-- dram_dq    : inout std_logic_vector(15 downto 0);
-- dram_addr  : out std_logic_vector(12 downto 0);

 hex0 : out std_logic_vector(7 downto 0);
 hex1 : out std_logic_vector(7 downto 0);
 hex2 : out std_logic_vector(7 downto 0);
 hex3 : out std_logic_vector(7 downto 0);
 hex4 : out std_logic_vector(7 downto 0);
 hex5 : out std_logic_vector(7 downto 0);

-- vga_r     : out std_logic_vector(3 downto 0);
-- vga_g     : out std_logic_vector(3 downto 0);
-- vga_b     : out std_logic_vector(3 downto 0);
-- vga_hs    : out std_logic;
-- vga_vs    : out std_logic;
 
-- gsensor_cs_n : out   std_logic;
-- gsensor_int  : in    std_logic_vector(2 downto 0); 
-- gsensor_sdi  : inout std_logic;
-- gsensor_sdo  : inout std_logic;
-- gsensor_sclk : out   std_logic;

-- arduino_io      : inout std_logic_vector(15 downto 0); 
-- arduino_reset_n : inout std_logic;
 
 gpio          : inout std_logic_vector(35 downto 0)
);
end usb_rx_tx_de10_lite;

architecture struct of usb_rx_tx_de10_lite is

signal clock_usb  : std_logic;
signal clock_30   : std_logic;
signal reset      : std_logic;
signal restart    : std_logic;
 
alias reset_n    : std_logic is key(0);
alias restart_n  : std_logic is key(1);
alias dp         : std_logic is gpio(0);
alias dm         : std_logic is gpio(2);

signal usb_eop   : std_logic;
signal usb_sleep     : std_logic;

signal usb_pid     : std_logic_vector(3 downto 0); 
signal usb_frame   : std_logic_vector(10 downto 0);
signal usb_data    : std_logic_vector(7 downto 0); 
signal usb_new_data: std_logic; 

signal usb_dp_tx  : std_logic;
signal usb_oe_tx  : std_logic;
signal usb_se0_tx : std_logic;
	
signal usb_new_data_r : std_logic;
signal nb_data : std_logic_vector(3 downto 0);
signal data_1  :  std_logic_vector(7 downto 0);
signal data_2  :  std_logic_vector(7 downto 0);
signal data_3  :  std_logic_vector(7 downto 0);


begin

--arduino_io not used pins
--arduino_io(7) <= '1'; -- to usb host shield max3421e RESET
--arduino_io(8) <= 'Z'; -- from usb host shield max3421e GPX
--arduino_io(9) <= 'Z'; -- from usb host shield max3421e INT
--arduino_io(13) <= 'Z'; -- not used
--arduino_io(14) <= 'Z'; -- not used

-- Clock 30MHz
clocks : entity work.max10_pll_30M_3p58M
port map(
 inclk0 => max10_clk1_50,
 c0 => clock_30, -- 30MHz
 c1 => open,     -- 3p58MHz
 locked => open  -- pll_locked
);

clocks_usb : entity work.max10_pll_96M_48M_24M
port map(
 inclk0 => max10_clk1_50,
 c0 => clock_usb,  -- 96MHz = 8*12MHz. Period ~10.42ns (8 times oversample signal)
 c1 => open,       -- 48MHz
 c2 => open,       -- 24MHz
 locked => open    -- pll_locked
);

reset   <= not reset_n;						  						
restart <= not restart_n;		
										
-- low signal level usb bus activity
dp <= usb_dp_tx when  usb_oe_tx  = '1' else
      '0'       when (usb_se0_tx = '1') or (reset = '1') else 'Z';
		
dm <= not usb_dp_tx when  usb_oe_tx  = '1' else
      '0'           when (usb_se0_tx = '1') or (reset = '1') else 'Z';

-- display
ledr(1) <= dp;
ledr(2) <= dm;

-- USB Tx machine
usb_tx : entity work.usb_tx
port map (
 clk     => clock_usb, -- 96Mhz
 reset   => reset,
 restart => restart,
 
 pid   => usb_pid,
 sleep => usb_sleep,
 
 dp  => usb_dp_tx,
 oe  => usb_oe_tx,
 se0 => usb_se0_tx
);

-- USB Rx machine
usb_rx : entity work.usb_rx
port map (
 clk     => clock_usb, -- 96Mhz
 reset   => reset,

 dp          => dp,
 dm          => dm,

 usb_eop     => usb_eop,
 usb_sleep   => usb_sleep,
 usb_pid     => usb_pid,
 usb_adr     => open,
 usb_ep      => open,
 usb_frame   => usb_frame,
 usb_data    => usb_data,
 usb_new_data=> usb_new_data,
 usb_crc_ok  => ledr(0)
);

-- JTAG UART machine control/display
usb_to_jtag_uart : entity work.usb_to_jtag_uart
port map(
 clock_usb  => clock_usb,
 clock_30   => clock_30,
 reset      => reset,
 restart    => restart,

 usb_pid      => usb_pid,
 usb_frame    => usb_frame,
 usb_data     => usb_data,
 usb_new_data => usb_new_data,
 usb_eop      => usb_eop,

 hex0 => hex0,
 hex1 => hex1,
 hex2 => hex2,
 hex3 => hex3,
 hex4 => hex4,
 hex5 => hex5
);

-- Or simple Hex display
--process (reset, clock_usb)
--begin
--	if reset = '1' then
--		nb_data <= (others => '0');	
--		
--	elsif rising_edge(clock_usb) then
--	
--		usb_new_data_r <= usb_new_data;
--		
--		if usb_sleep = '1' then
--			nb_data <= (others => '0');
--		elsif (usb_new_data_r = '1') and (usb_new_data = '0') then
--		
--			if nb_data < 15 then nb_data <= nb_data + 1; end if;
--			
--			if (nb_data = 3) then data_1 <= usb_data; end if;
--			if (nb_data = 4) then data_2 <= usb_data; end if;
--			if (nb_data = 5) then data_3 <= usb_data; end if;
--						
--		end if;
--		
--	end if;
--end process;
--
--h0 : entity work.decodeur_7_seg port map(data_1(3 downto 0),hex0);
--h1 : entity work.decodeur_7_seg port map(data_1(7 downto 4),hex1);
--h2 : entity work.decodeur_7_seg port map(data_2(3 downto 0),hex2);
--h3 : entity work.decodeur_7_seg port map(data_2(7 downto 4),hex3);
--h4 : entity work.decodeur_7_seg port map(data_3(3 downto 0),hex4);
--h5 : entity work.decodeur_7_seg port map(data_3(7 downto 4),hex5);

end struct;
