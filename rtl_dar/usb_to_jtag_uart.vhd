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
--    HEX   5 :
--       segment 0 : token packet filter on/off
--       segment 1 : sof   packet filter on/off
--       segment 2 : data  packet filter on/off
--       segment 3 : setup packet filter on/off
--
--  Commands (via nios2-terminal)
--    key '1' : toggle token packet filter 
--    key '2' : toggle sof   packet filter 
--    key '3' : toggle data  packet filter 
--    key '4' : toggle setup packet filter 
--
--    key 'space' : toggle all active filters on/off
--
--    key '6' : trigger/restart acquistion after stop (single shot)
--    key '7' : +32 lines to max capture buffer (wrap to 0 after 15, 0 = continous)
--    key '8' : -32 lines to max capture buffer (wrap to 15 after 0, 0 = continous)
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
-- Jtag-uart component can be rebuilt with Qsys from scracth :
--
--  - Launch Qsys
--  - Remove Clock source component
--  - Add Jtag uart component from IP_catalog Interface_Protocols\serial
--  - Choose Wite FIFO buffer depth
--  - Double-click on each 4 lines of column 'Export' (lines : Clk, reset, 
--       avalon_jtag_slave, irq)
--  - Click on Generate HDL
--  - Select HDL design files for synthesis => VHDL
--  - Uncheck Create block symbol file (.bsf)
--  - Set Ouput_directory
--  - Click on Generate, Give name jtag_uart_8kw.qsys
--  - Wait generation completed and close box when done
--  - Click on Finish in Qsys main windows
--
--  - Insert qsys/jtag_uart_8kw/synthesis/jtag_uart_8kw.qip Quartus project
--
--  - Modify jtag_uart_8kw.vhd in Quartus to simplify names for entity 
--    and component declaration :
--       first replace any jtag_uart_0_avalon_jtag_ with av_
--       then remove any remaining jtag_uart_0_
--
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity usb_to_jtag_uart is
port(
 clock_usb  : in std_logic;
 clock_30   : in std_logic;
 reset      : in std_logic;
 restart    : in std_logic;

 usb_pid     : in std_logic_vector(3 downto 0);
 usb_frame   : in std_logic_vector(10 downto 0); 
 usb_data    : in std_logic_vector(7 downto 0); 
 usb_new_data: in std_logic; 
 usb_eop     : in std_logic;

 hex0 : out std_logic_vector(7 downto 0);
 hex1 : out std_logic_vector(7 downto 0);
 hex2 : out std_logic_vector(7 downto 0);
 hex3 : out std_logic_vector(7 downto 0);
 hex4 : out std_logic_vector(7 downto 0);
 hex5 : out std_logic_vector(7 downto 0)

);
end usb_to_jtag_uart;

architecture struct of usb_to_jtag_uart is

-- Jtag UART from QSYS (8k fifo from avalon side to JTAG interface)
component jtag_uart_8kw is
port (
	av_chipselect  : in  std_logic                     := 'X';             -- chipselect
	av_address     : in  std_logic                     := 'X';             -- address
	av_read_n      : in  std_logic                     := 'X';             -- read_n
	av_readdata    : out std_logic_vector(31 downto 0);                    -- readdata
	av_write_n     : in  std_logic                     := 'X';             -- write_n
	av_writedata   : in  std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
	av_waitrequest : out std_logic;                                        -- waitrequest
	clk_clk        : in  std_logic                     := 'X';             -- clk
	irq_irq        : out std_logic;                                        -- irq
	reset_reset_n  : in  std_logic                     := 'X'              -- reset_n
);
end component jtag_uart_8kw;

signal reset_n : std_logic;

signal uart_chipselect  : std_logic := '0';             -- chipselect
signal uart_address     : std_logic := '0';             -- address
signal uart_read_n      : std_logic := '1';             -- read_n
signal uart_readdata    : std_logic_vector(31 downto 0);-- readdata
signal uart_write_n     : std_logic := '1';             -- write_n
signal uart_writedata   : std_logic_vector(31 downto 0) := (others => '0'); -- writedata
signal uart_waitrequest : std_logic;                  -- waitrequest
signal uart_irq         : std_logic;                  -- irq
signal uart_stm         : integer range 0 to 3;

signal uart_write_request : std_logic;
signal read_data          : std_logic_vector(7 downto 0);

signal new_data_cnt  : std_logic_vector(7 downto 0);
signal write_seq     : std_logic_vector(1  downto 0);
signal data_for_uart : std_logic_vector(17 downto 0);
signal uart_byte     : std_logic_vector(7 downto 0);

