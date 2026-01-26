-- M65832 Instruction Decoder
-- Decodes opcodes and generates control signals
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_Decoder is
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        
        -- Instruction input
        IR              : in  std_logic_vector(7 downto 0);   -- Instruction register
        IR_EXT          : in  std_logic_vector(7 downto 0);   -- Extended opcode (after $02)
        IR_EXT2         : in  std_logic_vector(7 downto 0);   -- Second extended byte (mode/op byte)
        IS_EXTENDED     : in  std_logic;                       -- Using extended opcode page
        IS_REGALU_EXT   : in  std_logic;                       -- Reading extended mode/op byte
        
        -- Mode flags
        E_MODE          : in  std_logic;  -- Emulation mode
        M_WIDTH         : in  std_logic_vector(1 downto 0);  -- Accumulator width
        X_WIDTH         : in  std_logic_vector(1 downto 0);  -- Index width
        COMPAT_MODE     : in  std_logic;
        
        -- Decoded instruction class
        IS_ALU_OP       : out std_logic;  -- ALU operation (ORA, AND, EOR, ADC, STA, LDA, CMP, SBC)
        IS_RMW_OP       : out std_logic;  -- Read-modify-write (ASL, ROL, LSR, ROR, INC, DEC)
        IS_BRANCH       : out std_logic;  -- Branch instruction
        IS_JUMP         : out std_logic;  -- JMP/JSR/RTS/RTI
        IS_STACK        : out std_logic;  -- Push/pull
        IS_TRANSFER     : out std_logic;  -- Register transfer (TAX, TXA, etc.)
        IS_FLAG_OP      : out std_logic;  -- Flag manipulation (CLC, SEC, etc.)
        IS_CONTROL      : out std_logic;  -- Control (BRK, NOP, WAI, STP)
        IS_BLOCK_MOVE   : out std_logic;  -- MVN/MVP
        
        -- Addressing mode
        ADDR_MODE       : out std_logic_vector(3 downto 0);
        -- 0000: Implied/Accumulator
        -- 0001: Immediate
        -- 0010: Zero Page / Direct
        -- 0011: Zero Page,X / Direct,X
        -- 0100: Zero Page,Y / Direct,Y  
        -- 0101: Absolute
        -- 0110: Absolute,X
        -- 0111: Absolute,Y
        -- 1000: (Indirect)
        -- 1001: (Indirect,X)
        -- 1010: (Indirect),Y
        -- 1011: [Indirect Long]
        -- 1100: [Indirect Long],Y
        -- 1101: Stack Relative
        -- 1110: (Stack Relative),Y
        -- 1111: Long Absolute
        
        -- ALU operation select
        ALU_OP          : out std_logic_vector(2 downto 0);
        -- 000: ORA
        -- 001: AND
        -- 010: EOR
        -- 011: ADC
        -- 100: STA (store, no ALU)
        -- 101: LDA (load)
        -- 110: CMP
        -- 111: SBC
        
        -- RMW operation select
        RMW_OP          : out std_logic_vector(2 downto 0);
        -- 000: ASL
        -- 001: ROL
        -- 010: LSR
        -- 011: ROR
        -- 100: STX/STY (store)
        -- 101: LDX/LDY (load)
        -- 110: DEC
        -- 111: INC
        
        -- Register select for transfers/operations
        REG_SRC         : out std_logic_vector(2 downto 0);
        REG_DST         : out std_logic_vector(2 downto 0);
        -- 000: A
        -- 001: X
        -- 010: Y
        -- 011: SP
        -- 100: D (Direct page)
        -- 101: B (Absolute base) - M65832
        -- 110: P (Status)
        -- 111: PC
        
        -- Branch condition
        BRANCH_COND     : out std_logic_vector(2 downto 0);
        -- 000: BPL (N=0)
        -- 001: BMI (N=1)
        -- 010: BVC (V=0)
        -- 011: BVS (V=1)
        -- 100: BCC (C=0)
        -- 101: BCS (C=1)
        -- 110: BNE (Z=0)
        -- 111: BEQ (Z=1)
        
        -- Instruction length (for PC increment)
        INSTR_LEN       : out std_logic_vector(2 downto 0);
        -- Length depends on addressing mode and width flags
        
        -- Special instruction flags
        IS_BRK          : out std_logic;
        IS_COP          : out std_logic;
        IS_RTI          : out std_logic;
        IS_RTS          : out std_logic;
        IS_RTL          : out std_logic;
        IS_JSR          : out std_logic;
        IS_JSL          : out std_logic;
        IS_JMP          : out std_logic;
        IS_JML          : out std_logic;
        IS_PER          : out std_logic;
        IS_WAI          : out std_logic;
        IS_STP          : out std_logic;
        IS_XCE          : out std_logic;
        IS_REP          : out std_logic;
        IS_SEP          : out std_logic;
        IS_WDM          : out std_logic;  -- Reserved for extension
        
        -- M65832 Extensions
        IS_EXT_OP       : out std_logic;  -- Extended opcode ($02 prefix)
        EXT_ALU         : out std_logic;  -- Extended ALU operation ($02 $80-$97)
        EXT_ALU_SIZE    : out std_logic_vector(1 downto 0);  -- Extended ALU data size (from mode)
        EXT_ADDR32      : out std_logic;  -- Extended ALU uses 32-bit absolute operand
        IS_RSET         : out std_logic;  -- Enable register window
        IS_RCLR         : out std_logic;  -- Disable register window
        IS_SB           : out std_logic;  -- Set B register
        IS_SVBR         : out std_logic;  -- Set VBR
        IS_CAS          : out std_logic;  -- Compare and swap
        IS_LLI          : out std_logic;  -- Load linked
        IS_SCI          : out std_logic;  -- Store conditional
        ILLEGAL_OP      : out std_logic;
        
        -- Register-Targeted ALU (Extended ALU target=1)
        IS_REGALU       : out std_logic;  -- Register-targeted ALU operation
        REGALU_OP       : out std_logic_vector(3 downto 0);  -- Operation (LD/ADC/SBC/AND/ORA/EOR/CMP)
        REGALU_SRC_MODE : out std_logic_vector(3 downto 0);  -- Source addressing mode
        REGALU_DEST_DP  : out std_logic_vector(7 downto 0);  -- Destination DP address (from IR_EXT2)
        
        -- Shifter ($02 $E9)
        IS_SHIFTER      : out std_logic;  -- Shifter operation
        SHIFT_OP        : out std_logic_vector(2 downto 0);  -- Shift type (SHL/SHR/SAR/ROL/ROR)
        SHIFT_COUNT     : out std_logic_vector(4 downto 0);  -- Shift count (or 11111 for A)
        
        -- Extend ($02 $EA)
        IS_EXTEND       : out std_logic;  -- Sign/zero extend operation
        EXTEND_OP       : out std_logic_vector(3 downto 0)   -- Extend type
    );
