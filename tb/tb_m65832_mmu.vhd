-- M65832 MMU Testbench (subset)
-- Focused MMU MMIO + translation checks
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

entity tb_M65832_MMU is
end entity tb_M65832_MMU;

architecture sim of tb_M65832_MMU is

    ---------------------------------------------------------------------------
    -- Clock and Reset
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal sim_done     : boolean := false;
    
    ---------------------------------------------------------------------------
    -- CPU Interface Signals
    ---------------------------------------------------------------------------
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
    
    ---------------------------------------------------------------------------
    -- Simulated Memory (64KB)
    ---------------------------------------------------------------------------
    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal memory : memory_t := (others => x"00");
    
    -- Test memory write interface (directly sets memory)
    signal test_wr_addr : integer range 0 to 65535 := 0;
    signal test_wr_data : std_logic_vector(7 downto 0) := x"00";
    signal test_wr_en   : std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_number  : integer := 0;
    signal test_passed  : integer := 0;
    signal test_failed  : integer := 0;
    signal cycle_count  : integer := 0;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
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
    
    ---------------------------------------------------------------------------
    -- Cycle Counter
    ---------------------------------------------------------------------------
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
    
    ---------------------------------------------------------------------------
    -- Device Under Test
    ---------------------------------------------------------------------------
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
    
    ---------------------------------------------------------------------------
    -- Memory Model
    ---------------------------------------------------------------------------
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
    
    ---------------------------------------------------------------------------
    -- Test Stimulus
    ---------------------------------------------------------------------------
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
        report "M65832 MMU Testbench Starting";
        report "========================================";
        
        -- Reset/IRQ/NMI/ABORT vectors (standard)
        poke16(16#FFFC#, x"8000");
        poke16(16#FFFE#, x"8100");
        poke16(16#FFFA#, x"8200");
        poke16(16#FFF8#, x"8300");
        
        -----------------------------------------------------------------------
        -- TEST 120: MMU MMIO register reads/writes
        -----------------------------------------------------------------------
        report "";
        report "TEST 120: MMU MMIO regs";
        
        -- Program: enter native, set M=32, write MMUCR/ASID via STA
        poke(16#8000#, x"18");  -- CLC
        poke(16#8001#, x"FB");  -- XCE
        poke(16#8002#, x"C2");  -- REP
        poke(16#8003#, x"40");  -- clear M0
        poke(16#8004#, x"E2");  -- SEP
        poke(16#8005#, x"80");  -- set M1 -> 32-bit
        
        -- MMUCR = 0x00000002
        poke(16#8006#, x"A9");  -- LDA #imm32
        poke(16#8007#, x"02");
        poke(16#8008#, x"00");
        poke(16#8009#, x"00");
        poke(16#800A#, x"00");
        poke(16#800B#, x"8D");  -- STA $F000
        poke(16#800C#, x"00");
        poke(16#800D#, x"F0");
        
        -- Pad to keep execution contiguous
        poke(16#800E#, x"EA");  -- NOP
        poke(16#800F#, x"EA");  -- NOP
        poke(16#8010#, x"EA");  -- NOP
        poke(16#8011#, x"EA");  -- NOP
        poke(16#8012#, x"EA");  -- NOP
        poke(16#8013#, x"EA");  -- NOP
        
        -- ASID = 0x000000AA
        poke(16#8014#, x"A9");  -- LDA #imm32
        poke(16#8015#, x"AA");
        poke(16#8016#, x"00");
        poke(16#8017#, x"00");
        poke(16#8018#, x"00");
        poke(16#8019#, x"8D");  -- STA $F008
        poke(16#801A#, x"08");
        poke(16#801B#, x"F0");
        
        poke(16#8022#, x"02");  -- extended STP
        poke(16#8023#, x"92");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(900);
        
        check_mem(16#F000#, x"02", "MMUCR byte0");
        check_mem(16#F001#, x"00", "MMUCR byte1");
        check_mem(16#F002#, x"00", "MMUCR byte2");
        check_mem(16#F003#, x"00", "MMUCR byte3");
        
        check_mem(16#F008#, x"AA", "ASID byte0");
        check_mem(16#F009#, x"00", "ASID byte1");
        
        -----------------------------------------------------------------------
        -- TEST 121: MMU basic translation
        -----------------------------------------------------------------------
        report "";
        report "TEST 121: MMU basic translation";
        
        -- Page table setup (PTBR=0x00001000)
        -- L1[0] -> L2 at 0x00002000 (P=1)
        poke(16#1000#, x"01");
        poke(16#1001#, x"20");
        poke(16#1002#, x"00");
        poke(16#1003#, x"00");
        poke(16#1004#, x"00");
        poke(16#1005#, x"00");
        poke(16#1006#, x"00");
        poke(16#1007#, x"00");
        
        -- L2[0] -> PA 0x00000000 (P=1, W=1, U=1)
        poke(16#2000#, x"07");
        poke(16#2001#, x"00");
        poke(16#2002#, x"00");
        poke(16#2003#, x"00");
        poke(16#2004#, x"00");
        poke(16#2005#, x"00");
        poke(16#2006#, x"00");
        poke(16#2007#, x"00");
        
        -- L2[3] -> PA 0x00004000 (P=1, W=1, U=1)
        poke(16#2018#, x"07");
        poke(16#2019#, x"40");
        poke(16#201A#, x"00");
        poke(16#201B#, x"00");
        poke(16#201C#, x"00");
        poke(16#201D#, x"00");
        poke(16#201E#, x"00");
        poke(16#201F#, x"00");
        
        -- L2[8] -> PA 0x00008000 (P=1, W=1, U=1) for code fetch
        poke(16#2040#, x"07");
        poke(16#2041#, x"80");
        poke(16#2042#, x"00");
        poke(16#2043#, x"00");
        poke(16#2044#, x"00");
        poke(16#2045#, x"00");
        poke(16#2046#, x"00");
        poke(16#2047#, x"00");
        
        -- Data at physical 0x4000
        poke(16#4000#, x"5A");
        
        -- Program: set PTBR, enable MMU, read VA $3000 -> PA $4000, store to $0500
        -- PTBR low dword = 0x00001000
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"8D");  -- STA $F014
        poke(16#8003#, x"14");
        poke(16#8004#, x"F0");
        poke(16#8005#, x"A9");  -- LDA #$10
        poke(16#8006#, x"10");
        poke(16#8007#, x"8D");  -- STA $F015
        poke(16#8008#, x"15");
        poke(16#8009#, x"F0");
        poke(16#800A#, x"A9");  -- LDA #$00
        poke(16#800B#, x"00");
        poke(16#800C#, x"8D");  -- STA $F016
        poke(16#800D#, x"16");
        poke(16#800E#, x"F0");
        poke(16#800F#, x"A9");  -- LDA #$00
        poke(16#8010#, x"00");
        poke(16#8011#, x"8D");  -- STA $F017
        poke(16#8012#, x"17");
        poke(16#8013#, x"F0");
        
        -- PTBR high dword = 0x00000000
        poke(16#8014#, x"A9");  -- LDA #$00
        poke(16#8015#, x"00");
        poke(16#8016#, x"8D");  -- STA $F018
        poke(16#8017#, x"18");
        poke(16#8018#, x"F0");
        poke(16#8019#, x"A9");  -- LDA #$00
        poke(16#801A#, x"00");
        poke(16#801B#, x"8D");  -- STA $F019
        poke(16#801C#, x"19");
        poke(16#801D#, x"F0");
        poke(16#801E#, x"A9");  -- LDA #$00
        poke(16#801F#, x"00");
        poke(16#8020#, x"8D");  -- STA $F01A
        poke(16#8021#, x"1A");
        poke(16#8022#, x"F0");
        poke(16#8023#, x"A9");  -- LDA #$00
        poke(16#8024#, x"00");
        poke(16#8025#, x"8D");  -- STA $F01B
        poke(16#8026#, x"1B");
        poke(16#8027#, x"F0");
        
        -- Enable MMU (MMUCR.PG)
        poke(16#8028#, x"A9");  -- LDA #$01
        poke(16#8029#, x"01");
        poke(16#802A#, x"8D");  -- STA $F000
        poke(16#802B#, x"00");
        poke(16#802C#, x"F0");
        
        -- Read back MMUCR to verify enable latch
        poke(16#802D#, x"AD");  -- LDA $F000
        poke(16#802E#, x"00");
        poke(16#802F#, x"F0");
        poke(16#8030#, x"8D");  -- STA $0502
        poke(16#8031#, x"02");
        poke(16#8032#, x"05");
        
        -- Read VA $3000, store to $0500
        poke(16#8033#, x"AD");  -- LDA $3000
        poke(16#8034#, x"00");
        poke(16#8035#, x"30");
        poke(16#8036#, x"8D");  -- STA $0500
        poke(16#8037#, x"00");
        poke(16#8038#, x"05");
        poke(16#8039#, x"02");  -- extended STP
        poke(16#803A#, x"92");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(1200);

        check_mem(16#0502#, x"01", "MMUCR readback");
        check_mem(16#0500#, x"5A", "MMU translated read");
        
        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        report "";
        report "========================================";
        report "MMU TEST SUMMARY";
        report "========================================";
        report "Total tests: " & integer'image(test_number);
        report "Passed:      " & integer'image(test_passed);
        report "Failed:      " & integer'image(test_failed);
        report "========================================";
        
        if test_failed = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;
        
        wait_cycles(10);
        sim_done <= true;
        wait;
        
    end process;

end architecture sim;
