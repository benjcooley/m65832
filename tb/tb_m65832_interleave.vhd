-- M65832 Interleave Scheduler Testbench

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_Interleave is
end tb_M65832_Interleave;

architecture sim of tb_M65832_Interleave is
    constant CLK_PERIOD : time := 20 ns;

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';

    signal target_freq : std_logic_vector(31 downto 0);
    signal master_freq : std_logic_vector(31 downto 0);
    signal enable      : std_logic := '0';

    signal core_sel    : std_logic_vector(1 downto 0);
    signal ce_main     : std_logic;
    signal ce_6502     : std_logic;

    signal cycle_count : std_logic_vector(19 downto 0);
    signal beam_x      : std_logic_vector(9 downto 0);
    signal beam_y      : std_logic_vector(9 downto 0);
    signal active_6502 : std_logic;
    signal cycles_since: std_logic_vector(7 downto 0);

    signal tick_count  : unsigned(15 downto 0) := (others => '0');
    signal cycle_idx   : integer := 0;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.M65832_Interleave
        port map (
            CLK             => clk,
            RST_N           => rst_n,
            TARGET_FREQ     => target_freq,
            MASTER_FREQ     => master_freq,
            ENABLE          => enable,
            CORE_SEL        => core_sel,
            CE_M65832       => ce_main,
            CE_6502         => ce_6502,
            CYCLE_COUNT     => cycle_count,
            BEAM_X          => beam_x,
            BEAM_Y          => beam_y,
            ACTIVE_6502     => active_6502,
            CYCLES_SINCE    => cycles_since
        );

    process(clk)
        variable acc : unsigned(31 downto 0) := (others => '0');
        variable expected_ticks : integer := 0;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                tick_count <= (others => '0');
                cycle_idx <= 0;
                acc := (others => '0');
                expected_ticks := 0;
            elsif enable = '1' then
                cycle_idx <= cycle_idx + 1;
                if ce_6502 = '1' then
                    tick_count <= tick_count + 1;
                end if;

                -- mirror the Bresenham accumulator
                acc := acc + unsigned(target_freq);
                if acc >= unsigned(master_freq) then
                    acc := acc - unsigned(master_freq);
                    expected_ticks := expected_ticks + 1;
                end if;

                if cycle_idx = 99 then
                    assert to_integer(tick_count) = expected_ticks
                        report "Tick count mismatch: expected " &
                               integer'image(expected_ticks) &
                               " got " & integer'image(to_integer(tick_count))
                        severity failure;
                end if;
            end if;
        end if;
    end process;

    process
    begin
        target_freq <= std_logic_vector(to_unsigned(3, 32));
        master_freq <= std_logic_vector(to_unsigned(10, 32));

        rst_n <= '0';
        enable <= '0';
        wait for 100 ns;
        rst_n <= '1';
        enable <= '1';

        wait for 2 us;
        report "Interleave test PASSED" severity note;
        wait;
    end process;
end sim;
