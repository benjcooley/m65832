-- M65832 PLL Wrapper
-- Generates CPU and SDRAM clocks from 50 MHz input
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Note: This is a behavioral model. For synthesis, replace the body
-- with an Altera PLL megafunction (altera_pll or altpll).
-- Use Quartus MegaWizard to generate the actual PLL.

library IEEE;
use IEEE.std_logic_1164.all;

entity M65832_PLL is
    port(
        CLK_IN      : in  std_logic;    -- 50 MHz input
        RST_N       : in  std_logic;    -- Async reset (active low)
        CLK_CPU     : out std_logic;    -- 50 MHz CPU clock
        CLK_SDRAM   : out std_logic;    -- 100 MHz SDRAM clock (phase-shifted)
        LOCKED      : out std_logic     -- PLL locked indicator
    );
end M65832_PLL;

architecture rtl of M65832_PLL is

    -- For simulation, just pass through the clock
    -- For synthesis, instantiate altera_pll here
    
    component altera_pll is
        generic(
            fractional_vco_multiplier   : string := "false";
            reference_clock_frequency   : string := "50.0 MHz";
            operation_mode              : string := "normal";
            number_of_clocks            : integer := 2;
            output_clock_frequency0     : string := "50.0 MHz";
            phase_shift0                : string := "0 ps";
            duty_cycle0                 : integer := 50;
            output_clock_frequency1     : string := "100.0 MHz";
            phase_shift1                : string := "-2500 ps";  -- -90 degrees at 100 MHz
            duty_cycle1                 : integer := 50;
            pll_type                    : string := "General";
            pll_subtype                 : string := "General"
        );
        port(
            refclk      : in  std_logic;
            rst         : in  std_logic;
            outclk      : out std_logic_vector(1 downto 0);
            locked      : out std_logic
        );
    end component;
    
    signal outclk : std_logic_vector(1 downto 0);

begin

    -- Synthesis: use Altera PLL
    -- synthesis translate_off
    -- Simulation model: just pass clock through
    CLK_CPU   <= CLK_IN;
    CLK_SDRAM <= CLK_IN;
    process(CLK_IN, RST_N)
        variable lock_cnt : integer := 0;
    begin
        if RST_N = '0' then
            lock_cnt := 0;
            LOCKED <= '0';
        elsif rising_edge(CLK_IN) then
            if lock_cnt < 100 then
                lock_cnt := lock_cnt + 1;
                LOCKED <= '0';
            else
                LOCKED <= '1';
            end if;
        end if;
    end process;
    -- synthesis translate_on
    
    -- synthesis read_comments_as_HDL on
    -- u_pll : altera_pll
    --     generic map(
    --         reference_clock_frequency   => "50.0 MHz",
    --         operation_mode              => "normal",
    --         number_of_clocks            => 2,
    --         output_clock_frequency0     => "50.0 MHz",
    --         phase_shift0                => "0 ps",
    --         duty_cycle0                 => 50,
    --         output_clock_frequency1     => "100.0 MHz",
    --         phase_shift1                => "-2500 ps",
    --         duty_cycle1                 => 50
    --     )
    --     port map(
    --         refclk  => CLK_IN,
    --         rst     => not RST_N,
    --         outclk  => outclk,
    --         locked  => LOCKED
    --     );
    -- CLK_CPU   <= outclk(0);
    -- CLK_SDRAM <= outclk(1);
    -- synthesis read_comments_as_HDL off

end rtl;
