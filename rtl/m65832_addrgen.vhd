-- M65832 Address Generator
-- Extended from 65816 AddrGen to support 32-bit addressing and base registers
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Based on AddrGen.vhd by srg320 (MiSTer project)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_AddrGen is
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        EN              : in  std_logic;
        
        -- PC Control
        LOAD_PC         : in  std_logic_vector(2 downto 0);
        PC_DEC          : in  std_logic;
        GOT_INTERRUPT   : in  std_logic;
        
        -- Address Control
        ADDR_CTRL       : in  std_logic_vector(7 downto 0);
        IND_CTRL        : in  std_logic_vector(1 downto 0);
        
        -- Base Register Control (M65832 extension)
        USE_BASE_B      : in  std_logic;  -- Use B register for absolute addressing
        USE_BASE_VBR    : in  std_logic;  -- Use VBR for 6502 emulation
        
        -- Data Input
        D_IN            : in  std_logic_vector(7 downto 0);
        
        -- Register Inputs (32-bit)
        X               : in  std_logic_vector(31 downto 0);
        Y               : in  std_logic_vector(31 downto 0);
        D               : in  std_logic_vector(31 downto 0);  -- Direct page base
        S               : in  std_logic_vector(31 downto 0);  -- Stack pointer
        T               : in  std_logic_vector(31 downto 0);  -- Temp register
        B               : in  std_logic_vector(31 downto 0);  -- Absolute base (M65832)
        VBR             : in  std_logic_vector(31 downto 0);  -- Virtual 6502 base (M65832)
        DR              : in  std_logic_vector(7 downto 0);   -- Data register
        
        -- Mode flags
        E_MODE          : in  std_logic;  -- Emulation mode (6502)
        W_MODE          : in  std_logic;  -- Wide mode (32-bit)
        
        -- Reset PC value (for initialization)
        RESET_PC        : in  std_logic_vector(31 downto 0);
        
        -- Outputs
        PC              : out std_logic_vector(31 downto 0);  -- Program counter
        VA              : out std_logic_vector(31 downto 0);  -- Virtual address
        AA              : out std_logic_vector(31 downto 0);  -- Absolute address
        DX              : out std_logic_vector(31 downto 0);  -- Direct/indexed address
        AA_CARRY        : out std_logic;                       -- Page crossing
        JUMP_NO_OFL     : out std_logic                        -- Branch no overflow
    );
end M65832_AddrGen;

