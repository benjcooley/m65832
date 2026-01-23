-- M65832 ALU
-- Extended from 65816 ALU to support 32-bit operations
--
-- Copyright (c) 2026 M65832 Project  
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Based on ALU.vhd by srg320 (MiSTer project)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_ALU is
    port(
        -- Operands (32-bit, masked by width)
        L       : in  std_logic_vector(31 downto 0);
        R       : in  std_logic_vector(31 downto 0);
        
        -- Control
        CTRL    : in  ALUCtrl_r;
        WIDTH   : in  std_logic_vector(1 downto 0);  -- 00=8, 01=16, 10=32
        BCD     : in  std_logic;                      -- Decimal mode
        CI      : in  std_logic;                      -- Carry in
        VI      : in  std_logic;                      -- Overflow in
        SI      : in  std_logic;                      -- Sign in
        
        -- Results
        CO      : out std_logic;                      -- Carry out
        VO      : out std_logic;                      -- Overflow out
        SO      : out std_logic;                      -- Sign out
        ZO      : out std_logic;                      -- Zero out
        RES     : out std_logic_vector(31 downto 0); -- Result
        IntR    : out std_logic_vector(31 downto 0)  -- Intermediate result
    );
end M65832_ALU;

architecture rtl of M65832_ALU is

    -- Intermediate results for each width
    signal IntR8  : std_logic_vector(7 downto 0);
    signal IntR16 : std_logic_vector(15 downto 0);
    signal IntR32 : std_logic_vector(31 downto 0);
    
    -- Carry from first stage for each width
    signal CR8, CR16, CR32, CR, ZR : std_logic;
    
    -- Adder signals
    signal AddR8  : std_logic_vector(7 downto 0);
    signal AddR16 : std_logic_vector(15 downto 0);
    signal AddR32 : std_logic_vector(31 downto 0);
    signal AddCO8, AddCO16, AddCO32 : std_logic;
    signal AddVO8, AddVO16, AddVO32 : std_logic;
    
    -- Final results for each width
    signal Result8  : std_logic_vector(7 downto 0);
    signal Result16 : std_logic_vector(15 downto 0);
    signal Result32 : std_logic_vector(31 downto 0);
    
    -- Width control
    signal w8, w16, w32 : std_logic;
    
    -- BCD control
    signal CIIn, ADDIn, BCDIn : std_logic;