signal get_data     : std_logic;
signal want_nothing : std_logic := '0';
signal want_token   : std_logic := '1';
signal want_sof     : std_logic := '1';
signal want_data    : std_logic := '1';
signal want_setup   : std_logic := '1';
signal line_cnt     : std_logic_vector(9 downto 0);
signal max_line     : std_logic_vector(3 downto 0);

begin

reset_n   <= not reset;	

-- Latch data to be sent to uart for display
process (clock_usb)
begin
	if reset = '1' then
		new_data_cnt  <= (others => '0'); -- fast counter reseted at each new byte
	
	elsif rising_edge(clock_usb) then
	
		-- Increment/reset fast counter, no need to count past 31
		if (new_data_cnt < 31) then 
			new_data_cnt <= new_data_cnt + 1;
		elsif (usb_new_data = '1') then
			new_data_cnt <= (others => '0');
		end if;
				
		if new_data_cnt = 14 then -- (MUST wait up to 14 to get usb_eop)

		   -- Set transfer flag only for selected data 
			data_for_uart(17) <= get_data;
			-- Keep trace of end of packet
			data_for_uart(16) <= usb_eop;
			
			-- Convert low nibble to HEX ASCII
			if usb_data(3 downto 0) < x"A" then 
				data_for_uart(7 downto 0) <= (x"0"&usb_data(3 downto 0)) + x"30";
			else
				data_for_uart(7 downto 0) <= (x"0"&usb_data(3 downto 0)) + x"41" - x"0A";
			end if;

			-- Convert high nibble to HEX ASCII
			if usb_data(7 downto 4) < x"A" then 
				data_for_uart(15 downto 8) <= (x"0"&usb_data(7 downto 4)) + x"30";
			else
				data_for_uart(15 downto 8) <= (x"0"&usb_data(7 downto 4)) + x"41" - x"0A";
			end if;
			
		end if;
		
		-- Release transfert flag
		-- Set to 1 from fast counter = 14 to 20 to allow clock domain crossing)
		if new_data_cnt = 20 then
			data_for_uart(17) <= '0';
		end if;

	end if;
end process;

-- Jtag UART from QSYS (8k fifo from avalon side to JTAG interface)
u0 : component jtag_uart_8kw
port map (
	av_chipselect  => uart_chipselect,         --    av.chipselect
	av_address     => uart_address,            --      .address
	av_read_n      => uart_read_n,             --      .read_n
	av_readdata    => uart_readdata,           --      .readdata
	av_write_n     => uart_write_n,            --      .write_n
	av_writedata   => uart_writedata,          --      .writedata
	av_waitrequest => uart_waitrequest,        --      .waitrequest
	clk_clk        => clock_30,
	irq_irq        => uart_irq,
	reset_reset_n  => reset_n
);

-- select data to be transfered w.r.t user commands
get_data <=
	'0' when line_cnt = "11"&x"FF" else -- max line reached
	'0' when (want_nothing = '1')  else
	'1' when (want_sof     = '1') and ( usb_pid  = x"5") else
	'1' when (want_data    = '1') and ((usb_pid  = x"B") or (usb_pid   = x"3")) else
	'1' when (want_setup   = '1') and ( usb_pid  = x"D") else
	'1' when (want_token   = '1') and ((usb_pid /= x"B") and (usb_pid /= x"3") and (usb_pid /= x"D") and (usb_pid /= x"5")) else
	'0';
	