architecture rtl of M65832_AddrGen is

    -- Internal registers
    signal AAL, AAH     : std_logic_vector(7 downto 0);   -- Address A low/high (65816 compat)
    signal AAX          : std_logic_vector(15 downto 0);  -- Address A extended (M65832)
    signal DL, DH       : std_logic_vector(7 downto 0);   -- Direct low/high
    signal DXL          : std_logic_vector(15 downto 0);  -- Direct extended (M65832)
    
    signal SavedCarry   : std_logic;
    signal AAHCarry     : std_logic;
    
    -- Computed values (use unsigned for arithmetic)
    signal NewAAL_u     : unsigned(8 downto 0);
    signal NewAAH_u     : unsigned(8 downto 0);
    signal NewAAHWithCarry_u : unsigned(8 downto 0);
    signal NewDL_u      : unsigned(8 downto 0);
    
    -- PC handling
    signal PCr          : std_logic_vector(31 downto 0);
    signal NextPC       : std_logic_vector(31 downto 0);
    signal NewPCWithOffset : std_logic_vector(31 downto 0);
    signal NewPCWithOffset16 : std_logic_vector(31 downto 0);
    signal PCOffset     : unsigned(31 downto 0);
    
    -- Control decode
    signal AALCtrl      : std_logic_vector(2 downto 0);
    signal AAHCtrl      : std_logic_vector(2 downto 0);
    signal ABSCtrl      : std_logic_vector(1 downto 0);
    
    -- Inner base selection
    signal InnerBase    : std_logic_vector(31 downto 0);
    
    -- Effective base for addressing
    signal EffectiveBase : std_logic_vector(31 downto 0);
    
    -- Sign extension helper
    signal DR_sign_ext  : std_logic_vector(31 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Control Signal Decode
    ---------------------------------------------------------------------------
    
    AALCtrl <= ADDR_CTRL(7 downto 5);
    AAHCtrl <= ADDR_CTRL(4 downto 2);
    ABSCtrl <= ADDR_CTRL(1 downto 0);
    
    -- Sign extend DR for relative branches
    DR_sign_ext <= (31 downto 8 => DR(7)) & DR;
    
    ---------------------------------------------------------------------------
    -- Base Register Selection
    ---------------------------------------------------------------------------
    
    -- Select effective base for absolute addressing
    process(USE_BASE_B, USE_BASE_VBR, B, VBR, E_MODE)
    begin
        if E_MODE = '1' and USE_BASE_VBR = '1' then
            -- 6502 emulation mode: use VBR
            EffectiveBase <= VBR;
        elsif USE_BASE_B = '1' then
            -- Use B register for based absolute
            EffectiveBase <= B;
        else
            -- Default: no base (zero)
            EffectiveBase <= (others => '0');
        end if;
    end process;
    
    -- Inner base for direct page operations
    InnerBase <= S when ABSCtrl = "11" and (AALCtrl(2) = '1' or AAHCtrl(2) = '1') else D;
    
    ---------------------------------------------------------------------------
    -- PC Offset Calculation
    ---------------------------------------------------------------------------
    
    -- Sign-extended 8-bit relative offset (for branches)
    NewPCWithOffset <= std_logic_vector(unsigned(PCr) + unsigned(DR_sign_ext));
    
    -- 16-bit relative offset
    NewPCWithOffset16 <= std_logic_vector(unsigned(PCr) + PCOffset);
    
    ---------------------------------------------------------------------------
    -- PC State Machine
    ---------------------------------------------------------------------------
    
    process(LOAD_PC, PCr, GOT_INTERRUPT, D_IN, DR, NewPCWithOffset16, 
            NewPCWithOffset, AAH, AAL, AAX, PC_DEC, W_MODE)
    begin
        case LOAD_PC is
            when "000" =>
                -- Hold PC
                NextPC <= PCr;
                
            when "001" =>
                -- PC++
                if GOT_INTERRUPT = '0' then
                    NextPC <= std_logic_vector(unsigned(PCr) + 1);
                else
                    NextPC <= PCr;
                end if;
                
            when "010" =>
                -- Load PC from D_IN:DR (16-bit)
                if W_MODE = '1' then
                    NextPC <= AAX & D_IN & DR;  -- 32-bit in wide mode
                else
                    NextPC <= x"0000" & D_IN & DR;  -- 16-bit
                end if;
                
            when "011" =>
                -- PC + 16-bit offset
                NextPC <= NewPCWithOffset16;
                
            when "100" =>
                -- PC + 8-bit signed offset (branch)
                NextPC <= NewPCWithOffset;
                
            when "101" =>
                -- PC + 16-bit offset (BRL)
                NextPC <= NewPCWithOffset16;
                
            when "110" =>
                -- Load PC from AA
                if W_MODE = '1' then
                    NextPC <= AAX & AAH & AAL;
                else
                    NextPC <= x"0000" & AAH & AAL;
                end if;
                
            when "111" =>
                -- PC - 3 (for MVN/MVP)
                if PC_DEC = '1' then
                    NextPC <= std_logic_vector(unsigned(PCr) - 3);
                else
                    NextPC <= PCr;
                end if;
                
            when others =>
                NextPC <= PCr;
        end case;
    end process;
    
    -- PC Register
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            PCr <= RESET_PC;  -- Initialize PC from reset value
            PCOffset <= (others => '0');
        elsif rising_edge(CLK) then
            if EN = '1' then
                PCOffset(31 downto 16) <= x"0000";
                PCOffset(15 downto 8) <= unsigned(D_IN);
                PCOffset(7 downto 0) <= unsigned(DR);
                PCr <= NextPC;
            end if;
        end if;
    end process;
    
    -- Branch overflow detection
    JUMP_NO_OFL <= (not (PCr(8) xor NewPCWithOffset(8))) and 
                   (not LOAD_PC(0)) and (not LOAD_PC(1)) and LOAD_PC(2);
    
    ---------------------------------------------------------------------------
    -- Address A (AA) Calculation - Index Operations
    ---------------------------------------------------------------------------
    
    process(IND_CTRL, AALCtrl, AAHCtrl, E_MODE, AAL, AAH, DL, DH, X, Y, NewAAL_u)
    begin
        -- AAL calculation
        case IND_CTRL is
            when "00" =>
                -- Add X
                if AALCtrl(2) = '0' then
                    NewAAL_u <= ('0' & unsigned(AAL)) + ('0' & unsigned(X(7 downto 0)));
                else
                    NewAAL_u <= ('0' & unsigned(DL)) + ('0' & unsigned(X(7 downto 0)));
                end if;
                
            when "01" =>
                -- Add Y
                if AALCtrl(2) = '0' then
                    NewAAL_u <= ('0' & unsigned(AAL)) + ('0' & unsigned(Y(7 downto 0)));
                else
                    NewAAL_u <= ('0' & unsigned(DL)) + ('0' & unsigned(Y(7 downto 0)));
                end if;
                
            when "10" =>
                -- Load X low
                NewAAL_u <= '0' & unsigned(X(7 downto 0));
                
            when "11" =>
                -- Load Y low
                NewAAL_u <= '0' & unsigned(Y(7 downto 0));
                
            when others =>
                NewAAL_u <= '0' & unsigned(AAL);
        end case;
        
        -- AAH calculation
        if E_MODE = '0' then
            -- Native mode: 16-bit index
            case IND_CTRL is
                when "00" =>
                    if AAHCtrl(2) = '0' then
                        NewAAH_u <= ('0' & unsigned(AAH)) + ('0' & unsigned(X(15 downto 8)));
                    else
                        NewAAH_u <= ('0' & unsigned(DH)) + ('0' & unsigned(X(15 downto 8))) + 
                                    (x"00" & NewAAL_u(8));
                    end if;
                    
                when "01" =>
                    if AAHCtrl(2) = '0' then
                        NewAAH_u <= ('0' & unsigned(AAH)) + ('0' & unsigned(Y(15 downto 8)));
                    else
                        NewAAH_u <= ('0' & unsigned(DH)) + ('0' & unsigned(Y(15 downto 8))) + 
                                    (x"00" & NewAAL_u(8));
                    end if;
                    
                when "10" =>
                    NewAAH_u <= '0' & unsigned(X(15 downto 8));
                    
                when "11" =>
                    NewAAH_u <= '0' & unsigned(Y(15 downto 8));
                    
                when others =>
                    NewAAH_u <= '0' & unsigned(AAH);
            end case;
        else
            -- Emulation mode: 8-bit index, no carry to high byte
            if AAHCtrl(2) = '0' then
                NewAAH_u <= '0' & unsigned(AAH);
            else
                NewAAH_u <= '0' & unsigned(DH);
            end if;
        end if;
    end process;
    
    -- DL calculation for direct page
    NewDL_u <= ('0' & unsigned(InnerBase(7 downto 0))) + ('0' & unsigned(D_IN));
    NewAAHWithCarry_u <= NewAAH_u + (x"00" & SavedCarry);
    
    ---------------------------------------------------------------------------
    -- Address Register Updates
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            AAL <= (others => '0');
            AAH <= (others => '0');
            AAX <= (others => '0');
            DL <= (others => '0');
            DH <= (others => '0');
            DXL <= (others => '0');
            AAHCarry <= '0';
            SavedCarry <= '0';
        elsif rising_edge(CLK) then
            if EN = '1' then
                -- AAL updates
                case AALCtrl is
                    when "000" =>
                        if IND_CTRL(1) = '1' then
                            AAL <= std_logic_vector(NewAAL_u(7 downto 0));
                        end if;
                        SavedCarry <= '0';
                        
                    when "001" =>
                        AAL <= std_logic_vector(NewAAL_u(7 downto 0));
                        SavedCarry <= NewAAL_u(8);
                        
                    when "010" =>
                        AAL <= D_IN;
                        SavedCarry <= '0';
                        
                    when "011" =>
                        AAL <= NewPCWithOffset16(7 downto 0);
                        SavedCarry <= '0';
                        
                    when "100" =>
                        DL <= std_logic_vector(NewAAL_u(7 downto 0));
                        SavedCarry <= NewAAL_u(8);
                        
                    when "101" =>
                        DL <= std_logic_vector(NewDL_u(7 downto 0));
                        SavedCarry <= NewDL_u(8);
                        
                    when "111" =>
                        null;  -- Hold
                        
                    when others =>
                        null;
                end case;
                
                -- AAH updates
                case AAHCtrl is
                    when "000" =>
                        if IND_CTRL(1) = '1' then
                            AAH <= std_logic_vector(NewAAH_u(7 downto 0));
                            AAHCarry <= '0';
                        end if;
                        
                    when "001" =>
                        AAH <= std_logic_vector(NewAAHWithCarry_u(7 downto 0));
                        AAHCarry <= NewAAHWithCarry_u(8);
                        
                    when "010" =>
                        AAH <= D_IN;
                        AAHCarry <= '0';
                        
                    when "011" =>
                        AAH <= NewPCWithOffset16(15 downto 8);
                        AAHCarry <= '0';
                        
                    when "100" =>
                        DH <= std_logic_vector(NewAAH_u(7 downto 0));
                        AAHCarry <= '0';
                        
                    when "101" =>
                        DH <= InnerBase(15 downto 8);
                        AAHCarry <= '0';
                        
                    when "110" =>
                        DH <= std_logic_vector(unsigned(DH) + ("0000000" & SavedCarry));
                        AAHCarry <= '0';
                        
                    when "111" =>
                        null;  -- Hold
                        
                    when others =>
                        null;
                end case;
                
                -- Extended address updates (M65832)
                case ABSCtrl is
                    when "00" =>
                        null;  -- Hold
                        
                    when "01" =>
                        -- Load extended byte
                        AAX(7 downto 0) <= D_IN;
                        
                    when "10" =>
                        -- Load extended byte with carry
                        AAX(7 downto 0) <= std_logic_vector(unsigned(D_IN) + 
                                           ("0000000" & NewAAHWithCarry_u(8)));
                        
                    when "11" =>
                        -- Load extended word (for 32-bit addresses)
                        AAX(15 downto 8) <= D_IN;
                        
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Output Generation
    ---------------------------------------------------------------------------
    
    -- Program Counter output
    PC <= PCr;
    
    -- Effective Virtual Address (with base register support)
    process(E_MODE, USE_BASE_VBR, VBR, EffectiveBase, AAX, AAH, AAL, AAHCarry, W_MODE)
        variable raw_addr : std_logic_vector(31 downto 0);
    begin
        if W_MODE = '1' then
            -- 32-bit mode: use full address
            raw_addr := AAX & AAH & AAL;
        else
            -- 16-bit mode: zero-extend
            raw_addr := x"0000" & AAH & AAL;
        end if;
        
        -- Add effective base
        VA <= std_logic_vector(unsigned(raw_addr) + unsigned(EffectiveBase));
    end process;
    
    -- Absolute Address (for backward compatibility)
    AA <= "000" & AAHCarry & x"000" & AAH & AAL;
    
    -- Direct/Indexed Address
    DX <= DXL & DH & DL;
    
    -- Page crossing indicator
    AA_CARRY <= NewAAL_u(8);

end rtl;
