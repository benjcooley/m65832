-- tb_m65832_jsr_debug.vhd
-- Minimal JSR/RTS debug test

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_JSR_Debug is
end tb_M65832_JSR_Debug;

architecture sim of tb_M65832_JSR_Debug is
    constant CLK_PERIOD : time := 20 ns;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal addr     : std_logic_vector(31 downto 0);
    signal data_out : std_logic_vector(7 downto 0);
    signal data_in  : std_logic_vector(7 downto 0);
    signal we       : std_logic;
    signal rdy      : std_logic := '1';

    signal irq_n    : std_logic := '1';
    signal nmi_n    : std_logic := '1';
    signal abort_n  : std_logic := '1';
    signal sync_out : std_logic;
    signal e_flag   : std_logic;
    signal m_flag   : std_logic_vector(1 downto 0);
    signal x_flag   : std_logic_vector(1 downto 0);

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (
        -- Program at $8000:
        -- JSR $8010   -> jump to subroutine
        -- STA $0205   -> store result
        -- STP         -> stop
        16#8000# => x"20",  -- JSR abs
        16#8001# => x"10",  -- $10
        16#8002# => x"80",  -- $80  -> target $8010

        16#8003# => x"8D",  -- STA abs
        16#8004# => x"05",  -- $05
        16#8005# => x"02",  -- $02  -> $0205

        16#8006# => x"DB",  -- STP

        -- Subroutine at $8010:
        -- LDA #$99
        -- RTS
        16#8010# => x"A9",  -- LDA #
        16#8011# => x"99",  -- $99
        16#8012# => x"60",  -- RTS

        others => x"00"
    );

    signal cycle_count : integer := 0;

begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.M65832_Core
        port map (
            CLK     => clk,
            RST_N   => rst_n,
            CE      => '1',
            ADDR    => addr,
            DATA_OUT=> data_out,
            DATA_IN => data_in,
            WE      => we,
            RDY     => rdy,
            VPA     => open,
            VDA     => open,
            VPB     => open,
            MLB     => open,
            NMI_N   => nmi_n,
            IRQ_N   => irq_n,
            ABORT_N => abort_n,
            E_FLAG  => e_flag,
            M_FLAG  => m_flag,
            X_FLAG  => x_flag,
            SYNC    => sync_out
        );

    data_in <= mem(to_integer(unsigned(addr(15 downto 0))));

    -- Memory write process
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
            end if;
        end if;
    end process;

    -- Full cycle trace
    process(clk)
    begin
        if rising_edge(clk) then
            cycle_count <= cycle_count + 1;
            if rst_n = '1' and cycle_count < 80 then
                report "cycle=" & integer'image(cycle_count) &
                       " addr=$" & to_hstring(addr(15 downto 0)) &
                       " din=$" & to_hstring(mem(to_integer(unsigned(addr(15 downto 0))))) &
                       " dout=$" & to_hstring(data_out) &
                       " we=" & std_logic'image(we)(2) &
                       " sync=" & std_logic'image(sync_out)(2) &
                       " E=" & std_logic'image(e_flag)(2) &
                       " M=" & to_hstring(m_flag)
                    severity note;
            end if;
            if we = '1' and rdy = '1' and rst_n = '1' then
                report "  >>> WRITE $" & to_hstring(addr(15 downto 0)) &
                       " <= $" & to_hstring(data_out) &
                       " @ cycle " & integer'image(cycle_count)
                    severity note;
            end if;
        end if;
    end process;

    -- Main test process
    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';

        wait for 100 us;

        report "=== JSR/RTS Debug Results ===" severity note;

        if mem(16#0205#) = x"99" then
            report "PASS: $0205 = $99" severity note;
        else
            report "FAIL: $0205 = $" & to_hstring(mem(16#0205#)) &
                   " (expected $99)" severity error;
        end if;

        -- Show stack area
        report "Stack: $01FF=" & to_hstring(mem(16#01FF#)) &
               " $01FE=" & to_hstring(mem(16#01FE#)) &
               " $01FD=" & to_hstring(mem(16#01FD#)) severity note;

        wait;
    end process;
end sim;
