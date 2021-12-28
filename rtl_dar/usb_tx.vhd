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
--  usb_tx produces D+ and se0 (EOP) signals to communicate with a simple device
--  usb_tx uses usb_sleep and usb_pid from usb_rx to interact with device replies
--
--  As a demo usb_tx performs the folowing action :
--
--  - Generate a few SOF packets to 'wake up' devices (constant frame 000)
--  - Request for device descriptor and read reply
--  - Set device address to 3
--  - Set configuration 1
--  - Periodicaly request for data from EP1
--
--  All messages are built-in and CRCs are already computed
--  This tiny demo allow to get data from keyboard, mouse, joysitck
--
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity usb_tx is
port(
 clk     : in std_logic; -- 96Mhz
 reset   : in std_logic;
 restart : in std_logic;
 
 pid     : in std_logic_vector(3 downto 0);
 sleep   : in std_logic;
 
 dp  : out std_logic;
 oe  : out std_logic;
 se0 : out std_logic
 );
end usb_tx;

architecture struct of usb_tx is

signal div_clk : std_logic_vector(2 downto 0);
signal en_bit  : std_logic;

signal div_1ms : std_logic_vector(14 downto 0);
signal en_1ms  : std_logic;

signal restart_r   : std_logic;
signal seq_stm     : integer range 0 to 200;
signal on_return   : integer range 0 to 200;
signal on_no_reply : integer range 0 to 200;
signal on_ack      : integer range 0 to 200;
signal on_data     : integer range 0 to 200;
signal on_nack     : integer range 0 to 200;
signal wait_nb_bit : integer range 0 to 200;
signal wait_nb_ms  : integer range 0 to 200;


subtype t_uint4 is integer range 0 to  15;
subtype t_uint8 is integer range 0 to 255;
type t_msg_start_addr is array(t_uint4 range <>) of t_uint8;
type t_msg_length     is array(t_uint4 range <>) of t_uint8;
type t_messages       is array(t_uint8 range <>) of std_logic_vector(7 downto 0);
signal msg_number     : t_uint4;
signal msg_addr       : t_uint8;

signal messages : t_messages(integer range 0 to 65) := 
(
	X"80",X"2D",X"00",X"10", -- SETUP 0,0
	X"80",X"C3",X"80",X"06",X"00",X"01",X"00",X"00",X"12",X"00",X"E0",x"F4", -- get descripteur
	X"80",X"D2",             -- ACK
	X"80",X"69",X"00",X"10", -- IN 0,0
	X"80",X"E1",X"00",X"10", -- OUT 0,0
	X"80",X"4B",X"00",X"00", -- DATA 00,00
	X"80",X"C3",X"00",X"05",X"03",X"00",X"00",X"00",X"00",X"00",X"EA",x"C7", -- set address 3
	X"80",X"A5",X"00",X"10", -- SOF 000
	X"80",X"69",X"83",X"E0", -- IN 3,1	
	X"80",X"2D",X"03",X"50", -- SETUP 3,0
	X"80",X"C3",X"00",X"09",X"01",X"00",X"00",X"00",X"00",X"00",X"27",x"25" -- set configuration 1	
);

signal msg_start_addr : t_msg_start_addr(integer range 0 to 11) :=
( 0, 4,16,18,22,26,30,42,46,50,54,66);

signal msg_length : t_msg_length(integer range 0 to 11) := 
( 4,12, 2, 4, 4, 4,12, 4, 4, 4,12, 0);

signal start_sending  : std_logic;
signal send_stm       : integer range 0 to 3;
signal nof_byte_sent  : t_uint8;
signal byte_to_send   : std_logic_vector(7 downto 0);
signal nof_bit_sent   : integer range 0 to 7;
signal stuff_cnt      : std_logic_vector(2 downto 0);


begin

-- Bit and ms counters
process (reset, clk)
begin
	if reset = '1' then
		div_clk <= (others => '0');
		div_1ms <= (others => '0');
	else
		if rising_edge(clk) then
			div_clk <= div_clk + 1;
			en_bit <= '0';
			en_1ms <= '0';
			if div_clk = "111" then
				en_bit <= '1';
				if div_1ms = 11999 then
					en_1ms <= '1';
					div_1ms <= (others => '0');
				else
					div_1ms <= div_1ms + 1;
				end if;
			end if;
		end if;
	end if;