-- Jtag UART management	
process (reset, restart, clock_30)
begin
	
	if rising_edge(clock_30) then
	
		-- Reset line counter on usb bus reset command
		-- (allow capturing setup packets)
		if (restart = '1') or (reset = '1') then line_cnt <= (others => '0'); end if; 
		
		-- Write sequence (3 stages for each byte to be written)
		case write_seq is
			when "00" =>
				-- Wait for previous write has ended and new data to be written.
				-- Then request for high nibbe HEX ASCII to be written.
				if (uart_write_request = '0') and (data_for_uart(17) = '1') then
					write_seq <= write_seq + 1;			
					uart_write_request <= '1';
					uart_byte <= data_for_uart(15 downto 8);
				end if;
			when "01" =>
				-- Wait for previous write has ended.
				-- Then request for low nibbe HEX ASCII to be written.
				if uart_write_request = '0' then
					write_seq <= write_seq + 1;			
					uart_write_request <= '1';
					uart_byte <= data_for_uart(7 downto 0);
				end if;
			when "10" =>
				-- Wait for previous write has ended.
				-- Then request for space or new line to be written 
				-- depending on end of packet flag.
				if uart_write_request = '0' then
					write_seq <= write_seq + 1;			
					uart_write_request <= '1';
					if data_for_uart(16) = '0' then -- eop flag
						uart_byte <= x"20";				
					else
						uart_byte <= x"0A";
						-- Count one more line after each packet if limited
						-- number of line is required.
						-- Set to all '1' when max number of lines is reached.
						if max_line /= x"0" then 
							if line_cnt < max_line & "000000" then 
								line_cnt <= line_cnt + 1;
							else
								line_cnt <= (others => '1');						
							end if;
						end if;
						
					end if;
				end if;
			when others =>
				write_seq <= (others => '0');			
		end case;

		-- JTAG UART state machine
		case uart_stm is
			-- Wait stage
			when 0 =>
				-- If write requested goto write stage
				-- otherwise prepare reading
				if uart_write_request = '1' then 
					uart_stm <= 2;
				else			
					uart_chipselect <= '1';
					uart_read_n     <= '0';
					uart_stm <= 1;
				end if;
			-- Read stage
			when 1 =>
				-- Wait for read ready then release read request
				if uart_waitrequest = '0' then 
					uart_chipselect <= '0';
					uart_read_n     <= '1';
					-- If data from jtag available then analyse user command
					-- Otherwise return to stage 0
					if uart_readdata(15) = '1'  then
						
						if uart_readdata(7 downto 0) = X"20" then -- space : start/stop acquisition
							want_nothing <= not want_nothing;
						end if;
						if uart_readdata(7 downto 0) = X"31" then -- 1 : toggle token packet filter
							want_token <= not want_token;
						end if;
						if uart_readdata(7 downto 0) = X"32" then -- 2 : toggle sof packet filter
							want_sof <= not want_sof;
						end if;
						if uart_readdata(7 downto 0) = X"33" then -- 3 : toggle data packet filter
							want_data <= not want_data;
						end if;
						if uart_readdata(7 downto 0) = X"34" then -- 4 : toggle setup packet filter
							want_setup <= not want_setup;
						end if;
						if uart_readdata(7 downto 0) = X"36" then -- 6 : trigger acquisition
							line_cnt <= (others => '0');
						end if;
						if uart_readdata(7 downto 0) = X"37" then -- 7 : more lines to be sent
							max_line <= max_line + 1;
						end if;
						if uart_readdata(7 downto 0) = X"38" then -- 8 : less lines to be sent
							max_line <= max_line - 1;
						end if;
												
						-- Latch user command (for 7 segments display)
						read_data <= uart_readdata(7 downto 0);
						
						-- Echo user command to jtag (loop back character to terminal)
						-- goto write stage 
						uart_byte <= uart_readdata(7 downto 0);
						uart_stm <= 2;
					else
						uart_stm <= 0;
					end if;					
				end if;
			-- Write stage
			when 2 =>
				uart_writedata <= x"000000"&uart_byte;
				uart_write_request <= '0';  -- Acknowlegde write request
				uart_chipselect <= '1';
				uart_write_n    <= '0';
				uart_stm <= 3;
			-- Wait for end of write
			when 3 =>
				-- Wait for write ready then release read request
				if uart_waitrequest = '0' then 
					uart_chipselect <= '0';
					uart_write_n    <= '1';
					-- Return to write stage if new write request is pending
					-- Otherwise goto stage 0
					if uart_write_request = '1' then
						uart_stm <= 2;
					else
						uart_stm <= 0;
					end if;
				end if;
				
			when others =>
					uart_stm <= 0;
					
		end case;

	end if;
end process;

h0 : entity work.decodeur_7_seg port map(read_data(3 downto 0),hex0); -- user command
h1 : entity work.decodeur_7_seg port map(read_data(7 downto 4),hex1); -- user command
h2 : entity work.decodeur_7_seg port map(usb_frame(7 downto 4),hex2);      -- usb bus frame counter
h3 : entity work.decodeur_7_seg port map('0'&usb_frame(10 downto 8),hex3); -- usb bus frame counter
h4 : entity work.decodeur_7_seg port map(max_line,hex4); -- max line number
hex5(0) <= not (want_token and not(want_nothing)); -- token filter state
hex5(1) <= not (want_sof   and not(want_nothing)); -- sof   filter state
hex5(2) <= not (want_data  and not(want_nothing)); -- data  filter state
hex5(3) <= not (want_setup and not(want_nothing)); -- setup filter state
hex5(7 downto 4) <= "1111";

end struct;
