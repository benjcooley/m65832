-- M65832 Servicer Context
-- Extended 6502 core for I/O handling with specialized instructions
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The Servicer is a modified 6502 with extra instructions for:
-- - Reading beam position (LDBY, LDBX)
-- - 16-bit cycle counter (LDC16)
-- - Bounding box collision (BBOX)
-- - Bit manipulation (SETBIT, CLRBIT, TSTBIT)
-- - Fast return (RTS_SVC)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_Servicer_Context is
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        CE              : in  std_logic;  -- Clock enable (from interleaver)
        
        ---------------------------------------------------------------------------
        -- Servicer Registers (6502 + extensions)
        ---------------------------------------------------------------------------
        
        -- Accumulator
        A_IN            : in  std_logic_vector(7 downto 0);
        A_LOAD          : in  std_logic;
        A_OUT           : out std_logic_vector(7 downto 0);
        
        -- Index X
        X_IN            : in  std_logic_vector(7 downto 0);
        X_LOAD          : in  std_logic;
        X_OUT           : out std_logic_vector(7 downto 0);
        
        -- Index Y
        Y_IN            : in  std_logic_vector(7 downto 0);
        Y_LOAD          : in  std_logic;
        Y_OUT           : out std_logic_vector(7 downto 0);
        
        -- Stack Pointer
        SP_IN           : in  std_logic_vector(7 downto 0);
        SP_LOAD         : in  std_logic;
        SP_INC          : in  std_logic;
        SP_DEC          : in  std_logic;
        SP_OUT          : out std_logic_vector(7 downto 0);
        
        -- Program Counter
        PC_IN           : in  std_logic_vector(15 downto 0);
        PC_LOAD         : in  std_logic;
        PC_INC          : in  std_logic;
        PC_OUT          : out std_logic_vector(15 downto 0);
        
        -- Status Register
        P_IN            : in  std_logic_vector(7 downto 0);
        P_LOAD          : in  std_logic;
        P_OUT           : out std_logic_vector(7 downto 0);
        
        -- Flag access
        FLAG_C_IN       : in  std_logic;
        FLAG_C_LOAD     : in  std_logic;
        FLAG_Z_IN       : in  std_logic;
        FLAG_Z_LOAD     : in  std_logic;
        FLAG_N_IN       : in  std_logic;
        FLAG_N_LOAD     : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Beam Position Inputs (from interleaver)
        ---------------------------------------------------------------------------
        BEAM_X          : in  std_logic_vector(9 downto 0);
        BEAM_Y          : in  std_logic_vector(9 downto 0);
        CYCLE_COUNT     : in  std_logic_vector(19 downto 0);
        
        ---------------------------------------------------------------------------
        -- Extended Instruction Interface
        ---------------------------------------------------------------------------
        -- Opcode being executed (for extension decode)
        OPCODE          : in  std_logic_vector(7 downto 0);
        
        -- Extended instruction results
        EXT_RESULT      : out std_logic_vector(7 downto 0);
        EXT_RESULT_HI   : out std_logic_vector(7 downto 0);  -- For 16-bit results
        EXT_VALID       : out std_logic;  -- Result is valid
        
        ---------------------------------------------------------------------------
        -- Bounding Box Collision (BBOX instruction)
        ---------------------------------------------------------------------------
        -- Box A: x, y, width, height at zero page address A
        -- Box B: x, y, width, height at zero page address B
        BBOX_ADDR_A     : in  std_logic_vector(7 downto 0);
        BBOX_ADDR_B     : in  std_logic_vector(7 downto 0);
        -- Box data from zero page (read by main memory interface)
        BBOX_A_X        : in  std_logic_vector(7 downto 0);
        BBOX_A_Y        : in  std_logic_vector(7 downto 0);
        BBOX_A_W        : in  std_logic_vector(7 downto 0);
        BBOX_A_H        : in  std_logic_vector(7 downto 0);
        BBOX_B_X        : in  std_logic_vector(7 downto 0);
        BBOX_B_Y        : in  std_logic_vector(7 downto 0);
        BBOX_B_W        : in  std_logic_vector(7 downto 0);
        BBOX_B_H        : in  std_logic_vector(7 downto 0);
        -- Collision result
        BBOX_COLLISION  : out std_logic;
        
        ---------------------------------------------------------------------------
        -- Servicer Code Location
        ---------------------------------------------------------------------------
        SVC_CODE_BASE   : in  std_logic_vector(31 downto 0);  -- Where servicer code lives
        
        ---------------------------------------------------------------------------
        -- Memory Interface
        ---------------------------------------------------------------------------
        ADDR_SVC        : in  std_logic_vector(15 downto 0);
        ADDR_PHYS       : out std_logic_vector(31 downto 0);
        
        ---------------------------------------------------------------------------
        -- Service Complete Signal
        ---------------------------------------------------------------------------
        SVC_DONE        : out std_logic  -- RTS_SVC executed
    );
