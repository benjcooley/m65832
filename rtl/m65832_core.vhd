-- M65832 CPU Core
-- Top-level integration of all CPU components
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_Core is
    port(
        ---------------------------------------------------------------------------
        -- Clock and Reset
        ---------------------------------------------------------------------------
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        CE              : in  std_logic;  -- Clock enable
        
        ---------------------------------------------------------------------------
        -- Memory Interface (32-bit virtual address)
        ---------------------------------------------------------------------------
        ADDR            : out std_logic_vector(31 downto 0);  -- Virtual address
        DATA_OUT        : out std_logic_vector(7 downto 0);   -- Data to write
        DATA_IN         : in  std_logic_vector(7 downto 0);   -- Data read
        WE              : out std_logic;                       -- Write enable (active high)
        RDY             : in  std_logic;                       -- Memory ready
        
        -- Bus status (65816 compatible)
        VPA             : out std_logic;  -- Valid Program Address
        VDA             : out std_logic;  -- Valid Data Address
        VPB             : out std_logic;  -- Vector Pull (active low)
        MLB             : out std_logic;  -- Memory Lock (active low, for RMW)
        
        ---------------------------------------------------------------------------
        -- Interrupts
        ---------------------------------------------------------------------------
        NMI_N           : in  std_logic;  -- Non-maskable interrupt (active low)
        IRQ_N           : in  std_logic;  -- Interrupt request (active low)
        ABORT_N         : in  std_logic;  -- Abort (active low)
        
        ---------------------------------------------------------------------------
        -- Status outputs
        ---------------------------------------------------------------------------
        E_FLAG          : out std_logic;  -- Emulation mode
        M_FLAG          : out std_logic_vector(1 downto 0);  -- Accumulator width
        X_FLAG          : out std_logic_vector(1 downto 0);  -- Index width
        
        ---------------------------------------------------------------------------
        -- Debug interface (active low active)
        ---------------------------------------------------------------------------
        SYNC            : out std_logic   -- Opcode fetch cycle
    );
end M65832_Core;

