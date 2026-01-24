-- Testbench for M65832 coprocessor integration

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_Coprocessor is
end tb_M65832_Coprocessor;

architecture sim of tb_M65832_Coprocessor is
    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    function is_clean(v : std_logic_vector) return boolean is
    begin
        for i in v'range loop
            if v(i) /= '0' and v(i) /= '1' then
                return false;
            end if;
        end loop;
        return true;
    end function;

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

    signal irq_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal irq_valid   : std_logic := '0';
    signal irq_req     : std_logic;
    signal irq_addr    : std_logic_vector(15 downto 0);
    signal core_sel    : std_logic_vector(1 downto 0);

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => x"00");
    signal init_done : std_logic := '0';
    signal write_seen : std_logic := '0';
    signal slot_count : unsigned(31 downto 0) := (others => '0');
    signal write_count : unsigned(31 downto 0) := (others => '0');
begin
    ---------------------------------------------------------------------------
    -- Clock
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------
    -- Memory model (read-combinational, write-synchronous)
    ---------------------------------------------------------------------------
    bus_data_in <= mem(to_integer(unsigned(bus_addr(15 downto 0))));

    process(clk)
    begin
        if rising_edge(clk) then
            if init_done = '0' then
                -- Initialize program and vectors once
                mem <= (others => x"00");
                mem(16#0000#) <= x"A9";
                mem(16#0001#) <= x"42";
                mem(16#0002#) <= x"8D";
                mem(16#0003#) <= x"00";
                mem(16#0004#) <= x"04";
                mem(16#0005#) <= x"4C";
                mem(16#0006#) <= x"00";
                mem(16#0007#) <= x"00";
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"00";
                init_done <= '1';
            end if;
            if core_sel = "01" then
                slot_count <= slot_count + 1;
            end if;
            if init_done = '1' and bus_we = '1' and bus_rdy = '1' and core_sel = "01" and
               is_clean(bus_addr(15 downto 0)) and is_clean(bus_data_out) then
                write_count <= write_count + 1;
                if not (bus_addr(15 downto 0) >= x"0000" and bus_addr(15 downto 0) <= x"0007") and
                   not (bus_addr(15 downto 0) = x"FFFC" or bus_addr(15 downto 0) = x"FFFD") then
                    mem(to_integer(unsigned(bus_addr(15 downto 0)))) <= bus_data_out;
                end if;
                if bus_addr(15 downto 0) = x"0400" then
                    if bus_data_out = x"42" then
                        write_seen <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------------
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

        wait for 2 ms;

        report "6502 slot count=" & integer'image(to_integer(slot_count)) &
               " write_count=" & integer'image(to_integer(write_count)) severity note;
        assert slot_count > 0
            report "6502 time-slice slots never occurred"
            severity failure;
        assert write_seen = '1'
            report "6502 did not write expected value to $0400"
            severity failure;

        report "Coprocessor integration test PASSED" severity note;
        wait;
    end process;
end sim;