end M65832_Servicer_Context;

architecture rtl of M65832_Servicer_Context is

    -- Servicer Registers
    signal Ar   : std_logic_vector(7 downto 0);
    signal Xr   : std_logic_vector(7 downto 0);
    signal Yr   : std_logic_vector(7 downto 0);
    signal SPr  : std_logic_vector(7 downto 0);
    signal PCr  : std_logic_vector(15 downto 0);
    signal Pr   : std_logic_vector(7 downto 0);
    
    -- Extended instruction opcodes
    constant OP_LDBY   : std_logic_vector(7 downto 0) := x"03";  -- A = beam_y
    constant OP_LDBX   : std_logic_vector(7 downto 0) := x"13";  -- A = beam_x
    constant OP_LDC16  : std_logic_vector(7 downto 0) := x"23";  -- X:A = cycle_count[15:0]
    constant OP_CMP16  : std_logic_vector(7 downto 0) := x"33";  -- Compare X:A vs [zp+1:zp]
    constant OP_CMPBY  : std_logic_vector(7 downto 0) := x"07";  -- Compare beam_y with zp
    constant OP_BBOX   : std_logic_vector(7 downto 0) := x"43";  -- Bounding box collision
    constant OP_SETBIT : std_logic_vector(7 downto 0) := x"53";  -- [zp] |= (1 << n)
    constant OP_CLRBIT : std_logic_vector(7 downto 0) := x"63";  -- [zp] &= ~(1 << n)
    constant OP_TSTBIT : std_logic_vector(7 downto 0) := x"73";  -- Z = ([zp] & (1 << n)) == 0
    constant OP_RTS_SVC: std_logic_vector(7 downto 0) := x"83";  -- Return from servicer
    constant OP_NOP_SVC: std_logic_vector(7 downto 0) := x"93";  -- Servicer NOP
    
    -- Bounding box calculation signals
    signal box_a_right  : unsigned(8 downto 0);
    signal box_a_bottom : unsigned(8 downto 0);
    signal box_b_right  : unsigned(8 downto 0);
    signal box_b_bottom : unsigned(8 downto 0);
    signal collision    : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Register Updates
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            Ar   <= x"00";
            Xr   <= x"00";
            Yr   <= x"00";
            SPr  <= x"FF";
            PCr  <= x"0000";
            Pr   <= x"24";
            
        elsif rising_edge(CLK) then
            if CE = '1' then
                -- Accumulator
                if A_LOAD = '1' then
                    Ar <= A_IN;
                end if;
                
                -- Index X
                if X_LOAD = '1' then
                    Xr <= X_IN;
                end if;
                
                -- Index Y
                if Y_LOAD = '1' then
                    Yr <= Y_IN;
                end if;
                
                -- Stack Pointer
                if SP_LOAD = '1' then
                    SPr <= SP_IN;
                elsif SP_INC = '1' then
                    SPr <= std_logic_vector(unsigned(SPr) + 1);
                elsif SP_DEC = '1' then
                    SPr <= std_logic_vector(unsigned(SPr) - 1);
                end if;
                
                -- Program Counter
                if PC_LOAD = '1' then
                    PCr <= PC_IN;
                elsif PC_INC = '1' then
                    PCr <= std_logic_vector(unsigned(PCr) + 1);
                end if;
                
                -- Status Register
                if P_LOAD = '1' then
                    Pr <= P_IN;
                else
                    if FLAG_C_LOAD = '1' then Pr(0) <= FLAG_C_IN; end if;
                    if FLAG_Z_LOAD = '1' then Pr(1) <= FLAG_Z_IN; end if;
                    if FLAG_N_LOAD = '1' then Pr(7) <= FLAG_N_IN; end if;
                end if;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Bounding Box Collision Detection
    ---------------------------------------------------------------------------
    -- Two boxes collide if they overlap in both X and Y dimensions
    -- Box format: x, y, width, height (4 bytes each)
    
    box_a_right  <= unsigned('0' & BBOX_A_X) + unsigned('0' & BBOX_A_W);
    box_a_bottom <= unsigned('0' & BBOX_A_Y) + unsigned('0' & BBOX_A_H);
    box_b_right  <= unsigned('0' & BBOX_B_X) + unsigned('0' & BBOX_B_W);
    box_b_bottom <= unsigned('0' & BBOX_B_Y) + unsigned('0' & BBOX_B_H);
    
    -- Collision occurs when boxes overlap
    collision <= '1' when (unsigned(BBOX_A_X) < box_b_right) and
                          (box_a_right > unsigned(BBOX_B_X)) and
                          (unsigned(BBOX_A_Y) < box_b_bottom) and
                          (box_a_bottom > unsigned(BBOX_B_Y))
                     else '0';
    
    BBOX_COLLISION <= collision;
    
    ---------------------------------------------------------------------------
    -- Extended Instruction Results
    ---------------------------------------------------------------------------
    
    process(OPCODE, BEAM_X, BEAM_Y, CYCLE_COUNT, collision)
    begin
        EXT_RESULT    <= x"00";
        EXT_RESULT_HI <= x"00";
        EXT_VALID     <= '0';
        SVC_DONE      <= '0';
        
        case OPCODE is
            when OP_LDBY =>
                -- Load beam Y position into A
                EXT_RESULT <= BEAM_Y(7 downto 0);
                EXT_VALID  <= '1';
                
            when OP_LDBX =>
                -- Load beam X position into A
                EXT_RESULT <= BEAM_X(7 downto 0);
                EXT_VALID  <= '1';
                
            when OP_LDC16 =>
                -- Load 16-bit cycle count into X:A
                EXT_RESULT    <= CYCLE_COUNT(7 downto 0);
                EXT_RESULT_HI <= CYCLE_COUNT(15 downto 8);
                EXT_VALID     <= '1';
                
            when OP_BBOX =>
                -- Bounding box collision - Z flag set if collision
                EXT_RESULT <= "0000000" & collision;
                EXT_VALID  <= '1';
                
            when OP_RTS_SVC =>
                -- Return from servicer
                SVC_DONE <= '1';
                EXT_VALID <= '1';
                
            when OP_NOP_SVC =>
                -- Servicer NOP
                EXT_VALID <= '1';
                
            when others =>
                null;
        end case;
    end process;
    
    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    
    A_OUT  <= Ar;
    X_OUT  <= Xr;
    Y_OUT  <= Yr;
    SP_OUT <= SPr;
    PC_OUT <= PCr;
    P_OUT  <= Pr;
    
    ---------------------------------------------------------------------------
    -- Address Translation
    ---------------------------------------------------------------------------
    -- Servicer code runs from SVC_CODE_BASE
    
    ADDR_PHYS <= std_logic_vector(unsigned(SVC_CODE_BASE) + unsigned(x"0000" & ADDR_SVC));

end rtl;
