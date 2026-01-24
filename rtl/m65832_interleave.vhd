-- M65832 Classic Coprocessor Interleaver
-- Manages cycle-accurate 6502 and main core interleaving
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This implements the two-core interleaved architecture:
-- 1. M65832 main core (Linux, ~90% of cycles)
-- 2. 6502 game core (cycle-accurate classic, ~2% of cycles)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_Interleave is
    port(
        ---------------------------------------------------------------------------
        -- Clock and Reset
        ---------------------------------------------------------------------------
        CLK             : in  std_logic;  -- Master clock (e.g., 50 MHz)
        RST_N           : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Configuration (memory-mapped control registers)
        ---------------------------------------------------------------------------
        -- Target 6502 frequency in Hz (e.g., 1022727 for C64 NTSC)
        TARGET_FREQ     : in  std_logic_vector(31 downto 0);
        -- Master clock frequency in Hz (e.g., 50000000 for 50 MHz)
        MASTER_FREQ     : in  std_logic_vector(31 downto 0);
        -- Enable classic coprocessor
        ENABLE          : in  std_logic;
        ---------------------------------------------------------------------------
        -- Core Select Outputs
        ---------------------------------------------------------------------------
        -- Which core should execute this cycle
        CORE_SEL        : out std_logic_vector(1 downto 0);
        -- "00" = M65832 main core
        -- "01" = 6502 game core  
        -- "10" = Reserved
        -- "11" = Reserved
        
        -- Clock enables for each core
        CE_M65832       : out std_logic;  -- M65832 clock enable
        CE_6502         : out std_logic;  -- 6502 clock enable
        
        ---------------------------------------------------------------------------
        -- Timing Outputs (for cycle-accurate emulation)
        ---------------------------------------------------------------------------
        -- Current cycle count within frame (for beam position)
        CYCLE_COUNT     : out std_logic_vector(19 downto 0);
        -- Beam position (computed from cycle count)
        BEAM_X          : out std_logic_vector(9 downto 0);
        BEAM_Y          : out std_logic_vector(9 downto 0);
        
        ---------------------------------------------------------------------------
        -- Status
        ---------------------------------------------------------------------------
        -- 6502 is active (for debugging)
        ACTIVE_6502     : out std_logic;
        -- Cycles since last 6502 tick
        CYCLES_SINCE    : out std_logic_vector(7 downto 0)
    );
end M65832_Interleave;

architecture rtl of M65832_Interleave is

    ---------------------------------------------------------------------------
    -- Fractional Clock Divider (Bresenham-style accumulator)
    ---------------------------------------------------------------------------
    -- This generates precise 6502 timing even when master clock is not
    -- an exact multiple of the target frequency.
    --
    -- Example: 50 MHz master, 1.022727 MHz target (C64 NTSC)
    -- Ratio = 50000000 / 1022727 ≈ 48.9
    -- So 6502 gets 1 cycle every ~49 master cycles on average
    -- Accumulator ensures exact long-term frequency match
    
    signal accumulator      : unsigned(31 downto 0);
    signal tick_6502        : std_logic;
    
    ---------------------------------------------------------------------------
    -- Cycle Counting
    ---------------------------------------------------------------------------
    
    signal cycle_cnt        : unsigned(19 downto 0);
    signal cycles_since_tick : unsigned(7 downto 0);
    
    -- Frame timing (configurable per system)
    constant CYCLES_PER_LINE : unsigned(9 downto 0) := to_unsigned(63, 10);   -- C64: 63 cycles/line
    constant LINES_PER_FRAME : unsigned(9 downto 0) := to_unsigned(312, 10);  -- PAL: 312 lines
    
    signal beam_x_reg       : unsigned(9 downto 0);
    signal beam_y_reg       : unsigned(9 downto 0);
    
    ---------------------------------------------------------------------------
    -- Core Selection
    ---------------------------------------------------------------------------
    
    signal core_sel_reg     : std_logic_vector(1 downto 0);
    signal active_6502_reg  : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Fractional Clock Divider
    ---------------------------------------------------------------------------
    -- Generates tick_6502 pulse at exactly TARGET_FREQ Hz
    -- Uses accumulator-based scheduling (like Bresenham's algorithm)
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            accumulator <= (others => '0');
            tick_6502 <= '0';
        elsif rising_edge(CLK) then
            tick_6502 <= '0';  -- Default: no tick
            
            if ENABLE = '1' then
                -- Add target frequency to accumulator each cycle
                accumulator <= accumulator + unsigned(TARGET_FREQ);
                
                -- Check for overflow (time for a 6502 cycle)
                if accumulator >= unsigned(MASTER_FREQ) then
                    -- Subtract master frequency (keep remainder for precision)
                    accumulator <= accumulator - unsigned(MASTER_FREQ);
                    tick_6502 <= '1';  -- Trigger 6502 execution
                end if;
            else
                accumulator <= (others => '0');
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Core Selection Logic
    ---------------------------------------------------------------------------
    -- Priority: 6502 > M65832
    -- This implements "cycle stealing" from M65832
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            core_sel_reg <= "00";
            active_6502_reg <= '0';
        elsif rising_edge(CLK) then
            -- Default: M65832 runs
            core_sel_reg <= "00";
            active_6502_reg <= '0';
            
            if ENABLE = '1' then
                if tick_6502 = '1' then
                    -- 6502 gets this cycle
                    core_sel_reg <= "01";
                    active_6502_reg <= '1';
                else
                    -- M65832 runs
                    core_sel_reg <= "00";
                end if;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Clock Enable Generation
    ---------------------------------------------------------------------------
    
    CE_M65832   <= '1' when core_sel_reg = "00" else '0';
    CE_6502     <= '1' when core_sel_reg = "01" else '0';
    
    ---------------------------------------------------------------------------
    -- Cycle Counter and Beam Position
    ---------------------------------------------------------------------------
    -- Tracks cycles for accurate beam position calculation
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            cycle_cnt <= (others => '0');
            beam_x_reg <= (others => '0');
            beam_y_reg <= (others => '0');
            cycles_since_tick <= (others => '0');
        elsif rising_edge(CLK) then
            if ENABLE = '1' then
                -- Count cycles since last 6502 tick
                if tick_6502 = '1' then
                    cycles_since_tick <= (others => '0');
                    
                    -- Update beam position
                    if beam_x_reg >= CYCLES_PER_LINE - 1 then
                        beam_x_reg <= (others => '0');
                        if beam_y_reg >= LINES_PER_FRAME - 1 then
                            beam_y_reg <= (others => '0');
                            cycle_cnt <= (others => '0');
                        else
                            beam_y_reg <= beam_y_reg + 1;
                        end if;
                    else
                        beam_x_reg <= beam_x_reg + 1;
                    end if;
                    
                    cycle_cnt <= cycle_cnt + 1;
                else
                    if cycles_since_tick < 255 then
                        cycles_since_tick <= cycles_since_tick + 1;
                    end if;
                end if;
            else
                cycle_cnt <= (others => '0');
                beam_x_reg <= (others => '0');
                beam_y_reg <= (others => '0');
                cycles_since_tick <= (others => '0');
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    
    CORE_SEL        <= core_sel_reg;
    CYCLE_COUNT     <= std_logic_vector(cycle_cnt);
    BEAM_X          <= std_logic_vector(beam_x_reg);
    BEAM_Y          <= std_logic_vector(beam_y_reg);
    ACTIVE_6502     <= active_6502_reg;
    CYCLES_SINCE    <= std_logic_vector(cycles_since_tick);

end rtl;