architecture rtl of M65832_Core is

    ---------------------------------------------------------------------------
    -- State Machine
    ---------------------------------------------------------------------------
    
    type cpu_state_t is (
        ST_RESET,
        ST_FETCH,
        ST_DECODE,
        ST_ADDR1,
        ST_ADDR2,
        ST_ADDR3,
        ST_ADDR4,
        ST_READ,
        ST_READ2,
        ST_READ3,
        ST_READ4,
        ST_EXECUTE,
        ST_WRITE,
        ST_WRITE2,
        ST_WRITE3,
        ST_WRITE4,
        ST_PUSH,
        ST_PULL,
        ST_BRANCH,
        ST_BRANCH2,
        ST_VECTOR1,
        ST_VECTOR2,
        ST_VECTOR3
    );
    
    signal state, next_state : cpu_state_t;
    signal cycle_count : unsigned(3 downto 0);
    
    ---------------------------------------------------------------------------
    -- Instruction Register
    ---------------------------------------------------------------------------
    
    signal IR           : std_logic_vector(7 downto 0);
    signal IR_EXT       : std_logic_vector(7 downto 0);
    signal is_extended  : std_logic;
    
    ---------------------------------------------------------------------------
    -- Register File Signals
    ---------------------------------------------------------------------------
    
    signal A_reg, X_reg, Y_reg : std_logic_vector(31 downto 0);
    signal SP_reg, D_reg       : std_logic_vector(31 downto 0);
    signal B_reg, VBR_reg      : std_logic_vector(31 downto 0);
    signal T_reg               : std_logic_vector(31 downto 0);
    signal P_reg               : std_logic_vector(P_WIDTH-1 downto 0);
    
    signal A_in, X_in, Y_in    : std_logic_vector(31 downto 0);
    signal A_load, X_load, Y_load : std_logic;
    signal SP_in               : std_logic_vector(31 downto 0);
    signal SP_load, SP_inc, SP_dec : std_logic;
    signal D_in, B_in, VBR_in  : std_logic_vector(31 downto 0);
    signal D_load, B_load, VBR_load : std_logic;
    signal T_in                : std_logic_vector(31 downto 0);
    signal T_load              : std_logic;
    signal P_in                : std_logic_vector(P_WIDTH-1 downto 0);
    signal P_load              : std_logic;
    
    signal E_mode, S_mode, R_mode : std_logic;
    signal M_width, X_width       : std_logic_vector(1 downto 0);
    
    ---------------------------------------------------------------------------
    -- ALU Signals
    ---------------------------------------------------------------------------
    
    signal ALU_L, ALU_R     : std_logic_vector(31 downto 0);
    signal ALU_CTRL         : ALUCtrl_r;
    signal ALU_WIDTH        : std_logic_vector(1 downto 0);
    signal ALU_BCD          : std_logic;
    signal ALU_CI, ALU_VI, ALU_SI : std_logic;
    signal ALU_CO, ALU_VO, ALU_SO, ALU_ZO : std_logic;
    signal ALU_RES, ALU_INTR : std_logic_vector(31 downto 0);
    
    ---------------------------------------------------------------------------
    -- Address Generator Signals
    ---------------------------------------------------------------------------
    
    signal PC_reg           : std_logic_vector(31 downto 0);
    signal VA_out           : std_logic_vector(31 downto 0);
    signal AA_out           : std_logic_vector(31 downto 0);
    signal DX_out           : std_logic_vector(31 downto 0);
    signal AA_carry         : std_logic;
    signal jump_no_ofl      : std_logic;
    
    signal LOAD_PC          : std_logic_vector(2 downto 0);
    signal PC_DEC           : std_logic;
    signal ADDR_CTRL        : std_logic_vector(7 downto 0);
    signal IND_CTRL         : std_logic_vector(1 downto 0);
    signal USE_BASE_B       : std_logic;
    signal USE_BASE_VBR     : std_logic;
    signal GOT_INTERRUPT    : std_logic;
    signal W_mode           : std_logic;
    
    ---------------------------------------------------------------------------
    -- Decoder Signals
    ---------------------------------------------------------------------------
    
    signal IS_ALU_OP, IS_RMW_OP   : std_logic;
    signal IS_BRANCH, IS_JUMP    : std_logic;
    signal IS_STACK, IS_TRANSFER : std_logic;
    signal IS_FLAG_OP, IS_CONTROL : std_logic;
    signal IS_BLOCK_MOVE         : std_logic;
    signal ADDR_MODE             : std_logic_vector(3 downto 0);
    signal ALU_OP                : std_logic_vector(2 downto 0);
    signal RMW_OP                : std_logic_vector(2 downto 0);
    signal REG_SRC, REG_DST      : std_logic_vector(2 downto 0);
    signal BRANCH_COND           : std_logic_vector(2 downto 0);
    signal INSTR_LEN             : std_logic_vector(2 downto 0);
    
    signal IS_BRK, IS_COP, IS_RTI, IS_RTS, IS_RTL : std_logic;
    signal IS_JSR, IS_JSL, IS_JMP_d, IS_JML       : std_logic;
    signal IS_PER, IS_WAI, IS_STP, IS_XCE         : std_logic;
    signal IS_REP, IS_SEP, IS_WDM                 : std_logic;
    signal IS_EXT_OP, IS_WID                      : std_logic;
    signal IS_RSET, IS_RCLR, IS_SB, IS_SVBR       : std_logic;
    signal IS_CAS, IS_LLI, IS_SCI                 : std_logic;
    
    ---------------------------------------------------------------------------
    -- Interrupt Handling
    ---------------------------------------------------------------------------
    
    signal nmi_pending      : std_logic;
    signal irq_pending      : std_logic;
    signal abort_pending    : std_logic;
    signal nmi_edge         : std_logic;
    signal old_nmi_n        : std_logic;
    signal interrupt_active : std_logic;
    signal vector_addr      : std_logic_vector(15 downto 0);
    
    ---------------------------------------------------------------------------
    -- Data Buffer
    ---------------------------------------------------------------------------
    
    signal data_buffer      : std_logic_vector(31 downto 0);
    signal data_byte_count  : unsigned(2 downto 0);
    
    ---------------------------------------------------------------------------
    -- Internal control
    ---------------------------------------------------------------------------
    
    signal addr_reg         : std_logic_vector(31 downto 0);
    signal write_data       : std_logic_vector(7 downto 0);
    signal branch_taken     : std_logic;
    
    -- DR (data register) for address generation
    signal DR               : std_logic_vector(7 downto 0);
    
    -- Effective address computed during address phases
    signal eff_addr         : std_logic_vector(31 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Component Instantiation: Register File
    ---------------------------------------------------------------------------
    
    RegFile_inst : entity work.M65832_RegFile
    port map(
        CLK         => CLK,
        RST_N       => RST_N,
        EN          => CE and RDY,
        
        A_IN        => A_in,
        A_LOAD      => A_load,
        A_OUT       => A_reg,
        
        X_IN        => X_in,
        X_LOAD      => X_load,
        X_OUT       => X_reg,
        
        Y_IN        => Y_in,
        Y_LOAD      => Y_load,
        Y_OUT       => Y_reg,
        
        SP_IN       => SP_in,
        SP_LOAD     => SP_load,
        SP_INC      => SP_inc,
        SP_DEC      => SP_dec,
        SP_OUT      => SP_reg,
        
        D_IN        => D_in,
        D_LOAD      => D_load,
        D_OUT       => D_reg,
        
        B_IN        => B_in,
        B_LOAD      => B_load,
        B_OUT       => B_reg,
        
        VBR_IN      => VBR_in,
        VBR_LOAD    => VBR_load,
        VBR_OUT     => VBR_reg,
        
        T_IN        => T_in,
        T_LOAD      => T_load,
        T_OUT       => T_reg,
        
        REG_WIN_EN  => R_mode,
        RW_ADDR1    => (others => '0'),
        RW_DATA1    => open,
        RW_ADDR2    => (others => '0'),
        RW_DATA2    => open,
        RW_WADDR    => (others => '0'),
        RW_WDATA    => (others => '0'),
        RW_WE       => '0',
        RW_WIDTH    => M_width,
        RW_BYTE_SEL => "00",
        
        P_IN        => P_in,
        P_LOAD      => P_load,
        P_OUT       => P_reg,
        
        FLAG_C_IN   => ALU_CO,
        FLAG_C_LOAD => '0',
        FLAG_Z_IN   => ALU_ZO,
        FLAG_Z_LOAD => '0',
        FLAG_I_IN   => '0',
        FLAG_I_LOAD => '0',
        FLAG_D_IN   => '0',
        FLAG_D_LOAD => '0',
        FLAG_V_IN   => ALU_VO,
        FLAG_V_LOAD => '0',
        FLAG_N_IN   => ALU_SO,
        FLAG_N_LOAD => '0',
        
        E_MODE      => E_mode,
        S_MODE      => S_mode,
        R_MODE      => R_mode,
        M_WIDTH     => M_width,
        X_WIDTH     => X_width,
        
        WIDTH_M     => M_width,
        WIDTH_X     => X_width
    );
    
    ---------------------------------------------------------------------------
    -- Component Instantiation: ALU
    ---------------------------------------------------------------------------
    
    ALU_inst : entity work.M65832_ALU
    port map(
        L       => ALU_L,
        R       => ALU_R,
        CTRL    => ALU_CTRL,
        WIDTH   => ALU_WIDTH,
        BCD     => ALU_BCD,
        CI      => ALU_CI,
        VI      => ALU_VI,
        SI      => ALU_SI,
        CO      => ALU_CO,
        VO      => ALU_VO,
        SO      => ALU_SO,
        ZO      => ALU_ZO,
        RES     => ALU_RES,
        IntR    => ALU_INTR
    );
    
    ---------------------------------------------------------------------------
    -- Component Instantiation: Address Generator
    ---------------------------------------------------------------------------
    
    AddrGen_inst : entity work.M65832_AddrGen
    port map(
        CLK             => CLK,
        RST_N           => RST_N,
        EN              => CE and RDY,
        
        LOAD_PC         => LOAD_PC,
        PC_DEC          => PC_DEC,
        GOT_INTERRUPT   => GOT_INTERRUPT,
        ADDR_CTRL       => ADDR_CTRL,
        IND_CTRL        => IND_CTRL,
        USE_BASE_B      => USE_BASE_B,
        USE_BASE_VBR    => USE_BASE_VBR,
        D_IN            => DATA_IN,
        X               => X_reg,
        Y               => Y_reg,
        D               => D_reg,
        S               => SP_reg,
        T               => T_reg,
        B               => B_reg,
        VBR             => VBR_reg,
        DR              => DR,
        E_MODE          => E_mode,
        W_MODE          => W_mode,
        RESET_PC        => x"00008000",  -- Default reset PC for testing
        PC              => PC_reg,
        VA              => VA_out,
        AA              => AA_out,
        DX              => DX_out,
        AA_CARRY        => AA_carry,
        JUMP_NO_OFL     => jump_no_ofl
    );
    
    ---------------------------------------------------------------------------
    -- Component Instantiation: Decoder
    ---------------------------------------------------------------------------
    
    Decoder_inst : entity work.M65832_Decoder
    port map(
        CLK             => CLK,
        RST_N           => RST_N,
        IR              => IR,
        IR_EXT          => IR_EXT,
        IS_EXTENDED     => is_extended,
        E_MODE          => E_mode,
        M_WIDTH         => M_width,
        X_WIDTH         => X_width,
        
        IS_ALU_OP       => IS_ALU_OP,
        IS_RMW_OP       => IS_RMW_OP,
        IS_BRANCH       => IS_BRANCH,
        IS_JUMP         => IS_JUMP,
        IS_STACK        => IS_STACK,
        IS_TRANSFER     => IS_TRANSFER,
        IS_FLAG_OP      => IS_FLAG_OP,
        IS_CONTROL      => IS_CONTROL,
        IS_BLOCK_MOVE   => IS_BLOCK_MOVE,
        
        ADDR_MODE       => ADDR_MODE,
        ALU_OP          => ALU_OP,
        RMW_OP          => RMW_OP,
        REG_SRC         => REG_SRC,
        REG_DST         => REG_DST,
        BRANCH_COND     => BRANCH_COND,
        INSTR_LEN       => INSTR_LEN,
        
        IS_BRK          => IS_BRK,
        IS_COP          => IS_COP,
        IS_RTI          => IS_RTI,
        IS_RTS          => IS_RTS,
        IS_RTL          => IS_RTL,
        IS_JSR          => IS_JSR,
        IS_JSL          => IS_JSL,
        IS_JMP          => IS_JMP_d,
        IS_JML          => IS_JML,
        IS_PER          => IS_PER,
        IS_WAI          => IS_WAI,
        IS_STP          => IS_STP,
        IS_XCE          => IS_XCE,
        IS_REP          => IS_REP,
        IS_SEP          => IS_SEP,
        IS_WDM          => IS_WDM,
        
        IS_EXT_OP       => IS_EXT_OP,
        IS_WID          => IS_WID,
        IS_RSET         => IS_RSET,
        IS_RCLR         => IS_RCLR,
        IS_SB           => IS_SB,
        IS_SVBR         => IS_SVBR,
        IS_CAS          => IS_CAS,
        IS_LLI          => IS_LLI,
        IS_SCI          => IS_SCI
    );
    
    ---------------------------------------------------------------------------
    -- Wide mode detection
    ---------------------------------------------------------------------------
    
    W_mode <= '1' when M_width = WIDTH_32 else '0';
    
    ---------------------------------------------------------------------------
    -- Interrupt Edge Detection
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            old_nmi_n <= '1';
            nmi_pending <= '0';
            irq_pending <= '0';
            abort_pending <= '0';
        elsif rising_edge(CLK) then
            if CE = '1' then
                old_nmi_n <= NMI_N;
                
                -- NMI edge detect
                if NMI_N = '0' and old_nmi_n = '1' then
                    nmi_pending <= '1';
                end if;
                
                -- Clear NMI when serviced
                if state = ST_VECTOR1 and nmi_pending = '1' then
                    nmi_pending <= '0';
                end if;
                
                -- IRQ level sensitive (cleared by CPU)
                irq_pending <= not IRQ_N and not P_reg(P_I);
                
                -- ABORT
                abort_pending <= not ABORT_N;
            end if;
        end if;
    end process;
    
    GOT_INTERRUPT <= nmi_pending or irq_pending or abort_pending;
    interrupt_active <= GOT_INTERRUPT;
    
    ---------------------------------------------------------------------------
    -- Main State Machine
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            state <= ST_RESET;
            cycle_count <= (others => '0');
            IR <= x"00";
            IR_EXT <= x"00";
            is_extended <= '0';
            data_buffer <= (others => '0');
            data_byte_count <= (others => '0');
            DR <= (others => '0');
            eff_addr <= (others => '0');
        elsif rising_edge(CLK) then
            if CE = '1' and RDY = '1' then
                case state is
                    when ST_RESET =>
                        -- Skip vector loading, PC is initialized via RESET_PC
                        -- Go directly to fetch first instruction
                        state <= ST_FETCH;
                        cycle_count <= (others => '0');
                        
                    when ST_FETCH =>
                        -- Fetch opcode
                        IR <= DATA_IN;
                        is_extended <= '0';
                        state <= ST_DECODE;
                        
                    when ST_DECODE =>
                        -- Check for extended opcode prefix
                        if IR = x"02" and E_mode = '0' then
                            -- Extended opcode - fetch next byte
                            is_extended <= '1';
                            IR_EXT <= DATA_IN;
                        end if;
                        
                        -- Determine next state based on instruction
                        if IS_CONTROL = '1' and IS_BRK = '0' and IS_COP = '0' then
                            -- Simple control instruction (NOP, etc.)
                            state <= ST_FETCH;
                        elsif IS_TRANSFER = '1' then
                            state <= ST_EXECUTE;
                        elsif IS_FLAG_OP = '1' then
                            state <= ST_EXECUTE;
                        elsif IS_BRANCH = '1' then
                            state <= ST_BRANCH;
                        elsif ADDR_MODE = "0000" then
                            -- Implied/Accumulator
                            state <= ST_EXECUTE;
                        elsif ADDR_MODE = "0001" then
                            -- Immediate
                            state <= ST_READ;
                            data_byte_count <= (others => '0');
                        else
                            -- Need to compute address
                            state <= ST_ADDR1;
                            data_byte_count <= (others => '0');
                        end if;
                        
                    when ST_ADDR1 =>
                        -- First address byte
                        DR <= DATA_IN;
                        data_buffer(7 downto 0) <= DATA_IN;
                        
                        case ADDR_MODE is
                            when "0010" | "0011" | "0100" =>
                                -- Direct page modes - done after 1 byte
                                -- Effective address = D + offset (for simplicity, just offset for now)
                                eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                if IS_ALU_OP = '1' and ALU_OP = "100" then
                                    -- Store operation
                                    state <= ST_WRITE;
                                elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                    -- STX/STY
                                    state <= ST_WRITE;
                                else
                                    state <= ST_READ;
                                end if;
                            when others =>
                                state <= ST_ADDR2;
                        end case;
                        
                    when ST_ADDR2 =>
                        -- Second address byte
                        data_buffer(15 downto 8) <= DATA_IN;
                        -- Compute absolute address: high byte : low byte
                        eff_addr <= x"0000" & DATA_IN & data_buffer(7 downto 0);
                        
                        case ADDR_MODE is
                            when "0101" | "0110" | "0111" | "1000" | "1001" | "1010" =>
                                -- Absolute modes - done after 2 bytes
                                if IS_ALU_OP = '1' and ALU_OP = "100" then
                                    state <= ST_WRITE;
                                elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                    state <= ST_WRITE;
                                else
                                    state <= ST_READ;
                                end if;
                            when "1111" =>
                                -- Long - need 3rd byte
                                state <= ST_ADDR3;
                            when others =>
                                state <= ST_READ;
                        end case;
                        
                    when ST_ADDR3 =>
                        data_buffer(23 downto 16) <= DATA_IN;
                        eff_addr <= x"00" & DATA_IN & data_buffer(15 downto 0);
                        if IS_ALU_OP = '1' and ALU_OP = "100" then
                            state <= ST_WRITE;
                        else
                            state <= ST_READ;
                        end if;
                        
                    when ST_ADDR4 =>
                        data_buffer(31 downto 24) <= DATA_IN;
                        eff_addr <= DATA_IN & data_buffer(23 downto 0);
                        state <= ST_READ;
                        
                    when ST_READ =>
                        -- Read data byte
                        data_buffer(7 downto 0) <= DATA_IN;
                        data_byte_count <= data_byte_count + 1;
                        
                        -- Check if we need more bytes based on width
                        if M_width = WIDTH_8 or data_byte_count = "011" then
                            state <= ST_EXECUTE;
                        elsif M_width = WIDTH_16 and data_byte_count = "001" then
                            state <= ST_EXECUTE;
                        else
                            state <= ST_READ2;
                        end if;
                        
                    when ST_READ2 =>
                        data_buffer(15 downto 8) <= DATA_IN;
                        data_byte_count <= data_byte_count + 1;
                        if M_width = WIDTH_16 then
                            state <= ST_EXECUTE;
                        else
                            state <= ST_READ3;
                        end if;
                        
                    when ST_READ3 =>
                        data_buffer(23 downto 16) <= DATA_IN;
                        data_byte_count <= data_byte_count + 1;
                        state <= ST_READ4;
                        
                    when ST_READ4 =>
                        data_buffer(31 downto 24) <= DATA_IN;
                        state <= ST_EXECUTE;
                        
                    when ST_EXECUTE =>
                        -- Execute instruction
                        state <= ST_FETCH;
                        
                    when ST_WRITE =>
                        data_byte_count <= data_byte_count + 1;
                        if M_width = WIDTH_8 or data_byte_count = "011" then
                            state <= ST_FETCH;
                        elsif M_width = WIDTH_16 and data_byte_count = "001" then
                            state <= ST_FETCH;
                        else
                            state <= ST_WRITE2;
                        end if;
                        
                    when ST_WRITE2 =>
                        data_byte_count <= data_byte_count + 1;
                        if M_width = WIDTH_16 then
                            state <= ST_FETCH;
                        else
                            state <= ST_WRITE3;
                        end if;
                        
                    when ST_WRITE3 =>
                        data_byte_count <= data_byte_count + 1;
                        state <= ST_WRITE4;
                        
                    when ST_WRITE4 =>
                        state <= ST_FETCH;
                        
                    when ST_PUSH =>
                        state <= ST_FETCH;  -- Simplified
                        
                    when ST_PULL =>
                        state <= ST_FETCH;  -- Simplified
                        
                    when ST_BRANCH =>
                        DR <= DATA_IN;
                        -- Evaluate branch condition
                        state <= ST_BRANCH2;
                        
                    when ST_BRANCH2 =>
                        state <= ST_FETCH;
                        
                    when ST_VECTOR1 =>
                        -- Latch low byte of vector into DR
                        DR <= DATA_IN;
                        data_buffer(7 downto 0) <= DATA_IN;
                        state <= ST_VECTOR2;
                        
                    when ST_VECTOR2 =>
                        -- High byte is on D_IN, low byte is in DR
                        -- LOAD_PC = "010" will load PC from D_IN:DR
                        data_buffer(15 downto 8) <= DATA_IN;
                        state <= ST_VECTOR3;
                        
                    when ST_VECTOR3 =>
                        -- PC should now be loaded, go fetch first instruction
                        state <= ST_FETCH;
                        
                    when others =>
                        state <= ST_FETCH;
                end case;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Address Output Mux
    ---------------------------------------------------------------------------
    
    process(state, PC_reg, VA_out, SP_reg, vector_addr, E_mode, eff_addr, data_byte_count)
    begin
        case state is
            when ST_FETCH | ST_DECODE =>
                ADDR <= PC_reg;
            when ST_ADDR1 | ST_ADDR2 | ST_ADDR3 | ST_ADDR4 =>
                -- Fetching address bytes from PC
                ADDR <= PC_reg;
            when ST_VECTOR1 =>
                ADDR <= x"0000" & VEC_RESET;
            when ST_VECTOR2 =>
                ADDR <= x"0000" & std_logic_vector(unsigned(VEC_RESET) + 1);
            when ST_PUSH =>
                ADDR <= SP_reg;
            when ST_PULL =>
                ADDR <= std_logic_vector(unsigned(SP_reg) + 1);
            when ST_READ | ST_READ2 | ST_READ3 | ST_READ4 =>
                -- Reading from effective address (multi-byte adds offset)
                ADDR <= std_logic_vector(unsigned(eff_addr) + resize(data_byte_count, 32));
            when ST_WRITE | ST_WRITE2 | ST_WRITE3 | ST_WRITE4 =>
                -- Writing to effective address
                ADDR <= std_logic_vector(unsigned(eff_addr) + resize(data_byte_count, 32));
            when others =>
                ADDR <= VA_out;
        end case;
    end process;
    
    ---------------------------------------------------------------------------
    -- Write Enable and Data Output
    ---------------------------------------------------------------------------
    
    WE <= '1' when state = ST_WRITE or state = ST_WRITE2 or 
                   state = ST_WRITE3 or state = ST_WRITE4 or
                   state = ST_PUSH else '0';
    
    -- Write data based on byte count and instruction
    -- STA uses A_reg, STX uses X_reg, STY uses Y_reg
    process(state, data_byte_count, A_reg, X_reg, Y_reg, IS_ALU_OP, IS_RMW_OP, ALU_OP, RMW_OP, REG_SRC)
        variable write_reg : std_logic_vector(31 downto 0);
    begin
        -- Select source register for stores
        if IS_ALU_OP = '1' and ALU_OP = "100" then
            -- STA
            write_reg := A_reg;
        elsif IS_RMW_OP = '1' and RMW_OP = "100" then
            -- STX or STY based on REG_SRC
            if REG_SRC = "001" then
                write_reg := X_reg;
            else
                write_reg := Y_reg;
            end if;
        else
            write_reg := A_reg;
        end if;
        
        case data_byte_count is
            when "000" => DATA_OUT <= write_reg(7 downto 0);
            when "001" => DATA_OUT <= write_reg(15 downto 8);
            when "010" => DATA_OUT <= write_reg(23 downto 16);
            when "011" => DATA_OUT <= write_reg(31 downto 24);
            when others => DATA_OUT <= write_reg(7 downto 0);
        end case;
    end process;
    
    ---------------------------------------------------------------------------
    -- Bus Status Signals
    ---------------------------------------------------------------------------
    
    SYNC <= '1' when state = ST_FETCH else '0';
    VPA  <= '1' when state = ST_FETCH or state = ST_DECODE else '0';
    VDA  <= '1' when state /= ST_FETCH and state /= ST_DECODE else '0';
    VPB  <= '0' when state = ST_VECTOR1 or state = ST_VECTOR2 else '1';
    MLB  <= '0' when IS_RMW_OP = '1' and (state = ST_READ or state = ST_WRITE) else '1';
    
    ---------------------------------------------------------------------------
    -- Status Outputs
    ---------------------------------------------------------------------------
    
    E_FLAG <= E_mode;
    M_FLAG <= M_width;
    X_FLAG <= X_width;
    
    ---------------------------------------------------------------------------
    -- ALU Connections (simplified)
    ---------------------------------------------------------------------------
    
    ALU_L <= A_reg;
    ALU_R <= data_buffer;
    ALU_WIDTH <= M_width;
    ALU_BCD <= P_reg(P_D);
    ALU_CI <= P_reg(P_C);
    ALU_VI <= P_reg(P_V);
    ALU_SI <= P_reg(P_N);
    
    ALU_CTRL.fstOp <= ALU_FST_PASS;
    ALU_CTRL.secOp <= ALU_OP;
    ALU_CTRL.fc <= '0';
    ALU_CTRL.w16 <= '1' when M_width = WIDTH_16 else '0';
    ALU_CTRL.w32 <= '1' when M_width = WIDTH_32 else '0';
    
    ---------------------------------------------------------------------------
    -- Register Load Signals
    ---------------------------------------------------------------------------
    
    -- Accumulator input: data_buffer for loads, ALU result for operations
    -- ALU_OP: 000=ORA, 001=AND, 010=EOR, 011=ADC, 100=STA, 101=LDA, 110=CMP, 111=SBC
    A_in <= data_buffer when (IS_ALU_OP = '1' and ALU_OP = "101") else ALU_RES;
    
    -- A loads on: LDA, or ALU operations that produce results (not STA, not CMP)
    A_load <= '1' when state = ST_EXECUTE and IS_ALU_OP = '1' and 
              ALU_OP /= "100" and ALU_OP /= "110"  -- not STA, not CMP
              else '0';
    
    -- X register: LDX is RMW_OP = "101" with REG_DST = "001"
    -- Also handle transfers TAX (REG_DST = "001")
    X_in <= data_buffer when (IS_RMW_OP = '1' and RMW_OP = "101" and REG_DST = "001")
            else A_reg when (IS_TRANSFER = '1' and REG_DST = "001")
            else (others => '0');
    X_load <= '1' when state = ST_EXECUTE and 
              ((IS_RMW_OP = '1' and RMW_OP = "101" and REG_DST = "001") or
               (IS_TRANSFER = '1' and REG_DST = "001"))
              else '0';
    
    -- Y register: LDY is RMW_OP = "101" with REG_DST = "010"
    Y_in <= data_buffer when (IS_RMW_OP = '1' and RMW_OP = "101" and REG_DST = "010")
            else A_reg when (IS_TRANSFER = '1' and REG_DST = "010")
            else (others => '0');
    Y_load <= '1' when state = ST_EXECUTE and 
              ((IS_RMW_OP = '1' and RMW_OP = "101" and REG_DST = "010") or
               (IS_TRANSFER = '1' and REG_DST = "010"))
              else '0';
    
    -- Stack pointer
    SP_in <= (others => '0');
    SP_load <= '0';
    SP_inc <= '1' when state = ST_PULL else '0';
    SP_dec <= '1' when state = ST_PUSH else '0';
    
    D_in <= (others => '0');
    D_load <= '0';
    B_in <= (others => '0');
    B_load <= '0';
    VBR_in <= (others => '0');
    VBR_load <= '0';
    T_in <= (others => '0');
    T_load <= '0';
    P_in <= (others => '0');
    P_load <= '0';
    
    ---------------------------------------------------------------------------
    -- Address Generator Control
    ---------------------------------------------------------------------------
    -- LOAD_PC: 000=hold, 001=increment, 010=load from D_IN:DR
    
    LOAD_PC <= "010" when state = ST_VECTOR2 -- Load PC from reset vector
               else "001" when (state = ST_FETCH or state = ST_DECODE or
                           state = ST_ADDR1 or state = ST_ADDR2 or 
                           state = ST_ADDR3 or state = ST_ADDR4 or
                           (state = ST_READ and ADDR_MODE = "0001")) -- Immediate mode
               else "000";
    PC_DEC <= '0';
    ADDR_CTRL <= (others => '0');
    IND_CTRL <= (others => '0');
    USE_BASE_B <= '0';
    USE_BASE_VBR <= E_mode;

end rtl;
