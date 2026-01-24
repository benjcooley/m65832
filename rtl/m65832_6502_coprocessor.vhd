-- M65832 6502 Coprocessor Wrapper
-- Keeps 6502 core state separate, uses shared memory/MMU externally
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_6502_Coprocessor is
    port(
        ---------------------------------------------------------------------------
        -- Clock and Reset
        ---------------------------------------------------------------------------
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        CE              : in  std_logic;  -- Clock enable (from interleaver)

        ---------------------------------------------------------------------------
        -- 6502 Interrupts (active high)
        ---------------------------------------------------------------------------
        NMI             : in  std_logic;
        IRQ             : in  std_logic;

        ---------------------------------------------------------------------------
        -- VBR (virtual base for 6502 address space)
        ---------------------------------------------------------------------------
        VBR_IN          : in  std_logic_vector(31 downto 0);
        VBR_LOAD        : in  std_logic;

        ---------------------------------------------------------------------------
        -- Shared Memory Interface (virtual address)
        ---------------------------------------------------------------------------
        ADDR_VA         : out std_logic_vector(31 downto 0);
        DATA_OUT        : out std_logic_vector(7 downto 0);
        DATA_IN         : in  std_logic_vector(7 downto 0);
        WE              : out std_logic;
        RDY             : in  std_logic;

        ---------------------------------------------------------------------------
        -- Shadow I/O Interface (optional)
        ---------------------------------------------------------------------------
        IO_ADDR         : out std_logic_vector(15 downto 0);
        IO_DATA_OUT     : out std_logic_vector(7 downto 0);
        IO_DATA_IN      : in  std_logic_vector(7 downto 0);
        IO_WE           : out std_logic;
        IO_RE           : out std_logic;
        IO_ACK          : in  std_logic;
        IO_HIT          : in  std_logic;

        ---------------------------------------------------------------------------
        -- Bus Status
        ---------------------------------------------------------------------------
        SYNC            : out std_logic
    );
end M65832_6502_Coprocessor;

architecture rtl of M65832_6502_Coprocessor is
    signal vbr_reg     : std_logic_vector(31 downto 0);
    signal ce_core     : std_logic;
    signal addr_16     : std_logic_vector(15 downto 0);
    signal rw          : std_logic;
    signal data_from_bus : std_logic_vector(7 downto 0);
    signal ready       : std_logic;
begin
    ---------------------------------------------------------------------------
    -- VBR register
    ---------------------------------------------------------------------------
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            vbr_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if VBR_LOAD = '1' then
                vbr_reg <= VBR_IN;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Ready/Wait control
    ---------------------------------------------------------------------------
    -- If the address hits shadow I/O, wait for IO_ACK.
    -- Otherwise, wait for memory RDY.
    ready <= IO_ACK when IO_HIT = '1' else RDY;
    ce_core <= CE and ready;

    ---------------------------------------------------------------------------
    -- Data mux (IO vs memory)
    ---------------------------------------------------------------------------
    data_from_bus <= IO_DATA_IN when IO_HIT = '1' else DATA_IN;

    ---------------------------------------------------------------------------
    -- 6502 Core
    ---------------------------------------------------------------------------
    core_6502 : entity work.mx65
        port map (
            clock    => CLK,
            reset    => not RST_N,
            ce       => ce_core,
            data_in  => data_from_bus,
            data_out => DATA_OUT,
            address  => addr_16,
            rw       => rw,
            sync     => SYNC,
            nmi      => NMI,
            irq      => IRQ
        );

    ---------------------------------------------------------------------------
    -- Address translation (virtual address)
    ---------------------------------------------------------------------------
    ADDR_VA <= std_logic_vector(unsigned(vbr_reg) + unsigned(x"0000" & addr_16));

    ---------------------------------------------------------------------------
    -- Bus control
    ---------------------------------------------------------------------------
    WE <= not rw;
    IO_WE <= (not rw) and IO_HIT;
    IO_RE <= rw and IO_HIT;
    IO_DATA_OUT <= DATA_OUT;
    IO_ADDR <= addr_16;
end rtl;
