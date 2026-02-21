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
    
    -- Data widths
    -- In legacy mode (W=00): M/X single-bit flags control width
    --   M=1 or X=1 → 8-bit, M=0 or X=0 → 16-bit (65816 compatible)
    -- In 32-bit mode (W=10): all standard ops are 32-bit (M/X ignored)
    -- Extended ALU instructions have their own size encoding regardless of mode
    constant WIDTH_8   : std_logic_vector(1 downto 0) := "00";
    constant WIDTH_16  : std_logic_vector(1 downto 0) := "01";
    constant WIDTH_32  : std_logic_vector(1 downto 0) := "10";
    -- "11" reserved for 64-bit (M65864)
    
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
        MODE_EMU,       -- W=00: 6502 emulation mode (E derived as '1')
        MODE_NATIVE16,  -- W=01: 65816-compatible native mode
        MODE_NATIVE32   -- W=10: Full 32-bit native mode
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
    -- Register-Targeted ALU (Extended ALU, mode byte target=1)
    ---------------------------------------------------------------------------
    
    -- Register-targeted ALU operation codes (mapped from ext opcode)
    constant REGALU_LD    : std_logic_vector(3 downto 0) := "0000";  -- Load
    constant REGALU_ADC   : std_logic_vector(3 downto 0) := "0001";  -- Add with carry
    constant REGALU_SBC   : std_logic_vector(3 downto 0) := "0010";  -- Subtract with borrow
    constant REGALU_AND   : std_logic_vector(3 downto 0) := "0011";  -- Logical AND
    constant REGALU_ORA   : std_logic_vector(3 downto 0) := "0100";  -- Logical OR
    constant REGALU_EOR   : std_logic_vector(3 downto 0) := "0101";  -- Exclusive OR
    constant REGALU_CMP   : std_logic_vector(3 downto 0) := "0110";  -- Compare
    constant REGALU_SHF   : std_logic_vector(3 downto 0) := "0111";  -- Shifts (reserved)
    
    -- Register-targeted ALU source modes (mapped from extended addr_mode)
    constant REGALU_SRC_DPX_IND : std_logic_vector(3 downto 0) := "0000";  -- (dp,X)
    constant REGALU_SRC_DP      : std_logic_vector(3 downto 0) := "0001";  -- dp
    constant REGALU_SRC_IMM     : std_logic_vector(3 downto 0) := "0010";  -- #imm
    constant REGALU_SRC_A       : std_logic_vector(3 downto 0) := "0011";  -- A
    constant REGALU_SRC_DP_Y    : std_logic_vector(3 downto 0) := "0100";  -- (dp),Y
    constant REGALU_SRC_DPX     : std_logic_vector(3 downto 0) := "0101";  -- dp,X
    constant REGALU_SRC_ABS     : std_logic_vector(3 downto 0) := "0110";  -- abs
    constant REGALU_SRC_ABSX    : std_logic_vector(3 downto 0) := "0111";  -- abs,X
    constant REGALU_SRC_ABSY    : std_logic_vector(3 downto 0) := "1000";  -- abs,Y
    constant REGALU_SRC_DP_IND  : std_logic_vector(3 downto 0) := "1001";  -- (dp)
    constant REGALU_SRC_DP_LONG : std_logic_vector(3 downto 0) := "1010";  -- [dp]
    constant REGALU_SRC_DPL_Y   : std_logic_vector(3 downto 0) := "1011";  -- [dp],Y
    constant REGALU_SRC_SR      : std_logic_vector(3 downto 0) := "1100";  -- sr,S
    constant REGALU_SRC_SR_Y    : std_logic_vector(3 downto 0) := "1101";  -- (sr,S),Y
    constant REGALU_SRC_X       : std_logic_vector(3 downto 0) := "1110";  -- X register source
    constant REGALU_SRC_Y       : std_logic_vector(3 downto 0) := "1111";  -- Y register source
    
    ---------------------------------------------------------------------------
    -- Shifter/Rotate Extended Opcode ($02 $98)
    ---------------------------------------------------------------------------
    -- Format: $02 $98 [op|cnt] [dest_dp] [src_dp]
    --   op (bits 7-5): shift operation
    --   cnt (bits 4-0): shift count (0-31 for immediate, or 11111 for A-sourced)
    
    constant EXT_SHIFTER  : std_logic_vector(7 downto 0) := x"98";
    
    -- Shift operation codes (bits 7-5 of op|cnt byte)
    constant SHIFT_SHL    : std_logic_vector(2 downto 0) := "000";  -- Shift left (logical)
    constant SHIFT_SHR    : std_logic_vector(2 downto 0) := "001";  -- Shift right (logical)
    constant SHIFT_SAR    : std_logic_vector(2 downto 0) := "010";  -- Shift right (arithmetic)
    constant SHIFT_ROL    : std_logic_vector(2 downto 0) := "011";  -- Rotate left through carry
    constant SHIFT_ROR    : std_logic_vector(2 downto 0) := "100";  -- Rotate right through carry
    
    -- Special shift count value: shift by A (low 5 bits)
    constant SHIFT_BY_A   : std_logic_vector(4 downto 0) := "11111";
    
    ---------------------------------------------------------------------------
    -- Sign/Zero Extend Extended Opcode ($02 $99)
    ---------------------------------------------------------------------------
    -- Format: $02 $99 [subop] [dest_dp] [src_dp]
    
    constant EXT_EXTEND   : std_logic_vector(7 downto 0) := x"99";
    
    -- Extend operation codes
    constant EXTEND_SEXT8  : std_logic_vector(3 downto 0) := "0000";  -- Sign extend 8->32
    constant EXTEND_SEXT16 : std_logic_vector(3 downto 0) := "0001";  -- Sign extend 16->32
    constant EXTEND_ZEXT8  : std_logic_vector(3 downto 0) := "0010";  -- Zero extend 8->32
    constant EXTEND_ZEXT16 : std_logic_vector(3 downto 0) := "0011";  -- Zero extend 16->32
    constant EXTEND_CLZ    : std_logic_vector(3 downto 0) := "0100";  -- Count leading zeros
    constant EXTEND_CTZ    : std_logic_vector(3 downto 0) := "0101";  -- Count trailing zeros
    constant EXTEND_POPCNT : std_logic_vector(3 downto 0) := "0110";  -- Population count
    
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
    -- 65816 P: N V M X D I Z C  (bits 7-0, + E separate)
    -- M65832 P: Extends 65816 with W field and privilege flags above bit 7.
    --           Bits 0-7 are IDENTICAL to 65816 for backwards compatibility.
    --
    -- Processor mode is controlled by W1:W0 (bits 9:8):
    --   W = 00: 6502 emulation mode (8-bit, VBR-relative)
    --   W = 01: 65816 native mode (M/X control 8/16-bit)
    --   W = 10: 32-bit mode (M/X ignored, all ops 32-bit)
    --   W = 11: Reserved for 64-bit (M65864)
    --
    -- E (emulation) is NOT a stored flag. It is derived: E = (W = "00").
    -- XCE swaps C with the derived E value and sets W accordingly:
    --   XCE with C=1: W <= "00" (enter emulation), C gets old E
    --   XCE with C=0: W <= "01" (enter native), C gets old E
    -- SEPE/REPE set W bits directly for 32-bit mode transitions.
    --
    -- Bit layout:
    --   [0]  C  - Carry
    --   [1]  Z  - Zero
    --   [2]  I  - IRQ disable
    --   [3]  D  - Decimal mode
    --   [4]  X  - Index width (1=8-bit, 0=16-bit; 65816 compatible)
    --   [5]  M  - Accumulator width (1=8-bit, 0=16-bit; 65816 compatible)
    --   [6]  V  - Overflow
    --   [7]  N  - Negative
    --   [8]  W0 - Wide mode bit 0
    --   [9]  W1 - Wide mode bit 1
    --   [10] (reserved)
    --   [11] S  - Supervisor (privilege level)
    --   [12] R  - Register window enable
    --   [13] K  - Compatibility (illegal opcodes as NOP in 8/16-bit)

    constant P_C  : integer := 0;
    constant P_Z  : integer := 1;
    constant P_I  : integer := 2;
    constant P_D  : integer := 3;
    constant P_X  : integer := 4;
    constant P_M  : integer := 5;
    constant P_V  : integer := 6;
    constant P_N  : integer := 7;
    constant P_W0 : integer := 8;
    constant P_W1 : integer := 9;
    -- Bit 10 reserved (E is derived from W, not stored)
    constant P_S  : integer := 11;
    constant P_R  : integer := 12;
    constant P_K  : integer := 13;

    constant P_WIDTH : integer := 14;
    
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
constant VEC_ILLEGAL : std_logic_vector(31 downto 0) := x"0000FFF8";
    
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
    constant MMIO_TLBFLUSH   : std_logic_vector(31 downto 0) := x"FFFFF01C";
    constant MMIO_TIMER_CTRL : std_logic_vector(31 downto 0) := x"FFFFF040";
    constant MMIO_TIMER_CMP  : std_logic_vector(31 downto 0) := x"FFFFF044";
    constant MMIO_TIMER_COUNT: std_logic_vector(31 downto 0) := x"FFFFF048";
    
    ---------------------------------------------------------------------------
    -- Processor Mode Constants
    ---------------------------------------------------------------------------

    constant WMODE_6502   : std_logic_vector(1 downto 0) := "00";  -- 6502 emulation
    constant WMODE_65816  : std_logic_vector(1 downto 0) := "01";  -- 65816 native
    constant WMODE_32BIT  : std_logic_vector(1 downto 0) := "11";  -- 32-bit mode
    -- W="10" reserved (future W2 bit for 64-bit: W=111)

    ---------------------------------------------------------------------------
    -- Helper Functions
    ---------------------------------------------------------------------------

    -- Get effective data width from M flag and W mode
    -- W=00 (6502): always 8-bit
    -- W=01 (65816): M=1 → 8-bit, M=0 → 16-bit
    -- W=11 (32-bit): always 32-bit (M ignored)
    function get_data_width(m : std_logic; w : std_logic_vector) return std_logic_vector;

    -- Get effective index width from X flag and W mode
    function get_index_width(x : std_logic; w : std_logic_vector) return std_logic_vector;

    -- Check if in 32-bit wide mode (W = "11")
    function is_wide_mode(w : std_logic_vector) return boolean;

