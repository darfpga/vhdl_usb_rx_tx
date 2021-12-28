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
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity usb_rx is
port(
 clk   : in std_logic; -- 96Mhz = 8*12MHz. Period ~10.42ns (8 times oversample signal)
 reset : in std_logic;

 dp    : in std_logic;
 dm    : in std_logic;

 usb_eop     : inout std_logic;
 usb_sleep   : inout std_logic;
 usb_pid     : inout std_logic_vector(3 downto 0); 
 usb_adr     : out std_logic_vector(6 downto 0); 
 usb_ep      : out std_logic_vector(3 downto 0); 
 usb_frame   : out std_logic_vector(10 downto 0);
 usb_data    : out std_logic_vector(7 downto 0); 
 usb_new_data: out std_logic; 
 usb_crc_ok  : out std_logic
);
end usb_rx;

architecture struct of usb_rx is
 
signal dp_r      : std_logic;
signal dp_rr     : std_logic;
signal se0       : std_logic;
signal se0_r     : std_logic;
signal se0_rr    : std_logic;

signal usb_cnt       : std_logic_vector(7 downto 0);
signal usb_bit_stuff : std_logic;
signal usb_bit_cnt   : std_logic_vector(7 downto 0);
signal usb_bit_r     : std_logic;
signal usb_shift_reg : std_logic_vector(15 downto 0); 

signal usb_crc5    : std_logic_vector(4 downto 0);
signal usb_crc16   : std_logic_vector(15 downto 0);

signal usb_sof_cnt   : std_logic_vector(15 downto 0);
signal usb_msg_cnt   : std_logic_vector(15 downto 0);
signal usb_setup_cnt : std_logic_vector(15 downto 0);

begin
										
se0 <= not(dp or dm);

process (clk)
begin
	if rising_edge(clk) then

		se0_r  <= se0;
		se0_rr <= se0_r;
		
		-- End of packet detection.
		if (se0_r = '1') and (se0_rr = '1') then
			usb_eop <= '1';
			usb_bit_stuff <= '0';
		else
			usb_eop <= '0';
		end if;
		
		dp_r <= dp;
		dp_rr <= dp_r;

		-- Usb sleep after end of packet and after ~830ns inactivity
		-- wakeup as soon as activity (always start with dp = '0')
		if usb_eop = '1' then 
			usb_sleep <= '1';
		elsif dp_r = '0' then
			usb_sleep <= '0';
		elsif usb_cnt > 80 then 
			usb_sleep <= '1';
		end if;
		
		-- Reset usb_cnt when sleep and after each signal (dp) change.
		-- If change occures after 6 bits (48 clk inactivity ~500ns)
		-- then this is a 'bit stuff' change => data bit to be ignored.
		if (usb_sleep = '1') or (dp_r /= dp_rr ) then 
			usb_cnt <= (others => '0');
			if usb_cnt > 48 then
				usb_bit_stuff <= '1';
			end if;
		else
			usb_cnt <= usb_cnt + 1;
		end if;

		-- Keep bit stuff until signal analysis but not more
		if usb_cnt = 6 then
			usb_bit_stuff <= '0';
		end if;

		-- Note : usb_cnt is reset to a 0 after each signal change.
		-- usb_cnt cannot derive widely from actual bus speed since there is
		--	at least one signal change every 6 data bits
		
	end if;
end process;

-- bit level usb bus activity
-- manage shift register data and CRCs
process (clk)
begin
	if rising_edge(clk) then
