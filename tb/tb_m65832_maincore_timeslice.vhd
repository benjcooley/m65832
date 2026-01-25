-- M65832 Main Core Time-Slice Integration Testbench

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_Maincore_Timeslice is
end tb_M65832_Maincore_Timeslice;

architecture sim of tb_M65832_Maincore_Timeslice is
    constant CLK_PERIOD : time := 20 ns;

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';

    signal target_freq : std_logic_vector(31 downto 0);
    signal master_freq : std_logic_vector(31 downto 0);
    signal enable      : std_logic := '0';

    signal bus_addr    : std_logic_vector(31 downto 0);
    signal bus_data_out: std_logic_vector(7 downto 0);
    signal bus_data_in : std_logic_vector(7 downto 0);
    signal bus_we      : std_logic;
    signal bus_rdy     : std_logic := '1';

    signal vbr_in      : std_logic_vector(31 downto 0) := (others => '0');
    signal vbr_load    : std_logic := '0';
    signal compat_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal compat_load : std_logic := '0';
    signal compat_out  : std_logic_vector(7 downto 0);

    signal irq_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal irq_valid   : std_logic := '0';
    signal irq_req     : std_logic;
    signal irq_addr    : std_logic_vector(15 downto 0);

    signal core_sel    : std_logic_vector(1 downto 0);

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => x"00");
    signal init_done : std_logic := '0';

    signal main_write_seen : std_logic := '0';
    signal cop_write_seen  : std_logic := '0';
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.M65832_Coprocessor_Top
        port map (
            CLK         => clk,
            RST_N       => rst_n,
            TARGET_FREQ => target_freq,
            MASTER_FREQ => master_freq,
            ENABLE      => enable,
            BUS_ADDR    => bus_addr,
            BUS_DATA_OUT=> bus_data_out,
            BUS_DATA_IN => bus_data_in,
            BUS_WE      => bus_we,
            BUS_RDY     => bus_rdy,
            VBR_IN      => vbr_in,
            VBR_LOAD    => vbr_load,
            COMPAT_IN   => compat_in,
            COMPAT_LOAD => compat_load,
            COMPAT_OUT  => compat_out,
            BANK0_BASE  => x"D000",
            BANK1_BASE  => x"D400",
            BANK2_BASE  => x"DC00",
            BANK3_BASE  => x"DD00",
            FRAME_NUMBER=> (others => '0'),
            IRQ_DATA    => irq_data,
            IRQ_VALID   => irq_valid,
            IRQ_REQ     => irq_req,
            IRQ_ADDR    => irq_addr,
            CORE_SEL_OUT=> core_sel
        );

    bus_data_in <= mem(to_integer(unsigned(bus_addr(15 downto 0))));

    process(clk)
    begin
        if rising_edge(clk) then
            if init_done = '0' then
                mem <= (others => x"00");
                -- Main core program at $8000:
                -- LDA #$AA
                -- STA $0200
                -- JMP $8000
                mem(16#8000#) <= x"A9";
                mem(16#8001#) <= x"AA";
                mem(16#8002#) <= x"8D";
                mem(16#8003#) <= x"00";
                mem(16#8004#) <= x"02";
                mem(16#8005#) <= x"4C";
                mem(16#8006#) <= x"00";
                mem(16#8007#) <= x"80";
                -- Main reset vector -> $8000
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"80";

                -- 6502 program at $0000:
                -- LDA #$55
                -- STA $0400
                -- JMP $0000
                mem(16#0000#) <= x"A9";
                mem(16#0001#) <= x"55";
                mem(16#0002#) <= x"8D";
                mem(16#0003#) <= x"00";
                mem(16#0004#) <= x"04";
                mem(16#0005#) <= x"4C";
                mem(16#0006#) <= x"00";
                mem(16#0007#) <= x"00";

                init_done <= '1';
            end if;

            if init_done = '1' and bus_we = '1' and bus_rdy = '1' then
                if not (bus_addr(15 downto 0) >= x"0000" and bus_addr(15 downto 0) <= x"0007") and
                   not (bus_addr(15 downto 0) >= x"8000" and bus_addr(15 downto 0) <= x"8007") and
                   not (bus_addr(15 downto 0) = x"FFFC" or bus_addr(15 downto 0) = x"FFFD") then
                    mem(to_integer(unsigned(bus_addr(15 downto 0)))) <= bus_data_out;
                end if;
                if core_sel = "00" and bus_addr(15 downto 0) = x"0200" and bus_data_out = x"AA" then
                    main_write_seen <= '1';
                elsif core_sel = "01" and bus_addr(15 downto 0) = x"0400" and bus_data_out = x"55" then
                    cop_write_seen <= '1';
                end if;
            end if;
        end if;
    end process;

    process
    begin
        target_freq <= std_logic_vector(to_unsigned(1022727, 32));
        master_freq <= std_logic_vector(to_unsigned(50000000, 32));

        rst_n <= '0';
        enable <= '0';
        wait for 200 ns;
        rst_n <= '1';
        vbr_load <= '1';
        wait for CLK_PERIOD;
        vbr_load <= '0';
        enable <= '1';

        wait for 5 ms;
        assert main_write_seen = '1'
            report "Main core did not write expected value while time-sliced"
            severity failure;
        assert cop_write_seen = '1'
            report "Coprocessor did not write expected value while time-sliced"
            severity failure;
        report "Main core time-slice test PASSED" severity note;
        wait;
    end process;
end sim;
