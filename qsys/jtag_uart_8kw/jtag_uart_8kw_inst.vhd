	component jtag_uart_8kw is
		port (
			jtag_uart_0_clk_clk                       : in  std_logic                     := 'X';             -- clk
			jtag_uart_0_reset_reset_n                 : in  std_logic                     := 'X';             -- reset_n
			jtag_uart_0_avalon_jtag_slave_chipselect  : in  std_logic                     := 'X';             -- chipselect
			jtag_uart_0_avalon_jtag_slave_address     : in  std_logic                     := 'X';             -- address
			jtag_uart_0_avalon_jtag_slave_read_n      : in  std_logic                     := 'X';             -- read_n
			jtag_uart_0_avalon_jtag_slave_readdata    : out std_logic_vector(31 downto 0);                    -- readdata
			jtag_uart_0_avalon_jtag_slave_write_n     : in  std_logic                     := 'X';             -- write_n
			jtag_uart_0_avalon_jtag_slave_writedata   : in  std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			jtag_uart_0_avalon_jtag_slave_waitrequest : out std_logic;                                        -- waitrequest
			jtag_uart_0_irq_irq                       : out std_logic                                         -- irq
		);
	end component jtag_uart_8kw;

	u0 : component jtag_uart_8kw
		port map (
			jtag_uart_0_clk_clk                       => CONNECTED_TO_jtag_uart_0_clk_clk,                       --               jtag_uart_0_clk.clk
			jtag_uart_0_reset_reset_n                 => CONNECTED_TO_jtag_uart_0_reset_reset_n,                 --             jtag_uart_0_reset.reset_n
			jtag_uart_0_avalon_jtag_slave_chipselect  => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_chipselect,  -- jtag_uart_0_avalon_jtag_slave.chipselect
			jtag_uart_0_avalon_jtag_slave_address     => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_address,     --                              .address
			jtag_uart_0_avalon_jtag_slave_read_n      => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_read_n,      --                              .read_n
			jtag_uart_0_avalon_jtag_slave_readdata    => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_readdata,    --                              .readdata
			jtag_uart_0_avalon_jtag_slave_write_n     => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_write_n,     --                              .write_n
			jtag_uart_0_avalon_jtag_slave_writedata   => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_writedata,   --                              .writedata
			jtag_uart_0_avalon_jtag_slave_waitrequest => CONNECTED_TO_jtag_uart_0_avalon_jtag_slave_waitrequest, --                              .waitrequest
			jtag_uart_0_irq_irq                       => CONNECTED_TO_jtag_uart_0_irq_irq                        --               jtag_uart_0_irq.irq
		);

