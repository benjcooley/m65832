-- M65832 Package
-- Extends 65816 architecture to 32-bit
-- 
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Based on P65816 by srg320 (MiSTer project)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package M65832_pkg is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    
    -- Data widths (controlled by M1:M0 and X1:X0 flags)
    constant WIDTH_8   : std_logic_vector(1 downto 0) := "00";
    constant WIDTH_16  : std_logic_vector(1 downto 0) := "01";
    constant WIDTH_32  : std_logic_vector(1 downto 0) := "10";
    -- "11" reserved
    
    -- Address spaces
    constant VA_WIDTH  : integer := 32;  -- Virtual address width
    constant PA_WIDTH  : integer := 65;  -- Physical address width (via paging)
    constant PAGE_BITS : integer := 12;  -- 4KB pages

    
    -- Register window
    constant REG_COUNT : integer := 64;  -- 64 x 32-bit registers in window
    constant REG_BITS  : integer := 6;   -- log2(64)
    
    ---------------------------------------------------------------------------
    -- CPU Modes
    ---------------------------------------------------------------------------
    
    type cpu_mode_t is (
        MODE_EMU,       -- E=1: 6502 emulation mode
        MODE_NATIVE16,  -- E=0, W=0: 65816-compatible native mode
        MODE_NATIVE32   -- E=0, W=1: Full 32-bit native mode
    );
    
    ---------------------------------------------------------------------------
    -- ALU Control (extended from 65816)
    ---------------------------------------------------------------------------
    
    type ALUCtrl_r is record
        fstOp   : std_logic_vector(2 downto 0);  -- First operation (shift/rotate/pass)
        secOp   : std_logic_vector(2 downto 0);  -- Second operation (logic/arith)
        fc      : std_logic;                      -- Function control (BIT, SBC variants)
        w16     : std_logic;                      -- 16-bit operation (65816 compat)
        w32     : std_logic;                      -- 32-bit operation (M65832 extension)
    end record;
    
    -- ALU first-stage operations (unchanged from 65816)
    constant ALU_FST_ASL  : std_logic_vector(2 downto 0) := "000";  -- Shift left
    constant ALU_FST_ROL  : std_logic_vector(2 downto 0) := "001";  -- Rotate left
    constant ALU_FST_LSR  : std_logic_vector(2 downto 0) := "010";  -- Shift right
    constant ALU_FST_ROR  : std_logic_vector(2 downto 0) := "011";  -- Rotate right
    constant ALU_FST_PASS : std_logic_vector(2 downto 0) := "100";  -- Pass through
    constant ALU_FST_SWAP : std_logic_vector(2 downto 0) := "101";  -- Swap bytes
    constant ALU_FST_DEC  : std_logic_vector(2 downto 0) := "110";  -- Decrement
    constant ALU_FST_INC  : std_logic_vector(2 downto 0) := "111";  -- Increment
    
    -- ALU second-stage operations (unchanged from 65816)
    constant ALU_SEC_OR   : std_logic_vector(2 downto 0) := "000";
    constant ALU_SEC_AND  : std_logic_vector(2 downto 0) := "001";
    constant ALU_SEC_XOR  : std_logic_vector(2 downto 0) := "010";
    constant ALU_SEC_ADC  : std_logic_vector(2 downto 0) := "011";
    constant ALU_SEC_PASS : std_logic_vector(2 downto 0) := "100";
    constant ALU_SEC_TRB  : std_logic_vector(2 downto 0) := "101";
    constant ALU_SEC_CMP  : std_logic_vector(2 downto 0) := "110";  -- Compare (sub no store)
    constant ALU_SEC_SBC  : std_logic_vector(2 downto 0) := "111";
    
    ---------------------------------------------------------------------------
    -- Microcode Control Record (extended from 65816)
    ---------------------------------------------------------------------------
    
    type MCode_r is record
        ALU_CTRL    : ALUCtrl_r;
        STATE_CTRL  : std_logic_vector(2 downto 0);
        ADDR_BUS    : std_logic_vector(3 downto 0);
        ADDR_INC    : std_logic_vector(1 downto 0);
        IND_CTRL    : std_logic_vector(1 downto 0);
        ADDR_CTRL   : std_logic_vector(7 downto 0);
        LOAD_PC     : std_logic_vector(2 downto 0);
        LOAD_SP     : std_logic_vector(2 downto 0);
        LOAD_AXY    : std_logic_vector(2 downto 0);
        LOAD_P      : std_logic_vector(2 downto 0);
        LOAD_T      : std_logic_vector(1 downto 0);
        LOAD_DKB    : std_logic_vector(1 downto 0);
        BUS_CTRL    : std_logic_vector(5 downto 0);
        BYTE_SEL    : std_logic_vector(1 downto 0);
        OUT_BUS     : std_logic_vector(2 downto 0);
        VA          : std_logic_vector(1 downto 0);
        -- M65832 extensions
        USE_BASE    : std_logic;                     -- Use B register for addressing
        REG_WIN     : std_logic;                     -- Access register window
        WIDE_IMM    : std_logic;                     -- 32-bit immediate follows
    end record;
    
    ---------------------------------------------------------------------------
    -- Status Register (P) - Extended
    ---------------------------------------------------------------------------
    -- 
    -- 65816 P: N V M X D I Z C  (+ E separate)
    -- M65832 P: N V M1 M0 X1 X0 D I Z C  (+ E, S, R)
    --
    -- Bit layout (internal representation):
    --   [0]  C  - Carry
    --   [1]  Z  - Zero
    --   [2]  I  - IRQ disable
    --   [3]  D  - Decimal mode
    --   [4]  X0 - Index width bit 0
    --   [5]  X1 - Index width bit 1
    --   [6]  M0 - Accumulator width bit 0
    --   [7]  M1 - Accumulator width bit 1
    --   [8]  V  - Overflow
    --   [9]  N  - Negative
    --   [10] E  - Emulation (6502 mode)
    --   [11] S  - Supervisor (privilege level)
    --   [12] R  - Register window enable
    
    constant P_C  : integer := 0;
    constant P_Z  : integer := 1;
    constant P_I  : integer := 2;
    constant P_D  : integer := 3;
    constant P_X0 : integer := 4;
    constant P_X1 : integer := 5;
    constant P_M0 : integer := 6;
    constant P_M1 : integer := 7;
    constant P_V  : integer := 8;
    constant P_N  : integer := 9;
    constant P_E  : integer := 10;
    constant P_S  : integer := 11;
    constant P_R  : integer := 12;
    
    constant P_WIDTH : integer := 13;
    
    ---------------------------------------------------------------------------
    -- Register File
    ---------------------------------------------------------------------------
    
    -- Main registers (directly accessible)
    type main_regs_t is record
        A   : std_logic_vector(31 downto 0);  -- Accumulator
        X   : std_logic_vector(31 downto 0);  -- Index X
        Y   : std_logic_vector(31 downto 0);  -- Index Y
        SP  : std_logic_vector(31 downto 0);  -- Stack pointer
        D   : std_logic_vector(31 downto 0);  -- Direct page base
        B   : std_logic_vector(31 downto 0);  -- Absolute base (M65832)
        VBR : std_logic_vector(31 downto 0);  -- Virtual 6502 base (M65832)
        PC  : std_logic_vector(31 downto 0);  -- Program counter
    end record;
    
    -- Register window (64 x 32-bit)
    type reg_window_t is array(0 to REG_COUNT-1) of std_logic_vector(31 downto 0);
    
    ---------------------------------------------------------------------------
    -- MMU Types
    ---------------------------------------------------------------------------
    
    type pte_t is record
        valid   : std_logic;
        read    : std_logic;
        write   : std_logic;
        execute : std_logic;
        user    : std_logic;
        dirty   : std_logic;
        accessed: std_logic;
        ppn     : std_logic_vector(52 downto 0);  -- Physical page number (65-12=53 bits)
    end record;
    
    type tlb_entry_t is record
        valid : std_logic;
        asid  : std_logic_vector(7 downto 0);
        vpn   : std_logic_vector(19 downto 0);  -- Virtual page number (32-12=20 bits)
        pte   : pte_t;
    end record;
    
    ---------------------------------------------------------------------------
    -- Interrupt Vectors
    ---------------------------------------------------------------------------
    
    -- Native mode vectors (bank 0)
    constant VEC_COP_N   : std_logic_vector(15 downto 0) := x"FFE4";
    constant VEC_BRK_N   : std_logic_vector(15 downto 0) := x"FFE6";
    constant VEC_ABORT_N : std_logic_vector(15 downto 0) := x"FFE8";
    constant VEC_NMI_N   : std_logic_vector(15 downto 0) := x"FFEA";
    constant VEC_IRQ_N   : std_logic_vector(15 downto 0) := x"FFEE";
    
    -- Emulation mode vectors
    constant VEC_COP_E   : std_logic_vector(15 downto 0) := x"FFF4";
    constant VEC_ABORT_E : std_logic_vector(15 downto 0) := x"FFF8";
    constant VEC_NMI_E   : std_logic_vector(15 downto 0) := x"FFFA";
    constant VEC_RESET   : std_logic_vector(15 downto 0) := x"FFFC";
    constant VEC_IRQ_E   : std_logic_vector(15 downto 0) := x"FFFE";
    
    -- M65832 extended vectors (for page faults, syscalls, etc.)
    constant VEC_PGFAULT : std_logic_vector(31 downto 0) := x"0000FFD0";
    constant VEC_SYSCALL : std_logic_vector(31 downto 0) := x"0000FFD4";
    
    ---------------------------------------------------------------------------
    -- MMU Control Registers (MMIO)
    ---------------------------------------------------------------------------
    
    constant MMIO_MMUCR      : std_logic_vector(31 downto 0) := x"FFFFF000";
    constant MMIO_TLBINVAL   : std_logic_vector(31 downto 0) := x"FFFFF004";
    constant MMIO_ASID       : std_logic_vector(31 downto 0) := x"FFFFF008";
    constant MMIO_ASIDINVAL  : std_logic_vector(31 downto 0) := x"FFFFF00C";
    constant MMIO_FAULTVA    : std_logic_vector(31 downto 0) := x"FFFFF010";
    constant MMIO_PTBR_LO    : std_logic_vector(31 downto 0) := x"FFFFF014";
    constant MMIO_PTBR_HI    : std_logic_vector(31 downto 0) := x"FFFFF018";
    
    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------
    
    -- Get effective data width from M1:M0 flags
    function get_data_width(m1, m0, e : std_logic) return std_logic_vector;
    
    -- Get effective index width from X1:X0 flags  
    function get_index_width(x1, x0, e : std_logic) return std_logic_vector;
    
    -- Check if in 32-bit wide mode
    function is_wide_mode(e : std_logic; m1m0 : std_logic_vector) return boolean;
    
end package M65832_pkg;

package body M65832_pkg is

    function get_data_width(m1, m0, e : std_logic) return std_logic_vector is
    begin
        if e = '1' then
            return WIDTH_8;  -- Emulation mode always 8-bit
        else
            return m1 & m0;
        end if;
    end function;
    
    function get_index_width(x1, x0, e : std_logic) return std_logic_vector is
    begin
        if e = '1' then
            return WIDTH_8;  -- Emulation mode always 8-bit
        else
            return x1 & x0;
        end if;
    end function;
    
    function is_wide_mode(e : std_logic; m1m0 : std_logic_vector) return boolean is
    begin
        return (e = '0') and (m1m0 = WIDTH_32);
    end function;
    
end package body M65832_pkg;