end process;

-- Enum and query state machine
process (reset, clk)
begin
	if reset = '1' then
		seq_stm <= 0;
		wait_nb_bit <= 0;
		wait_nb_ms  <= 0;
		start_sending <= '0';
	else
		if rising_edge(clk) then
			restart_r <= restart;
			start_sending <= '0';

			-- bit wide timeout
			if en_bit = '1' then
				if wait_nb_bit > 0 then 
					wait_nb_bit <= wait_nb_bit - 1;
				end if;	
			end if;

			-- ms wide timeout
			if en_1ms = '1' then
				if wait_nb_ms > 0 then 
					wait_nb_ms <= wait_nb_ms - 1;
				end if;	
			end if;

			-- state machine
			case seq_stm is

			when 0 => 
				if (restart_r = '1') and (restart = '0') then
					wait_nb_ms <= 10;
					seq_stm    <= 100; -- go to send SOF
					on_return  <= 1;
				end if;
				
			when 1 =>			
				if (send_stm = 0) then   
					msg_number    <=  0; -- send SETUP 0,0
					start_sending <= '1';
					seq_stm <= seq_stm + 1;
				end if;

			when 2 => 
				if (send_stm = 0) and (start_sending = '0') then 
					msg_number    <=  1; -- send get descripteur
					start_sending <= '1';
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 0;
					on_ack      <= 3;
					on_data     <= 0;
					on_nack     <= 0;
				end if;
				
			when 3 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  3; -- send IN 0,0
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 0;
					on_ack      <= 0;
					on_data     <= 4;
					on_nack     <= 3;
				end if;
													
			when 4 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  2; -- send ACK
					start_sending <= '1';				
					seq_stm       <= seq_stm + 1;
					wait_nb_bit   <= 80; -- wait ~10 bytes
				end if;
				
			when 5 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  3; -- send IN 0,0
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 0;
					on_ack      <= 0;
					on_data     <= 6;
					on_nack     <= 5;
				end if;
													
			when 6 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  2; -- send ACK
					start_sending <= '1';				
					seq_stm       <= seq_stm + 1;
					wait_nb_bit   <= 80; -- wait ~10 bytes
				end if;

			when 7 => 
				if (wait_nb_bit = 0) then
					msg_number    <=  4; -- send OUT 0,0
					start_sending <= '1';				
					seq_stm <= seq_stm + 1;
				end if;

			when 8 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  5; -- send DATA 00,00
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 0;
					on_ack      <= 20;
					on_data     <= 0;
					on_nack     <= 0;
				end if;

			-- Set address
			when 20 =>			
				if (send_stm = 0) and (start_sending = '0') then   
					msg_number    <=  0; -- send SETUP 0,0
					start_sending <= '1';
					seq_stm <= seq_stm + 1;
				end if;

			when 21 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  6; -- send set address 3
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 0;
					on_ack      <= 22;
					on_data     <= 0;
					on_nack     <= 0;
				end if;

			when 22 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  3; -- send IN 0,0
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 0;
					on_ack      <= 0;
					on_data     <= 23;
					on_nack     <= 22;
				end if;

			when 23 => 
				if (wait_nb_bit = 0) then
					msg_number    <=  2; -- send ACK
					start_sending <= '1';				
					seq_stm     <= seq_stm + 1;
					wait_nb_ms  <= 10; -- wait a while for device to change address
				end if;
				
			when 24 => 
				if (wait_nb_ms = 0) then
					seq_stm <= 40;
				end if;
				
			-- Set configuration				
			when 40 =>			
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  9; -- send SETUP 3,0
					start_sending <= '1';
					seq_stm <= seq_stm + 1;
				end if;

			when 41 => 
				if (send_stm = 0) and (start_sending = '0') then 
					msg_number    <= 10; -- send set configuration 1
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 42;
					on_ack      <= 60;
					on_data     <= 0;
					on_nack     <= 0;
					wait_nb_ms  <= 2; -- repeat ~2ms	
			end if;
			
			when 42 => 
				if (wait_nb_ms = 0) then
					seq_stm <= 40;
				end if;
								
			-- Get data from @3, EP1
			when 60 => 
				if (en_1ms = '1') then 
					msg_number    <=  8; -- send IN 3,1
					start_sending <= '1';				
					seq_stm     <= 110; -- go to wait device reply
					wait_nb_bit <= 160; -- watchdog ~20 bytes
					on_no_reply <= 60;
					on_ack      <= 0;
					on_data     <= 61;
					on_nack     <= 60;
			end if;
								
			when 61 => 
				if (send_stm = 0) and (start_sending = '0') then
					msg_number    <=  2; -- send ACK
					start_sending <= '1';
					seq_stm <= seq_stm + 1;
				end if;
			when 62 => 
				if (en_1ms = '1')  then
					seq_stm <= seq_stm + 1;
				end if;
			when 63 => 
				if (en_1ms = '1')  then
					seq_stm <= 60;
				end if;
				
								
			-- send SOF function
			--------------------
			when 100 =>
				if (wait_nb_ms = 0) then
					seq_stm <= on_return;
				elsif (send_stm = 0) and (start_sending = '0') and (en_1ms = '1') then
					msg_number <= 7; -- send SOF
					start_sending <= '1';
				end if;

			-- wait for device reply function
			---------------------------------
			when 110 =>
				-- wait device start of reply
				if (send_stm = 0) and (start_sending = '0') and (sleep = '0') then
					seq_stm <= seq_stm + 1;
				elsif (wait_nb_bit = 0) then
					seq_stm <= on_no_reply;
				end if;
					
			when 111 =>
				-- wait device end of reply
				if (sleep = '1') then
					wait_nb_bit <= 2;
					seq_stm <= seq_stm + 1;
				end if;
				
			when 112 =>
				-- analyse device reply
				if (wait_nb_bit = 0) then
					if    (pid = x"A") then -- NACK received
						seq_stm <= on_nack;
					elsif	(pid = x"B")  or (pid = x"3") then -- DATA received
						seq_stm <= on_data;
					elsif (pid = x"2") then -- ACK received
						seq_stm <= on_ack;
					else
						seq_stm <= 0;
					end if;
				end if;
		
			when others => 
					seq_stm <= 0;
					
			end case;

		end if;
	end if;
