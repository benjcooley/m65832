-- M65832 Register File
-- Implements 64x32-bit register window plus main CPU registers
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_RegFile is
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        EN              : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Main Register Access
        ---------------------------------------------------------------------------
        
        -- Accumulator
        A_IN            : in  std_logic_vector(31 downto 0);
        A_LOAD          : in  std_logic;
        A_OUT           : out std_logic_vector(31 downto 0);
        
        -- Index X
        X_IN            : in  std_logic_vector(31 downto 0);
        X_LOAD          : in  std_logic;
        X_OUT           : out std_logic_vector(31 downto 0);
        
        -- Index Y
        Y_IN            : in  std_logic_vector(31 downto 0);
        Y_LOAD          : in  std_logic;
        Y_OUT           : out std_logic_vector(31 downto 0);
        
        -- Stack Pointer
        SP_IN           : in  std_logic_vector(31 downto 0);
        SP_LOAD         : in  std_logic;
        SP_INC          : in  std_logic;
        SP_DEC          : in  std_logic;
        SP_OUT          : out std_logic_vector(31 downto 0);
        
        -- Direct Page Base
        D_IN            : in  std_logic_vector(31 downto 0);
        D_LOAD          : in  std_logic;
        D_OUT           : out std_logic_vector(31 downto 0);
        
        -- Absolute Base (M65832)
        B_IN            : in  std_logic_vector(31 downto 0);
        B_LOAD          : in  std_logic;
        B_OUT           : out std_logic_vector(31 downto 0);
        
        -- Virtual 6502 Base (M65832)
        VBR_IN          : in  std_logic_vector(31 downto 0);
        VBR_LOAD        : in  std_logic;
        VBR_OUT         : out std_logic_vector(31 downto 0);
        
        -- Temp Register
        T_IN            : in  std_logic_vector(31 downto 0);
        T_LOAD          : in  std_logic;
        T_OUT           : out std_logic_vector(31 downto 0);
        
        ---------------------------------------------------------------------------
        -- Register Window Access (Direct Page as Register File)
        ---------------------------------------------------------------------------
        
        -- Register window enable
        REG_WIN_EN      : in  std_logic;
        
        -- Read port 1
        RW_ADDR1        : in  std_logic_vector(5 downto 0);   -- Register 0-63
        RW_DATA1        : out std_logic_vector(31 downto 0);
        
        -- Read port 2
        RW_ADDR2        : in  std_logic_vector(5 downto 0);   -- Register 0-63
        RW_DATA2        : out std_logic_vector(31 downto 0);
        
        -- Write port
        RW_WADDR        : in  std_logic_vector(5 downto 0);   -- Register 0-63
        RW_WDATA        : in  std_logic_vector(31 downto 0);
        RW_WE           : in  std_logic;
        
        -- Byte/word access within register (for 8/16-bit ops)
        RW_WIDTH        : in  std_logic_vector(1 downto 0);   -- 00=8, 01=16, 10=32
        RW_BYTE_SEL     : in  std_logic_vector(1 downto 0);   -- Which byte/word
        
        ---------------------------------------------------------------------------
        -- Status Register (P)
        ---------------------------------------------------------------------------
        
        P_IN            : in  std_logic_vector(P_WIDTH-1 downto 0);
        P_LOAD          : in  std_logic;
        P_OUT           : out std_logic_vector(P_WIDTH-1 downto 0);
        
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
        
        -- Mode flags
        E_MODE          : out std_logic;  -- Emulation mode
        S_MODE          : out std_logic;  -- Supervisor mode
        R_MODE          : out std_logic;  -- Register window mode
        M_WIDTH         : out std_logic_vector(1 downto 0);  -- Accumulator width
        X_WIDTH         : out std_logic_vector(1 downto 0);  -- Index width
        
        ---------------------------------------------------------------------------
        -- Width control for register masking
        ---------------------------------------------------------------------------
        
        WIDTH_M         : in  std_logic_vector(1 downto 0);  -- For A operations
        WIDTH_X         : in  std_logic_vector(1 downto 0)   -- For X/Y operations
    );
end M65832_RegFile;