end package M65832_pkg;

package body M65832_pkg is

    function get_data_width(m : std_logic; w : std_logic_vector) return std_logic_vector is
    begin
        case w is
            when WMODE_6502  => return WIDTH_8;   -- 6502: always 8-bit
            when WMODE_32BIT => return WIDTH_32;   -- 32-bit mode (W=11)
            when others =>                         -- 65816 native (W=01) or reserved (W=10)
                if m = '1' then
                    return WIDTH_8;                -- M=1 → 8-bit
                else
                    return WIDTH_16;               -- M=0 → 16-bit
                end if;
        end case;
    end function;

    function get_index_width(x : std_logic; w : std_logic_vector) return std_logic_vector is
    begin
        case w is
            when WMODE_6502  => return WIDTH_8;   -- 6502: always 8-bit
            when WMODE_32BIT => return WIDTH_32;   -- 32-bit mode (W=11)
            when others =>                         -- 65816 native (W=01) or reserved (W=10)
                if x = '1' then
                    return WIDTH_8;                -- X=1 → 8-bit
                else
                    return WIDTH_16;               -- X=0 → 16-bit
                end if;
        end case;
    end function;

    function is_wide_mode(w : std_logic_vector) return boolean is
    begin
        return (w = WMODE_32BIT);
    end function;

end package body M65832_pkg;