begin

    -- Decode width
    w8  <= '1' when WIDTH = WIDTH_8  else '0';
    w16 <= '1' when WIDTH = WIDTH_16 else '0';
    w32 <= '1' when WIDTH = WIDTH_32 else '0';
    
    ---------------------------------------------------------------------------
    -- First Stage: Shift/Rotate/INC/DEC/Pass
    ---------------------------------------------------------------------------
    
    process(CTRL, CI, R)
    begin
        -- Default: carry comes from input
        CR8  <= CI;
        CR16 <= CI;
        CR32 <= CI;
        
        case CTRL.fstOp is
            when ALU_FST_ASL =>  -- Arithmetic shift left
                CR8  <= R(7);
                CR16 <= R(15);
                CR32 <= R(31);
                IntR8  <= R(6 downto 0) & "0";
                IntR16 <= R(14 downto 0) & "0";
                IntR32 <= R(30 downto 0) & "0";
                
            when ALU_FST_ROL =>  -- Rotate left through carry
                CR8  <= R(7);
                CR16 <= R(15);
                CR32 <= R(31);
                IntR8  <= R(6 downto 0) & CI;
                IntR16 <= R(14 downto 0) & CI;
                IntR32 <= R(30 downto 0) & CI;
                
            when ALU_FST_LSR =>  -- Logical shift right
                CR8  <= R(0);
                CR16 <= R(0);
                CR32 <= R(0);
                IntR8  <= "0" & R(7 downto 1);
                IntR16 <= "0" & R(15 downto 1);
                IntR32 <= "0" & R(31 downto 1);
                
            when ALU_FST_ROR =>  -- Rotate right through carry
                CR8  <= R(0);
                CR16 <= R(0);
                CR32 <= R(0);
                IntR8  <= CI & R(7 downto 1);
                IntR16 <= CI & R(15 downto 1);
                IntR32 <= CI & R(31 downto 1);
                
            when ALU_FST_PASS =>  -- Pass through
                IntR8  <= R(7 downto 0);
                IntR16 <= R(15 downto 0);
                IntR32 <= R;
                
            when ALU_FST_SWAP =>  -- Swap bytes (XBA and friends)
                IntR8  <= R(15 downto 8);  -- Get high byte
                IntR16 <= R(7 downto 0) & R(15 downto 8);
                IntR32 <= R(23 downto 16) & R(31 downto 24) & 
                          R(7 downto 0) & R(15 downto 8);  -- Swap halfwords
                
            when ALU_FST_DEC =>  -- Decrement
                IntR8  <= std_logic_vector(unsigned(R(7 downto 0)) - 1);
                IntR16 <= std_logic_vector(unsigned(R(15 downto 0)) - 1);
                IntR32 <= std_logic_vector(unsigned(R) - 1);
                
            when ALU_FST_INC =>  -- Increment
                IntR8  <= std_logic_vector(unsigned(R(7 downto 0)) + 1);
                IntR16 <= std_logic_vector(unsigned(R(15 downto 0)) + 1);
                IntR32 <= std_logic_vector(unsigned(R) + 1);
                
            when others =>
                IntR8  <= R(7 downto 0);
                IntR16 <= R(15 downto 0);
                IntR32 <= R;
        end case;
    end process;
    
    -- Select carry based on width
    CR <= CR8  when w8 = '1' else
          CR16 when w16 = '1' else
          CR32;
    
    ---------------------------------------------------------------------------
    -- Adder/Subtractor (with BCD support for 8/16-bit only)
    ---------------------------------------------------------------------------
    
    CIIn  <= CR or not CTRL.secOp(0);
    ADDIn <= not CTRL.secOp(2);
    BCDIn <= BCD and CTRL.secOp(0) and not w32;  -- No BCD in 32-bit mode
    
    -- 8-bit adder
    process(L, R, CIIn, ADDIn, BCDIn)
        variable sum : unsigned(8 downto 0);
        variable a, b : unsigned(7 downto 0);
    begin
        a := unsigned(L(7 downto 0));
        if ADDIn = '1' then
            b := unsigned(R(7 downto 0));
        else
            b := unsigned(not R(7 downto 0));
        end if;
        
        sum := ('0' & a) + ('0' & b) + ("00000000" & CIIn);
        AddR8 <= std_logic_vector(sum(7 downto 0));
        AddCO8 <= sum(8);
        AddVO8 <= (a(7) xnor b(7)) and (a(7) xor sum(7));
    end process;
    
    -- 16-bit adder
    process(L, R, CIIn, ADDIn)
        variable sum : unsigned(16 downto 0);
        variable a, b : unsigned(15 downto 0);
    begin
        a := unsigned(L(15 downto 0));
        if ADDIn = '1' then
            b := unsigned(R(15 downto 0));
        else
            b := unsigned(not R(15 downto 0));
        end if;
        
        sum := ('0' & a) + ('0' & b) + (x"0000" & CIIn);
        AddR16 <= std_logic_vector(sum(15 downto 0));
        AddCO16 <= sum(16);
        AddVO16 <= (a(15) xnor b(15)) and (a(15) xor sum(15));
    end process;
    
    -- 32-bit adder
    process(L, R, CIIn, ADDIn)
        variable sum : unsigned(32 downto 0);
        variable a, b : unsigned(31 downto 0);
    begin
        a := unsigned(L);
        if ADDIn = '1' then
            b := unsigned(R);
        else
            b := unsigned(not R);
        end if;
        
        sum := ('0' & a) + ('0' & b) + (x"00000000" & CIIn);
        AddR32 <= std_logic_vector(sum(31 downto 0));
        AddCO32 <= sum(32);
        AddVO32 <= (a(31) xnor b(31)) and (a(31) xor sum(31));
    end process;
    
    ---------------------------------------------------------------------------
    -- Second Stage: Logic/Arithmetic
    ---------------------------------------------------------------------------
    
    process(CTRL, CR, IntR8, IntR16, IntR32, L, AddCO8, AddCO16, AddCO32,
            AddR8, AddR16, AddR32, w8, w16)
    begin
        ZR <= '0';
        
        case CTRL.secOp is
            when ALU_SEC_OR =>
                CO <= CR;
                Result8  <= L(7 downto 0) or IntR8;
                Result16 <= L(15 downto 0) or IntR16;
                Result32 <= L or IntR32;
                
            when ALU_SEC_AND =>
                CO <= CR;
                Result8  <= L(7 downto 0) and IntR8;
                Result16 <= L(15 downto 0) and IntR16;
                Result32 <= L and IntR32;
                
            when ALU_SEC_XOR =>
                CO <= CR;
                Result8  <= L(7 downto 0) xor IntR8;
                Result16 <= L(15 downto 0) xor IntR16;
                Result32 <= L xor IntR32;
                
            when ALU_SEC_ADC | ALU_SEC_CMP | ALU_SEC_SBC =>
                -- Use appropriate width adder
                if w8 = '1' then
                    CO <= AddCO8;
                    Result8 <= AddR8;
                elsif w16 = '1' then
                    CO <= AddCO16;
                    Result16 <= AddR16;
                else
                    CO <= AddCO32;
                    Result32 <= AddR32;
                end if;
                Result8  <= AddR8;
                Result16 <= AddR16;
                Result32 <= AddR32;
                
            when ALU_SEC_PASS =>
                CO <= CR;
                Result8  <= IntR8;
                Result16 <= IntR16;
                Result32 <= IntR32;
                
            when ALU_SEC_TRB =>  -- Test and Reset Bits / Test and Set Bits
                CO <= CR;
                if CTRL.fc = '0' then
                    -- TRB: result = mem AND NOT acc
                    Result8  <= IntR8 and (not L(7 downto 0));
                    Result16 <= IntR16 and (not L(15 downto 0));
                    Result32 <= IntR32 and (not L);
                else
                    -- TSB: result = mem OR acc
                    Result8  <= IntR8 or L(7 downto 0);
                    Result16 <= IntR16 or L(15 downto 0);
                    Result32 <= IntR32 or L;
                end if;
                
                -- Zero flag based on AND of operands
                if (IntR8 and L(7 downto 0)) = x"00" and w8 = '1' then
                    ZR <= '1';
                elsif (IntR16 and L(15 downto 0)) = x"0000" and w16 = '1' then
                    ZR <= '1';
                elsif (IntR32 and L) = x"00000000" and w8 = '0' and w16 = '0' then
                    ZR <= '1';
                end if;
                
            when others =>
                CO <= CR;
                Result8  <= IntR8;
                Result16 <= IntR16;
                Result32 <= IntR32;
        end case;
    end process;
    
    ---------------------------------------------------------------------------
    -- Flags
    ---------------------------------------------------------------------------
    
    process(CTRL, w8, w16, VI, SI, IntR8, IntR16, IntR32, 
            Result8, Result16, Result32, AddVO8, AddVO16, AddVO32)
    begin
        VO <= VI;  -- Default: preserve
        
        -- Sign flag from result MSB
        if w8 = '1' then
            SO <= Result8(7);
        elsif w16 = '1' then
            SO <= Result16(15);
        else
            SO <= Result32(31);
        end if;
        
        case CTRL.secOp is
            when ALU_SEC_AND =>
                if CTRL.fc = '1' then
                    -- BIT instruction: V and N from memory operand
                    if w8 = '1' then
                        VO <= IntR8(6);
                        SO <= IntR8(7);
                    elsif w16 = '1' then
                        VO <= IntR16(14);
                        SO <= IntR16(15);
                    else
                        VO <= IntR32(30);
                        SO <= IntR32(31);
                    end if;
                end if;
                
            when ALU_SEC_ADC =>
                -- ADC always sets V
                if w8 = '1' then
                    VO <= AddVO8;
                elsif w16 = '1' then
                    VO <= AddVO16;
                else
                    VO <= AddVO32;
                end if;
                
            when ALU_SEC_TRB =>
                SO <= SI;  -- Preserve sign for TRB/TSB
                
            when ALU_SEC_SBC =>
                if CTRL.fc = '1' then
                    -- Only SBC sets V
                    if w8 = '1' then
                        VO <= AddVO8;
                    elsif w16 = '1' then
                        VO <= AddVO16;
                    else
                        VO <= AddVO32;
                    end if;
                end if;
                
            when others => null;
        end case;
    end process;
    
    ---------------------------------------------------------------------------
    -- Zero Flag
    ---------------------------------------------------------------------------
    
    ZO <= ZR when CTRL.secOp = ALU_SEC_TRB else
          '1' when (w8 = '1' and Result8 = x"00") else
          '1' when (w16 = '1' and Result16 = x"0000") else
          '1' when (w32 = '1' and Result32 = x"00000000") else
          '0';
    
    ---------------------------------------------------------------------------
    -- Output Mux
    ---------------------------------------------------------------------------
    
    RES <= x"000000" & Result8  when w8 = '1' else
           x"0000" & Result16   when w16 = '1' else
           Result32;
           
    IntR <= x"000000" & IntR8  when w8 = '1' else
            x"0000" & IntR16   when w16 = '1' else
            IntR32;

end rtl;