architecture rtl of M65832_RegFile is

    -- Main registers
    signal Ar   : std_logic_vector(31 downto 0);
    signal Xr   : std_logic_vector(31 downto 0);
    signal Yr   : std_logic_vector(31 downto 0);
    signal SPr  : std_logic_vector(31 downto 0);
    signal Dr   : std_logic_vector(31 downto 0);
    signal Br   : std_logic_vector(31 downto 0);
    signal VBRr : std_logic_vector(31 downto 0);
    signal Tr   : std_logic_vector(31 downto 0);
    
    -- Status register
    signal Pr   : std_logic_vector(P_WIDTH-1 downto 0);
    
    -- Register window (64 x 32-bit)
    type reg_array_t is array(0 to 63) of std_logic_vector(31 downto 0);
    signal RegWindow : reg_array_t;
    
    -- Width-masked values
    function mask_by_width(val : std_logic_vector(31 downto 0); 
                           width : std_logic_vector(1 downto 0))
                           return std_logic_vector is
    begin
        case width is
            when WIDTH_8 =>
                return x"000000" & val(7 downto 0);
            when WIDTH_16 =>
                return x"0000" & val(15 downto 0);
            when others =>
                return val;
        end case;
    end function;
    
    -- Merge value by width (preserve high bits)
    function merge_by_width(old_val : std_logic_vector(31 downto 0);
                            new_val : std_logic_vector(31 downto 0);
                            width : std_logic_vector(1 downto 0))
                            return std_logic_vector is
    begin
        case width is
            when WIDTH_8 =>
                return old_val(31 downto 8) & new_val(7 downto 0);
            when WIDTH_16 =>
                return old_val(31 downto 16) & new_val(15 downto 0);
            when others =>
                return new_val;
        end case;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Main Register Updates
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            Ar   <= (others => '0');
            Xr   <= (others => '0');
            Yr   <= (others => '0');
            SPr  <= x"000001FF";  -- Default stack at $01FF (6502 compatible)
            Dr   <= (others => '0');
            Br   <= (others => '0');
            VBRr <= (others => '0');
            Tr   <= (others => '0');
            Pr   <= "0110000001100";  -- E=1, S=1, R=0, M1:M0=00, X1:X0=00, D=1, I=1, Z=0, C=0
            
        elsif rising_edge(CLK) then
            if EN = '1' then
                -- Accumulator
                if A_LOAD = '1' then
                    Ar <= merge_by_width(Ar, A_IN, WIDTH_M);
                end if;
                
                -- Index X
                if X_LOAD = '1' then
                    Xr <= merge_by_width(Xr, X_IN, WIDTH_X);
                end if;
                
                -- Index Y
                if Y_LOAD = '1' then
                    Yr <= merge_by_width(Yr, Y_IN, WIDTH_X);
                end if;
                
                -- Stack Pointer
                if SP_LOAD = '1' then
                    if Pr(P_E) = '1' then
                        -- Emulation mode: SP high byte locked to $01
                        SPr <= x"000001" & SP_IN(7 downto 0);
                    else
                        SPr <= SP_IN;
                    end if;
                elsif SP_INC = '1' then
                    if Pr(P_E) = '1' then
                        SPr(7 downto 0) <= std_logic_vector(unsigned(SPr(7 downto 0)) + 1);
                    else
                        SPr <= std_logic_vector(unsigned(SPr) + 1);
                    end if;
                elsif SP_DEC = '1' then
                    if Pr(P_E) = '1' then
                        SPr(7 downto 0) <= std_logic_vector(unsigned(SPr(7 downto 0)) - 1);
                    else
                        SPr <= std_logic_vector(unsigned(SPr) - 1);
                    end if;
                end if;
                
                -- Direct Page Base
                if D_LOAD = '1' then
                    Dr <= D_IN;
                end if;
                
                -- Absolute Base
                if B_LOAD = '1' then
                    Br <= B_IN;
                end if;
                
                -- Virtual 6502 Base
                if VBR_LOAD = '1' then
                    VBRr <= VBR_IN;
                end if;
                
                -- Temp Register
                if T_LOAD = '1' then
                    Tr <= T_IN;
                end if;
                
                -- Status Register
                if P_LOAD = '1' then
                    Pr <= P_IN;
                else
                    -- Individual flag updates
                    if FLAG_C_LOAD = '1' then Pr(P_C) <= FLAG_C_IN; end if;
                    if FLAG_Z_LOAD = '1' then Pr(P_Z) <= FLAG_Z_IN; end if;
                    if FLAG_I_LOAD = '1' then Pr(P_I) <= FLAG_I_IN; end if;
                    if FLAG_D_LOAD = '1' then Pr(P_D) <= FLAG_D_IN; end if;
                    if FLAG_V_LOAD = '1' then Pr(P_V) <= FLAG_V_IN; end if;
                    if FLAG_N_LOAD = '1' then Pr(P_N) <= FLAG_N_IN; end if;
                end if;
                
                -- Special: when X flag changes from 0 to 1, clear high bytes
                -- (65816 behavior preserved)
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Register Window Updates
    ---------------------------------------------------------------------------
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            if EN = '1' and RW_WE = '1' and REG_WIN_EN = '1' then
                case RW_WIDTH is
                    when WIDTH_8 =>
                        -- Write single byte
                        case RW_BYTE_SEL is
                            when "00" =>
                                RegWindow(to_integer(unsigned(RW_WADDR)))(7 downto 0) <= RW_WDATA(7 downto 0);
                            when "01" =>
                                RegWindow(to_integer(unsigned(RW_WADDR)))(15 downto 8) <= RW_WDATA(7 downto 0);
                            when "10" =>
                                RegWindow(to_integer(unsigned(RW_WADDR)))(23 downto 16) <= RW_WDATA(7 downto 0);
                            when "11" =>
                                RegWindow(to_integer(unsigned(RW_WADDR)))(31 downto 24) <= RW_WDATA(7 downto 0);
                            when others =>
                                null;
                        end case;
                        
                    when WIDTH_16 =>
                        -- Write 16-bit word
                        if RW_BYTE_SEL(0) = '0' then
                            RegWindow(to_integer(unsigned(RW_WADDR)))(15 downto 0) <= RW_WDATA(15 downto 0);
                        else
                            RegWindow(to_integer(unsigned(RW_WADDR)))(31 downto 16) <= RW_WDATA(15 downto 0);
                        end if;
                        
                    when others =>
                        -- Write full 32-bit
                        RegWindow(to_integer(unsigned(RW_WADDR))) <= RW_WDATA;
                end case;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    
    -- Main registers (masked by width)
    A_OUT  <= mask_by_width(Ar, WIDTH_M);
    X_OUT  <= mask_by_width(Xr, WIDTH_X);
    Y_OUT  <= mask_by_width(Yr, WIDTH_X);
    SP_OUT <= SPr;
    D_OUT  <= Dr;
    B_OUT  <= Br;
    VBR_OUT <= VBRr;
    T_OUT  <= Tr;
    
    -- Status register
    P_OUT <= Pr;
    
    -- Mode flags
    E_MODE  <= Pr(P_E);
    S_MODE  <= Pr(P_S);
    R_MODE  <= Pr(P_R);
    M_WIDTH <= Pr(P_M1) & Pr(P_M0);
    X_WIDTH <= Pr(P_X1) & Pr(P_X0);
    
    -- Register window read ports
    process(REG_WIN_EN, RW_ADDR1, RW_ADDR2, RW_WIDTH, RW_BYTE_SEL, RegWindow)
        variable reg1, reg2 : std_logic_vector(31 downto 0);
    begin
        if REG_WIN_EN = '1' then
            reg1 := RegWindow(to_integer(unsigned(RW_ADDR1)));
            reg2 := RegWindow(to_integer(unsigned(RW_ADDR2)));
            
            case RW_WIDTH is
                when WIDTH_8 =>
                    case RW_BYTE_SEL is
                        when "00" =>
                            RW_DATA1 <= x"000000" & reg1(7 downto 0);
                            RW_DATA2 <= x"000000" & reg2(7 downto 0);
                        when "01" =>
                            RW_DATA1 <= x"000000" & reg1(15 downto 8);
                            RW_DATA2 <= x"000000" & reg2(15 downto 8);
                        when "10" =>
                            RW_DATA1 <= x"000000" & reg1(23 downto 16);
                            RW_DATA2 <= x"000000" & reg2(23 downto 16);
                        when "11" =>
                            RW_DATA1 <= x"000000" & reg1(31 downto 24);
                            RW_DATA2 <= x"000000" & reg2(31 downto 24);
                        when others =>
                            RW_DATA1 <= reg1;
                            RW_DATA2 <= reg2;
                    end case;
                    
                when WIDTH_16 =>
                    if RW_BYTE_SEL(0) = '0' then
                        RW_DATA1 <= x"0000" & reg1(15 downto 0);
                        RW_DATA2 <= x"0000" & reg2(15 downto 0);
                    else
                        RW_DATA1 <= x"0000" & reg1(31 downto 16);
                        RW_DATA2 <= x"0000" & reg2(31 downto 16);
                    end if;
                    
                when others =>
                    RW_DATA1 <= reg1;
                    RW_DATA2 <= reg2;
            end case;
        else
            RW_DATA1 <= (others => '0');
            RW_DATA2 <= (others => '0');
        end if;
    end process;

end rtl;