end M65832_Decoder;

architecture rtl of M65832_Decoder is

    -- Instruction groups based on opcode bits
    signal cc   : std_logic_vector(1 downto 0);  -- IR[1:0]
    signal bbb  : std_logic_vector(2 downto 0);  -- IR[4:2]
    signal aaa  : std_logic_vector(2 downto 0);  -- IR[7:5]
    
    -- Decoded addressing mode from bbb
    signal addr_mode_base : std_logic_vector(3 downto 0);
    
begin

    -- Extract opcode fields (6502-style encoding)
    cc  <= IR(1 downto 0);
    bbb <= IR(4 downto 2);
    aaa <= IR(7 downto 5);
    
    ---------------------------------------------------------------------------
    -- Main Instruction Decoder
    ---------------------------------------------------------------------------
    
    process(IR, IR_EXT, IR_EXT2, IS_EXTENDED, IS_REGALU_EXT, E_MODE, M_WIDTH, X_WIDTH, COMPAT_MODE, cc, bbb, aaa)
        variable regalu_src : std_logic_vector(3 downto 0);
        variable ext_mode   : std_logic_vector(7 downto 0);
        variable ext_size   : std_logic_vector(1 downto 0);
        variable ext_target : std_logic;
        variable ext_addr   : std_logic_vector(4 downto 0);
        variable ext_len    : integer range 1 to 8;
    begin
        -- Default outputs
        IS_ALU_OP     <= '0';
        IS_RMW_OP     <= '0';
        IS_BRANCH     <= '0';
        IS_JUMP       <= '0';
        IS_STACK      <= '0';
        IS_TRANSFER   <= '0';
        IS_FLAG_OP    <= '0';
        IS_CONTROL    <= '0';
        IS_BLOCK_MOVE <= '0';
        
        ADDR_MODE     <= "0000";
        ALU_OP        <= "000";
        RMW_OP        <= "000";
        REG_SRC       <= "000";
        REG_DST       <= "000";
        BRANCH_COND   <= "000";
        INSTR_LEN     <= "001";  -- Default 1 byte
        
        IS_BRK  <= '0';
        IS_COP  <= '0';
        IS_RTI  <= '0';
        IS_RTS  <= '0';
        IS_RTL  <= '0';
        IS_JSR  <= '0';
        IS_JSL  <= '0';
        IS_JMP  <= '0';
        IS_JML  <= '0';
        IS_PER  <= '0';
        IS_WAI  <= '0';
        IS_STP  <= '0';
        IS_XCE  <= '0';
        IS_REP  <= '0';
        IS_SEP  <= '0';
        IS_WDM  <= '0';
        
        IS_EXT_OP <= '0';
        EXT_ALU   <= '0';
        EXT_ALU_SIZE <= WIDTH_32;
        EXT_ADDR32 <= '0';
        IS_RSET   <= '0';
        IS_RCLR   <= '0';
        IS_SB     <= '0';
        IS_SVBR   <= '0';
        IS_CAS    <= '0';
        IS_LLI    <= '0';
        IS_SCI    <= '0';
        ILLEGAL_OP <= '0';
        
        -- Register-targeted ALU defaults
        IS_REGALU       <= '0';
        REGALU_OP       <= "0000";
        REGALU_SRC_MODE <= "0000";
        REGALU_DEST_DP  <= (others => '0');
        
        -- Shifter defaults
        IS_SHIFTER      <= '0';
        SHIFT_OP        <= "000";
        SHIFT_COUNT     <= "00000";
        
        -- Extend defaults
        IS_EXTEND       <= '0';
        EXTEND_OP       <= "0000";
        
        if IS_EXTENDED = '1' then
            -- Extended opcode page (after $02 prefix)
            IS_EXT_OP <= '1';
            
            case IR_EXT is
                -- Multiply/Divide
                when x"00" | x"01" | x"04" | x"05" =>
                    ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- MUL/MULU/DIV/DIVU dp
                when x"02" | x"03" | x"06" | x"07" =>
                    ADDR_MODE <= "0101"; INSTR_LEN <= "100";  -- MUL/MULU/DIV/DIVU abs
                
                -- CAS/LLI/SCI
                when x"10" | x"12" | x"14" =>
                    ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- dp
                when x"11" | x"13" | x"15" =>
                    ADDR_MODE <= "0101"; INSTR_LEN <= "100";  -- abs
                
                -- Set base registers (imm32 or dp)
                when x"20" | x"22" | x"24" =>
                    ADDR_MODE <= "0001"; INSTR_LEN <= "110";  -- imm32
                when x"21" | x"23" | x"25" =>
                    ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- dp
                
                -- Register window control
                when x"30" => IS_RSET <= '1'; INSTR_LEN <= "010";  -- RSET
                when x"31" => IS_RCLR <= '1'; INSTR_LEN <= "010";  -- RCLR
                
                -- TRAP and fences
                when x"40" => ADDR_MODE <= "0001"; INSTR_LEN <= "011";  -- TRAP #imm8
                when x"50" | x"51" | x"52" =>
                    INSTR_LEN <= "010";  -- FENCE/FENCER/FENCEW
                
                -- Extended status ops
                when x"60" | x"61" =>
                    ADDR_MODE <= "0001"; INSTR_LEN <= "011";  -- REPE/SEPE #imm8
                
                -- Extended stack ops (32-bit)
                when x"70" => IS_STACK <= '1'; REG_SRC <= "100"; INSTR_LEN <= "010";  -- PHD (32)
                when x"71" => IS_STACK <= '1'; REG_DST <= "100"; INSTR_LEN <= "010";  -- PLD (32)
                when x"72" => IS_STACK <= '1'; REG_SRC <= "101"; INSTR_LEN <= "010";  -- PHB (32)
                when x"73" => IS_STACK <= '1'; REG_DST <= "101"; INSTR_LEN <= "010";  -- PLB (32)
                when x"74" => IS_STACK <= '1'; REG_SRC <= "111"; INSTR_LEN <= "010";  -- PHVBR (32)
                when x"75" => IS_STACK <= '1'; REG_DST <= "111"; INSTR_LEN <= "010";  -- PLVBR (32)
                
                -- Transfer T (remainder/temp)
                when x"9A" => INSTR_LEN <= "010";  -- TTA (A = T)
                when x"9B" => INSTR_LEN <= "010";  -- TAT (T = A)
                
                -- 64-bit load/store (A=low, T=high)
                when x"9C" => ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- LDQ dp
                when x"9D" => ADDR_MODE <= "0101"; INSTR_LEN <= "100";  -- LDQ abs
                when x"9E" => ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- STQ dp
                when x"9F" => ADDR_MODE <= "0101"; INSTR_LEN <= "100";  -- STQ abs
                
                -- FPU load/store (64-bit)
                when x"B0" | x"B2" | x"B4" | x"B6" | x"B8" | x"BA" =>
                    ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- LDF/STF dp
                when x"B1" | x"B3" | x"B5" | x"B7" | x"B9" | x"BB" =>
                    ADDR_MODE <= "0101"; INSTR_LEN <= "100";  -- LDF/STF abs
                
                -- LEA
                when x"A0" =>
                    ADDR_MODE <= "0010"; INSTR_LEN <= "011";  -- LEA dp
                when x"A1" =>
                    ADDR_MODE <= "0011"; INSTR_LEN <= "011";  -- LEA dp,X
                when x"A2" =>
                    ADDR_MODE <= "0101"; INSTR_LEN <= "100";  -- LEA abs
                when x"A3" =>
                    ADDR_MODE <= "0110"; INSTR_LEN <= "100";  -- LEA abs,X
                
                -- FPU coprocessor ops (implied)
                when x"C0" | x"C1" | x"C2" | x"C3" | x"C4" | x"C5" | x"C6" | x"C7" | x"C8" |
                     x"D0" | x"D1" | x"D2" | x"D3" | x"D4" | x"D5" | x"D6" | x"D7" | x"D8" =>
                    INSTR_LEN <= "010";
                
                -- Extended ALU ($02 $80-$97) with mode byte
                when x"80" | x"81" | x"82" | x"83" | x"84" | x"85" | x"86" | x"87" |
                     x"88" | x"89" | x"8A" | x"8B" | x"8C" | x"8D" | x"8E" | x"8F" |
                     x"90" | x"97" =>
                    IS_EXT_OP <= '1';
                    EXT_ALU <= '1';
                    if IS_REGALU_EXT = '1' then
                        ext_mode := IR_EXT2;
                        ext_size := ext_mode(7 downto 6);
                        ext_target := ext_mode(5);
                        ext_addr := ext_mode(4 downto 0);
                        EXT_ALU_SIZE <= ext_size;
                        
                        -- Map opcode to ALU/reg-ALU operation
                        case IR_EXT is
                            when x"80" => REGALU_OP <= REGALU_LD;  ALU_OP <= "101"; -- LD -> LDA
                            when x"81" => ALU_OP <= "100"; -- ST -> STA (A-target only)
                            when x"82" => REGALU_OP <= REGALU_ADC; ALU_OP <= "011";
                            when x"83" => REGALU_OP <= REGALU_SBC; ALU_OP <= "111";
                            when x"84" => REGALU_OP <= REGALU_AND; ALU_OP <= "001";
                            when x"85" => REGALU_OP <= REGALU_ORA; ALU_OP <= "000";
                            when x"86" => REGALU_OP <= REGALU_EOR; ALU_OP <= "010";
                            when x"87" => REGALU_OP <= REGALU_CMP; ALU_OP <= "110";
                            when x"88" => ALU_OP <= "001"; -- BIT
                            when x"89" => ALU_OP <= "001"; -- TSB (A-target only)
                            when x"8A" => ALU_OP <= "001"; -- TRB (A-target only)
                            when x"8B" => RMW_OP <= "111"; -- INC
                            when x"8C" => RMW_OP <= "110"; -- DEC
                            when x"8D" => RMW_OP <= "000"; -- ASL
                            when x"8E" => RMW_OP <= "010"; -- LSR
                            when x"8F" => RMW_OP <= "001"; -- ROL
                            when x"90" => RMW_OP <= "011"; -- ROR
                            when x"97" => ALU_OP <= "100"; -- STZ (A-target only)
                            when others => null;
                        end case;
                        
                        -- Addressing mode mapping
                        ext_len := 3;  -- $02, op, mode
                        regalu_src := REGALU_SRC_DP;
                        if ext_target = '1' then
                            if IR_EXT = x"80" or IR_EXT = x"82" or IR_EXT = x"83" or IR_EXT = x"84" or
                               IR_EXT = x"85" or IR_EXT = x"86" or IR_EXT = x"87" then
                                IS_REGALU <= '1';
                                ext_len := 4;  -- + dest_dp
                            else
                                ILLEGAL_OP <= '1';
                            end if;
                        else
                            IS_ALU_OP <= '1';
                        end if;
                        
                        case ext_addr is
                            when "00000" => regalu_src := REGALU_SRC_DP;      ADDR_MODE <= "0010"; ext_len := ext_len + 1;
                            when "00001" => regalu_src := REGALU_SRC_DPX;     ADDR_MODE <= "0011"; ext_len := ext_len + 1;
                            when "00010" => regalu_src := REGALU_SRC_DP_Y;    ADDR_MODE <= "0100"; ext_len := ext_len + 1;
                            when "00011" => regalu_src := REGALU_SRC_DPX_IND; ADDR_MODE <= "1001"; ext_len := ext_len + 1;
                            when "00100" => regalu_src := REGALU_SRC_DP_Y;    ADDR_MODE <= "1010"; ext_len := ext_len + 1;
                            when "00101" => regalu_src := REGALU_SRC_DP_IND;  ADDR_MODE <= "1000"; ext_len := ext_len + 1;
                            when "00110" => regalu_src := REGALU_SRC_DP_LONG; ADDR_MODE <= "1011"; ext_len := ext_len + 1;
                            when "00111" => regalu_src := REGALU_SRC_DPL_Y;   ADDR_MODE <= "1100"; ext_len := ext_len + 1;
                            when "01000" => regalu_src := REGALU_SRC_ABS;     ADDR_MODE <= "0101"; ext_len := ext_len + 2;
                            when "01001" => regalu_src := REGALU_SRC_ABSX;    ADDR_MODE <= "0110"; ext_len := ext_len + 2;
                            when "01010" => regalu_src := REGALU_SRC_ABSY;    ADDR_MODE <= "0111"; ext_len := ext_len + 2;
                            when "10000" => regalu_src := REGALU_SRC_ABS;     ADDR_MODE <= "0101"; EXT_ADDR32 <= '1'; ext_len := ext_len + 4;
                            when "10001" => regalu_src := REGALU_SRC_ABSX;    ADDR_MODE <= "0110"; EXT_ADDR32 <= '1'; ext_len := ext_len + 4;
                            when "10010" => regalu_src := REGALU_SRC_ABSY;    ADDR_MODE <= "0111"; EXT_ADDR32 <= '1'; ext_len := ext_len + 4;
                            when "11000" => regalu_src := REGALU_SRC_IMM;     ADDR_MODE <= "0001";
                                if ext_size = WIDTH_8 then
                                    ext_len := ext_len + 1;
                                elsif ext_size = WIDTH_16 then
                                    ext_len := ext_len + 2;
                                else
                                    ext_len := ext_len + 4;
                                end if;
                            when "11001" => regalu_src := REGALU_SRC_A;       ADDR_MODE <= "0000";
                            when "11010" => regalu_src := REGALU_SRC_X;       ADDR_MODE <= "0000";
                            when "11011" => regalu_src := REGALU_SRC_Y;       ADDR_MODE <= "0000";
                            when "11100" => regalu_src := REGALU_SRC_SR;      ADDR_MODE <= "1101"; ext_len := ext_len + 1;
                            when "11101" => regalu_src := REGALU_SRC_SR_Y;    ADDR_MODE <= "1110"; ext_len := ext_len + 1;
                            when others =>
                                ILLEGAL_OP <= '1';
                        end case;
                        
                        REGALU_SRC_MODE <= regalu_src;
                        if ext_target = '0' and ext_addr = "00000" and
                           (IR_EXT = x"8B" or IR_EXT = x"8C" or IR_EXT = x"8D" or
                            IR_EXT = x"8E" or IR_EXT = x"8F" or IR_EXT = x"90") then
                            IS_ALU_OP <= '0';
                            IS_RMW_OP <= '1';
                            REG_DST <= "000";
                            ADDR_MODE <= "0000";
                            ext_len := 3;
                        end if;
                        if ext_len = 8 then
                            INSTR_LEN <= "000";
                        else
                            INSTR_LEN <= std_logic_vector(to_unsigned(ext_len, 3));
                        end if;
                    else
                        -- Not yet fetched mode byte
                        INSTR_LEN <= "011";  -- At least 3 bytes so far
                    end if;
                
                -- Shifter/Rotate ($02 $98)
                -- Format: $02 $98 [op|cnt] [dest_dp] [src_dp]
                when x"98" =>
                    IS_EXT_OP <= '1';
                    IS_SHIFTER <= '1';
                    if IS_REGALU_EXT = '1' then
                        -- op|cnt byte is in IR_EXT2
                        SHIFT_OP <= IR_EXT2(7 downto 5);
                        SHIFT_COUNT <= IR_EXT2(4 downto 0);
                        INSTR_LEN <= "101";  -- 5 bytes: $02 $98 op|cnt dest_dp src_dp
                        ADDR_MODE <= "0010"; -- dp-like (two DP operands)
                    else
                        INSTR_LEN <= "011";  -- At least 3 bytes so far
                    end if;
                
                -- Sign/Zero Extend ($02 $99)
                -- Format: $02 $99 [subop] [dest_dp] [src_dp]
                when x"99" =>
                    IS_EXT_OP <= '1';
                    IS_EXTEND <= '1';
                    if IS_REGALU_EXT = '1' then
                        EXTEND_OP <= IR_EXT2(3 downto 0);
                        INSTR_LEN <= "101";  -- 5 bytes: $02 $99 subop dest_dp src_dp
                        ADDR_MODE <= "0010"; -- dp-like (two DP operands)
                    else
                        INSTR_LEN <= "011";  -- At least 3 bytes so far
                    end if;
                
                when others =>
                    if IR_EXT = x"D9" or IR_EXT = x"DA" or IR_EXT = x"DB" or IR_EXT = x"DC" or
                       IR_EXT = x"DD" or IR_EXT = x"DE" or IR_EXT = x"DF" or IR_EXT = x"E0" or
                       IR_EXT = x"E1" or IR_EXT = x"E2" or IR_EXT = x"E3" or IR_EXT = x"E4" or
                       IR_EXT = x"E5" or IR_EXT = x"E6" then
                        -- Reserved FP opcodes trap via TRAP vector
                        INSTR_LEN <= "010";
                    elsif COMPAT_MODE = '1' then
                        IS_CONTROL <= '1';  -- Unknown extended op = NOP in compat
                        INSTR_LEN <= "010";
                    else
                        ILLEGAL_OP <= '1';
                        IS_CONTROL <= '1';
                        INSTR_LEN <= "010";
                    end if;
            end case;
            
        else
            -- Standard 65816 opcode space
            
            case cc is
                when "01" =>
                    -- Group 1: ORA, AND, EOR, ADC, STA, LDA, CMP, SBC
                    IS_ALU_OP <= '1';
                    ALU_OP <= aaa;
                    
                    case bbb is
                        when "000" => ADDR_MODE <= "1001"; INSTR_LEN <= "010";  -- (dp,X)
                        when "001" => ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- dp
                        when "010" => ADDR_MODE <= "0001"; -- Immediate
                            if M_WIDTH = WIDTH_32 then
                                INSTR_LEN <= "101";  -- 5 bytes (op + 32-bit imm)
                            elsif M_WIDTH = WIDTH_16 then
                                INSTR_LEN <= "011";  -- 3 bytes
                            else
                                INSTR_LEN <= "010";  -- 2 bytes
                            end if;
                        when "011" => ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- abs
                        when "100" => ADDR_MODE <= "1010"; INSTR_LEN <= "010";  -- (dp),Y
                        when "101" => ADDR_MODE <= "0011"; INSTR_LEN <= "010";  -- dp,X
                        when "110" => ADDR_MODE <= "0111"; INSTR_LEN <= "011";  -- abs,Y
                        when "111" => ADDR_MODE <= "0110"; INSTR_LEN <= "011";  -- abs,X
                        when others => null;
                    end case;
                    
                when "10" =>
                    -- Group 2: ASL, ROL, LSR, ROR, STX, LDX, DEC, INC
                    -- plus implied/register transfers that share cc="10"
                    if IR = x"22" then
                        IS_JSL <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- JSL long
                    elsif IR = x"62" then
                        IS_PER <= '1'; IS_STACK <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "011";  -- PER
                    elsif IR = x"B2" then
                        IS_ALU_OP <= '1'; ALU_OP <= "101"; ADDR_MODE <= "1000"; INSTR_LEN <= "010";  -- LDA (dp)
                    elsif IR = x"92" then
                        IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "1000"; INSTR_LEN <= "010";  -- STA (dp)
                    elsif IR = x"42" then
                        IS_WDM <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "010";  -- Reserved (WDM)
                    elsif IR = x"C2" then
                        IS_REP <= '1'; IS_FLAG_OP <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "010";  -- REP #imm
                    elsif IR = x"E2" then
                        IS_SEP <= '1'; IS_FLAG_OP <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "010";  -- SEP #imm
                    elsif IR = x"AA" then
                        IS_TRANSFER <= '1'; REG_SRC <= "000"; REG_DST <= "001"; INSTR_LEN <= "001";  -- TAX
                    elsif IR = x"8A" then
                        IS_TRANSFER <= '1'; REG_SRC <= "001"; REG_DST <= "000"; INSTR_LEN <= "001";  -- TXA
                    elsif IR = x"BA" then
                        IS_TRANSFER <= '1'; REG_SRC <= "011"; REG_DST <= "001"; INSTR_LEN <= "001";  -- TSX
                    elsif IR = x"9A" then
                        IS_TRANSFER <= '1'; REG_SRC <= "001"; REG_DST <= "011"; INSTR_LEN <= "001";  -- TXS
                    elsif IR = x"CA" then
                        IS_RMW_OP <= '1'; RMW_OP <= "110"; REG_DST <= "001"; ADDR_MODE <= "0000"; INSTR_LEN <= "001";  -- DEX
                    elsif IR = x"DA" then
                        IS_STACK <= '1'; REG_SRC <= "001"; INSTR_LEN <= "001";  -- PHX
                    elsif IR = x"FA" then
                        IS_STACK <= '1'; REG_DST <= "001"; INSTR_LEN <= "001";  -- PLX
                    elsif IR = x"5A" then
                        IS_STACK <= '1'; REG_SRC <= "010"; INSTR_LEN <= "001";  -- PHY
                    elsif IR = x"7A" then
                        IS_STACK <= '1'; REG_DST <= "010"; INSTR_LEN <= "001";  -- PLY
                    else
                        IS_RMW_OP <= '1';
                        RMW_OP <= aaa;
                        
                        -- Set register source/destination for STX/LDX
                        if aaa = "101" then
                            REG_DST <= "001";  -- LDX
                        elsif aaa = "100" then
                            REG_SRC <= "001";  -- STX
                        end if;
                        
                        case bbb is
                            when "000" =>  -- Immediate (LDX only)
                                if aaa = "101" then
                                    ADDR_MODE <= "0001";
                                    if X_WIDTH = WIDTH_32 then
                                        INSTR_LEN <= "101";
                                    elsif X_WIDTH = WIDTH_16 then
                                        INSTR_LEN <= "011";
                                    else
                                        INSTR_LEN <= "010";
                                    end if;
                                else
                                    ADDR_MODE <= "0000";  -- Accumulator
                                    INSTR_LEN <= "001";
                                end if;
                            when "001" => ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- dp
                            when "010" => ADDR_MODE <= "0000"; INSTR_LEN <= "001";  -- Accumulator
                            when "011" => ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- abs
                            when "101" =>  -- dp,X or dp,Y
                                if aaa = "100" or aaa = "101" then
                                    ADDR_MODE <= "0100";  -- dp,Y (STX, LDX)
                                else
                                    ADDR_MODE <= "0011";  -- dp,X
                                end if;
                                INSTR_LEN <= "010";
                            when "111" =>  -- abs,X or abs,Y
                                if aaa = "101" then
                                    ADDR_MODE <= "0111";  -- abs,Y (LDX)
                                else
                                    ADDR_MODE <= "0110";  -- abs,X
                                end if;
                                INSTR_LEN <= "011";
                            when others => null;
                        end case;
                    end if;
                    
                when "00" =>
                    -- Group 0: Mixed instructions
                    case IR is
                        -- BRK, RTI, RTS
                        when x"00" => IS_BRK <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "010";
                        when x"02" =>  -- COP or Extended prefix
                            if E_MODE = '1' then
                                IS_COP <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "010";
                            else
                                IS_EXT_OP <= '1'; INSTR_LEN <= "010";  -- Extended opcode prefix
                            end if;
                        when x"40" => IS_RTI <= '1'; IS_JUMP <= '1'; INSTR_LEN <= "001";
                        when x"60" => IS_RTS <= '1'; IS_JUMP <= '1'; INSTR_LEN <= "001";
                        when x"6B" => IS_RTL <= '1'; IS_JUMP <= '1'; INSTR_LEN <= "001";
                        
                        -- JSR, JMP
                        when x"20" => IS_JSR <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- JSR abs
                        when x"22" => IS_JSL <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- JSL long
                        when x"4C" => IS_JMP <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- JMP abs
                        when x"5C" => IS_JML <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- JML long
                        when x"6C" => IS_JMP <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "1000"; INSTR_LEN <= "011";  -- JMP (abs)
                        when x"7C" => IS_JMP <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "1001"; INSTR_LEN <= "011";  -- JMP (abs,X)
                        when x"DC" => IS_JML <= '1'; IS_JUMP <= '1'; ADDR_MODE <= "1011"; INSTR_LEN <= "011";  -- JML [abs]
                        
                        -- Branches
                        when x"10" => IS_BRANCH <= '1'; BRANCH_COND <= "000"; INSTR_LEN <= "010";  -- BPL
                        when x"30" => IS_BRANCH <= '1'; BRANCH_COND <= "001"; INSTR_LEN <= "010";  -- BMI
                        when x"50" => IS_BRANCH <= '1'; BRANCH_COND <= "010"; INSTR_LEN <= "010";  -- BVC
                        when x"70" => IS_BRANCH <= '1'; BRANCH_COND <= "011"; INSTR_LEN <= "010";  -- BVS
                        when x"90" => IS_BRANCH <= '1'; BRANCH_COND <= "100"; INSTR_LEN <= "010";  -- BCC
                        when x"B0" => IS_BRANCH <= '1'; BRANCH_COND <= "101"; INSTR_LEN <= "010";  -- BCS
                        when x"D0" => IS_BRANCH <= '1'; BRANCH_COND <= "110"; INSTR_LEN <= "010";  -- BNE
                        when x"F0" => IS_BRANCH <= '1'; BRANCH_COND <= "111"; INSTR_LEN <= "010";  -- BEQ
                        when x"80" => IS_BRANCH <= '1'; INSTR_LEN <= "010";  -- BRA
                        when x"82" => IS_BRANCH <= '1'; INSTR_LEN <= "011";  -- BRL
                        
                        -- Stack operations
                        when x"08" => IS_STACK <= '1'; REG_SRC <= "110"; INSTR_LEN <= "001";  -- PHP
                        when x"28" => IS_STACK <= '1'; REG_DST <= "110"; INSTR_LEN <= "001";  -- PLP
                        when x"48" => IS_STACK <= '1'; REG_SRC <= "000"; INSTR_LEN <= "001";  -- PHA
                        when x"68" => IS_STACK <= '1'; REG_DST <= "000"; INSTR_LEN <= "001";  -- PLA
                        when x"DA" => IS_STACK <= '1'; REG_SRC <= "001"; INSTR_LEN <= "001";  -- PHX
                        when x"FA" => IS_STACK <= '1'; REG_DST <= "001"; INSTR_LEN <= "001";  -- PLX
                        when x"5A" => IS_STACK <= '1'; REG_SRC <= "010"; INSTR_LEN <= "001";  -- PHY
                        when x"7A" => IS_STACK <= '1'; REG_DST <= "010"; INSTR_LEN <= "001";  -- PLY
                        when x"0B" => IS_STACK <= '1'; REG_SRC <= "100"; INSTR_LEN <= "001";  -- PHD
                        when x"2B" => IS_STACK <= '1'; REG_DST <= "100"; INSTR_LEN <= "001";  -- PLD
                        when x"8B" => IS_STACK <= '1'; REG_SRC <= "101"; INSTR_LEN <= "001";  -- PHB
                        when x"AB" => IS_STACK <= '1'; REG_DST <= "101"; INSTR_LEN <= "001";  -- PLB
                        when x"4B" => IS_STACK <= '1'; REG_SRC <= "111"; INSTR_LEN <= "001";  -- PHK
                        when x"62" => IS_PER <= '1'; IS_STACK <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "011";     -- PER
                        when x"D4" => IS_STACK <= '1'; ADDR_MODE <= "0010"; INSTR_LEN <= "010"; -- PEI (dp)
                        when x"F4" => IS_STACK <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "011"; -- PEA #imm16
                        
                        -- Flag operations
                        when x"18" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- CLC
                        when x"38" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- SEC
                        when x"58" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- CLI
                        when x"78" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- SEI
                        when x"B8" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- CLV
                        when x"D8" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- CLD
                        when x"F8" => IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- SED
                        when x"C2" => IS_REP <= '1'; IS_FLAG_OP <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "010";  -- REP #imm
                        when x"E2" => IS_SEP <= '1'; IS_FLAG_OP <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "010";  -- SEP #imm
                        when x"FB" => IS_XCE <= '1'; IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- XCE
                        
                        -- Transfers
                        when x"AA" => IS_TRANSFER <= '1'; REG_SRC <= "000"; REG_DST <= "001"; INSTR_LEN <= "001";  -- TAX
                        when x"8A" => IS_TRANSFER <= '1'; REG_SRC <= "001"; REG_DST <= "000"; INSTR_LEN <= "001";  -- TXA
                        when x"A8" => IS_TRANSFER <= '1'; REG_SRC <= "000"; REG_DST <= "010"; INSTR_LEN <= "001";  -- TAY
                        when x"98" => IS_TRANSFER <= '1'; REG_SRC <= "010"; REG_DST <= "000"; INSTR_LEN <= "001";  -- TYA
                        when x"BA" => IS_TRANSFER <= '1'; REG_SRC <= "011"; REG_DST <= "001"; INSTR_LEN <= "001";  -- TSX
                        when x"9A" => IS_TRANSFER <= '1'; REG_SRC <= "001"; REG_DST <= "011"; INSTR_LEN <= "001";  -- TXS
                        when x"9B" => IS_TRANSFER <= '1'; REG_SRC <= "001"; REG_DST <= "010"; INSTR_LEN <= "001";  -- TXY
                        when x"BB" => IS_TRANSFER <= '1'; REG_SRC <= "010"; REG_DST <= "001"; INSTR_LEN <= "001";  -- TYX
                        when x"5B" => IS_TRANSFER <= '1'; REG_SRC <= "000"; REG_DST <= "100"; INSTR_LEN <= "001";  -- TCD
                        when x"7B" => IS_TRANSFER <= '1'; REG_SRC <= "100"; REG_DST <= "000"; INSTR_LEN <= "001";  -- TDC
                        when x"1B" => IS_TRANSFER <= '1'; REG_SRC <= "000"; REG_DST <= "011"; INSTR_LEN <= "001";  -- TCS
                        when x"3B" => IS_TRANSFER <= '1'; REG_SRC <= "011"; REG_DST <= "000"; INSTR_LEN <= "001";  -- TSC
                        
                        -- Control
                        when x"EA" => IS_CONTROL <= '1'; INSTR_LEN <= "001";  -- NOP
                        when x"42" => IS_WDM <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "010";  -- Reserved (WDM)
                        when x"CB" => IS_WAI <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "001";  -- WAI
                        when x"DB" => IS_STP <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "001";  -- STP
                        
                        -- Block moves
                        when x"44" => IS_BLOCK_MOVE <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "011";  -- MVN
                        when x"54" => IS_BLOCK_MOVE <= '1'; ADDR_MODE <= "0001"; INSTR_LEN <= "011";  -- MVP
                        
                        -- BIT, CPX, CPY, STY, LDY
                        when x"24" => IS_ALU_OP <= '1'; ALU_OP <= "001"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- BIT dp
                        when x"2C" => IS_ALU_OP <= '1'; ALU_OP <= "001"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- BIT abs
                        when x"34" => IS_ALU_OP <= '1'; ALU_OP <= "001"; ADDR_MODE <= "0011"; INSTR_LEN <= "010";  -- BIT dp,X
                        when x"3C" => IS_ALU_OP <= '1'; ALU_OP <= "001"; ADDR_MODE <= "0110"; INSTR_LEN <= "011";  -- BIT abs,X
                        when x"89" => IS_ALU_OP <= '1'; ALU_OP <= "001"; ADDR_MODE <= "0001";  -- BIT #imm
                            if M_WIDTH = WIDTH_32 then INSTR_LEN <= "101";
                            elsif M_WIDTH = WIDTH_16 then INSTR_LEN <= "011";
                            else INSTR_LEN <= "010";
                            end if;
                        
                        when x"E0" => IS_ALU_OP <= '1'; ALU_OP <= "110"; REG_SRC <= "001"; ADDR_MODE <= "0001";  -- CPX #imm
                            if X_WIDTH = WIDTH_32 then INSTR_LEN <= "101";
                            elsif X_WIDTH = WIDTH_16 then INSTR_LEN <= "011";
                            else INSTR_LEN <= "010";
                            end if;
                        when x"E4" => IS_ALU_OP <= '1'; ALU_OP <= "110"; REG_SRC <= "001"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- CPX dp
                        when x"EC" => IS_ALU_OP <= '1'; ALU_OP <= "110"; REG_SRC <= "001"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- CPX abs
                        
                        when x"C0" => IS_ALU_OP <= '1'; ALU_OP <= "110"; REG_SRC <= "010"; ADDR_MODE <= "0001";  -- CPY #imm
                            if X_WIDTH = WIDTH_32 then INSTR_LEN <= "101";
                            elsif X_WIDTH = WIDTH_16 then INSTR_LEN <= "011";
                            else INSTR_LEN <= "010";
                            end if;
                        when x"C4" => IS_ALU_OP <= '1'; ALU_OP <= "110"; REG_SRC <= "010"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- CPY dp
                        when x"CC" => IS_ALU_OP <= '1'; ALU_OP <= "110"; REG_SRC <= "010"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- CPY abs
                        
                        -- STY, LDY
                        when x"84" => IS_RMW_OP <= '1'; RMW_OP <= "100"; REG_SRC <= "010"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- STY dp
                        when x"8C" => IS_RMW_OP <= '1'; RMW_OP <= "100"; REG_SRC <= "010"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- STY abs
                        when x"94" => IS_RMW_OP <= '1'; RMW_OP <= "100"; REG_SRC <= "010"; ADDR_MODE <= "0011"; INSTR_LEN <= "010";  -- STY dp,X
                        
                        when x"A0" => IS_RMW_OP <= '1'; RMW_OP <= "101"; REG_DST <= "010"; ADDR_MODE <= "0001";  -- LDY #imm
                            if X_WIDTH = WIDTH_32 then INSTR_LEN <= "101";
                            elsif X_WIDTH = WIDTH_16 then INSTR_LEN <= "011";
                            else INSTR_LEN <= "010";
                            end if;
                        when x"A4" => IS_RMW_OP <= '1'; RMW_OP <= "101"; REG_DST <= "010"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- LDY dp
                        when x"AC" => IS_RMW_OP <= '1'; RMW_OP <= "101"; REG_DST <= "010"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- LDY abs
                        when x"B4" => IS_RMW_OP <= '1'; RMW_OP <= "101"; REG_DST <= "010"; ADDR_MODE <= "0011"; INSTR_LEN <= "010";  -- LDY dp,X
                        when x"BC" => IS_RMW_OP <= '1'; RMW_OP <= "101"; REG_DST <= "010"; ADDR_MODE <= "0110"; INSTR_LEN <= "011";  -- LDY abs,X
                        
                        -- STZ
                        when x"64" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- STZ dp
                        when x"74" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "0011"; INSTR_LEN <= "010";  -- STZ dp,X
                        when x"9C" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- STZ abs
                        when x"9E" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "0110"; INSTR_LEN <= "011";  -- STZ abs,X
                        
                        -- TSB, TRB
                        when x"04" => IS_RMW_OP <= '1'; RMW_OP <= "111"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- TSB dp
                        when x"0C" => IS_RMW_OP <= '1'; RMW_OP <= "111"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- TSB abs
                        when x"14" => IS_RMW_OP <= '1'; RMW_OP <= "110"; ADDR_MODE <= "0010"; INSTR_LEN <= "010";  -- TRB dp
                        when x"1C" => IS_RMW_OP <= '1'; RMW_OP <= "110"; ADDR_MODE <= "0101"; INSTR_LEN <= "011";  -- TRB abs
                        
                        -- (dp) indirect for LDA/STA
                        when x"B2" => IS_ALU_OP <= '1'; ALU_OP <= "101"; ADDR_MODE <= "1000"; INSTR_LEN <= "010";  -- LDA (dp)
                        when x"92" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "1000"; INSTR_LEN <= "010";  -- STA (dp)
                        
                        -- STA long / STA long,X
                        when x"8F" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- STA long
                        when x"9F" => IS_ALU_OP <= '1'; ALU_OP <= "100"; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- STA long,X
                        
                        -- INX, INY, DEX, DEY
                        when x"E8" => IS_RMW_OP <= '1'; RMW_OP <= "111"; REG_DST <= "001"; INSTR_LEN <= "001";  -- INX
                        when x"C8" => IS_RMW_OP <= '1'; RMW_OP <= "111"; REG_DST <= "010"; INSTR_LEN <= "001";  -- INY
                        when x"CA" => IS_RMW_OP <= '1'; RMW_OP <= "110"; REG_DST <= "001"; INSTR_LEN <= "001";  -- DEX
                        when x"88" => IS_RMW_OP <= '1'; RMW_OP <= "110"; REG_DST <= "010"; INSTR_LEN <= "001";  -- DEY
                        
                        when others => 
                            IS_CONTROL <= '1';  -- Unknown opcode
                            INSTR_LEN <= "001";
                            if COMPAT_MODE = '0' then
                                ILLEGAL_OP <= '1';
                            end if;
                    end case;
                    
                when "11" =>
                    -- Group 3: 65816 new addressing modes
                    if IR = x"CB" then
                        IS_WAI <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "001";  -- WAI
                    elsif IR = x"DB" then
                        IS_STP <= '1'; IS_CONTROL <= '1'; INSTR_LEN <= "001";  -- STP
                    elsif IR = x"6B" then
                        IS_RTL <= '1'; IS_JUMP <= '1'; INSTR_LEN <= "001";  -- RTL
                    elsif IR = x"FB" then
                        IS_XCE <= '1'; IS_FLAG_OP <= '1'; INSTR_LEN <= "001";  -- XCE
                    else
                        IS_ALU_OP <= '1';
                        ALU_OP <= aaa;
                        
                        if IR = x"8F" then
                            ALU_OP <= "100"; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- STA long
                        elsif IR = x"9F" then
                            ALU_OP <= "100"; ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- STA long,X
                        else
                            case bbb is
                                when "000" => ADDR_MODE <= "1101"; INSTR_LEN <= "010";  -- sr,S
                                when "001" => ADDR_MODE <= "1011"; INSTR_LEN <= "010";  -- [dp]
                                when "010" => ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- long
                                when "011" => ADDR_MODE <= "1110"; INSTR_LEN <= "010";  -- (sr,S),Y
                                when "100" => ADDR_MODE <= "1100"; INSTR_LEN <= "010";  -- [dp],Y
                                when "111" => ADDR_MODE <= "1111"; INSTR_LEN <= "100";  -- long,X
                                when others => null;
                            end case;
                        end if;
                    end if;
                    
                when others => null;
            end case;
        end if;
    end process;

end rtl;
