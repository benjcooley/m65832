-- M65832 Dedicated 6502 Context
-- Separate register set for the interleaved 6502 core
-- Enables zero-overhead context switching between M65832 and 6502
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_6502_Context is
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        CE              : in  std_logic;  -- Clock enable (from interleaver)
        
        ---------------------------------------------------------------------------
        -- 6502 Register Interface
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
        
        -- Stack Pointer (8-bit, high byte is always $01)
        SP_IN           : in  std_logic_vector(7 downto 0);
        SP_LOAD         : in  std_logic;
        SP_INC          : in  std_logic;
        SP_DEC          : in  std_logic;
        SP_OUT          : out std_logic_vector(7 downto 0);
        
        -- Program Counter (16-bit, within VBR window)
        PC_IN           : in  std_logic_vector(15 downto 0);
        PC_LOAD         : in  std_logic;
        PC_INC          : in  std_logic;
        PC_OUT          : out std_logic_vector(15 downto 0);
        
        -- Status Register (P)
        -- Bit 7: N (Negative)
        -- Bit 6: V (Overflow)
        -- Bit 5: 1 (always set)
        -- Bit 4: B (Break - not really stored, but pushed)
        -- Bit 3: D (Decimal)
        -- Bit 2: I (IRQ disable)
        -- Bit 1: Z (Zero)
        -- Bit 0: C (Carry)
        P_IN            : in  std_logic_vector(7 downto 0);
        P_LOAD          : in  std_logic;
        P_OUT           : out std_logic_vector(7 downto 0);
        
        -- Individual flag access
        FLAG_C_IN       : in  std_logic;
        FLAG_C_LOAD     : in  std_logic;
        FLAG_Z_IN       : in  std_logic;
        FLAG_Z_LOAD     : in  std_logic;
        FLAG_I_IN       : in  std_logic;
        FLAG_I_LOAD     : in  std_logic;
        FLAG_D_IN       : in  std_logic;
        FLAG_D_LOAD     : in  std_logic;
        FLAG_V_IN       : in  std_logic;
        FLAG_V_LOAD     : in  std_logic;
        FLAG_N_IN       : in  std_logic;
        FLAG_N_LOAD     : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Virtual Base Register (set by Linux driver)
        ---------------------------------------------------------------------------
        -- The 6502 sees addresses 0000-FFFF, but they're actually at VBR+addr
        VBR_IN          : in  std_logic_vector(31 downto 0);
        VBR_LOAD        : in  std_logic;
        VBR_OUT         : out std_logic_vector(31 downto 0);
        
        ---------------------------------------------------------------------------
        -- Memory Interface (translated through VBR)
        ---------------------------------------------------------------------------
        -- Physical address = VBR + 16-bit 6502 address
        ADDR_6502       : in  std_logic_vector(15 downto 0);
        ADDR_PHYS       : out std_logic_vector(31 downto 0);
        
        ---------------------------------------------------------------------------
        -- Interrupt Vectors (pre-translated)
        ---------------------------------------------------------------------------
        VEC_NMI         : out std_logic_vector(31 downto 0);
        VEC_RESET       : out std_logic_vector(31 downto 0);
        VEC_IRQ         : out std_logic_vector(31 downto 0)
    );
end M65832_6502_Context;

architecture rtl of M65832_6502_Context is

    -- 6502 Registers
    signal Ar   : std_logic_vector(7 downto 0);
    signal Xr   : std_logic_vector(7 downto 0);
    signal Yr   : std_logic_vector(7 downto 0);
    signal SPr  : std_logic_vector(7 downto 0);
    signal PCr  : std_logic_vector(15 downto 0);
    signal Pr   : std_logic_vector(7 downto 0);
    
    -- Virtual Base Register
    signal VBRr : std_logic_vector(31 downto 0);

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
            SPr  <= x"FF";  -- Stack starts at $01FF
            PCr  <= x"0000";
            Pr   <= x"24";  -- IRQ disabled, unused bit set
            VBRr <= x"00000000";
            
        elsif rising_edge(CLK) then
            -- VBR can be updated by Linux at any time
            if VBR_LOAD = '1' then
                VBRr <= VBR_IN;
            end if;
            
            -- Other registers only update when 6502 core is enabled
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
                    -- Individual flag updates
                    if FLAG_C_LOAD = '1' then Pr(0) <= FLAG_C_IN; end if;
                    if FLAG_Z_LOAD = '1' then Pr(1) <= FLAG_Z_IN; end if;
                    if FLAG_I_LOAD = '1' then Pr(2) <= FLAG_I_IN; end if;
                    if FLAG_D_LOAD = '1' then Pr(3) <= FLAG_D_IN; end if;
                    if FLAG_V_LOAD = '1' then Pr(6) <= FLAG_V_IN; end if;
                    if FLAG_N_LOAD = '1' then Pr(7) <= FLAG_N_IN; end if;
                end if;
            end if;
        end if;
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
    VBR_OUT <= VBRr;
    
    ---------------------------------------------------------------------------
    -- Address Translation
    ---------------------------------------------------------------------------
    -- 6502 address space (0000-FFFF) is mapped to VBR + offset
    
    ADDR_PHYS <= std_logic_vector(unsigned(VBRr) + unsigned(x"0000" & ADDR_6502));
    
    ---------------------------------------------------------------------------
    -- Vector Addresses (pre-computed for fast interrupt entry)
    ---------------------------------------------------------------------------
    
    VEC_NMI   <= std_logic_vector(unsigned(VBRr) + x"0000FFFA");
    VEC_RESET <= std_logic_vector(unsigned(VBRr) + x"0000FFFC");
    VEC_IRQ   <= std_logic_vector(unsigned(VBRr) + x"0000FFFE");

end rtl;
