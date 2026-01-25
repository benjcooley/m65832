-- M65832 Timer Testbench (isolated)
-- Focuses on TIMER_CTRL/CMP/COUNT behavior and IRQ
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;
use IEEE.std_logic_textio.all;

library work;
use work.M65832_pkg.all;

entity tb_M65832_Timer is
end entity tb_M65832_Timer;

architecture sim of tb_M65832_Timer is
    constant CLK_PERIOD : time := 20 ns;
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal sim_done     : boolean := false;

    signal addr         : std_logic_vector(31 downto 0);
    signal data_out     : std_logic_vector(7 downto 0);
    signal data_in      : std_logic_vector(7 downto 0);
    signal we           : std_logic;
    signal ce           : std_logic := '1';
    signal vda          : std_logic;
    signal vpa          : std_logic;
    signal vpb          : std_logic;
    signal mlb          : std_logic;
    signal rdy          : std_logic := '1';
    signal irq_n        : std_logic := '1';
    signal nmi_n        : std_logic := '1';
    signal abort_n      : std_logic := '1';
    signal e_flag       : std_logic;
    signal m_flag       : std_logic_vector(1 downto 0);
    signal x_flag       : std_logic_vector(1 downto 0);
    signal sync_out     : std_logic;

    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal memory : memory_t := (others => x"00");

    signal test_wr_addr : integer range 0 to 65535 := 0;
    signal test_wr_data : std_logic_vector(7 downto 0) := x"00";
    signal test_wr_en   : std_logic := '0';

    signal test_number  : integer := 0;
    signal test_passed  : integer := 0;
    signal test_failed  : integer := 0;
    signal cycle_count  : integer := 0;
