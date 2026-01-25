-- M65832 CPU Core
-- Top-level integration of all CPU components
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.float_pkg.all;
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
        ST_VECTOR3,
        ST_VECTOR4,
        ST_INT_NEXT,
        ST_RTI_NEXT,
        ST_WAI,
        ST_STOP,
        ST_BM_READ,
        ST_BM_WRITE
    );
    
    signal state, next_state : cpu_state_t;
    signal cycle_count : unsigned(3 downto 0);
    
    ---------------------------------------------------------------------------
    -- Instruction Register
    ---------------------------------------------------------------------------
    
    signal IR           : std_logic_vector(7 downto 0);
    signal IR_EXT       : std_logic_vector(7 downto 0);
    signal is_extended  : std_logic;
    signal wid_prefix   : std_logic;
    signal wid_active   : std_logic;
    
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
    signal M_width_eff            : std_logic_vector(1 downto 0);
    
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
    signal compat_mode      : std_logic;
    
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
    signal ILLEGAL_OP                              : std_logic;
    
    ---------------------------------------------------------------------------
    -- Interrupt Handling
    ---------------------------------------------------------------------------
    
    signal nmi_pending      : std_logic;
    signal irq_pending      : std_logic;
    signal abort_pending    : std_logic;
    signal nmi_edge         : std_logic;
    signal old_nmi_n        : std_logic;
    signal interrupt_active : std_logic;
    
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
    signal is_indirect_addr : std_logic;
    signal is_long_x        : std_logic;
    signal is_bit_op        : std_logic;
    
    -- Extended op helpers
    signal ext_mul, ext_mulu, ext_div, ext_divu : std_logic;
    signal ext_cas, ext_lli, ext_sci            : std_logic;
    signal ext_sb, ext_svbr, ext_sd             : std_logic;
    signal ext_lea, ext_trap                    : std_logic;
    signal ext_tta, ext_tat                     : std_logic;
    signal ext_fpu                             : std_logic;
    signal ext_ldf, ext_stf                    : std_logic;
    signal f_reg_sel                           : std_logic_vector(1 downto 0);
    signal ext_fpu_trap                        : std_logic;
    
    -- MMU control registers (MMIO)
    signal mmu_mmucr       : std_logic_vector(31 downto 0);
    signal mmu_asid        : std_logic_vector(15 downto 0);
    signal mmu_faultva     : std_logic_vector(31 downto 0);
    signal mmu_ptbr        : std_logic_vector(64 downto 0);
    signal mmu_tlbinval    : std_logic_vector(31 downto 0);
    signal mmu_asid_inval  : std_logic_vector(15 downto 0);
    signal mmu_tlb_flush   : std_logic;
    signal mmu_tlb_flush_asid : std_logic;
    signal mmu_tlb_flush_va : std_logic;

    -- Timer control (MMIO)
    signal timer_ctrl     : std_logic_vector(7 downto 0);
    signal timer_cmp      : std_logic_vector(31 downto 0);
    signal timer_count    : std_logic_vector(31 downto 0);
    signal timer_pending  : std_logic;
    signal timer_irq      : std_logic;
    
    signal mmio_read_hit   : std_logic;
    signal mmio_read_data  : std_logic_vector(7 downto 0);
    signal data_in_read    : std_logic_vector(7 downto 0);
    signal mmio_addr_read  : std_logic_vector(31 downto 0);
    signal mmio_addr_write : std_logic_vector(31 downto 0);
    signal mmio_addr_read_lo  : std_logic_vector(15 downto 0);
    signal mmio_addr_write_lo : std_logic_vector(15 downto 0);
    
    -- MMU integration
    signal mem_ready       : std_logic;
    signal mem_addr_virt   : std_logic_vector(31 downto 0);
    signal mmu_translate   : std_logic;
    signal mmu_access_type : std_logic_vector(1 downto 0);
    signal mmu_va_valid    : std_logic;
    signal mmu_enable      : std_logic;
    signal mmu_wp          : std_logic;
    signal mmu_nx          : std_logic;
    signal mmu_pa          : std_logic_vector(64 downto 0);
    signal mmu_pa_valid    : std_logic;
    signal mmu_pa_ready    : std_logic;
    signal mmu_page_fault  : std_logic;
    signal mmu_fault_type  : std_logic_vector(2 downto 0);
    signal mmu_fault_va    : std_logic_vector(31 downto 0);
    signal mmu_pa_hold     : std_logic;
    signal mmu_fault_hold  : std_logic;
    signal mmu_bypass      : std_logic;
    signal priv_op         : std_logic;
    signal priv_mmio       : std_logic;
    signal priv_stp        : std_logic;
    signal priv_violation  : std_logic;
    signal mmu_ptw_req     : std_logic;
    signal mmu_ptw_ack     : std_logic;
    signal mmu_ptw_addr    : std_logic_vector(64 downto 0);
    signal mmu_ptw_data    : std_logic_vector(63 downto 0);
    signal ptw_active      : std_logic;
    signal ptw_addr_reg    : std_logic_vector(64 downto 0);
    signal ptw_req_addr    : std_logic_vector(64 downto 0);
    signal ptw_data_reg    : std_logic_vector(63 downto 0);
    signal ptw_byte_count  : unsigned(2 downto 0);
    signal ptw_ack_hold    : std_logic;
    signal ptw_addr_armed  : std_logic;
    signal ptw_req_latched : std_logic;
    signal ptw_cooldown    : std_logic;

    constant PRIV_TRAP_CODE : std_logic_vector(7 downto 0) := x"FF";
    
    -- Register window (DP-as-registers)
    signal rw_addr1    : std_logic_vector(5 downto 0);
    signal rw_data1    : std_logic_vector(31 downto 0);
    signal rw_addr2    : std_logic_vector(5 downto 0);
    signal rw_data2    : std_logic_vector(31 downto 0);
    signal rw_waddr    : std_logic_vector(5 downto 0);
    signal rw_wdata    : std_logic_vector(31 downto 0);
    signal rw_we       : std_logic;
    signal rw_width    : std_logic_vector(1 downto 0);
    signal rw_byte_sel : std_logic_vector(1 downto 0);
    signal dp_reg_index: std_logic_vector(5 downto 0);
    signal dp_reg_index_next: std_logic_vector(5 downto 0);
    signal dp_reg_index_next_plus1: std_logic_vector(5 downto 0);
    
    signal ext_ldq, ext_stq               : std_logic;
    signal ldq_high_buffer                : std_logic_vector(31 downto 0);
    signal ldq_low_buffer                 : std_logic_vector(31 downto 0);
    signal ldq_high_phase                 : std_logic;
    signal stq_high_reg                   : std_logic;
    signal ext_repe, ext_sepe                   : std_logic;
    signal ext_fence, ext_fencer, ext_fencew    : std_logic;
    signal ext_stack32_push, ext_stack32_pull   : std_logic;
    
    signal ext_result       : std_logic_vector(31 downto 0);
    signal ext_result_valid : std_logic;
    signal exec_result      : std_logic_vector(31 downto 0);
    signal ext_remainder    : std_logic_vector(31 downto 0);
    signal ext_rem_valid    : std_logic;
    signal ext_flag_z       : std_logic;
    signal ext_flag_n       : std_logic;
    signal ext_flag_v       : std_logic;
    signal ext_flag_load    : std_logic;

    -- FPU coprocessor registers (64-bit)
    signal f0_reg           : std_logic_vector(63 downto 0);
    signal f1_reg           : std_logic_vector(63 downto 0);
    signal f2_reg           : std_logic_vector(63 downto 0);
    signal fpu_result       : std_logic_vector(63 downto 0);
    signal fpu_int_result   : std_logic_vector(31 downto 0);
    signal fpu_write_f0     : std_logic;
    signal fpu_write_a      : std_logic;
    signal fpu_flag_z       : std_logic;
    signal fpu_flag_n       : std_logic;
    signal fpu_flag_v       : std_logic;
    signal fpu_flag_c       : std_logic;
    signal fpu_flag_load    : std_logic;
    signal fpu_flag_c_load  : std_logic;
    signal f_stq_high_reg   : std_logic;
    
    signal stack_is_pull    : std_logic;
    signal stack_width      : std_logic_vector(1 downto 0);
    signal stack_write_reg  : std_logic_vector(31 downto 0);
    signal stack_width_eff  : std_logic_vector(1 downto 0);
    signal stack_write_reg_eff : std_logic_vector(31 downto 0);
    
    signal link_valid       : std_logic;
    signal link_addr        : std_logic_vector(31 downto 0);
    signal cas_match        : std_logic;
    signal sci_success      : std_logic;
    signal read_width       : std_logic_vector(1 downto 0);
    signal write_width      : std_logic_vector(1 downto 0);
    signal alu_width_eff    : std_logic_vector(1 downto 0);
    signal p_next           : std_logic_vector(P_WIDTH-1 downto 0);
    signal p_override       : std_logic_vector(P_WIDTH-1 downto 0);
    signal p_override_valid : std_logic;
    
    -- Interrupt/trap sequencing
    signal int_in_progress  : std_logic;
    signal int_step         : unsigned(1 downto 0);
    signal int_vector_addr  : std_logic_vector(31 downto 0);
    signal int_push_reg     : std_logic_vector(31 downto 0);
    signal int_push_width   : std_logic_vector(1 downto 0);
    signal rti_in_progress  : std_logic;
    signal rti_step         : unsigned(1 downto 0);
    signal rti_pull_width   : std_logic_vector(1 downto 0);
    
    -- Block move (MVN/MVP)
    signal block_active    : std_logic;
    signal block_dir       : std_logic;
    signal block_src_bank  : std_logic_vector(7 downto 0);
    signal block_dst_bank  : std_logic_vector(7 downto 0);
    signal block_src_addr  : std_logic_vector(31 downto 0);
    signal block_dst_addr  : std_logic_vector(31 downto 0);
    signal block_a_next    : std_logic_vector(31 downto 0);
    signal block_x_next    : std_logic_vector(31 downto 0);
    signal block_y_next    : std_logic_vector(31 downto 0);
    
    -- DR (data register) for address generation
    signal DR               : std_logic_vector(7 downto 0);
    
    -- JSR/RTS return address (minimal stackless support)
    signal jsr_return       : std_logic_vector(31 downto 0);
    signal pc_direct        : std_logic_vector(31 downto 0);
    
    -- Effective address computed during address phases
    signal eff_addr         : std_logic_vector(31 downto 0);
    
    -- Flag update control signals
    signal flag_c_in        : std_logic;
    signal flag_c_load      : std_logic;
    signal flag_i_in        : std_logic;
    signal flag_i_load      : std_logic;
    signal flag_nzv_load    : std_logic;
    signal flag_z_in        : std_logic;
    signal flag_n_in        : std_logic;
    signal flag_v_in        : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Component Instantiation: Register File
    ---------------------------------------------------------------------------
    
    RegFile_inst : entity work.M65832_RegFile
    port map(
        CLK         => CLK,
        RST_N       => RST_N,
        EN          => CE and mem_ready,
        
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
        RW_ADDR1    => rw_addr1,
        RW_DATA1    => rw_data1,
        RW_ADDR2    => rw_addr2,
        RW_DATA2    => rw_data2,
        RW_WADDR    => rw_waddr,
        RW_WDATA    => rw_wdata,
        RW_WE       => rw_we,
        RW_WIDTH    => rw_width,
        RW_BYTE_SEL => rw_byte_sel,
        
        P_IN        => P_in,
        P_LOAD      => P_load,
        P_OUT       => P_reg,
        
        FLAG_C_IN   => flag_c_in,
        FLAG_C_LOAD => flag_c_load,
        FLAG_Z_IN   => flag_z_in,
        FLAG_Z_LOAD => flag_nzv_load,
        FLAG_I_IN   => flag_i_in,
        FLAG_I_LOAD => flag_i_load,
        FLAG_D_IN   => '0',
        FLAG_D_LOAD => '0',
        FLAG_V_IN   => flag_v_in,
        FLAG_V_LOAD => flag_nzv_load,
        FLAG_N_IN   => flag_n_in,
        FLAG_N_LOAD => flag_nzv_load,
        
        E_MODE      => E_mode,
        S_MODE      => S_mode,
        R_MODE      => R_mode,
        M_WIDTH     => M_width,
        X_WIDTH     => X_width,
        
        WIDTH_M     => M_width_eff,
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
        EN              => CE and mem_ready,
        
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
        PC_DIRECT       => pc_direct,
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
        COMPAT_MODE     => compat_mode,
        
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
        IS_SCI          => IS_SCI,
        ILLEGAL_OP      => ILLEGAL_OP
    );
    
    ---------------------------------------------------------------------------
    -- Wide mode detection
    ---------------------------------------------------------------------------
    
    W_mode <= '1' when M_width = WIDTH_32 else '0';
    compat_mode <= '1' when M_width = WIDTH_32 else P_reg(P_K);

    ---------------------------------------------------------------------------
    -- MMU Integration
    ---------------------------------------------------------------------------
    
    MMU_inst : entity work.M65832_MMU
    port map(
        CLK             => CLK,
        RST_N           => RST_N,
        
        VA              => mem_addr_virt,
        VA_VALID        => mmu_va_valid,
        ACCESS_TYPE     => mmu_access_type,
        SUPERVISOR      => S_mode,
        
        PA              => mmu_pa,
        PA_VALID        => mmu_pa_valid,
        PA_READY        => mmu_pa_ready,
        
        PAGE_FAULT      => mmu_page_fault,
        FAULT_TYPE      => mmu_fault_type,
        FAULT_VA        => mmu_fault_va,
        
        PTBR            => mmu_ptbr,
        ASID            => mmu_asid(7 downto 0),
        MMU_ENABLE      => mmu_enable,
        WP_ENABLE       => mmu_wp,
        NX_ENABLE       => mmu_nx,
        
        TLB_FLUSH       => mmu_tlb_flush,
        TLB_FLUSH_ASID  => mmu_tlb_flush_asid,
        TLB_FLUSH_VA    => mmu_tlb_flush_va,
        TLB_FLUSH_ADDR  => mmu_tlbinval,
        
        PTW_ADDR        => mmu_ptw_addr,
        PTW_REQ         => mmu_ptw_req,
        PTW_ACK         => mmu_ptw_ack,
        PTW_DATA        => mmu_ptw_data,
        
        TLB_HIT_COUNT   => open,
        TLB_MISS_COUNT  => open
    );
    
    mmu_ptw_data <= ptw_data_reg;
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            ptw_active <= '0';
            ptw_addr_reg <= (others => '0');
            ptw_req_addr <= (others => '0');
            ptw_data_reg <= (others => '0');
            ptw_byte_count <= (others => '0');
            ptw_ack_hold <= '0';
            mmu_ptw_ack <= '0';
            mmu_pa_hold <= '0';
            mmu_fault_hold <= '0';
            ptw_addr_armed <= '0';
            ptw_req_latched <= '0';
            ptw_cooldown <= '0';
        elsif rising_edge(CLK) then
            if mmu_ptw_req = '1' then
                ptw_req_latched <= '1';
                ptw_req_addr <= mmu_ptw_addr;
            end if;
            if ptw_ack_hold = '1' then
                mmu_ptw_ack <= '1';
                ptw_ack_hold <= '0';
                ptw_cooldown <= '1';
            elsif ptw_cooldown = '1' then
                mmu_ptw_ack <= '0';
                ptw_cooldown <= '0';
            else
                mmu_ptw_ack <= '0';
                if ptw_active = '0' and ptw_cooldown = '0' then
                    if ptw_req_latched = '1' then
                        ptw_active <= '1';
                        ptw_addr_reg <= ptw_req_addr;
                        ptw_data_reg <= (others => '0');
                        ptw_byte_count <= (others => '0');
                        ptw_addr_armed <= '0';
                        ptw_req_latched <= '0';
                    end if;
                else
                    if ptw_addr_armed = '0' then
                        ptw_addr_armed <= '1';
                    elsif RDY = '1' then
                        case ptw_byte_count is
                            when "000" => ptw_data_reg(7 downto 0) <= DATA_IN;
                            when "001" => ptw_data_reg(15 downto 8) <= DATA_IN;
                            when "010" => ptw_data_reg(23 downto 16) <= DATA_IN;
                            when "011" => ptw_data_reg(31 downto 24) <= DATA_IN;
                            when "100" => ptw_data_reg(39 downto 32) <= DATA_IN;
                            when "101" => ptw_data_reg(47 downto 40) <= DATA_IN;
                            when "110" => ptw_data_reg(55 downto 48) <= DATA_IN;
                            when others => ptw_data_reg(63 downto 56) <= DATA_IN;
                        end case;
                        if ptw_byte_count = "111" then
                            ptw_active <= '0';
                            ptw_ack_hold <= '1';
                            ptw_addr_armed <= '0';
                        else
                            ptw_byte_count <= ptw_byte_count + 1;
                        end if;
                    end if;
                end if;
            end if;
            
            if mmu_translate = '1' then
                if mmu_pa_valid = '1' then
                    mmu_pa_hold <= '1';
                end if;
                if mmu_page_fault = '1' then
                    mmu_fault_hold <= '1';
                end if;
            end if;
            if CE = '1' and mem_ready = '1' then
                mmu_pa_hold <= '0';
                mmu_fault_hold <= '0';
            end if;
        end if;
    end process;
    
    process(mem_addr_virt, mmu_enable, mmu_pa, mmu_pa_valid, mmu_translate, ptw_active, ptw_addr_reg, ptw_byte_count)
    begin
        if ptw_active = '1' then
            ADDR <= std_logic_vector(unsigned(ptw_addr_reg(31 downto 0)) + resize(ptw_byte_count, 32));
        elsif mmu_enable = '1' and mmu_translate = '1' and mmu_bypass = '0' and
              (mmu_pa_valid = '1' or mmu_pa_hold = '1') then
            ADDR <= mmu_pa(31 downto 0);
        else
            ADDR <= mem_addr_virt;
        end if;
    end process;
    
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
                irq_pending <= (not IRQ_N or timer_irq) and not P_reg(P_I);
                
                -- ABORT
                abort_pending <= not ABORT_N;
            end if;
        end if;
    end process;
    
    GOT_INTERRUPT <= nmi_pending or irq_pending or abort_pending;
    interrupt_active <= GOT_INTERRUPT;
    
    mmu_enable <= mmu_mmucr(0);
    mmu_wp <= mmu_mmucr(1);
    mmu_nx <= '1';
    mmu_bypass <= '1' when mem_addr_virt(15 downto 8) = x"F0" else '0';
    timer_irq <= timer_pending and timer_ctrl(2);
    priv_op <= '1' when S_mode = '0' and
                        (IS_SVBR = '1' or IS_SB = '1' or IS_RSET = '1' or
                         IS_RCLR = '1' or IS_XCE = '1') else '0';
    priv_stp <= '1' when S_mode = '0' and IS_STP = '1' else '0';
    priv_mmio <= '1' when S_mode = '0' and mmu_bypass = '1' and
                         mmu_translate = '1' else '0';
    priv_violation <= '1' when (state = ST_EXECUTE and priv_op = '1') or
                               (state = ST_DECODE and priv_stp = '1') or
                               priv_mmio = '1'
                      else '0';
    
    process(state, ADDR_MODE)
    begin
        mmu_translate <= '0';
        mmu_access_type <= "00";
        case state is
            when ST_READ | ST_READ2 | ST_READ3 | ST_READ4 |
                 ST_PULL | ST_BM_READ =>
                mmu_translate <= '1';
                mmu_access_type <= "00";
            when ST_WRITE | ST_WRITE2 | ST_WRITE3 | ST_WRITE4 |
                 ST_PUSH | ST_BM_WRITE =>
                mmu_translate <= '1';
                mmu_access_type <= "01";
            when others =>
                null;
        end case;
    end process;
    
    mmu_va_valid <= mmu_translate and (not ptw_active) and (not mmu_bypass);
    mem_ready <= '1' when (RDY = '1' and ptw_active = '0' and
                           (mmu_enable = '0' or mmu_translate = '0' or mmu_bypass = '1' or
                            mmu_pa_hold = '1' or mmu_fault_hold = '1'))
                 else '0';
    
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
            wid_prefix <= '0';
            wid_active <= '0';
            data_buffer <= (others => '0');
            data_byte_count <= (others => '0');
            DR <= (others => '0');
            eff_addr <= (others => '0');
            jsr_return <= (others => '0');
            link_valid <= '0';
            link_addr <= (others => '0');
            dp_reg_index <= (others => '0');
            ldq_high_buffer <= (others => '0');
            ldq_low_buffer <= (others => '0');
            ldq_high_phase <= '0';
            stq_high_reg <= '0';
            f_stq_high_reg <= '0';
            int_in_progress <= '0';
            int_step <= (others => '0');
            int_vector_addr <= (others => '0');
            int_push_reg <= (others => '0');
            int_push_width <= WIDTH_8;
            rti_in_progress <= '0';
            rti_step <= (others => '0');
            rti_pull_width <= WIDTH_8;
            block_active <= '0';
            block_dir <= '0';
            block_src_bank <= (others => '0');
            block_dst_bank <= (others => '0');
        elsif rising_edge(CLK) then
            if CE = '1' and mem_ready = '1' then
                if (mmu_page_fault = '1' or mmu_fault_hold = '1') and int_in_progress = '0' and rti_in_progress = '0' then
                    int_in_progress <= '1';
                    int_step <= (others => '0');
                    int_push_reg <= PC_reg;
                    int_push_width <= WIDTH_32;
                    data_byte_count <= (others => '0');
                    int_vector_addr <= VEC_PGFAULT;
                    state <= ST_PUSH;
                elsif ILLEGAL_OP = '1' and ext_fpu_trap = '0' and state = ST_DECODE and
                      int_in_progress = '0' and rti_in_progress = '0' then
                    int_in_progress <= '1';
                    int_step <= (others => '0');
                    int_push_reg <= PC_reg;
                    int_push_width <= WIDTH_32;
                    data_byte_count <= (others => '0');
                    int_vector_addr <= VEC_ILLEGAL;
                    state <= ST_PUSH;
                elsif priv_violation = '1' and int_in_progress = '0' and rti_in_progress = '0' then
                    int_in_progress <= '1';
                    int_step <= (others => '0');
                    int_push_reg <= PC_reg;
                    int_push_width <= WIDTH_32;
                    data_byte_count <= (others => '0');
                    int_vector_addr <= std_logic_vector(unsigned(VEC_SYSCALL) +
                                      (resize(unsigned(PRIV_TRAP_CODE), 32) sll 2));
                    state <= ST_PUSH;
                else
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
                        if int_in_progress = '0' and rti_in_progress = '0' then
                            if nmi_pending = '1' or abort_pending = '1' or irq_pending = '1' then
                                int_in_progress <= '1';
                                int_step <= (others => '0');
                                int_push_reg <= PC_reg;
                                int_push_width <= WIDTH_32;
                                data_byte_count <= (others => '0');
                                if nmi_pending = '1' then
                                    if E_mode = '1' then
                                        int_vector_addr <= x"0000" & VEC_NMI_E;
                                    else
                                        int_vector_addr <= x"0000" & VEC_NMI_N;
                                    end if;
                                elsif abort_pending = '1' then
                                    if E_mode = '1' then
                                        int_vector_addr <= x"0000" & VEC_ABORT_E;
                                    else
                                        int_vector_addr <= x"0000" & VEC_ABORT_N;
                                    end if;
                                else
                                    if E_mode = '1' then
                                        int_vector_addr <= x"0000" & VEC_IRQ_E;
                                    else
                                        int_vector_addr <= x"0000" & VEC_IRQ_N;
                                    end if;
                                end if;
                                state <= ST_PUSH;
                            end if;
                        end if;
                        
                    when ST_DECODE =>
                        -- Check for extended opcode prefix
                        if IR = x"02" and is_extended = '0' then
                            -- Extended opcode - fetch next byte
                            is_extended <= '1';
                            IR_EXT <= DATA_IN;
                            state <= ST_DECODE;
                            data_byte_count <= (others => '0');
                        end if;
                        
                        -- WID prefix ($42) extends next operand to 32-bit
                        if IR = x"02" and is_extended = '0' then
                            null;
                        elsif IS_WID = '1' then
                            wid_prefix <= '1';
                            wid_active <= '0';
                            state <= ST_FETCH;
                        else
                            wid_active <= wid_prefix;
                            wid_prefix <= '0';
                            data_byte_count <= (others => '0');
                            
                            -- Determine next state based on instruction
                            if IS_WAI = '1' then
                                state <= ST_WAI;
                            elsif IS_STP = '1' then
                                if priv_stp = '1' then
                                    int_in_progress <= '1';
                                    int_step <= (others => '0');
                                    int_push_reg <= PC_reg;
                                    int_push_width <= WIDTH_32;
                                    data_byte_count <= (others => '0');
                                    int_vector_addr <= std_logic_vector(unsigned(VEC_SYSCALL) +
                                                      (resize(unsigned(PRIV_TRAP_CODE), 32) sll 2));
                                    state <= ST_PUSH;
                                else
                                    state <= ST_STOP;
                                end if;
                            elsif IS_CONTROL = '1' and IS_BRK = '0' and IS_COP = '0' then
                                -- Simple control instruction (NOP, etc.)
                                state <= ST_FETCH;
                            elsif IS_TRANSFER = '1' then
                                state <= ST_EXECUTE;
                            elsif IS_FLAG_OP = '1' and IS_REP = '0' and IS_SEP = '0' then
                                state <= ST_EXECUTE;
                            elsif IS_BRANCH = '1' then
                                state <= ST_BRANCH;
                            elsif IS_BLOCK_MOVE = '1' then
                                state <= ST_READ;
                                data_byte_count <= (others => '0');
                            elsif IS_STACK = '1' then
                                if IR = x"F4" or IR = x"D4" or IR = x"62" then
                                    -- PEA/PEI/PER need operand read before push
                                    if ADDR_MODE = "0001" then
                                        state <= ST_READ;
                                    else
                                        state <= ST_ADDR1;
                                    end if;
                                elsif stack_is_pull = '1' then
                                    state <= ST_PULL;
                                else
                                    state <= ST_PUSH;
                                end if;
                                data_byte_count <= (others => '0');
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
                        end if;
                        
                    when ST_ADDR1 =>
                        -- First address byte
                        DR <= DATA_IN;
                        data_buffer(7 downto 0) <= DATA_IN;
                        
                        case ADDR_MODE is
                            when "0010" | "0011" | "0100" =>
                                -- Direct page modes - done after 1 byte
                                -- Effective address = D + offset (with index if needed)
                                if ADDR_MODE = "0011" then
                                    -- Register window ignores D_reg; use offset + X low byte
                                    dp_reg_index <= dp_reg_index_next;
                                    eff_addr <= D_reg(31 downto 8) &
                                                std_logic_vector(unsigned(DATA_IN) + unsigned(X_reg(7 downto 0)));
                                elsif ADDR_MODE = "0100" then
                                    -- Register window ignores D_reg; use offset + Y low byte
                                    dp_reg_index <= dp_reg_index_next;
                                    eff_addr <= D_reg(31 downto 8) &
                                                std_logic_vector(unsigned(DATA_IN) + unsigned(Y_reg(7 downto 0)));
                                else
                                    -- Register window ignores D_reg; use offset
                                    dp_reg_index <= dp_reg_index_next;
                                    eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                end if;
                                if R_mode = '1' then
                                    -- DP-as-registers: use reg window instead of memory
                                    if ext_ldq = '1' or ext_ldf = '1' then
                                        data_buffer <= rw_data1;
                                        ldq_low_buffer <= rw_data1;
                                        ldq_high_buffer <= rw_data2;
                                        ldq_high_phase <= '0';
                                        state <= ST_EXECUTE;
                                    elsif ext_stq = '1' then
                                        stq_high_reg <= '1';
                                        state <= ST_EXECUTE;
                                    elsif ext_stf = '1' then
                                        f_stq_high_reg <= '1';
                                        state <= ST_EXECUTE;
                                    elsif IS_ALU_OP = '1' and ALU_OP = "100" then
                                        state <= ST_FETCH;
                                    elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                        state <= ST_FETCH;
                                    else
                                        data_buffer <= rw_data1;
                                        state <= ST_EXECUTE;
                                    end if;
                                elsif ext_lea = '1' then
                                    state <= ST_EXECUTE;
                                elsif IS_ALU_OP = '1' and ALU_OP = "100" then
                                    -- Store operation
                                    state <= ST_WRITE;
                                elsif ext_stq = '1' or ext_stf = '1' then
                                    data_byte_count <= (others => '0');
                                    ldq_high_phase <= '0';
                                    state <= ST_WRITE;
                                elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                    -- STX/STY
                                    state <= ST_WRITE;
                                else
                                    if ext_ldq = '1' or ext_ldf = '1' then
                                        data_byte_count <= (others => '0');
                                        ldq_high_phase <= '0';
                                    end if;
                                    state <= ST_READ;
                                end if;
                            when "1001" =>
                                if IS_JMP_d = '1' then
                                    -- JMP (abs,X): absolute address, handle in next byte
                                    state <= ST_ADDR2;
                                else
                                    -- (dp,X): compute pointer address, then fetch pointer bytes
                                    eff_addr <= D_reg(31 downto 8) &
                                                std_logic_vector(unsigned(DATA_IN) + unsigned(X_reg(7 downto 0)));
                                    state <= ST_ADDR2;
                                end if;
                            when "1000" =>
                                if IS_JMP_d = '1' then
                                    -- JMP (abs): use absolute pointer address
                                    state <= ST_ADDR2;
                                else
                                    -- (dp): pointer address is direct page byte
                                    eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                    state <= ST_ADDR2;
                                end if;
                            when "1010" | "1011" | "1100" =>
                                -- (dp),Y and [dp]/[dp],Y: pointer address is direct page byte
                                eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                state <= ST_ADDR2;
                            when "1101" =>
                                -- sr,S: effective address = SP + offset
                                eff_addr <= std_logic_vector(unsigned(SP_reg) + resize(unsigned(DATA_IN), 32));
                                if IS_ALU_OP = '1' and ALU_OP = "100" then
                                    state <= ST_WRITE;
                                elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                    state <= ST_WRITE;
                                else
                                    state <= ST_READ;
                                end if;
                            when "1110" =>
                                -- (sr,S),Y: pointer address = SP + offset
                                eff_addr <= std_logic_vector(unsigned(SP_reg) + resize(unsigned(DATA_IN), 32));
                                state <= ST_ADDR2;
                            when "1111" =>
                                -- Long/Long,X: need full 24-bit address
                                state <= ST_ADDR2;
                            when others =>
                                state <= ST_ADDR2;
                        end case;
                        
                    when ST_ADDR2 =>
                        -- Second address byte
                        data_buffer(15 downto 8) <= DATA_IN;
                        -- WID absolute addressing uses 32-bit operand
                        if wid_active = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
                            state <= ST_ADDR3;
                        -- Compute absolute address: high byte : low byte (with index if needed)
                        elsif ADDR_MODE = "0110" then
                            -- Absolute,X
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32) +
                                unsigned(B_reg) +
                                unsigned(X_reg));
                        elsif ADDR_MODE = "0111" then
                            -- Absolute,Y
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32) +
                                unsigned(B_reg) +
                                unsigned(Y_reg));
                        elsif ADDR_MODE = "1000" or ADDR_MODE = "1001" or ADDR_MODE = "1010" or ADDR_MODE = "1011" or
                              ADDR_MODE = "1100" or ADDR_MODE = "1110" or ADDR_MODE = "1111" then
                            if IS_JMP_d = '1' and ADDR_MODE = "1001" then
                                -- JMP (abs,X): pointer address = abs + X
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 16) sll 8) or
                                        resize(unsigned(data_buffer(7 downto 0)), 16),
                                        32) +
                                    unsigned(X_reg));
                            elsif IS_JMP_d = '1' and ADDR_MODE = "1000" then
                                -- JMP (abs): pointer address is absolute
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 16) sll 8) or
                                        resize(unsigned(data_buffer(7 downto 0)), 16),
                                        32));
                            elsif IS_JML = '1' and ADDR_MODE = "1011" then
                                -- JML [abs]: pointer address is absolute operand
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 16) sll 8) or
                                        resize(unsigned(data_buffer(7 downto 0)), 16),
                                        32));
                            elsif ADDR_MODE = "1111" then
                                -- Long/Long,X: latch high byte, bank next
                                null;
                            else
                                -- Indirect modes: latch pointer low byte, fetch high next
                                data_buffer(7 downto 0) <= DATA_IN;
                            end if;
                        else
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32) +
                                unsigned(B_reg));
                        end if;
                        
                        if wid_active = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
                            null;
                        elsif ADDR_MODE = "1000" and IS_JMP_d = '1' then
                            -- JMP (abs): pointer read follows
                            state <= ST_READ;
                        else
                            case ADDR_MODE is
                                when "0101" | "0110" | "0111" =>
                                    -- Absolute modes - done after 2 bytes
                                    if IS_JSR = '1' then
                                        -- JSR: capture return address (PC of high byte)
                                        jsr_return <= PC_reg;
                                    end if;
                                    if ext_lea = '1' then
                                        state <= ST_EXECUTE;
                                    elsif IS_ALU_OP = '1' and ALU_OP = "100" then
                                        state <= ST_WRITE;
                                    elsif ext_stq = '1' or ext_stf = '1' then
                                        data_byte_count <= (others => '0');
                                        state <= ST_WRITE;
                                    elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                        state <= ST_WRITE;
                                    else
                                        if ext_ldq = '1' or ext_ldf = '1' then
                                            data_byte_count <= (others => '0');
                                            ldq_high_phase <= '0';
                                        end if;
                                        state <= ST_READ;
                                    end if;
                                when "1000" | "1001" | "1010" | "1011" | "1100" | "1110" | "1111" =>
                                    -- Indirect/long modes - fetch next byte(s)
                                    state <= ST_ADDR3;
                                when others =>
                                    state <= ST_READ;
                            end case;
                        end if;
                        
                    when ST_ADDR3 =>
                        if IS_JMP_d = '1' and ADDR_MODE = "1001" then
                            -- JMP (abs,X): pointer low byte
                            DR <= DATA_IN;
                            state <= ST_ADDR4;
                        elsif wid_active = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
                            data_buffer(23 downto 16) <= DATA_IN;
                            state <= ST_ADDR4;
                        elsif ADDR_MODE = "1000" then
                            -- (dp): pointer high in DATA_IN, low in data_buffer(7:0)
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32));
                        elsif ADDR_MODE = "1001" then
                            -- (dp,X): pointer high in DATA_IN, low in data_buffer(7:0)
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32));
                        elsif ADDR_MODE = "1010" then
                            -- (dp),Y: pointer + Y
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32) +
                                unsigned(Y_reg));
                        elsif ADDR_MODE = "1011" then
                            -- [dp]: pointer high in DATA_IN, bank next
                            data_buffer(15 downto 8) <= DATA_IN;
                            state <= ST_ADDR4;
                        elsif ADDR_MODE = "1100" then
                            -- [dp],Y: pointer high in DATA_IN, bank next
                            data_buffer(15 downto 8) <= DATA_IN;
                            state <= ST_ADDR4;
                        elsif ADDR_MODE = "1110" then
                            -- (sr,S),Y: pointer + Y
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 16) sll 8) or
                                    resize(unsigned(data_buffer(7 downto 0)), 16),
                                    32) +
                                unsigned(Y_reg));
                        elsif ADDR_MODE = "1111" then
                            -- Long/Long,X: bank byte in DATA_IN
                            if is_long_x = '1' then
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 24) sll 16) or
                                        resize(unsigned(data_buffer(15 downto 0)), 24),
                                        32) +
                                    unsigned(X_reg));
                            else
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 24) sll 16) or
                                        resize(unsigned(data_buffer(15 downto 0)), 24),
                                        32));
                            end if;
                            if IS_JSL = '1' then
                                jsr_return <= PC_reg;
                            end if;
                        else
                            data_buffer(23 downto 16) <= DATA_IN;
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 24) sll 16) or
                                    resize(unsigned(data_buffer(15 downto 0)), 24),
                                    32));
                        end if;
                        if wid_active = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
                            null;
                        elsif IS_JMP_d = '1' and ADDR_MODE = "1001" then
                            null;
                        elsif IS_JML = '1' and ADDR_MODE = "1011" then
                            -- JML [abs]: read long pointer from eff_addr
                            data_byte_count <= (others => '0');
                            state <= ST_READ;
                        elsif ADDR_MODE = "1011" or ADDR_MODE = "1100" then
                            null;
                        elsif ADDR_MODE = "1111" and (IS_JML = '1' or IS_JSL = '1') then
                            state <= ST_EXECUTE;
                        elsif IS_ALU_OP = '1' and ALU_OP = "100" then
                            state <= ST_WRITE;
                        else
                            state <= ST_READ;
                        end if;
                        
                    when ST_ADDR4 =>
                        if wid_active = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
                            if ADDR_MODE = "0110" then
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 32) sll 24) or
                                        resize(unsigned(data_buffer(23 downto 0)), 32),
                                        32) +
                                    unsigned(X_reg));
                            elsif ADDR_MODE = "0111" then
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 32) sll 24) or
                                        resize(unsigned(data_buffer(23 downto 0)), 32),
                                        32) +
                                    unsigned(Y_reg));
                            else
                                eff_addr <= std_logic_vector(
                                    resize(
                                        (resize(unsigned(DATA_IN), 32) sll 24) or
                                        resize(unsigned(data_buffer(23 downto 0)), 32),
                                        32));
                            end if;
                            if ext_lea = '1' then
                                state <= ST_EXECUTE;
                            elsif IS_ALU_OP = '1' and ALU_OP = "100" then
                                state <= ST_WRITE;
                            elsif ext_stq = '1' or ext_stf = '1' then
                                state <= ST_WRITE;
                            elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                state <= ST_WRITE;
                            else
                                state <= ST_READ;
                            end if;
                        elsif IS_JMP_d = '1' and ADDR_MODE = "1001" then
                            -- JMP (abs,X): pointer high byte, then jump
                            data_buffer(15 downto 8) <= DATA_IN;
                            state <= ST_FETCH;
                        elsif ADDR_MODE = "1011" then
                            -- [dp]: bank byte in DATA_IN
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 24) sll 16) or
                                    resize(unsigned(data_buffer(15 downto 0)), 24),
                                    32));
                            if IS_ALU_OP = '1' and ALU_OP = "100" then
                                state <= ST_WRITE;
                            elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                state <= ST_WRITE;
                            else
                                state <= ST_READ;
                            end if;
                        elsif ADDR_MODE = "1100" then
                            -- [dp],Y: bank byte in DATA_IN, then add Y
                            eff_addr <= std_logic_vector(
                                resize(
                                    (resize(unsigned(DATA_IN), 24) sll 16) or
                                    resize(unsigned(data_buffer(15 downto 0)), 24),
                                    32) +
                                unsigned(Y_reg));
                            if IS_ALU_OP = '1' and ALU_OP = "100" then
                                state <= ST_WRITE;
                            elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                state <= ST_WRITE;
                            else
                                state <= ST_READ;
                            end if;
                        else
                            data_buffer(31 downto 24) <= DATA_IN;
                            eff_addr <= DATA_IN & data_buffer(23 downto 0);
                            state <= ST_READ;
                        end if;
                        
                    when ST_READ =>
                        -- Read data byte
                        if ext_ldq = '1' or ext_ldf = '1' then
                            if ldq_high_phase = '1' then
                                case data_byte_count(1 downto 0) is
                                    when "00" => data_buffer(7 downto 0) <= data_in_read;
                                    when "01" => data_buffer(15 downto 8) <= data_in_read;
                                    when "10" => data_buffer(23 downto 16) <= data_in_read;
                                    when others => data_buffer(31 downto 24) <= data_in_read;
                                end case;
                            else
                                case data_byte_count(1 downto 0) is
                                    when "00" => ldq_low_buffer(7 downto 0) <= data_in_read;
                                    when "01" => ldq_low_buffer(15 downto 8) <= data_in_read;
                                    when "10" => ldq_low_buffer(23 downto 16) <= data_in_read;
                                    when others => ldq_low_buffer(31 downto 24) <= data_in_read;
                                end case;
                            end if;
                        else
                            data_buffer(7 downto 0) <= data_in_read;
                        end if;
                        if IS_JMP_d = '1' and (ADDR_MODE = "1000" or ADDR_MODE = "1001") then
                            DR <= data_in_read;  -- latch indirect low byte
                        end if;
                        data_byte_count <= data_byte_count + 1;
                        
                        -- Check if we need more bytes based on width
                        if ext_ldq = '1' or ext_ldf = '1' then
                            state <= ST_READ2;
                        elsif read_width = WIDTH_8 or data_byte_count = "011" then
                            state <= ST_EXECUTE;
                        elsif read_width = WIDTH_16 and data_byte_count = "001" then
                            state <= ST_EXECUTE;
                        else
                            state <= ST_READ2;
                        end if;
                        
                    when ST_READ2 =>
                        if ext_ldq = '1' or ext_ldf = '1' then
                            if ldq_high_phase = '1' then
                                case data_byte_count(1 downto 0) is
                                    when "00" => data_buffer(7 downto 0) <= data_in_read;
                                    when "01" => data_buffer(15 downto 8) <= data_in_read;
                                    when "10" => data_buffer(23 downto 16) <= data_in_read;
                                    when others => data_buffer(31 downto 24) <= data_in_read;
                                end case;
                            else
                                case data_byte_count(1 downto 0) is
                                    when "00" => ldq_low_buffer(7 downto 0) <= data_in_read;
                                    when "01" => ldq_low_buffer(15 downto 8) <= data_in_read;
                                    when "10" => ldq_low_buffer(23 downto 16) <= data_in_read;
                                    when others => ldq_low_buffer(31 downto 24) <= data_in_read;
                                end case;
                            end if;
                        else
                            data_buffer(15 downto 8) <= data_in_read;
                        end if;
                        data_byte_count <= data_byte_count + 1;
                        if IS_JMP_d = '1' and (ADDR_MODE = "1000" or ADDR_MODE = "1001") then
                            state <= ST_FETCH;
                        elsif ext_ldq = '1' or ext_ldf = '1' then
                            state <= ST_READ3;
                        elsif read_width = WIDTH_16 then
                            state <= ST_EXECUTE;
                        else
                            state <= ST_READ3;
                        end if;
                        
                    when ST_READ3 =>
                        if ext_ldq = '1' or ext_ldf = '1' then
                            if ldq_high_phase = '1' then
                                case data_byte_count(1 downto 0) is
                                    when "00" => data_buffer(7 downto 0) <= data_in_read;
                                    when "01" => data_buffer(15 downto 8) <= data_in_read;
                                    when "10" => data_buffer(23 downto 16) <= data_in_read;
                                    when others => data_buffer(31 downto 24) <= data_in_read;
                                end case;
                            else
                                case data_byte_count(1 downto 0) is
                                    when "00" => ldq_low_buffer(7 downto 0) <= data_in_read;
                                    when "01" => ldq_low_buffer(15 downto 8) <= data_in_read;
                                    when "10" => ldq_low_buffer(23 downto 16) <= data_in_read;
                                    when others => ldq_low_buffer(31 downto 24) <= data_in_read;
                                end case;
                            end if;
                        else
                            data_buffer(23 downto 16) <= data_in_read;
                        end if;
                        data_byte_count <= data_byte_count + 1;
                        state <= ST_READ4;
                        
                    when ST_READ4 =>
                        if ext_ldq = '1' or ext_ldf = '1' then
                            if ldq_high_phase = '1' then
                                case data_byte_count(1 downto 0) is
                                    when "00" => data_buffer(7 downto 0) <= data_in_read;
                                    when "01" => data_buffer(15 downto 8) <= data_in_read;
                                    when "10" => data_buffer(23 downto 16) <= data_in_read;
                                    when others => data_buffer(31 downto 24) <= data_in_read;
                                end case;
                            else
                                case data_byte_count(1 downto 0) is
                                    when "00" => ldq_low_buffer(7 downto 0) <= data_in_read;
                                    when "01" => ldq_low_buffer(15 downto 8) <= data_in_read;
                                    when "10" => ldq_low_buffer(23 downto 16) <= data_in_read;
                                    when others => ldq_low_buffer(31 downto 24) <= data_in_read;
                                end case;
                            end if;
                        else
                            data_buffer(31 downto 24) <= data_in_read;
                        end if;
                        if ext_ldq = '1' or ext_ldf = '1' then
                            if data_byte_count = "011" and ldq_high_phase = '0' then
                                ldq_high_phase <= '1';
                                data_byte_count <= (others => '0');
                                eff_addr <= std_logic_vector(unsigned(eff_addr) + 4);
                                state <= ST_READ;
                            elsif data_byte_count = "011" and ldq_high_phase = '1' then
                                ldq_high_buffer(23 downto 0) <= data_buffer(23 downto 0);
                                ldq_high_buffer(31 downto 24) <= DATA_IN;
                                ldq_high_phase <= '0';
                                state <= ST_EXECUTE;
                            else
                                data_byte_count <= data_byte_count + 1;
                                state <= ST_READ;
                            end if;
                        else
                            state <= ST_EXECUTE;
                        end if;
                        
                    when ST_EXECUTE =>
                        -- Execute instruction
                        if f_stq_high_reg = '1' then
                            f_stq_high_reg <= '0';
                            state <= ST_FETCH;
                        elsif stq_high_reg = '1' then
                            stq_high_reg <= '0';
                            state <= ST_FETCH;
                        elsif ext_lli = '1' then
                            link_valid <= '1';
                            link_addr <= eff_addr;
                        end if;
                        if IS_BRK = '1' then
                            int_in_progress <= '1';
                            int_step <= (others => '0');
                            int_push_reg <= PC_reg;
                            int_push_width <= WIDTH_32;
                            data_byte_count <= (others => '0');
                            if E_mode = '1' then
                                int_vector_addr <= x"0000" & VEC_IRQ_E;
                            else
                                int_vector_addr <= x"0000" & VEC_BRK_N;
                            end if;
                            state <= ST_PUSH;
                        elsif ext_fpu_trap = '1' then
                            int_in_progress <= '1';
                            int_step <= (others => '0');
                            int_push_reg <= PC_reg;
                            int_push_width <= WIDTH_32;
                            data_byte_count <= (others => '0');
                            int_vector_addr <= std_logic_vector(unsigned(VEC_SYSCALL) + (resize(unsigned(IR_EXT), 32) sll 2));
                            state <= ST_PUSH;
                        elsif ext_trap = '1' then
                            int_in_progress <= '1';
                            int_step <= (others => '0');
                            int_push_reg <= PC_reg;
                            int_push_width <= WIDTH_32;
                            data_byte_count <= (others => '0');
                            int_vector_addr <= std_logic_vector(unsigned(VEC_SYSCALL) + (resize(unsigned(data_buffer(7 downto 0)), 32) sll 2));
                            state <= ST_PUSH;
                        elsif IS_RTI = '1' then
                            rti_in_progress <= '1';
                            rti_step <= (others => '0');
                            rti_pull_width <= WIDTH_16;
                            data_byte_count <= (others => '0');
                            state <= ST_PULL;
                        elsif IS_BLOCK_MOVE = '1' then
                            block_active <= '1';
                            if IR = x"54" then
                                block_dir <= '1';
                            else
                                block_dir <= '0';
                            end if;
                            block_dst_bank <= data_buffer(7 downto 0);
                            block_src_bank <= data_buffer(15 downto 8);
                            state <= ST_BM_READ;
                        else
                        if IS_STACK = '1' and (IR = x"F4" or IR = x"D4" or IR = x"62") then
                            -- PEA/PEI/PER push after operand fetch
                            state <= ST_PUSH;
                            data_byte_count <= (others => '0');
                        elsif ext_cas = '1' and cas_match = '1' then
                            -- CAS match: write A back
                            state <= ST_WRITE;
                            data_byte_count <= (others => '0');
                        elsif ext_sci = '1' and sci_success = '1' then
                            -- SCI success: write A
                            state <= ST_WRITE;
                            data_byte_count <= (others => '0');
                        elsif R_mode = '1' and IS_RMW_OP = '1' and
                              (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100") and
                              RMW_OP /= "100" and RMW_OP /= "101" then
                            -- Register-window RMW writes back via reg file
                            state <= ST_FETCH;
                        elsif IS_RMW_OP = '1' and ADDR_MODE /= "0000" and
                           RMW_OP /= "100" and RMW_OP /= "101" then
                            -- Memory RMW (INC/DEC/shift/rotate): write back result
                            state <= ST_WRITE;
                            data_byte_count <= (others => '0');
                        else
                            state <= ST_FETCH;
                        end if;
                        end if;
                        
                    when ST_WRITE =>
                        link_valid <= '0';
                        data_byte_count <= data_byte_count + 1;
                        if ext_stq = '1' or ext_stf = '1' then
                            state <= ST_WRITE2;
                        elsif write_width = WIDTH_8 or data_byte_count = "011" then
                            state <= ST_FETCH;
                        elsif write_width = WIDTH_16 and data_byte_count = "001" then
                            state <= ST_FETCH;
                        else
                            state <= ST_WRITE2;
                        end if;
                        
                    when ST_WRITE2 =>
                        data_byte_count <= data_byte_count + 1;
                        if ext_stq = '1' or ext_stf = '1' then
                            state <= ST_WRITE3;
                        elsif write_width = WIDTH_16 then
                            state <= ST_FETCH;
                        else
                            state <= ST_WRITE3;
                        end if;
                        
                    when ST_WRITE3 =>
                        data_byte_count <= data_byte_count + 1;
                        state <= ST_WRITE4;
                        
                    when ST_WRITE4 =>
                        if ext_stq = '1' or ext_stf = '1' then
                            if data_byte_count = "111" then
                                state <= ST_FETCH;
                            else
                                data_byte_count <= data_byte_count + 1;
                                state <= ST_WRITE;
                            end if;
                        else
                            state <= ST_FETCH;
                        end if;
                        
                    when ST_PUSH =>
                        data_byte_count <= data_byte_count + 1;
                        if stack_width_eff = WIDTH_8 or data_byte_count = "011" then
                            if int_in_progress = '1' then
                                state <= ST_INT_NEXT;
                            else
                                state <= ST_FETCH;
                            end if;
                        elsif stack_width_eff = WIDTH_16 and data_byte_count = "001" then
                            if int_in_progress = '1' then
                                state <= ST_INT_NEXT;
                            else
                                state <= ST_FETCH;
                            end if;
                        else
                            state <= ST_PUSH;
                        end if;
                        
                    when ST_PULL =>
                        case data_byte_count is
                            when "000" => data_buffer(7 downto 0) <= DATA_IN;
                            when "001" => data_buffer(15 downto 8) <= DATA_IN;
                            when "010" => data_buffer(23 downto 16) <= DATA_IN;
                            when "011" => data_buffer(31 downto 24) <= DATA_IN;
                            when others => null;
                        end case;
                        data_byte_count <= data_byte_count + 1;
                        if rti_in_progress = '1' and rti_step = to_unsigned(0, rti_step'length) then
                            if data_byte_count = "001" then
                                state <= ST_RTI_NEXT;
                            else
                                state <= ST_PULL;
                            end if;
                        elsif stack_width_eff = WIDTH_8 or data_byte_count = "011" then
                            if rti_in_progress = '1' then
                                state <= ST_RTI_NEXT;
                            else
                                state <= ST_EXECUTE;
                            end if;
                        elsif stack_width_eff = WIDTH_16 and data_byte_count = "001" then
                            if rti_in_progress = '1' then
                                state <= ST_RTI_NEXT;
                            else
                                state <= ST_EXECUTE;
                            end if;
                        else
                            state <= ST_PULL;
                        end if;
                        
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
                        data_buffer(15 downto 8) <= DATA_IN;
                        state <= ST_VECTOR3;
                        
                    when ST_VECTOR3 =>
                        data_buffer(23 downto 16) <= DATA_IN;
                        state <= ST_VECTOR4;
                        
                    when ST_VECTOR4 =>
                        data_buffer(31 downto 24) <= DATA_IN;
                        state <= ST_FETCH;
                        
                    when ST_INT_NEXT =>
                        if int_step = to_unsigned(0, int_step'length) then
                            int_step <= to_unsigned(1, int_step'length);
                            int_push_reg <= x"0000" & std_logic_vector(resize(unsigned(P_reg), 16));
                            int_push_width <= WIDTH_16;
                            data_byte_count <= (others => '0');
                            state <= ST_PUSH;
                        else
                            int_in_progress <= '0';
                            int_step <= (others => '0');
                            state <= ST_VECTOR1;
                        end if;
                        
                    when ST_RTI_NEXT =>
                        if rti_step = to_unsigned(0, rti_step'length) then
                            rti_step <= to_unsigned(1, rti_step'length);
                            rti_pull_width <= WIDTH_32;
                            data_byte_count <= (others => '0');
                            state <= ST_PULL;
                        else
                            rti_in_progress <= '0';
                            rti_step <= (others => '0');
                            state <= ST_FETCH;
                        end if;
                        
                    when ST_WAI =>
                        if nmi_pending = '1' or abort_pending = '1' or irq_pending = '1' then
                            state <= ST_FETCH;
                        else
                            state <= ST_WAI;
                        end if;
                        
                    when ST_STOP =>
                        state <= ST_STOP;
                        
                    when ST_BM_READ =>
                        data_buffer(7 downto 0) <= DATA_IN;
                        state <= ST_BM_WRITE;
                        
                    when ST_BM_WRITE =>
                        if A_reg = x"00000000" then
                            block_active <= '0';
                            state <= ST_FETCH;
                        else
                            state <= ST_BM_READ;
                        end if;
                        
                    when others =>
                        state <= ST_FETCH;
                end case;
                end if;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Address Output Mux
    ---------------------------------------------------------------------------
    
    process(state, PC_reg, VA_out, SP_reg, int_vector_addr, E_mode, eff_addr, data_byte_count, ADDR_MODE,
            block_src_addr, block_dst_addr)
    begin
        case state is
            when ST_FETCH | ST_DECODE | ST_BRANCH =>
                mem_addr_virt <= PC_reg;
            when ST_ADDR1 | ST_ADDR2 | ST_ADDR3 | ST_ADDR4 =>
                -- Fetching address bytes from PC or pointer reads for indirect modes
                if (ADDR_MODE = "1000" or ADDR_MODE = "1001" or ADDR_MODE = "1010" or
                    ADDR_MODE = "1011" or ADDR_MODE = "1100" or ADDR_MODE = "1110") then
                    if IS_JMP_d = '1' and ADDR_MODE = "1001" then
                        if state = ST_ADDR3 then
                            mem_addr_virt <= eff_addr;
                        elsif state = ST_ADDR4 then
                            mem_addr_virt <= std_logic_vector(unsigned(eff_addr) + 1);
                        else
                            mem_addr_virt <= PC_reg;
                        end if;
                    elsif IS_JMP_d = '1' and ADDR_MODE = "1000" then
                        -- JMP (abs): pointer reads happen in ST_READ, keep PC here
                        mem_addr_virt <= PC_reg;
                    elsif IS_JML = '1' and ADDR_MODE = "1011" then
                        if state = ST_ADDR2 then
                            mem_addr_virt <= PC_reg;
                        elsif state = ST_ADDR3 then
                            mem_addr_virt <= eff_addr;
                        elsif state = ST_ADDR4 then
                            mem_addr_virt <= std_logic_vector(unsigned(eff_addr) + 1);
                        else
                            mem_addr_virt <= PC_reg;
                        end if;
                    else
                        if state = ST_ADDR2 then
                            mem_addr_virt <= eff_addr;
                        elsif state = ST_ADDR3 then
                            mem_addr_virt <= std_logic_vector(unsigned(eff_addr) + 1);
                        elsif state = ST_ADDR4 and (ADDR_MODE = "1011" or ADDR_MODE = "1100") then
                            mem_addr_virt <= std_logic_vector(unsigned(eff_addr) + 2);
                        else
                            mem_addr_virt <= PC_reg;
                        end if;
                    end if;
                else
                    mem_addr_virt <= PC_reg;
                end if;
            when ST_VECTOR1 =>
                mem_addr_virt <= int_vector_addr;
            when ST_VECTOR2 =>
                mem_addr_virt <= std_logic_vector(unsigned(int_vector_addr) + 1);
            when ST_VECTOR3 =>
                mem_addr_virt <= std_logic_vector(unsigned(int_vector_addr) + 2);
            when ST_VECTOR4 =>
                mem_addr_virt <= std_logic_vector(unsigned(int_vector_addr) + 3);
            when ST_PUSH =>
                mem_addr_virt <= SP_reg;
            when ST_PULL =>
                mem_addr_virt <= std_logic_vector(unsigned(SP_reg) + 1);
            when ST_READ | ST_READ2 | ST_READ3 | ST_READ4 =>
                -- Reading from effective address (multi-byte adds offset)
                if ADDR_MODE = "0001" then
                    -- Immediate reads come from PC
                    mem_addr_virt <= PC_reg;
                else
                    mem_addr_virt <= std_logic_vector(unsigned(eff_addr) + resize(data_byte_count, 32));
                end if;
            when ST_BM_READ =>
                mem_addr_virt <= block_src_addr;
            when ST_BM_WRITE =>
                mem_addr_virt <= block_dst_addr;
            when ST_WRITE | ST_WRITE2 | ST_WRITE3 | ST_WRITE4 =>
                -- Writing to effective address
                mem_addr_virt <= std_logic_vector(unsigned(eff_addr) + resize(data_byte_count, 32));
            when others =>
                mem_addr_virt <= VA_out;
        end case;
    end process;
    
    ---------------------------------------------------------------------------
    -- MMIO Read Decode (MMU control registers)
    ---------------------------------------------------------------------------
    
    mmio_addr_read <= std_logic_vector(unsigned(eff_addr) + resize(data_byte_count, 32));
    mmio_addr_read_lo <= mmio_addr_read(15 downto 0);
    
    process(state, ADDR_MODE, mmio_addr_read, mmu_mmucr, mmu_asid, mmu_faultva, mmu_ptbr, mmu_tlbinval, mmu_asid_inval)
    begin
        mmio_read_hit <= '0';
        mmio_read_data <= (others => '0');
        
        if (state = ST_READ or state = ST_READ2 or state = ST_READ3 or state = ST_READ4) and
           ADDR_MODE /= "0001" then
            if unsigned(mmio_addr_read_lo) >= unsigned(MMIO_FAULTVA(15 downto 0)) and
               unsigned(mmio_addr_read_lo) <= unsigned(MMIO_FAULTVA(15 downto 0)) + 3 then
                mmio_read_hit <= '1';
                case to_integer(unsigned(mmio_addr_read_lo) - unsigned(MMIO_FAULTVA(15 downto 0))) is
                    when 0 =>
                        mmio_read_data <= mmu_faultva(7 downto 0);
                    when 1 =>
                        mmio_read_data <= mmu_faultva(15 downto 8);
                    when 2 =>
                        mmio_read_data <= mmu_faultva(23 downto 16);
                    when others =>
                        mmio_read_data <= mmu_faultva(31 downto 24);
                end case;
            else
                case mmio_addr_read_lo is
                when MMIO_MMUCR(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_mmucr(7 downto 0);
                when std_logic_vector(unsigned(MMIO_MMUCR(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_mmucr(15 downto 8);
                when std_logic_vector(unsigned(MMIO_MMUCR(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_mmucr(23 downto 16);
                when std_logic_vector(unsigned(MMIO_MMUCR(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_mmucr(31 downto 24);
                
                when MMIO_ASID(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_asid(7 downto 0);
                when std_logic_vector(unsigned(MMIO_ASID(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_asid(15 downto 8);
                
                when MMIO_ASIDINVAL(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_asid_inval(7 downto 0);
                when std_logic_vector(unsigned(MMIO_ASIDINVAL(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_asid_inval(15 downto 8);
                
                when MMIO_PTBR_LO(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(7 downto 0);
                when std_logic_vector(unsigned(MMIO_PTBR_LO(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(15 downto 8);
                when std_logic_vector(unsigned(MMIO_PTBR_LO(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(23 downto 16);
                when std_logic_vector(unsigned(MMIO_PTBR_LO(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(31 downto 24);
                
                when MMIO_PTBR_HI(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(39 downto 32);
                when std_logic_vector(unsigned(MMIO_PTBR_HI(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(47 downto 40);
                when std_logic_vector(unsigned(MMIO_PTBR_HI(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(55 downto 48);
                when std_logic_vector(unsigned(MMIO_PTBR_HI(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_ptbr(63 downto 56);

                when MMIO_TIMER_CTRL(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_ctrl;
                    mmio_read_data(7) <= timer_pending;
                when MMIO_TIMER_CMP(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_cmp(7 downto 0);
                when std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_cmp(15 downto 8);
                when std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_cmp(23 downto 16);
                when std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_cmp(31 downto 24);

                when MMIO_TIMER_COUNT(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_count(7 downto 0);
                when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_count(15 downto 8);
                when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_count(23 downto 16);
                when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= timer_count(31 downto 24);
                
                when MMIO_TLBINVAL(15 downto 0) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_tlbinval(7 downto 0);
                when std_logic_vector(unsigned(MMIO_TLBINVAL(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_tlbinval(15 downto 8);
                when std_logic_vector(unsigned(MMIO_TLBINVAL(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_tlbinval(23 downto 16);
                when std_logic_vector(unsigned(MMIO_TLBINVAL(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    mmio_read_data <= mmu_tlbinval(31 downto 24);
                
                when others =>
                    null;
                end case;
            end if;
        end if;
    end process;
    
    process(mmio_read_hit, mmio_read_data, DATA_IN, state, ADDR_MODE, mmio_addr_read_lo, mmu_faultva)
    begin
        if (state = ST_READ or state = ST_READ2 or state = ST_READ3 or state = ST_READ4) and
           ADDR_MODE /= "0001" and
           unsigned(mmio_addr_read_lo) >= unsigned(MMIO_FAULTVA(15 downto 0)) and
           unsigned(mmio_addr_read_lo) <= unsigned(MMIO_FAULTVA(15 downto 0)) + 3 then
            case to_integer(unsigned(mmio_addr_read_lo) - unsigned(MMIO_FAULTVA(15 downto 0))) is
                when 0 =>
                    data_in_read <= mmu_faultva(7 downto 0);
                when 1 =>
                    data_in_read <= mmu_faultva(15 downto 8);
                when 2 =>
                    data_in_read <= mmu_faultva(23 downto 16);
                when others =>
                    data_in_read <= mmu_faultva(31 downto 24);
            end case;
        elsif mmio_read_hit = '1' then
            data_in_read <= mmio_read_data;
        else
            data_in_read <= DATA_IN;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Write Enable and Data Output
    ---------------------------------------------------------------------------
    
WE <= '1' when (state = ST_WRITE or state = ST_WRITE2 or 
                state = ST_WRITE3 or state = ST_WRITE4 or
                state = ST_PUSH or state = ST_BM_WRITE) and ptw_active = '0' and
                priv_mmio = '0'
      else '0';
    
    -- Write data based on byte count and instruction
    -- STA uses A_reg, STX uses X_reg, STY uses Y_reg
    process(state, data_byte_count, A_reg, X_reg, Y_reg, T_reg, f0_reg, f1_reg, f2_reg, f_reg_sel,
            IS_ALU_OP, IS_RMW_OP, ALU_OP, RMW_OP, REG_SRC, ALU_RES, stack_write_reg_eff, stack_width_eff,
            ext_stq, ext_stf)
        variable write_reg : std_logic_vector(31 downto 0);
        variable f_reg     : std_logic_vector(63 downto 0);
    begin
        case f_reg_sel is
            when "00" => f_reg := f0_reg;
            when "01" => f_reg := f1_reg;
            when others => f_reg := f2_reg;
        end case;
        -- Select source register for stores
        if state = ST_PUSH then
            write_reg := stack_write_reg_eff;
        elsif IS_RMW_OP = '1' and RMW_OP /= "100" and RMW_OP /= "101" then
            -- RMW writeback uses ALU result
            write_reg := ALU_RES;
        elsif IS_ALU_OP = '1' and ALU_OP = "100" then
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
        
        if state = ST_BM_WRITE then
            DATA_OUT <= data_buffer(7 downto 0);
        elsif ext_stq = '1' then
            if data_byte_count(2) = '1' then
                case data_byte_count(1 downto 0) is
                    when "00" => DATA_OUT <= T_reg(7 downto 0);
                    when "01" => DATA_OUT <= T_reg(15 downto 8);
                    when "10" => DATA_OUT <= T_reg(23 downto 16);
                    when others => DATA_OUT <= T_reg(31 downto 24);
                end case;
            else
                case data_byte_count(1 downto 0) is
                    when "00" => DATA_OUT <= A_reg(7 downto 0);
                    when "01" => DATA_OUT <= A_reg(15 downto 8);
                    when "10" => DATA_OUT <= A_reg(23 downto 16);
                    when others => DATA_OUT <= A_reg(31 downto 24);
                end case;
            end if;
        elsif ext_stf = '1' then
            if data_byte_count(2) = '1' then
                case data_byte_count(1 downto 0) is
                    when "00" => DATA_OUT <= f_reg(39 downto 32);
                    when "01" => DATA_OUT <= f_reg(47 downto 40);
                    when "10" => DATA_OUT <= f_reg(55 downto 48);
                    when others => DATA_OUT <= f_reg(63 downto 56);
                end case;
            else
                case data_byte_count(1 downto 0) is
                    when "00" => DATA_OUT <= f_reg(7 downto 0);
                    when "01" => DATA_OUT <= f_reg(15 downto 8);
                    when "10" => DATA_OUT <= f_reg(23 downto 16);
                    when others => DATA_OUT <= f_reg(31 downto 24);
                end case;
            end if;
        elsif state = ST_PUSH then
            if stack_width_eff = WIDTH_8 then
                DATA_OUT <= write_reg(7 downto 0);
            elsif stack_width_eff = WIDTH_16 then
                if data_byte_count = "000" then
                    DATA_OUT <= write_reg(15 downto 8);
                else
                    DATA_OUT <= write_reg(7 downto 0);
                end if;
            else
                case data_byte_count is
                    when "000" => DATA_OUT <= write_reg(31 downto 24);
                    when "001" => DATA_OUT <= write_reg(23 downto 16);
                    when "010" => DATA_OUT <= write_reg(15 downto 8);
                    when "011" => DATA_OUT <= write_reg(7 downto 0);
                    when others => DATA_OUT <= write_reg(7 downto 0);
                end case;
            end if;
        else
            case data_byte_count is
                when "000" => DATA_OUT <= write_reg(7 downto 0);
                when "001" => DATA_OUT <= write_reg(15 downto 8);
                when "010" => DATA_OUT <= write_reg(23 downto 16);
                when "011" => DATA_OUT <= write_reg(31 downto 24);
                when others => DATA_OUT <= write_reg(7 downto 0);
            end case;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- MMU MMIO Write Handling
    ---------------------------------------------------------------------------
    
    mmio_addr_write <= std_logic_vector(unsigned(eff_addr) + resize(data_byte_count, 32));
    mmio_addr_write_lo <= mmio_addr_write(15 downto 0);
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            mmu_mmucr <= (others => '0');
            mmu_asid <= (others => '0');
            mmu_faultva <= (others => '0');
            mmu_ptbr <= (others => '0');
            mmu_tlbinval <= (others => '0');
            mmu_asid_inval <= (others => '0');
            mmu_tlb_flush <= '0';
            mmu_tlb_flush_asid <= '0';
            mmu_tlb_flush_va <= '0';
            timer_ctrl <= (others => '0');
            timer_cmp <= (others => '0');
            timer_count <= (others => '0');
            timer_pending <= '0';
        elsif rising_edge(CLK) then
            if CE = '1' then
                if mmu_page_fault = '1' then
                    mmu_faultva <= mmu_fault_va;
                    mmu_mmucr(4 downto 2) <= mmu_fault_type;
                end if;

                if timer_ctrl(0) = '1' then
                    if timer_ctrl(2) = '1' and timer_pending = '0' and timer_cmp /= x"00000000" and
                       unsigned(timer_count) >= unsigned(timer_cmp) then
                        timer_pending <= '1';
                        if timer_ctrl(1) = '1' then
                            timer_count <= (others => '0');
                        end if;
                    elsif timer_pending = '0' or timer_ctrl(1) = '1' then
                        timer_count <= std_logic_vector(unsigned(timer_count) + 1);
                    end if;
                end if;
                
                if mem_ready = '1' then
                    mmu_tlb_flush <= '0';
                    mmu_tlb_flush_asid <= '0';
                    mmu_tlb_flush_va <= '0';
                    
                    if (state = ST_WRITE or state = ST_WRITE2 or state = ST_WRITE3 or state = ST_WRITE4) and
                       priv_mmio = '0' then
                        if S_mode = '1' then
                            case mmio_addr_write_lo is
                            when MMIO_MMUCR(15 downto 0) =>
                                mmu_mmucr(7 downto 0) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_MMUCR(15 downto 0)) + 1) =>
                                mmu_mmucr(15 downto 8) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_MMUCR(15 downto 0)) + 2) =>
                                mmu_mmucr(23 downto 16) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_MMUCR(15 downto 0)) + 3) =>
                                mmu_mmucr(31 downto 24) <= DATA_OUT;
                            
                            when MMIO_ASID(15 downto 0) =>
                                mmu_asid(7 downto 0) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_ASID(15 downto 0)) + 1) =>
                                mmu_asid(15 downto 8) <= DATA_OUT;
                            
                            when MMIO_ASIDINVAL(15 downto 0) =>
                                mmu_asid_inval(7 downto 0) <= DATA_OUT;
                                mmu_tlb_flush_asid <= '1';
                            when std_logic_vector(unsigned(MMIO_ASIDINVAL(15 downto 0)) + 1) =>
                                mmu_asid_inval(15 downto 8) <= DATA_OUT;
                                mmu_tlb_flush_asid <= '1';
                            
                            when MMIO_TLBINVAL(15 downto 0) =>
                                mmu_tlbinval(7 downto 0) <= DATA_OUT;
                                mmu_tlb_flush_va <= '1';
                            when std_logic_vector(unsigned(MMIO_TLBINVAL(15 downto 0)) + 1) =>
                                mmu_tlbinval(15 downto 8) <= DATA_OUT;
                                mmu_tlb_flush_va <= '1';
                            when std_logic_vector(unsigned(MMIO_TLBINVAL(15 downto 0)) + 2) =>
                                mmu_tlbinval(23 downto 16) <= DATA_OUT;
                                mmu_tlb_flush_va <= '1';
                            when std_logic_vector(unsigned(MMIO_TLBINVAL(15 downto 0)) + 3) =>
                                mmu_tlbinval(31 downto 24) <= DATA_OUT;
                                mmu_tlb_flush_va <= '1';
                            
                            when MMIO_PTBR_LO(15 downto 0) =>
                                mmu_ptbr(7 downto 0) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_PTBR_LO(15 downto 0)) + 1) =>
                                mmu_ptbr(15 downto 8) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_PTBR_LO(15 downto 0)) + 2) =>
                                mmu_ptbr(23 downto 16) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_PTBR_LO(15 downto 0)) + 3) =>
                                mmu_ptbr(31 downto 24) <= DATA_OUT;
                            
                            when MMIO_PTBR_HI(15 downto 0) =>
                                mmu_ptbr(39 downto 32) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_PTBR_HI(15 downto 0)) + 1) =>
                                mmu_ptbr(47 downto 40) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_PTBR_HI(15 downto 0)) + 2) =>
                                mmu_ptbr(55 downto 48) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_PTBR_HI(15 downto 0)) + 3) =>
                                mmu_ptbr(63 downto 56) <= DATA_OUT;

                            when MMIO_TLBFLUSH(15 downto 0) =>
                                mmu_tlb_flush <= '1';

                            when MMIO_TIMER_CTRL(15 downto 0) =>
                                timer_ctrl(2 downto 0) <= DATA_OUT(2 downto 0);
                                if DATA_OUT(3) = '1' then
                                    timer_pending <= '0';
                                end if;
                            when MMIO_TIMER_CMP(15 downto 0) =>
                                timer_cmp(7 downto 0) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 1) =>
                                timer_cmp(15 downto 8) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 2) =>
                                timer_cmp(23 downto 16) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 3) =>
                                timer_cmp(31 downto 24) <= DATA_OUT;

                            when MMIO_TIMER_COUNT(15 downto 0) =>
                                timer_count(7 downto 0) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 1) =>
                                timer_count(15 downto 8) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 2) =>
                                timer_count(23 downto 16) <= DATA_OUT;
                            when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 3) =>
                                timer_count(31 downto 24) <= DATA_OUT;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end if;
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
    
    ALU_L <= X_reg when (IS_ALU_OP = '1' and ALU_OP = "110" and REG_SRC = "001") else
             Y_reg when (IS_ALU_OP = '1' and ALU_OP = "110" and REG_SRC = "010") else
             A_reg;
    
    -- ALU_R: select operand based on instruction type
    -- - Accumulator RMW (ASL A, LSR A, etc.): use A_reg
    -- - Register RMW (INX, DEX, INY, DEY): use X_reg or Y_reg
    -- - Memory operations: use data_buffer
    ALU_R <= A_reg when (IS_RMW_OP = '1' and ADDR_MODE = "0000" and REG_DST = "000") else
             X_reg when (IS_RMW_OP = '1' and ADDR_MODE = "0000" and REG_DST = "001") else
             Y_reg when (IS_RMW_OP = '1' and ADDR_MODE = "0000" and REG_DST = "010") else
             data_buffer;
    
    alu_width_eff <= X_width when (IS_ALU_OP = '1' and ALU_OP = "110" and
                                   (REG_SRC = "001" or REG_SRC = "010"))
                     else M_width;
    
    ALU_WIDTH <= alu_width_eff;
    ALU_BCD <= P_reg(P_D);
    ALU_CI <= P_reg(P_C);
    ALU_VI <= P_reg(P_V);
    ALU_SI <= P_reg(P_N);
    
    exec_result <= ext_result when ext_result_valid = '1' else ALU_RES;
    
    process(ext_mul, ext_mulu, ext_div, ext_divu, ext_lea, M_width, A_reg, data_buffer, eff_addr)
        variable a_s32 : signed(31 downto 0);
        variable b_s32 : signed(31 downto 0);
        variable a_u32 : unsigned(31 downto 0);
        variable b_u32 : unsigned(31 downto 0);
        variable q_s32 : signed(31 downto 0);
        variable q_u32 : unsigned(31 downto 0);
        variable r_s32 : signed(31 downto 0);
        variable r_u32 : unsigned(31 downto 0);
    begin
        ext_result <= (others => '0');
        ext_remainder <= (others => '0');
        ext_result_valid <= '0';
        ext_rem_valid <= '0';
        
        if ext_lea = '1' then
            ext_result <= eff_addr;
            ext_result_valid <= '1';
        elsif ext_mul = '1' then
            ext_result_valid <= '1';
            if M_width = WIDTH_8 then
                a_s32 := resize(signed(A_reg(7 downto 0)), 32);
                b_s32 := resize(signed(data_buffer(7 downto 0)), 32);
                ext_result <= std_logic_vector(resize(a_s32 * b_s32, 32));
            elsif M_width = WIDTH_16 then
                a_s32 := resize(signed(A_reg(15 downto 0)), 32);
                b_s32 := resize(signed(data_buffer(15 downto 0)), 32);
                ext_result <= std_logic_vector(resize(a_s32 * b_s32, 32));
            else
                a_s32 := signed(A_reg);
                b_s32 := signed(data_buffer);
                ext_result <= std_logic_vector(resize(a_s32 * b_s32, 32));
            end if;
        elsif ext_mulu = '1' then
            ext_result_valid <= '1';
            if M_width = WIDTH_8 then
                a_u32 := resize(unsigned(A_reg(7 downto 0)), 32);
                b_u32 := resize(unsigned(data_buffer(7 downto 0)), 32);
                ext_result <= std_logic_vector(resize(a_u32 * b_u32, 32));
            elsif M_width = WIDTH_16 then
                a_u32 := resize(unsigned(A_reg(15 downto 0)), 32);
                b_u32 := resize(unsigned(data_buffer(15 downto 0)), 32);
                ext_result <= std_logic_vector(resize(a_u32 * b_u32, 32));
            else
                a_u32 := unsigned(A_reg);
                b_u32 := unsigned(data_buffer);
                ext_result <= std_logic_vector(resize(a_u32 * b_u32, 32));
            end if;
        elsif ext_div = '1' then
            ext_result_valid <= '1';
            ext_rem_valid <= '1';
            if M_width = WIDTH_8 then
                a_s32 := resize(signed(A_reg(7 downto 0)), 32);
                b_s32 := resize(signed(data_buffer(7 downto 0)), 32);
            elsif M_width = WIDTH_16 then
                a_s32 := resize(signed(A_reg(15 downto 0)), 32);
                b_s32 := resize(signed(data_buffer(15 downto 0)), 32);
            else
                a_s32 := signed(A_reg);
                b_s32 := signed(data_buffer);
            end if;
            if b_s32 = 0 then
                q_s32 := (others => '0');
                r_s32 := a_s32;
            else
                q_s32 := a_s32 / b_s32;
                r_s32 := a_s32 mod b_s32;
            end if;
            ext_result <= std_logic_vector(q_s32);
            ext_remainder <= std_logic_vector(r_s32);
        elsif ext_divu = '1' then
            ext_result_valid <= '1';
            ext_rem_valid <= '1';
            if M_width = WIDTH_8 then
                a_u32 := resize(unsigned(A_reg(7 downto 0)), 32);
                b_u32 := resize(unsigned(data_buffer(7 downto 0)), 32);
            elsif M_width = WIDTH_16 then
                a_u32 := resize(unsigned(A_reg(15 downto 0)), 32);
                b_u32 := resize(unsigned(data_buffer(15 downto 0)), 32);
            else
                a_u32 := unsigned(A_reg);
                b_u32 := unsigned(data_buffer);
            end if;
            if b_u32 = 0 then
                q_u32 := (others => '0');
                r_u32 := a_u32;
            else
                q_u32 := a_u32 / b_u32;
                r_u32 := a_u32 mod b_u32;
            end if;
            ext_result <= std_logic_vector(q_u32);
            ext_remainder <= std_logic_vector(r_u32);
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- FPU Coprocessor Operations (F0, F1, F2)
    ---------------------------------------------------------------------------

    process(IR_EXT, ext_fpu, f0_reg, f1_reg, f2_reg, A_reg)
        variable f1_s, f2_s : float32;
        variable f1_d, f2_d : float64;
        variable s_res      : float32;
        variable d_res      : float64;
        variable int32_res  : signed(31 downto 0);
        variable a_int      : integer;
        variable s_bits     : std_logic_vector(31 downto 0);
        variable d_bits     : std_logic_vector(63 downto 0);
    begin
        fpu_result     <= (others => '0');
        fpu_int_result <= (others => '0');
        fpu_write_f0   <= '0';
        fpu_write_a    <= '0';
        fpu_flag_load  <= '0';
        fpu_flag_c_load <= '0';
        fpu_flag_z     <= '0';
        fpu_flag_n     <= '0';
        fpu_flag_v     <= '0';
        fpu_flag_c     <= '0';

        if ext_fpu = '1' then
            if IR_EXT(7 downto 4) = x"C" then
                f1_s := to_float(f1_reg(31 downto 0), 8, 23);
                f2_s := to_float(f2_reg(31 downto 0), 8, 23);
                case IR_EXT is
                    when x"C0" => s_res := f1_s + f2_s;
                    when x"C1" => s_res := f1_s - f2_s;
                    when x"C2" => s_res := f1_s * f2_s;
                    when x"C3" => s_res := f1_s / f2_s;
                    when x"C4" => s_res := -f1_s;
                    when x"C5" => s_res := abs(f1_s);
                    when x"C6" =>
                        fpu_flag_load <= '1';
                        fpu_flag_c_load <= '1';
                        if f1_s = f2_s then
                            fpu_flag_z <= '1';
                            fpu_flag_c <= '1';
                            fpu_flag_n <= '0';
                        elsif f1_s < f2_s then
                            fpu_flag_z <= '0';
                            fpu_flag_c <= '0';
                            fpu_flag_n <= '1';
                        else
                            fpu_flag_z <= '0';
                            fpu_flag_c <= '1';
                            fpu_flag_n <= '0';
                        end if;
                    when x"C7" =>
                        int32_res := to_signed(to_integer(f1_s, IEEE.fixed_float_types.round_zero), 32);
                        fpu_int_result <= std_logic_vector(int32_res);
                        fpu_write_a <= '1';
                        fpu_flag_load <= '1';
                        if int32_res = 0 then
                            fpu_flag_z <= '1';
                        end if;
                        fpu_flag_n <= int32_res(31);
                    when x"C8" =>
                        a_int := to_integer(signed(A_reg));
                        s_res := to_float(a_int, 8, 23);
                    when others => null;
                end case;

                if IR_EXT /= x"C6" and IR_EXT /= x"C7" then
                    s_bits := to_slv(s_res);
                    fpu_result(31 downto 0) <= s_bits;
                    fpu_write_f0 <= '1';
                    fpu_flag_load <= '1';
                    if s_bits = x"00000000" then
                        fpu_flag_z <= '1';
                    end if;
                    fpu_flag_n <= s_bits(31);
                end if;

            elsif IR_EXT(7 downto 4) = x"D" then
                f1_d := to_float(f1_reg, 11, 52);
                f2_d := to_float(f2_reg, 11, 52);
                case IR_EXT is
                    when x"D0" => d_res := f1_d + f2_d;
                    when x"D1" => d_res := f1_d - f2_d;
                    when x"D2" => d_res := f1_d * f2_d;
                    when x"D3" => d_res := f1_d / f2_d;
                    when x"D4" => d_res := -f1_d;
                    when x"D5" => d_res := abs(f1_d);
                    when x"D6" =>
                        fpu_flag_load <= '1';
                        fpu_flag_c_load <= '1';
                        if f1_d = f2_d then
                            fpu_flag_z <= '1';
                            fpu_flag_c <= '1';
                            fpu_flag_n <= '0';
                        elsif f1_d < f2_d then
                            fpu_flag_z <= '0';
                            fpu_flag_c <= '0';
                            fpu_flag_n <= '1';
                        else
                            fpu_flag_z <= '0';
                            fpu_flag_c <= '1';
                            fpu_flag_n <= '0';
                        end if;
                    when x"D7" =>
                        int32_res := to_signed(to_integer(f1_d, IEEE.fixed_float_types.round_zero), 32);
                        fpu_int_result <= std_logic_vector(int32_res);
                        fpu_write_a <= '1';
                        fpu_flag_load <= '1';
                        if int32_res = 0 then
                            fpu_flag_z <= '1';
                        end if;
                        fpu_flag_n <= int32_res(31);
                    when x"D8" =>
                        a_int := to_integer(signed(A_reg));
                        d_res := to_float(a_int, 11, 52);
                    when others => null;
                end case;

                if IR_EXT /= x"D6" and IR_EXT /= x"D7" then
                    d_bits := to_slv(d_res);
                    fpu_result <= d_bits;
                    fpu_write_f0 <= '1';
                    fpu_flag_load <= '1';
                    if d_bits = x"0000000000000000" then
                        fpu_flag_z <= '1';
                    end if;
                    fpu_flag_n <= d_bits(63);
                end if;
            end if;
        end if;
    end process;

    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            f0_reg <= (others => '0');
            f1_reg <= (others => '0');
            f2_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if CE = '1' and mem_ready = '1' then
                if state = ST_EXECUTE then
                    if ext_ldf = '1' then
                        case f_reg_sel is
                            when "00" => f0_reg <= ldq_high_buffer & ldq_low_buffer;
                            when "01" => f1_reg <= ldq_high_buffer & ldq_low_buffer;
                            when others => f2_reg <= ldq_high_buffer & ldq_low_buffer;
                        end case;
                    elsif fpu_write_f0 = '1' then
                        f0_reg <= fpu_result;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    process(ext_result, ext_result_valid, ext_lea, ext_mul, ext_mulu, ext_div, ext_divu, ext_lli, ext_tta, T_reg,
            stack_is_pull, IR, data_buffer, M_width, X_width)
        variable value32 : std_logic_vector(31 downto 0);
        variable width_sel : std_logic_vector(1 downto 0);
    begin
        ext_flag_load <= '0';
        ext_flag_z <= '0';
        ext_flag_n <= '0';
        ext_flag_v <= '0';
        
        if ext_tta = '1' then
            ext_flag_load <= '1';
            value32 := T_reg;
            width_sel := M_width;
        elsif ext_result_valid = '1' and ext_lea = '0' then
            ext_flag_load <= '1';
            value32 := ext_result;
            width_sel := M_width;
        elsif ext_lli = '1' then
            ext_flag_load <= '1';
            value32 := data_buffer;
            width_sel := M_width;
        elsif stack_is_pull = '1' and (IR = x"68" or IR = x"FA" or IR = x"7A") then
            ext_flag_load <= '1';
            value32 := data_buffer;
            if IR = x"68" then
                width_sel := M_width;
            else
                width_sel := X_width;
            end if;
        end if;
        
        if ext_flag_load = '1' then
            if width_sel = WIDTH_8 then
                if value32(7 downto 0) = x"00" then
                    ext_flag_z <= '1';
                else
                    ext_flag_z <= '0';
                end if;
                ext_flag_n <= value32(7);
            elsif width_sel = WIDTH_16 then
                if value32(15 downto 0) = x"0000" then
                    ext_flag_z <= '1';
                else
                    ext_flag_z <= '0';
                end if;
                ext_flag_n <= value32(15);
            else
                if value32 = x"00000000" then
                    ext_flag_z <= '1';
                else
                    ext_flag_z <= '0';
                end if;
                ext_flag_n <= value32(31);
            end if;
        end if;
    end process;
    is_bit_op <= '1' when (IS_ALU_OP = '1' and ALU_OP = "001" and
                           (IR = x"24" or IR = x"2C" or IR = x"34" or
                            IR = x"3C" or IR = x"89"))
                else '0';
    
    read_width <= WIDTH_32 when (IS_JML = '1' and ADDR_MODE = "1011") else
                  WIDTH_16 when (IS_JMP_d = '1' and (ADDR_MODE = "1000" or ADDR_MODE = "1001")) else
                  WIDTH_16 when (IS_STACK = '1' and (IR = x"F4" or IR = x"D4" or IR = x"62")) else
                  WIDTH_16 when (IS_BLOCK_MOVE = '1') else
                  WIDTH_8 when (IS_REP = '1' or IS_SEP = '1') else
                  WIDTH_8 when (ext_repe = '1' or ext_sepe = '1' or ext_trap = '1') else
                  WIDTH_32 when (is_extended = '1' and (IR_EXT = x"20" or IR_EXT = x"22" or IR_EXT = x"24")) else
                  WIDTH_32 when (is_extended = '1' and (IR_EXT = x"21" or IR_EXT = x"23" or IR_EXT = x"25")) else
                  WIDTH_32 when (wid_active = '1' and ADDR_MODE = "0001") else
                  X_width when (IS_RMW_OP = '1' and RMW_OP = "101" and
                                (REG_DST = "001" or REG_DST = "010")) else
                  X_width when (IS_ALU_OP = '1' and ALU_OP = "110" and
                                (REG_SRC = "001" or REG_SRC = "010")) else
                  M_width;
    
    write_width <= X_width when (IS_RMW_OP = '1' and RMW_OP = "100" and
                                 (REG_SRC = "001" or REG_SRC = "010")) else
                   M_width;
    
    M_width_eff <= WIDTH_32 when ext_ldq = '1' else M_width;

    process(IR, M_width, X_width, A_reg, X_reg, Y_reg, D_reg, B_reg, VBR_reg, P_reg, PC_reg, data_buffer,
            ext_stack32_push, ext_stack32_pull)
    begin
        stack_width <= WIDTH_8;
        stack_write_reg <= (others => '0');
        
        if ext_stack32_push = '1' or ext_stack32_pull = '1' then
            stack_width <= WIDTH_32;
        elsif IR = x"48" or IR = x"68" then
            stack_width <= M_width;
        elsif IR = x"DA" or IR = x"FA" or IR = x"5A" or IR = x"7A" then
            stack_width <= X_width;
        elsif IR = x"0B" or IR = x"2B" then
            stack_width <= WIDTH_16;
        elsif IR = x"F4" or IR = x"D4" or IR = x"62" then
            stack_width <= WIDTH_16;
        else
            stack_width <= WIDTH_8;
        end if;
        
        if ext_stack32_push = '1' then
            if IR_EXT = x"70" then
                stack_write_reg <= D_reg;
            elsif IR_EXT = x"72" then
                stack_write_reg <= B_reg;
            elsif IR_EXT = x"74" then
                stack_write_reg <= VBR_reg;
            else
                stack_write_reg <= (others => '0');
            end if;
        elsif IR = x"08" then
            stack_write_reg <= x"000000" & P_reg(7 downto 0);
        elsif IR = x"48" then
            stack_write_reg <= A_reg;
        elsif IR = x"DA" then
            stack_write_reg <= X_reg;
        elsif IR = x"5A" then
            stack_write_reg <= Y_reg;
        elsif IR = x"0B" then
            stack_write_reg <= D_reg;
        elsif IR = x"8B" then
            stack_write_reg <= B_reg;
        elsif IR = x"4B" then
            stack_write_reg <= x"000000" & PC_reg(23 downto 16);
        elsif IR = x"62" then
            -- PER: push PC-relative address (signed 16-bit offset)
            stack_write_reg <= std_logic_vector(
                signed(PC_reg) + resize(signed(data_buffer(15 downto 0)), 32));
        elsif IR = x"F4" or IR = x"D4" then
            stack_write_reg <= data_buffer;
        else
            stack_write_reg <= A_reg;
        end if;
    end process;
    
    stack_width_eff <= int_push_width when int_in_progress = '1'
                       else WIDTH_16 when (rti_in_progress = '1' and rti_step = to_unsigned(0, rti_step'length))
                       else WIDTH_32 when (rti_in_progress = '1' and rti_step = to_unsigned(1, rti_step'length))
                       else rti_pull_width when IS_RTI = '1'
                       else stack_width;
    
    stack_write_reg_eff <= int_push_reg when int_in_progress = '1'
                           else stack_write_reg;
    
    block_src_addr <= x"00" & block_src_bank & X_reg(15 downto 0);
    block_dst_addr <= x"00" & block_dst_bank & Y_reg(15 downto 0);
    block_a_next <= std_logic_vector(unsigned(A_reg) - 1);
    block_x_next <= std_logic_vector(unsigned(X_reg) - 1) when block_dir = '1'
                    else std_logic_vector(unsigned(X_reg) + 1);
    block_y_next <= std_logic_vector(unsigned(Y_reg) - 1) when block_dir = '1'
                    else std_logic_vector(unsigned(Y_reg) + 1);
    
    process(IS_RMW_OP, RMW_OP, ALU_OP, M_width, is_bit_op)
    begin
        -- Defaults for ALU ops
        ALU_CTRL.fstOp <= ALU_FST_PASS;
        ALU_CTRL.fc <= '0';
        ALU_CTRL.w16 <= '1' when M_width = WIDTH_16 else '0';
        ALU_CTRL.w32 <= '1' when M_width = WIDTH_32 else '0';
        
        -- Map ALU_OP to secOp (note: LDA/STA map to PASS, not TRB!)
        -- ALU_OP: 000=ORA, 001=AND, 010=EOR, 011=ADC, 100=STA, 101=LDA, 110=CMP, 111=SBC
        -- ALU_SEC: 000=OR, 001=AND, 010=XOR, 011=ADC, 100=PASS, 101=TRB, 110=CMP, 111=SBC
        case ALU_OP is
            when "100" | "101" => ALU_CTRL.secOp <= ALU_SEC_PASS;  -- STA, LDA
            when others        => ALU_CTRL.secOp <= ALU_OP;
        end case;
        
        if is_bit_op = '1' then
            ALU_CTRL.fc <= '1';
        end if;
        
        if IS_RMW_OP = '1' then
            -- RMW uses first-stage operation and pass-through
            ALU_CTRL.secOp <= ALU_SEC_PASS;
            case RMW_OP is
                when "000" => ALU_CTRL.fstOp <= ALU_FST_ASL;
                when "001" => ALU_CTRL.fstOp <= ALU_FST_ROL;
                when "010" => ALU_CTRL.fstOp <= ALU_FST_LSR;
                when "011" => ALU_CTRL.fstOp <= ALU_FST_ROR;
                when "110" => ALU_CTRL.fstOp <= ALU_FST_DEC;
                when "111" => ALU_CTRL.fstOp <= ALU_FST_INC;
                when others => ALU_CTRL.fstOp <= ALU_FST_PASS;
            end case;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Register Load Signals
    ---------------------------------------------------------------------------
    
    -- Accumulator input: data_buffer for loads, ALU result for operations, register for transfers
    -- ALU_OP: 000=ORA, 001=AND, 010=EOR, 011=ADC, 100=STA, 101=LDA, 110=CMP, 111=SBC
    A_in <= block_a_next when (state = ST_BM_WRITE and block_active = '1')
            else data_buffer when ((IS_ALU_OP = '1' and ALU_OP = "101") or
                               ext_lli = '1' or
                               (stack_is_pull = '1' and IR = x"68"))
            else ldq_low_buffer when (ext_ldq = '1')
            else T_reg when (ext_tta = '1')
            else fpu_int_result when (fpu_write_a = '1')
            else X_reg when (IS_TRANSFER = '1' and REG_SRC = "001" and REG_DST = "000")  -- TXA
            else Y_reg when (IS_TRANSFER = '1' and REG_SRC = "010" and REG_DST = "000")  -- TYA
            else eff_addr when (ext_lea = '1')
            else exec_result;
    
    -- A loads on: LDA, ALU operations that produce results (not STA, not CMP),
    -- accumulator RMW (ASL A, etc.), or transfers to A (TXA, TYA)
    A_load <= '1' when (state = ST_EXECUTE or (state = ST_BM_WRITE and block_active = '1')) and 
              ((IS_ALU_OP = '1' and ALU_OP /= "100" and ALU_OP /= "110" and is_bit_op = '0') or  -- ALU ops except STA, CMP, BIT
               (IS_RMW_OP = '1' and ADDR_MODE = "0000" and REG_DST = "000" and 
                RMW_OP /= "100" and RMW_OP /= "101") or  -- Accumulator RMW (not stores/loads)
               (IS_TRANSFER = '1' and REG_DST = "000") or  -- Transfers to A (TXA, TYA)
               ext_lli = '1' or ext_lea = '1' or ext_mul = '1' or ext_mulu = '1' or
               ext_div = '1' or ext_divu = '1' or ext_tta = '1' or ext_ldq = '1' or
               fpu_write_a = '1' or
               (stack_is_pull = '1' and IR = x"68") or
               (state = ST_BM_WRITE and block_active = '1'))
              else '0';
    
    -- X register: LDX is RMW_OP = "101" with REG_DST = "001"
    -- Also handle transfers TAX (REG_DST = "001")
    -- Also handle INX/DEX (RMW_OP = "110"/"111" with REG_DST = "001")
    X_in <= block_x_next when (state = ST_BM_WRITE and block_active = '1')
            else data_buffer when (IS_RMW_OP = '1' and RMW_OP = "101" and REG_DST = "001")
            else data_buffer when (stack_is_pull = '1' and IR = x"FA")
            else data_buffer when (ext_cas = '1' and cas_match = '0')
            else A_reg when (IS_TRANSFER = '1' and REG_DST = "001")
            else ALU_RES when (IS_RMW_OP = '1' and REG_DST = "001")
            else (others => '0');
    X_load <= '1' when (state = ST_EXECUTE or (state = ST_BM_WRITE and block_active = '1')) and 
              ((IS_RMW_OP = '1' and REG_DST = "001" and RMW_OP /= "100") or  -- LDX, INX, DEX
               (IS_TRANSFER = '1' and REG_DST = "001") or
               (stack_is_pull = '1' and IR = x"FA") or
               (ext_cas = '1' and cas_match = '0') or
               (state = ST_BM_WRITE and block_active = '1'))
              else '0';
    
    -- Y register: LDY is RMW_OP = "101" with REG_DST = "010"
    -- Also handle INY/DEY (RMW_OP = "110"/"111" with REG_DST = "010")
    Y_in <= block_y_next when (state = ST_BM_WRITE and block_active = '1')
            else data_buffer when (IS_RMW_OP = '1' and RMW_OP = "101" and REG_DST = "010")
            else data_buffer when (stack_is_pull = '1' and IR = x"7A")
            else A_reg when (IS_TRANSFER = '1' and REG_DST = "010")
            else ALU_RES when (IS_RMW_OP = '1' and REG_DST = "010")
            else (others => '0');
    Y_load <= '1' when (state = ST_EXECUTE or (state = ST_BM_WRITE and block_active = '1')) and 
              ((IS_RMW_OP = '1' and REG_DST = "010" and RMW_OP /= "100") or  -- LDY, INY, DEY
               (IS_TRANSFER = '1' and REG_DST = "010") or
               (stack_is_pull = '1' and IR = x"7A") or
               (state = ST_BM_WRITE and block_active = '1'))
              else '0';
    
    -- Stack pointer
    SP_in <= (others => '0');
    SP_load <= '0';
    SP_inc <= '1' when state = ST_PULL else '0';
    SP_dec <= '1' when state = ST_PUSH else '0';
    
    D_in <= data_buffer;
    D_load <= '1' when state = ST_EXECUTE and
              ((stack_is_pull = '1' and IR = x"2B") or
               (ext_stack32_pull = '1' and IR_EXT = x"71") or
               ext_sd = '1')
              else '0';
    
    B_in <= data_buffer;
    B_load <= '1' when state = ST_EXECUTE and
              ((stack_is_pull = '1' and IR = x"AB") or
               (ext_stack32_pull = '1' and IR_EXT = x"73") or
               ext_sb = '1')
              else '0';
    
    VBR_in <= data_buffer;
    VBR_load <= '1' when state = ST_EXECUTE and
                ((ext_stack32_pull = '1' and IR_EXT = x"75") or
                 ext_svbr = '1')
                else '0';
    
    T_in <= ext_remainder when ext_rem_valid = '1'
            else ldq_high_buffer when ext_ldq = '1'
            else A_reg;
    T_load <= '1' when state = ST_EXECUTE and (ext_rem_valid = '1' or ext_tat = '1' or ext_ldq = '1') else '0';

    ---------------------------------------------------------------------------
    -- Register Window Access (DP-as-registers)
    ---------------------------------------------------------------------------
    
    rw_addr1 <= dp_reg_index_next when (state = ST_ADDR1 and
                                        (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                else dp_reg_index;
    rw_addr2 <= dp_reg_index_next_plus1 when ((ext_ldq = '1' or ext_ldf = '1') and R_mode = '1' and state = ST_ADDR1 and
                                              (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                else (others => '0');
    rw_waddr <= dp_reg_index_next_plus1 when ((stq_high_reg = '1' or f_stq_high_reg = '1') and state = ST_EXECUTE)
                else dp_reg_index_next when (state = ST_ADDR1 and
                                             (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                else dp_reg_index;
    rw_width <= X_width when (IS_RMW_OP = '1' and RMW_OP = "101" and
                              (REG_DST = "001" or REG_DST = "010")) else
                X_width when (IS_RMW_OP = '1' and RMW_OP = "100" and
                              (REG_SRC = "001" or REG_SRC = "010")) else
                M_width;
    rw_byte_sel <= "00";
    
    process(IS_ALU_OP, IS_RMW_OP, ALU_OP, RMW_OP, REG_SRC, A_reg, X_reg, Y_reg, T_reg, ALU_RES, stq_high_reg,
            f_stq_high_reg, ext_stf, f_reg_sel, f0_reg, f1_reg, f2_reg)
        variable f_reg : std_logic_vector(63 downto 0);
    begin
        case f_reg_sel is
            when "00" => f_reg := f0_reg;
            when "01" => f_reg := f1_reg;
            when others => f_reg := f2_reg;
        end case;

        if f_stq_high_reg = '1' then
            rw_wdata <= f_reg(63 downto 32);
        elsif ext_stf = '1' then
            rw_wdata <= f_reg(31 downto 0);
        elsif stq_high_reg = '1' then
            rw_wdata <= T_reg;
        elsif IS_ALU_OP = '1' and ALU_OP = "100" then
            rw_wdata <= A_reg;
        elsif IS_RMW_OP = '1' and RMW_OP = "100" then
            if REG_SRC = "001" then
                rw_wdata <= X_reg;
            else
                rw_wdata <= Y_reg;
            end if;
        elsif IS_RMW_OP = '1' then
            rw_wdata <= ALU_RES;
        else
            rw_wdata <= A_reg;
        end if;
    end process;
    
    rw_we <= '1' when (R_mode = '1' and
                       ((state = ST_ADDR1 and (IS_ALU_OP = '1' and ALU_OP = "100")) or
                        (state = ST_ADDR1 and (IS_RMW_OP = '1' and RMW_OP = "100")) or
                        (state = ST_ADDR1 and ext_stq = '1') or
                        (state = ST_ADDR1 and ext_stf = '1') or
                        (stq_high_reg = '1' and state = ST_EXECUTE) or
                        (f_stq_high_reg = '1' and state = ST_EXECUTE) or
                        (state = ST_EXECUTE and IS_RMW_OP = '1' and RMW_OP /= "100" and RMW_OP /= "101" and
                         (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))))
             else '0';

    process(state, ADDR_MODE, DATA_IN, X_reg, Y_reg, dp_reg_index, R_mode, ext_ldf, ext_stf)
    begin
        dp_reg_index_next <= dp_reg_index;
        if state = ST_ADDR1 and (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100") then
            if R_mode = '1' and (ext_ldf = '1' or ext_stf = '1') then
                -- 16-byte alignment for F register pairs in R-mode (Rk/Rk+1)
                dp_reg_index_next <= DATA_IN(5 downto 2) & "00";
            elsif ADDR_MODE = "0011" then
                dp_reg_index_next <= std_logic_vector(resize(unsigned(DATA_IN) + unsigned(X_reg(7 downto 0)), 6));
            elsif ADDR_MODE = "0100" then
                dp_reg_index_next <= std_logic_vector(resize(unsigned(DATA_IN) + unsigned(Y_reg(7 downto 0)), 6));
            else
                dp_reg_index_next <= DATA_IN(5 downto 0);
            end if;
        end if;
    end process;
    
    dp_reg_index_next_plus1 <= std_logic_vector(unsigned(dp_reg_index_next) + 1);
    
    p_next <= P_reg(P_WIDTH-1 downto 8) & (P_reg(7 downto 0) and (not data_buffer(7 downto 0)))
              when (IS_REP = '1' or ext_repe = '1') else
              P_reg(P_WIDTH-1 downto 8) & (P_reg(7 downto 0) or data_buffer(7 downto 0))
              when (IS_SEP = '1' or ext_sepe = '1') else
              P_reg;
    
    process(state, stack_is_pull, IR, data_buffer, ext_cas, cas_match, ext_sci, sci_success, P_reg, int_step, rti_step, IS_XCE)
    begin
        p_override <= P_reg;
        p_override_valid <= '0';
        if state = ST_EXECUTE and stack_is_pull = '1' and IR = x"28" then
            p_override <= P_reg(P_WIDTH-1 downto 8) & data_buffer(7 downto 0);
            p_override_valid <= '1';
        elsif state = ST_EXECUTE and IS_XCE = '1' then
            p_override <= P_reg;
            p_override(P_C) <= P_reg(P_E);
            p_override(P_E) <= P_reg(P_C);
            if P_reg(P_C) = '1' then
                p_override(P_M0) <= '1';
                p_override(P_M1) <= '1';
                p_override(P_X0) <= '1';
                p_override(P_X1) <= '1';
            end if;
            p_override_valid <= '1';
        elsif state = ST_RTI_NEXT and rti_step = to_unsigned(0, rti_step'length) then
            p_override <= data_buffer(P_WIDTH-1 downto 0);
            p_override_valid <= '1';
        elsif state = ST_INT_NEXT and int_step = to_unsigned(1, int_step'length) then
            p_override <= P_reg;
            p_override(P_I) <= '1';
            p_override(P_S) <= '1';
            p_override_valid <= '1';
        elsif state = ST_EXECUTE and IS_RSET = '1' then
            p_override <= P_reg(P_WIDTH-1 downto P_R+1) & '1' & P_reg(P_R-1 downto 0);
            p_override_valid <= '1';
        elsif state = ST_EXECUTE and IS_RCLR = '1' then
            p_override <= P_reg(P_WIDTH-1 downto P_R+1) & '0' & P_reg(P_R-1 downto 0);
            p_override_valid <= '1';
        elsif state = ST_EXECUTE and ext_cas = '1' then
            if cas_match = '1' then
                p_override <= P_reg(P_WIDTH-1 downto 8) & (P_reg(7 downto 0) or "00000010");
            else
                p_override <= P_reg(P_WIDTH-1 downto 8) & (P_reg(7 downto 0) and "11111101");
            end if;
            p_override_valid <= '1';
        elsif state = ST_EXECUTE and ext_sci = '1' then
            if sci_success = '1' then
                p_override <= P_reg(P_WIDTH-1 downto 8) & (P_reg(7 downto 0) or "00000010");
            else
                p_override <= P_reg(P_WIDTH-1 downto 8) & (P_reg(7 downto 0) and "11111101");
            end if;
            p_override_valid <= '1';
        end if;
    end process;
    
    P_in <= p_override when p_override_valid = '1' else p_next;
    P_load <= '1' when (state = ST_EXECUTE and (IS_REP = '1' or IS_SEP = '1' or ext_repe = '1' or
                                                ext_sepe = '1' or IS_RSET = '1' or IS_RCLR = '1')) or
                       p_override_valid = '1'
              else '0';
    
    ---------------------------------------------------------------------------
    -- Flag Update Logic
    ---------------------------------------------------------------------------
    
    -- Carry flag input: ALU carry for arithmetic, or explicit set/clear for CLC/SEC
    flag_c_in <= fpu_flag_c when fpu_flag_c_load = '1' else
                 '0' when (IS_FLAG_OP = '1' and IR = x"18") else  -- CLC
                 '1' when (IS_FLAG_OP = '1' and IR = x"38") else  -- SEC
                 ALU_CO;
    
    -- Interrupt disable flag input: CLI/SEI
    flag_i_in <= '0' when (IS_FLAG_OP = '1' and IR = x"58") else  -- CLI
                 '1' when (IS_FLAG_OP = '1' and IR = x"78") else  -- SEI
                 P_reg(P_I);
    
    -- Carry flag load: CLC/SEC, ADC/SBC/CMP, or shift/rotate operations
    flag_c_load <= '1' when state = ST_EXECUTE and 
                   (fpu_flag_c_load = '1' or
                    (IS_FLAG_OP = '1' and (IR = x"18" or IR = x"38")) or  -- CLC, SEC
                    (IS_ALU_OP = '1' and (ALU_OP = "011" or ALU_OP = "110" or ALU_OP = "111")) or  -- ADC, CMP, SBC
                    (IS_RMW_OP = '1' and (RMW_OP = "000" or RMW_OP = "001" or 
                                          RMW_OP = "010" or RMW_OP = "011")))  -- ASL, ROL, LSR, ROR
                   else '0';
    
    flag_i_load <= '1' when state = ST_EXECUTE and
                   (IS_FLAG_OP = '1' and (IR = x"58" or IR = x"78"))  -- CLI, SEI
                   else '0';
    
    -- N, Z, V flags load: most ALU operations and RMW operations
    flag_z_in <= fpu_flag_z when fpu_flag_load = '1' else
                 ext_flag_z when ext_flag_load = '1' else ALU_ZO;
    flag_n_in <= fpu_flag_n when fpu_flag_load = '1' else
                 ext_flag_n when ext_flag_load = '1' else ALU_SO;
    flag_v_in <= fpu_flag_v when fpu_flag_load = '1' else
                 ext_flag_v when ext_flag_load = '1' else ALU_VO;
    
    flag_nzv_load <= '1' when state = ST_EXECUTE and
                     (fpu_flag_load = '1' or
                      ext_flag_load = '1' or
                      (IS_ALU_OP = '1' and ALU_OP /= "100") or  -- All ALU except STA
                      (IS_RMW_OP = '1' and RMW_OP /= "100"))    -- All RMW except STX/STY
                     else '0';
    
    ---------------------------------------------------------------------------
    -- Branch Condition Evaluation
    ---------------------------------------------------------------------------
    -- BRANCH_COND: 000=BPL(N=0), 001=BMI(N=1), 010=BVC(V=0), 011=BVS(V=1),
    --              100=BCC(C=0), 101=BCS(C=1), 110=BNE(Z=0), 111=BEQ(Z=1)
    
    branch_taken <= '1' when IS_BRANCH = '1' and 
                    (IR = x"80" or  -- BRA: always taken
                     IR = x"82" or  -- BRL: always taken
                     (BRANCH_COND = "000" and P_reg(P_N) = '0') or  -- BPL: N=0
                     (BRANCH_COND = "001" and P_reg(P_N) = '1') or  -- BMI: N=1
                     (BRANCH_COND = "010" and P_reg(P_V) = '0') or  -- BVC: V=0
                     (BRANCH_COND = "011" and P_reg(P_V) = '1') or  -- BVS: V=1
                     (BRANCH_COND = "100" and P_reg(P_C) = '0') or  -- BCC: C=0
                     (BRANCH_COND = "101" and P_reg(P_C) = '1') or  -- BCS: C=1
                     (BRANCH_COND = "110" and P_reg(P_Z) = '0') or  -- BNE: Z=0
                     (BRANCH_COND = "111" and P_reg(P_Z) = '1'))    -- BEQ: Z=1
                    else '0';
    
    ---------------------------------------------------------------------------
    -- Address Generator Control
    ---------------------------------------------------------------------------
    -- LOAD_PC: 000=hold, 001=increment, 010=load from D_IN:DR, 100=branch offset
    
    pc_direct <= DATA_IN & data_buffer(23 downto 0) when state = ST_VECTOR4
                 else data_buffer when (state = ST_RTI_NEXT and rti_step = to_unsigned(1, rti_step'length))
                 else data_buffer when (state = ST_EXECUTE and IS_JML = '1' and ADDR_MODE = "1011")
                 else eff_addr when (state = ST_EXECUTE and (IS_JML = '1' or IS_JSL = '1'))
                 else std_logic_vector(unsigned(jsr_return) + 1);
    
    is_indirect_addr <= '1' when ((ADDR_MODE = "1000" and IS_JMP_d = '0') or
                                  ADDR_MODE = "1001" or ADDR_MODE = "1010" or
                                  ADDR_MODE = "1011" or ADDR_MODE = "1100" or
                                  ADDR_MODE = "1110") else '0';
    is_long_x <= '1' when (ADDR_MODE = "1111" and IR(4 downto 0) = "11111") else '0';
    
    ext_mul  <= '1' when (is_extended = '1' and (IR_EXT = x"00" or IR_EXT = x"02")) else '0';
    ext_mulu <= '1' when (is_extended = '1' and (IR_EXT = x"01" or IR_EXT = x"03")) else '0';
    ext_div  <= '1' when (is_extended = '1' and (IR_EXT = x"04" or IR_EXT = x"06")) else '0';
    ext_divu <= '1' when (is_extended = '1' and (IR_EXT = x"05" or IR_EXT = x"07")) else '0';
    
    ext_cas  <= '1' when (is_extended = '1' and (IR_EXT = x"10" or IR_EXT = x"11")) else '0';
    ext_lli  <= '1' when (is_extended = '1' and (IR_EXT = x"12" or IR_EXT = x"13")) else '0';
    ext_sci  <= '1' when (is_extended = '1' and (IR_EXT = x"14" or IR_EXT = x"15")) else '0';
    
    ext_svbr <= '1' when (is_extended = '1' and (IR_EXT = x"20" or IR_EXT = x"21")) else '0';
    ext_sb   <= '1' when (is_extended = '1' and (IR_EXT = x"22" or IR_EXT = x"23")) else '0';
    ext_sd   <= '1' when (is_extended = '1' and (IR_EXT = x"24" or IR_EXT = x"25")) else '0';
    
    ext_trap <= '1' when (is_extended = '1' and IR_EXT = x"40") else '0';
    ext_fence   <= '1' when (is_extended = '1' and IR_EXT = x"50") else '0';
    ext_fencer  <= '1' when (is_extended = '1' and IR_EXT = x"51") else '0';
    ext_fencew  <= '1' when (is_extended = '1' and IR_EXT = x"52") else '0';
    ext_fpu <= '1' when (is_extended = '1' and
                         (IR_EXT = x"C0" or IR_EXT = x"C1" or IR_EXT = x"C2" or IR_EXT = x"C3" or
                          IR_EXT = x"C4" or IR_EXT = x"C5" or IR_EXT = x"C6" or IR_EXT = x"C7" or
                          IR_EXT = x"C8" or IR_EXT = x"D0" or IR_EXT = x"D1" or IR_EXT = x"D2" or
                          IR_EXT = x"D3" or IR_EXT = x"D4" or IR_EXT = x"D5" or IR_EXT = x"D6" or
                          IR_EXT = x"D7" or IR_EXT = x"D8")) else '0';
    ext_fpu_trap <= '1' when (is_extended = '1' and
                              (IR_EXT = x"D9" or IR_EXT = x"DA" or IR_EXT = x"DB" or IR_EXT = x"DC" or
                               IR_EXT = x"DD" or IR_EXT = x"DE" or IR_EXT = x"DF" or IR_EXT = x"E0" or
                               IR_EXT = x"E1" or IR_EXT = x"E2" or IR_EXT = x"E3" or IR_EXT = x"E4" or
                               IR_EXT = x"E5" or IR_EXT = x"E6")) else '0';
    
    ext_repe <= '1' when (is_extended = '1' and IR_EXT = x"60") else '0';
    ext_sepe <= '1' when (is_extended = '1' and IR_EXT = x"61") else '0';
    
    ext_stack32_push <= '1' when (is_extended = '1' and (IR_EXT = x"70" or IR_EXT = x"72" or IR_EXT = x"74")) else '0';
    ext_stack32_pull <= '1' when (is_extended = '1' and (IR_EXT = x"71" or IR_EXT = x"73" or IR_EXT = x"75")) else '0';
    
    ext_lea <= '1' when (is_extended = '1' and (IR_EXT = x"A0" or IR_EXT = x"A1" or
                                                IR_EXT = x"A2" or IR_EXT = x"A3")) else '0';
    ext_tta <= '1' when (is_extended = '1' and IR_EXT = x"86") else '0';
    ext_tat <= '1' when (is_extended = '1' and IR_EXT = x"87") else '0';
    ext_ldq <= '1' when (IR = x"02" and (IR_EXT = x"88" or IR_EXT = x"89")) else '0';
    ext_stq <= '1' when (IR = x"02" and (IR_EXT = x"8A" or IR_EXT = x"8B")) else '0';
    ext_ldf <= '1' when (IR = x"02" and (IR_EXT = x"B0" or IR_EXT = x"B1" or IR_EXT = x"B4" or
                                         IR_EXT = x"B5" or IR_EXT = x"B8" or IR_EXT = x"B9")) else '0';
    ext_stf <= '1' when (IR = x"02" and (IR_EXT = x"B2" or IR_EXT = x"B3" or IR_EXT = x"B6" or
                                         IR_EXT = x"B7" or IR_EXT = x"BA" or IR_EXT = x"BB")) else '0';
    f_reg_sel <= "00" when (IR_EXT = x"B0" or IR_EXT = x"B1" or IR_EXT = x"B2" or IR_EXT = x"B3") else
                 "01" when (IR_EXT = x"B4" or IR_EXT = x"B5" or IR_EXT = x"B6" or IR_EXT = x"B7") else
                 "10" when (IR_EXT = x"B8" or IR_EXT = x"B9" or IR_EXT = x"BA" or IR_EXT = x"BB") else
                 "00";
    
    stack_is_pull <= '1' when (IS_STACK = '1' and
                               (IR = x"28" or IR = x"68" or IR = x"FA" or IR = x"7A" or
                                IR = x"2B" or IR = x"AB" or ext_stack32_pull = '1'))
                     else '0';
    
    sci_success <= '1' when (ext_sci = '1' and link_valid = '1' and link_addr = eff_addr) else '0';
    
    process(ext_cas, M_width, data_buffer, X_reg)
    begin
        cas_match <= '0';
        if ext_cas = '1' then
            if M_width = WIDTH_8 then
                if data_buffer(7 downto 0) = X_reg(7 downto 0) then
                    cas_match <= '1';
                end if;
            elsif M_width = WIDTH_16 then
                if data_buffer(15 downto 0) = X_reg(15 downto 0) then
                    cas_match <= '1';
                end if;
            else
                if data_buffer = X_reg then
                    cas_match <= '1';
                end if;
            end if;
        end if;
    end process;
    
    LOAD_PC <= "111" when (state = ST_VECTOR4 or (state = ST_RTI_NEXT and rti_step = to_unsigned(1, rti_step'length))) else
               "010" when (state = ST_ADDR2 and (IS_JSR = '1' or IS_JMP_d = '1')) -- Load PC from D_IN:DR
              else "010" when (state = ST_READ2 and IS_JMP_d = '1' and
                               (ADDR_MODE = "1000" or ADDR_MODE = "1001")) -- JMP indirect
              else "010" when (state = ST_ADDR4 and IS_JMP_d = '1' and
                               ADDR_MODE = "1001") -- JMP (abs,X) indirect
               else "100" when (state = ST_BRANCH2 and branch_taken = '1') -- Branch taken: add offset
               else "001" when (state = ST_FETCH or
                           state = ST_ADDR1 or 
                           (state = ST_ADDR2 and is_indirect_addr = '0') or 
                           (state = ST_ADDR3 and is_indirect_addr = '0') or
                           (state = ST_ADDR4 and is_indirect_addr = '0') or
                           state = ST_BRANCH or  -- Fetch branch offset
                           ((state = ST_DECODE) and IR = x"02" and is_extended = '0') or
                           ((state = ST_READ or state = ST_READ2 or state = ST_READ3 or state = ST_READ4) and
                            ADDR_MODE = "0001")) -- Immediate mode
               else "111" when (state = ST_EXECUTE and (IS_RTS = '1' or IS_RTL = '1' or IS_JML = '1' or IS_JSL = '1'))
                   -- RTS/RTL uses stored return, JML/JSL use eff_addr via pc_direct
               else "000";
    PC_DEC <= '0';
    ADDR_CTRL <= (others => '0');
    IND_CTRL <= (others => '0');
    USE_BASE_B <= '0';
    USE_BASE_VBR <= E_mode;

end rtl;
