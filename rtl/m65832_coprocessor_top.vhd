-- M65832 Coprocessor Top-Level Integration
-- Interleaves main core and 6502 coprocessor with shared memory
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_Coprocessor_Top is
    port(
        ---------------------------------------------------------------------------
        -- Clock and Reset
        ---------------------------------------------------------------------------
        CLK             : in  std_logic;
        RST_N           : in  std_logic;

        ---------------------------------------------------------------------------
        -- Scheduler Configuration
        ---------------------------------------------------------------------------
        TARGET_FREQ     : in  std_logic_vector(31 downto 0);
        MASTER_FREQ     : in  std_logic_vector(31 downto 0);
        ENABLE          : in  std_logic;

        ---------------------------------------------------------------------------
        -- Shared Memory Interface (virtual address)
        ---------------------------------------------------------------------------
        BUS_ADDR        : out std_logic_vector(31 downto 0);
        BUS_DATA_OUT    : out std_logic_vector(7 downto 0);
        BUS_DATA_IN     : in  std_logic_vector(7 downto 0);
        BUS_WE          : out std_logic;
        BUS_RDY         : in  std_logic;

        ---------------------------------------------------------------------------
        -- 6502 VBR control
        ---------------------------------------------------------------------------
        VBR_IN          : in  std_logic_vector(31 downto 0);
        VBR_LOAD        : in  std_logic;

        ---------------------------------------------------------------------------
        -- 6502 compatibility control
        ---------------------------------------------------------------------------
        COMPAT_IN       : in  std_logic_vector(7 downto 0);
        COMPAT_LOAD     : in  std_logic;
        COMPAT_OUT      : out std_logic_vector(7 downto 0);

        ---------------------------------------------------------------------------
        -- Shadow I/O configuration
        ---------------------------------------------------------------------------
        BANK0_BASE      : in  std_logic_vector(15 downto 0);
        BANK1_BASE      : in  std_logic_vector(15 downto 0);
        BANK2_BASE      : in  std_logic_vector(15 downto 0);
        BANK3_BASE      : in  std_logic_vector(15 downto 0);
        FRAME_NUMBER    : in  std_logic_vector(15 downto 0);

        ---------------------------------------------------------------------------
        -- Shadow I/O IRQ response (main CPU handler)
        ---------------------------------------------------------------------------
        IRQ_DATA        : in  std_logic_vector(7 downto 0);
        IRQ_VALID       : in  std_logic;
        IRQ_REQ         : out std_logic;
        IRQ_ADDR        : out std_logic_vector(15 downto 0);

        ---------------------------------------------------------------------------
        -- Debug
        ---------------------------------------------------------------------------
        CORE_SEL_OUT    : out std_logic_vector(1 downto 0)
    );
end M65832_Coprocessor_Top;

architecture rtl of M65832_Coprocessor_Top is
    signal core_sel     : std_logic_vector(1 downto 0);
    signal ce_main      : std_logic;
    signal ce_6502      : std_logic;

    signal m_addr       : std_logic_vector(31 downto 0);
    signal m_data_out   : std_logic_vector(7 downto 0);
    signal m_we         : std_logic;

    signal c_addr       : std_logic_vector(31 downto 0);
    signal c_data_out   : std_logic_vector(7 downto 0);
    signal c_we         : std_logic;

    signal c_io_addr    : std_logic_vector(15 downto 0);
    signal c_io_data_out: std_logic_vector(7 downto 0);
    signal c_io_data_in : std_logic_vector(7 downto 0);
    signal c_io_we      : std_logic;
    signal c_io_re      : std_logic;
    signal c_io_ack     : std_logic;
    signal c_io_hit     : std_logic;

    signal cycle_count  : std_logic_vector(19 downto 0);
    signal irq_req_int  : std_logic;
    signal irq_addr_int : std_logic_vector(15 downto 0);