end process;

-- Low level send message state machine
process (reset, clk)
begin
	if reset = '1' then
		se0 <= '0';	
		oe  <= '0';
		dp  <= '1';
	else
		if rising_edge(clk) then
		
			case send_stm is
			
			when 0 =>
				-- release bus control while waiting for start signal
				oe  <= '0';
				dp  <= '1';
				nof_byte_sent <= 0;
				nof_bit_sent  <= 0;
				msg_addr <= msg_start_addr(msg_number);
				byte_to_send <= messages(msg_start_addr(msg_number));
				if start_sending = '1' then send_stm <= send_stm + 1; end if;

			when 1 =>
				if en_bit = '1' then
					-- take bus control
					oe <= '1';
					-- toggle dp state to send '0', no change to send '1'
					-- count number of consecutive '1'
					if byte_to_send(nof_bit_sent) = '0' then 
						dp <= not dp;
						stuff_cnt <= (others => '0');
					else
						stuff_cnt <= stuff_cnt + 1;
					end if;
					if stuff_cnt < 6 then
						-- no bit stuffing : goto next bit, next byte
						nof_bit_sent <= nof_bit_sent + 1;
						if nof_bit_sent = 7 then
							nof_bit_sent <= 0;
							if nof_byte_sent < (msg_length(msg_number)-1) then
								nof_byte_sent <= nof_byte_sent + 1;
								msg_addr <= msg_addr +1;
								byte_to_send  <= messages(msg_addr + 1);
							else
								-- no nore data to send
								send_stm <= send_stm + 1;
							end if;
						end if;
					else
						-- bit stuffing : toggle dp, stay on current bit
						-- and reset stuffing counter
						dp <= not dp;
						stuff_cnt <= (others => '0');
					end if;

				end if;
			when 2 =>
				-- release dp control 
				-- send EOP for 2 bits duration
				-- return to standby after a while
				if en_bit = '1' then
					nof_bit_sent <= nof_bit_sent + 1;
					oe  <= '0';
					dp  <= '1';
					if nof_bit_sent = 0 then
						se0 <= '1';
					end if;
					if nof_bit_sent = 2 then
						se0 <= '0';
					end if;
					if nof_bit_sent = 7 then
						send_stm <= 0;
					end if;
				end if;
			
			when others =>
				 send_stm <= 0;
					
			end case;				
		end if;
	end if;
end process;

end struct;