--		if usb_sleep = '1' then
		if (usb_sleep = '1') and (usb_eop = '0') then
			usb_bit_cnt <= (others => '0');
			usb_bit_r <= '1';
			usb_shift_reg <= (others => '0');
		else
			-- latch current signal around mid bit period (1 bit period = 8 clk)
			if (usb_cnt(2 downto 0) = 3)  then 
				usb_bit_r <= dp_r;
			end if;
			
			-- at mid bit period analyse signal change only when there is 
			-- no bit stuffing
			if (usb_cnt(2 downto 0) = 3) and (usb_bit_stuff = '0') then 
				-- increment bit counter (ignore stuffing bit)
				-- no need to count past 255 but should avoid wrap back
				if usb_bit_cnt < 255 then 
					usb_bit_cnt <= usb_bit_cnt + 1;
				end if;
				
				-- if there is *NO* signal change => shift data in with '1'
				-- always left shift CRC
				-- and XOR CRC with polynome if MSB of current CRC is '0'
				if usb_bit_r = dp_r then
					usb_shift_reg <= '1' & usb_shift_reg(15 downto 1);
					
					if usb_crc5(4) = '0' then
						usb_crc5 <= usb_crc5(3 downto 0) &'0' xor "00101";
					else
						usb_crc5 <= usb_crc5(3 downto 0) &'0';
					end if;
					
					if usb_crc16(15) = '0' then
						usb_crc16 <= usb_crc16(14 downto 0) &'0' xor "1000000000000101";
					else
						usb_crc16 <= usb_crc16(14 downto 0) &'0';
					end if;
					
				-- if there is a signal change => shift data in with '0'
				-- always left shift CRC
				-- and XOR CRC with polynome if MSB of current CRC is '1'					
				else
					usb_shift_reg <= '0' & usb_shift_reg(15 downto 1);
					
					if usb_crc5(4) = '1' then
						usb_crc5 <= usb_crc5(3 downto 0) &'0' xor "00101";
					else
						usb_crc5 <= usb_crc5(3 downto 0) &'0';
					end if;
					
					if usb_crc16(15) = '1' then
						usb_crc16 <= usb_crc16(14 downto 0) &'0' xor "1000000000000101";
					else
						usb_crc16 <= usb_crc16(14 downto 0) &'0';
					end if;
										
				end if;
				
				-- Initialise CRC with all '1' at beginning of packet.
				-- CRCs computation will start with 16th bit.
				if usb_bit_cnt < 16 then
					usb_crc5 <= (others => '1');
					usb_crc16 <= (others => '1');
				end if;
			end if;
		end if;
	end if;
end process;

-- latch useful data from shift register at the right moment
process (clk)
begin

	if reset = '1' then
		usb_pid       <= (others => '0');
		usb_adr       <= (others => '0');
		usb_ep        <= (others => '0');
		usb_frame     <= (others => '0');
		usb_data      <= (others => '0');
		usb_crc_ok    <= '0';
		usb_sof_cnt   <= (others => '0');
		usb_msg_cnt   <= (others => '0');
		usb_setup_cnt <= (others => '0');
		usb_new_data  <= '0';
	
	elsif rising_edge(clk) then
	
		-- Latch pid
		if usb_bit_cnt = X"10" then
			usb_pid <= usb_shift_reg(11 downto 8);
		end if;
		
		-- Latch new data (byte) and advice user process
		usb_new_data <= '0';
		if (usb_bit_cnt(2 downto 0) = "000") and (usb_sleep = '0') then
			usb_data <= usb_shift_reg(15 downto 8);
			if (usb_bit_cnt > 8 ) then 
				usb_new_data <= '1';
			end if;
		end if;
		
		-- Latch device address and end point on PING/OUT/IN/SETUP token
		if (usb_pid = x"4") or (usb_pid = x"1") or (usb_pid = x"9") or (usb_pid = x"D") then
			if usb_bit_cnt = X"17" then
				usb_adr <= usb_shift_reg(15 downto 9);
			end if;

			if usb_bit_cnt = X"1B" then
				usb_ep <= usb_shift_reg(15 downto 12);
			end if;			
		end if;

		-- Latch frame number on SOF token
		if (usb_pid = x"5") and (usb_bit_cnt = X"1B") then
			usb_frame <= usb_shift_reg(15 downto 5);
		end if;

		-- Check CRCs at end of packet (depends on packet type)
		if usb_eop = '1' then
			if (usb_crc5 = "01100") or (usb_crc16 = x"800D") then
				usb_crc_ok <= '1';
			end if;
		else
				usb_crc_ok <= '0';
		end if;

		-- Count number of SOF packet since reset
		-- Count number of SETUP packet since reset
		-- Count number of non SOF packet since last SETUP packet
		if (usb_cnt(2 downto 0) = 5) and usb_bit_cnt = X"10" then
			if usb_pid = x"5" then 
				usb_sof_cnt <= usb_sof_cnt + 1;
			elsif usb_pid = x"D" then 
				usb_setup_cnt <= usb_setup_cnt + 1;
				usb_msg_cnt <= (others => '0');
			else
				usb_msg_cnt <= usb_msg_cnt + 1;
			end if;
		end if;

	end if;
end process;

end struct;