begin
    clk_process: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    cycle_counter: process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                cycle_count <= 0;
            else
                cycle_count <= cycle_count + 1;
            end if;
        end if;
    end process;

    DUT: entity work.M65832_Core
        port map (
            CLK         => clk,
            RST_N       => rst_n,
            CE          => ce,
            ADDR        => addr,
            DATA_OUT    => data_out,
            DATA_IN     => data_in,
            WE          => we,
            RDY         => rdy,
            VPA         => vpa,
            VDA         => vda,
            VPB         => vpb,
            MLB         => mlb,
            NMI_N       => nmi_n,
            IRQ_N       => irq_n,
            ABORT_N     => abort_n,
            E_FLAG      => e_flag,
            M_FLAG      => m_flag,
            X_FLAG      => x_flag,
            SYNC        => sync_out
        );

    data_in <= memory(to_integer(unsigned(addr(15 downto 0))));

    memory_process: process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            if test_wr_en = '1' then
                memory(test_wr_addr) <= test_wr_data;
            elsif we = '1' then
                addr_int := to_integer(unsigned(addr(15 downto 0)));
                memory(addr_int) <= data_out;
            end if;
        end if;
    end process;

    test_process: process
        procedure poke(addr_val : integer; data_val : std_logic_vector(7 downto 0)) is
        begin
            test_wr_addr <= addr_val;
            test_wr_data <= data_val;
            test_wr_en <= '1';
            wait until rising_edge(clk);
            test_wr_en <= '0';
        end procedure;

        procedure poke16(addr_val : integer; data_val : std_logic_vector(15 downto 0)) is
        begin
            poke(addr_val, data_val(7 downto 0));
            poke(addr_val + 1, data_val(15 downto 8));
        end procedure;

        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure check_mem(addr_val : integer; expected : std_logic_vector(7 downto 0); msg : string) is
            variable addr_slv : std_logic_vector(15 downto 0);
        begin
            test_number <= test_number + 1;
            addr_slv := std_logic_vector(to_unsigned(addr_val, 16));
            if memory(addr_val) = expected then
                test_passed <= test_passed + 1;
                report "PASS: " & msg & " - $" & to_hstring(addr_slv) &
                       " = $" & to_hstring(memory(addr_val));
            else
                test_failed <= test_failed + 1;
                report "FAIL: " & msg & " - $" & to_hstring(addr_slv) &
                       " = $" & to_hstring(memory(addr_val)) &
                       " expected $" & to_hstring(expected)
                    severity error;
            end if;
        end procedure;
    begin
        report "========================================";
        report "M65832 Timer Testbench Starting";
        report "========================================";

        -- IRQ vector at $FFFE/$FFFF -> $8800
        poke16(16#FFFE#, x"8800");

        -- Timer IRQ handler at $8800: mark, clear pending, RTI
        poke(16#8800#, x"A9");  -- LDA #$5A
        poke(16#8801#, x"5A");
        poke(16#8802#, x"8D");  -- STA $0600
        poke(16#8803#, x"00");
        poke(16#8804#, x"06");
        poke(16#8805#, x"A9");  -- LDA #$0D (enable+irq+clear)
        poke(16#8806#, x"0D");
        poke(16#8807#, x"8D");  -- STA $F040 (TIMER_CTRL)
        poke(16#8808#, x"40");
        poke(16#8809#, x"F0");
        poke(16#880A#, x"40");  -- RTI

        -- Program: enable IRQs, set CMP=0x10, enable timer, WAI, read CMP+COUNT, STP
        poke(16#8000#, x"58");  -- CLI

        poke(16#8001#, x"A9");  -- LDA #$10
        poke(16#8002#, x"10");
        poke(16#8003#, x"8D");  -- STA $F044 (TIMER_CMP low)
        poke(16#8004#, x"44");
        poke(16#8005#, x"F0");
        poke(16#8006#, x"A9");  -- LDA #$00
        poke(16#8007#, x"00");
        poke(16#8008#, x"8D");  -- STA $F045
        poke(16#8009#, x"45");
        poke(16#800A#, x"F0");
        poke(16#800B#, x"8D");  -- STA $F046
        poke(16#800C#, x"46");
        poke(16#800D#, x"F0");
        poke(16#800E#, x"8D");  -- STA $F047
        poke(16#800F#, x"47");
        poke(16#8010#, x"F0");

        poke(16#8011#, x"A9");  -- LDA #$00
        poke(16#8012#, x"00");
        poke(16#8013#, x"8D");  -- STA $F048 (TIMER_COUNT low)
        poke(16#8014#, x"48");
        poke(16#8015#, x"F0");
        poke(16#8016#, x"8D");  -- STA $F049
        poke(16#8017#, x"49");
        poke(16#8018#, x"F0");
        poke(16#8019#, x"8D");  -- STA $F04A
        poke(16#801A#, x"4A");
        poke(16#801B#, x"F0");
        poke(16#801C#, x"8D");  -- STA $F04B
        poke(16#801D#, x"4B");
        poke(16#801E#, x"F0");

        poke(16#801F#, x"A9");  -- LDA #$05 (enable+irq)
        poke(16#8020#, x"05");
        poke(16#8021#, x"8D");  -- STA $F040 (TIMER_CTRL)
        poke(16#8022#, x"40");
        poke(16#8023#, x"F0");

        poke(16#8024#, x"CB");  -- WAI
        poke(16#8025#, x"AD");  -- LDA $F044 (TIMER_CMP low)
        poke(16#8026#, x"44");
        poke(16#8027#, x"F0");
        poke(16#8028#, x"8D");  -- STA $0602
        poke(16#8029#, x"02");
        poke(16#802A#, x"06");
        poke(16#802B#, x"AD");  -- LDA $F048 (TIMER_COUNT low)
        poke(16#802C#, x"48");
        poke(16#802D#, x"F0");
        poke(16#802E#, x"8D");  -- STA $0601
        poke(16#802F#, x"01");
        poke(16#8030#, x"06");
        poke(16#8031#, x"DB");  -- STP

        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(800);

        check_mem(16#0600#, x"5A", "Timer IRQ handler ran");
        check_mem(16#0602#, x"10", "Timer CMP readback");
        check_mem(16#0601#, x"10", "Timer COUNT latched");

        report "========================================";
        report "Timer Test Summary";
        report "Total tests: " & integer'image(test_number);
        report "Passed:      " & integer'image(test_passed);
        report "Failed:      " & integer'image(test_failed);
        report "========================================";

        sim_done <= true;
        wait;
    end process;
end architecture sim;