begin
    ---------------------------------------------------------------------------
    -- Interleaver (time slicing)
    ---------------------------------------------------------------------------
    interleave_inst : entity work.M65832_Interleave
        port map (
            CLK             => CLK,
            RST_N           => RST_N,
            TARGET_FREQ     => TARGET_FREQ,
            MASTER_FREQ     => MASTER_FREQ,
            ENABLE          => ENABLE,
            CORE_SEL        => core_sel,
            CE_M65832       => ce_main,
            CE_6502         => ce_6502,
            CYCLE_COUNT     => cycle_count,
            BEAM_X          => open,
            BEAM_Y          => open,
            ACTIVE_6502     => open,
            CYCLES_SINCE    => open
        );

    ---------------------------------------------------------------------------
    -- Main M65832 core
    ---------------------------------------------------------------------------
    main_core : entity work.M65832_Core
        port map (
            CLK     => CLK,
            RST_N   => RST_N,
            CE      => ce_main,
            ADDR    => m_addr,
            DATA_OUT=> m_data_out,
            DATA_IN => BUS_DATA_IN,
            WE      => m_we,
            RDY     => BUS_RDY,
            VPA     => open,
            VDA     => open,
            VPB     => open,
            MLB     => open,
            NMI_N   => '1',
            IRQ_N   => not irq_req_int,
            ABORT_N => '1',
            E_FLAG  => open,
            M_FLAG  => open,
            X_FLAG  => open,
            SYNC    => open
        );

    ---------------------------------------------------------------------------
    -- 6502 Coprocessor
    ---------------------------------------------------------------------------
    cop_6502 : entity work.M65832_6502_Coprocessor
        port map (
            CLK         => CLK,
            RST_N       => RST_N,
            CE          => ce_6502,
            NMI         => '1',
            IRQ         => '1',
            VBR_IN      => VBR_IN,
            VBR_LOAD    => VBR_LOAD,
            COMPAT_IN   => COMPAT_IN,
            COMPAT_LOAD => COMPAT_LOAD,
            COMPAT_OUT  => COMPAT_OUT,
            ADDR_VA     => c_addr,
            DATA_OUT    => c_data_out,
            DATA_IN     => BUS_DATA_IN,
            WE          => c_we,
            RDY         => BUS_RDY,
            IO_ADDR     => c_io_addr,
            IO_DATA_OUT => c_io_data_out,
            IO_DATA_IN  => c_io_data_in,
            IO_WE       => c_io_we,
            IO_RE       => c_io_re,
            IO_ACK      => c_io_ack,
            IO_HIT      => c_io_hit,
            SYNC        => open
        );

    ---------------------------------------------------------------------------
    -- Shadow I/O (MMIO front door)
    ---------------------------------------------------------------------------
    shadow_io : entity work.M65832_Shadow_IO
        port map (
            CLK          => CLK,
            RST_N        => RST_N,
            IO_ADDR      => c_io_addr,
            IO_DATA_IN   => c_io_data_out,
            IO_DATA_OUT  => c_io_data_in,
            IO_WE        => c_io_we,
            IO_RE        => c_io_re,
            IO_ACK       => c_io_ack,
            IO_HIT       => c_io_hit,
            CYCLE_COUNT  => cycle_count,
            FRAME_NUMBER => FRAME_NUMBER,
            IRQ_REQ      => irq_req_int,
            IRQ_ADDR     => irq_addr_int,
            IRQ_DATA     => IRQ_DATA,
            IRQ_VALID    => IRQ_VALID,
            SHADOW_BANK  => (others => '0'),
            SHADOW_REG   => (others => '0'),
            SHADOW_DATA  => open,
            FIFO_RD      => '0',
            FIFO_EMPTY   => open,
            FIFO_DATA    => open,
            FIFO_COUNT   => open,
            BANK0_BASE   => BANK0_BASE,
            BANK1_BASE   => BANK1_BASE,
            BANK2_BASE   => BANK2_BASE,
            BANK3_BASE   => BANK3_BASE,
            FIFO_OVERFLOW=> open
        );

    ---------------------------------------------------------------------------
    -- Shared memory mux
    ---------------------------------------------------------------------------
    BUS_ADDR     <= m_addr when core_sel = "00" else c_addr;
    BUS_DATA_OUT <= m_data_out when core_sel = "00" else c_data_out;
    BUS_WE       <= m_we when core_sel = "00" else c_we;

    CORE_SEL_OUT <= core_sel;
    IRQ_REQ <= irq_req_int;
    IRQ_ADDR <= irq_addr_int;
end rtl;
