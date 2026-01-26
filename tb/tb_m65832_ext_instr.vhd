-- M65832 Extended Instructions Testbench
-- Tests the new extended instruction formats:
--   $02 $80-$87 - Extended ALU with mode byte (reg-target via mode bit)
--   $02 $98 - Shifter/Rotate operations
--   $02 $99 - Sign/Zero extend operations
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.M65832_pkg.all;

entity tb_M65832_Ext_Instr is
end tb_M65832_Ext_Instr;

architecture sim of tb_M65832_Ext_Instr is
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
    signal e_flag   : std_logic;
    signal m_flag   : std_logic_vector(1 downto 0);
    signal x_flag   : std_logic_vector(1 downto 0);

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => x"00");
    signal init_done : std_logic := '0';
    signal test_pass : std_logic := '0';
    signal test_stage : integer := 0;
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
            SYNC    => open
        );

    data_in <= mem(to_integer(unsigned(addr(15 downto 0))));

    process(clk)
        variable pc : integer;
    begin
        if rising_edge(clk) then
            cycle_count <= cycle_count + 1;
            
            if init_done = '0' then
                mem <= (others => x"EA");  -- Fill with NOPs
                
                -- Test program at $8000:
                -- Tests for extended instructions:
                --   $02 $80-$87 - Extended ALU (register-targeted via mode bit)
                --   $02 $98 - Shifter/Rotate
                --   $02 $99 - Sign/Zero Extend
                --
                pc := 16#8000#;
                
                -- CLC; XCE  - Enter native mode (E=0)
                mem(pc) <= x"18"; pc := pc + 1;  -- CLC
                mem(pc) <= x"FB"; pc := pc + 1;  -- XCE
                
                -- SEP #$50 - Set M_WIDTH="01" and X_WIDTH="01" (16-bit mode)
                mem(pc) <= x"E2"; pc := pc + 1;  -- SEP
                mem(pc) <= x"50"; pc := pc + 1;  -- #$50
                
                -- RSET ($02 $30) - Enable register window
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"30"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 1: LD $04, A (Register-targeted ALU)
                ---------------------------------------------------------------
                -- Load A with $1234, then LD R1, A
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$1234
                mem(pc) <= x"34"; pc := pc + 1;
                mem(pc) <= x"12"; pc := pc + 1;
                
                -- $02 $80 $79 $04: LD R1, A (WORD, target=Rn, src=A)
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"80"; pc := pc + 1;
                mem(pc) <= x"79"; pc := pc + 1;  -- size=WORD, target=Rn, addr_mode=A
                mem(pc) <= x"04"; pc := pc + 1;  -- dest_dp = $04 (R1)
                
                -- Store A to $0200 for verification
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0200
                mem(pc) <= x"00"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                -- Read R1 back and store to $0202
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $04
                mem(pc) <= x"04"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0202
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 2: SHL $08, $04, #4 (Shifter - shift left by 4)
                ---------------------------------------------------------------
                -- R1 = $1234, shift left by 4 -> R2 = $12340
                -- $02 $98 [op=000|cnt=00100] $08 $04
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"98"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;  -- SHL (000), count=4 (00100)
                mem(pc) <= x"08"; pc := pc + 1;  -- dest = $08 (R2)
                mem(pc) <= x"04"; pc := pc + 1;  -- src = $04 (R1)
                
                -- Read R2 and store to $0204
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $08
                mem(pc) <= x"08"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0204
                mem(pc) <= x"04"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 3: SHR $0C, $04, #8 (Shifter - shift right by 8)
                ---------------------------------------------------------------
                -- R1 = $1234, shift right by 8 -> R3 = $12
                -- $02 $98 [op=001|cnt=01000] $0C $04
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"98"; pc := pc + 1;
                mem(pc) <= x"28"; pc := pc + 1;  -- SHR (001), count=8 (01000)
                mem(pc) <= x"0C"; pc := pc + 1;  -- dest = $0C (R3)
                mem(pc) <= x"04"; pc := pc + 1;  -- src = $04 (R1)
                
                -- Read R3 and store to $0206
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $0C
                mem(pc) <= x"0C"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0206
                mem(pc) <= x"06"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 4: SEXT8 $10, $0C (Sign extend 8->16/32)
                ---------------------------------------------------------------
                -- First put $FF in R3 (negative when sign extended)
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$00FF
                mem(pc) <= x"FF"; pc := pc + 1;
                mem(pc) <= x"00"; pc := pc + 1;
                mem(pc) <= x"85"; pc := pc + 1;  -- STA $0C (R3)
                mem(pc) <= x"0C"; pc := pc + 1;
                
                -- SEXT8: $02 $99 $00 $10 $0C
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"99"; pc := pc + 1;
                mem(pc) <= x"00"; pc := pc + 1;  -- SEXT8
                mem(pc) <= x"10"; pc := pc + 1;  -- dest = $10 (R4)
                mem(pc) <= x"0C"; pc := pc + 1;  -- src = $0C (R3)
                
                -- Read R4 and store to $0208 (should be $FFFF for 16-bit mode)
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $10
                mem(pc) <= x"10"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0208
                mem(pc) <= x"08"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 5: ZEXT8 $14, $0C (Zero extend 8->16/32)
                ---------------------------------------------------------------
                -- ZEXT8: $02 $99 $02 $14 $0C
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"99"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;  -- ZEXT8
                mem(pc) <= x"14"; pc := pc + 1;  -- dest = $14 (R5)
                mem(pc) <= x"0C"; pc := pc + 1;  -- src = $0C (R3)
                
                -- Read R5 and store to $020A (should be $00FF)
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $14
                mem(pc) <= x"14"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $020A
                mem(pc) <= x"0A"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 6: CLZ $18, $1C (Count leading zeros)
                ---------------------------------------------------------------
                -- Put $0080 in R7 ($1C), CLZ of $00000080 = 24 (binary 00011000)
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$0080
                mem(pc) <= x"80"; pc := pc + 1;
                mem(pc) <= x"00"; pc := pc + 1;
                mem(pc) <= x"85"; pc := pc + 1;  -- STA $1C (R7)
                mem(pc) <= x"1C"; pc := pc + 1;
                
                -- CLZ: $02 $99 $04 $18 $1C
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"99"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;  -- CLZ
                mem(pc) <= x"18"; pc := pc + 1;  -- dest = $18 (R6)
                mem(pc) <= x"1C"; pc := pc + 1;  -- src = $1C (R7)
                
                -- Read R6 and store to $020C (should be $0018 = 24)
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $18
                mem(pc) <= x"18"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $020C
                mem(pc) <= x"0C"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 7: CTZ $20, $24 (Count trailing zeros)
                ---------------------------------------------------------------
                -- Put $0100 in R9 ($24), CTZ of $00000100 = 8
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$0100
                mem(pc) <= x"00"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"85"; pc := pc + 1;  -- STA $24 (R9)
                mem(pc) <= x"24"; pc := pc + 1;
                
                -- CTZ: $02 $99 $05 $20 $24
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"99"; pc := pc + 1;
                mem(pc) <= x"05"; pc := pc + 1;  -- CTZ
                mem(pc) <= x"20"; pc := pc + 1;  -- dest = $20 (R8)
                mem(pc) <= x"24"; pc := pc + 1;  -- src = $24 (R9)
                
                -- Read R8 and store to $020E (should be $0008 = 8)
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $20
                mem(pc) <= x"20"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $020E
                mem(pc) <= x"0E"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- TEST 8: POPCNT $28, $2C (Population count)
                ---------------------------------------------------------------
                -- Put $5555 in R11 ($2C), POPCNT of $00005555 = 8 (alternating bits)
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$5555
                mem(pc) <= x"55"; pc := pc + 1;
                mem(pc) <= x"55"; pc := pc + 1;
                mem(pc) <= x"85"; pc := pc + 1;  -- STA $2C (R11)
                mem(pc) <= x"2C"; pc := pc + 1;
                
                -- POPCNT: $02 $99 $06 $28 $2C
                mem(pc) <= x"02"; pc := pc + 1;
                mem(pc) <= x"99"; pc := pc + 1;
                mem(pc) <= x"06"; pc := pc + 1;  -- POPCNT
                mem(pc) <= x"28"; pc := pc + 1;  -- dest = $28 (R10)
                mem(pc) <= x"2C"; pc := pc + 1;  -- src = $2C (R11)
                
                -- Read R10 and store to $0210 (should be $0008 = 8)
                mem(pc) <= x"A5"; pc := pc + 1;  -- LDA $28
                mem(pc) <= x"28"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0210
                mem(pc) <= x"10"; pc := pc + 1;
                mem(pc) <= x"02"; pc := pc + 1;
                
                ---------------------------------------------------------------
                -- Signal completion by writing $55 to $0300
                ---------------------------------------------------------------
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$55
                mem(pc) <= x"55"; pc := pc + 1;
                mem(pc) <= x"00"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0300
                mem(pc) <= x"00"; pc := pc + 1;
                mem(pc) <= x"03"; pc := pc + 1;
                
                -- Loop forever
                mem(pc) <= x"4C"; pc := pc + 1;
                mem(pc) <= std_logic_vector(to_unsigned(pc mod 256, 8)); pc := pc + 1;
                mem(pc) <= x"80"; pc := pc + 1;
                
                -- Reset vector -> $8000
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"80";
                
                init_done <= '1';
                report "Test program loaded at $8000" severity note;
            end if;

            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                
                -- Check for completion marker
                if addr(15 downto 0) = x"0300" and data_out = x"55" then
                    test_stage <= 1;
                    report "Test completion marker received" severity note;
                end if;
                
                -- Track all memory writes for debugging
                report "[@" & integer'image(cycle_count) & "] Write to $" & 
                       to_hstring(addr(15 downto 0)) & " = $" & to_hstring(data_out)
                    severity note;
            end if;
            
            -- Trace instruction fetches (first 100 cycles only, with flags)
            if cycle_count < 100 and rdy = '1' then
                report "[@" & integer'image(cycle_count) & "] Addr=$" & 
                       to_hstring(addr(15 downto 0)) & " Data=$" & to_hstring(data_in) &
                       " WE=" & std_logic'image(we) &
                       " E=" & std_logic'image(e_flag) & " M=" & to_hstring(m_flag)
                    severity note;
            end if;
        end if;
    end process;

    -- Main test process
    process
        variable test_ok : boolean;
    begin
        report "=== Extended Instructions Test ===" severity note;
        
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';
        report "Reset released, starting execution" severity note;

        -- Wait for test completion or timeout
        wait for 500 us;
        
        -- Check results
        test_ok := true;
        if test_stage = 1 then
            report "Test sequence completed, checking results..." severity note;
            
            -- TEST 1: Check $0200 (LD $04, A: A=$1234)
            if mem(16#0200#) = x"34" and mem(16#0201#) = x"12" then
                report "PASS TEST 1: $0200 = $1234 (LD dp, A)" severity note;
            else
                report "FAIL TEST 1: $0200 = " & to_hstring(mem(16#0201#)) & to_hstring(mem(16#0200#)) & 
                       " (expected $1234)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 1b: Check $0202 (R1 read back)
            if mem(16#0202#) = x"34" and mem(16#0203#) = x"12" then
                report "PASS TEST 1b: $0202 = $1234 (R1 read back)" severity note;
            else
                report "FAIL TEST 1b: $0202 = " & to_hstring(mem(16#0203#)) & to_hstring(mem(16#0202#)) & 
                       " (expected $1234)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 2: Check $0204 (SHL $08, $04, #4: $1234 << 4 = $2340 for 16-bit)
            if mem(16#0204#) = x"40" and mem(16#0205#) = x"23" then
                report "PASS TEST 2: $0204 = $2340 (SHL by 4)" severity note;
            else
                report "FAIL TEST 2: $0204 = " & to_hstring(mem(16#0205#)) & to_hstring(mem(16#0204#)) & 
                       " (expected $2340)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 3: Check $0206 (SHR $0C, $04, #8: $1234 >> 8 = $0012)
            if mem(16#0206#) = x"12" and mem(16#0207#) = x"00" then
                report "PASS TEST 3: $0206 = $0012 (SHR by 8)" severity note;
            else
                report "FAIL TEST 3: $0206 = " & to_hstring(mem(16#0207#)) & to_hstring(mem(16#0206#)) & 
                       " (expected $0012)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 4: Check $0208 (SEXT8 $10, $0C: $00FF -> $FFFF for 16-bit)
            if mem(16#0208#) = x"FF" and mem(16#0209#) = x"FF" then
                report "PASS TEST 4: $0208 = $FFFF (SEXT8)" severity note;
            else
                report "FAIL TEST 4: $0208 = " & to_hstring(mem(16#0209#)) & to_hstring(mem(16#0208#)) & 
                       " (expected $FFFF)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 5: Check $020A (ZEXT8 $14, $0C: $00FF -> $00FF)
            if mem(16#020A#) = x"FF" and mem(16#020B#) = x"00" then
                report "PASS TEST 5: $020A = $00FF (ZEXT8)" severity note;
            else
                report "FAIL TEST 5: $020A = " & to_hstring(mem(16#020B#)) & to_hstring(mem(16#020A#)) & 
                       " (expected $00FF)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 6: Check $020C (CLZ: $00000080 -> 24 = $0018)
            if mem(16#020C#) = x"18" and mem(16#020D#) = x"00" then
                report "PASS TEST 6: $020C = $0018 (CLZ of $0080 = 24)" severity note;
            else
                report "FAIL TEST 6: $020C = " & to_hstring(mem(16#020D#)) & to_hstring(mem(16#020C#)) & 
                       " (expected $0018 = 24)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 7: Check $020E (CTZ: $00000100 -> 8 = $0008)
            if mem(16#020E#) = x"08" and mem(16#020F#) = x"00" then
                report "PASS TEST 7: $020E = $0008 (CTZ of $0100 = 8)" severity note;
            else
                report "FAIL TEST 7: $020E = " & to_hstring(mem(16#020F#)) & to_hstring(mem(16#020E#)) & 
                       " (expected $0008 = 8)" severity error;
                test_ok := false;
            end if;
            
            -- TEST 8: Check $0210 (POPCNT: $00005555 -> 8 = $0008)
            if mem(16#0210#) = x"08" and mem(16#0211#) = x"00" then
                report "PASS TEST 8: $0210 = $0008 (POPCNT of $5555 = 8)" severity note;
            else
                report "FAIL TEST 8: $0210 = " & to_hstring(mem(16#0211#)) & to_hstring(mem(16#0210#)) & 
                       " (expected $0008 = 8)" severity error;
                test_ok := false;
            end if;
            
        else
            report "FAIL: Test did not complete (no write to $0300)" severity error;
            report "Cycles executed: " & integer'image(cycle_count) severity note;
            test_ok := false;
        end if;
        
        if test_ok then
            report "=== ALL EXTENDED INSTRUCTION TESTS PASSED ===" severity note;
        else
            report "=== EXTENDED INSTRUCTION TESTS FAILED ===" severity failure;
        end if;
        
        wait;
    end process;
    
end sim;
