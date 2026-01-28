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
        ST_BRANCH3,
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
    signal ext_addr32   : std_logic;
    signal ext_alu      : std_logic;
    signal ext_alu_size : std_logic_vector(1 downto 0);
    signal M_width_eff, X_width_eff  : std_logic_vector(1 downto 0);
    
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
    signal IS_EXT_OP                              : std_logic;
    signal IS_RSET, IS_RCLR, IS_SB, IS_SVBR       : std_logic;
    signal IS_CAS, IS_LLI, IS_SCI                 : std_logic;
    signal ILLEGAL_OP                              : std_logic;
    signal illegal_regalu                          : std_logic;
    signal illegal_dp_align                        : std_logic;
    signal dp_addr_unaligned                       : std_logic;
    
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
    signal branch_wide      : std_logic;
    signal load_no_flags    : std_logic;
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
    signal ext_ldf_s, ext_stf_s                : std_logic;
    signal ext_fpu_xfer                        : std_logic;      -- FPU register transfer ops (E0-E5)
    signal fpu_indirect                        : std_logic;      -- FPU register-indirect load/store
    signal fpu_mem_reg                         : unsigned(3 downto 0); -- FPU reg for load/store
    signal ext_fpu_trap                        : std_logic;
    
    -- Extended ALU/Shifter/Extend mode/op byte
    signal IR_EXT2          : std_logic_vector(7 downto 0);   -- mode/op byte after ext opcode
    signal is_regalu_ext    : std_logic;                       -- Fetching reg-ALU op|mode
    signal IS_REGALU        : std_logic;                       -- Register-targeted ALU op
    signal REGALU_OP        : std_logic_vector(3 downto 0);   -- Operation code
    signal REGALU_SRC_MODE  : std_logic_vector(3 downto 0);   -- Source addressing mode
    signal REGALU_DEST_DP   : std_logic_vector(7 downto 0);   -- Destination DP address
    signal regalu_dest_addr : std_logic_vector(31 downto 0);  -- Computed dest effective address
    signal regalu_dest_data : std_logic_vector(31 downto 0);  -- Data read from dest
    signal regalu_src_data  : std_logic_vector(31 downto 0);  -- Data read from source
    signal regalu_result    : std_logic_vector(31 downto 0);  -- ALU result
    
    -- Shifter signals ($02 $E9)
    signal IS_SHIFTER       : std_logic;                       -- Shifter operation
    signal SHIFT_OP         : std_logic_vector(2 downto 0);   -- Shift type
    signal SHIFT_COUNT      : std_logic_vector(4 downto 0);   -- Shift count
    signal shifter_src_data : std_logic_vector(31 downto 0);  -- Source data for shift
    signal shifter_result   : std_logic_vector(31 downto 0);  -- Shift result
    signal shifter_carry    : std_logic;                       -- Carry out from shift
    
    -- Extend signals ($02 $EA)
    signal IS_EXTEND        : std_logic;                       -- Extend operation
    signal EXTEND_OP        : std_logic_vector(3 downto 0);   -- Extend type
    signal extend_src_data  : std_logic_vector(31 downto 0);  -- Source data for extend
    signal extend_result    : std_logic_vector(31 downto 0);  -- Extend result
    signal regalu_phase     : std_logic_vector(1 downto 0);   -- Execution phase
    
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
    signal timer_count_latched : std_logic_vector(31 downto 0);
    signal timer_latched_valid : std_logic;
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
    signal timer_mmio_access : std_logic;
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
    signal dp_byte_sel_reg : std_logic_vector(1 downto 0);
    signal dp_byte_sel_next : std_logic_vector(1 downto 0);
    
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

    -- FPU coprocessor registers (16 x 64-bit)
    type fp_reg_array is array (0 to 15) of std_logic_vector(63 downto 0);
    signal fp_regs          : fp_reg_array;
    signal fpu_result       : std_logic_vector(63 downto 0);
    signal fpu_int_result   : std_logic_vector(31 downto 0);
    signal fpu_write_fd     : std_logic;                        -- Write to destination FP reg
    signal fpu_write_a      : std_logic;
    signal fpu_flag_z       : std_logic;
    signal fpu_flag_n       : std_logic;
    signal fpu_flag_v       : std_logic;
    signal fpu_flag_c       : std_logic;
    signal fpu_flag_load    : std_logic;
    signal fpu_flag_c_load  : std_logic;
    signal f_stq_high_reg   : std_logic;
    signal fpu_reg_byte     : std_logic_vector(7 downto 0);     -- FPU register byte (DDDD SSSS)
    signal fpu_dest         : unsigned(3 downto 0);              -- Destination register (0-15)
    signal fpu_src          : unsigned(3 downto 0);              -- Source register (0-15)
    signal is_fpu_ext       : std_logic;                         -- Fetching FPU register byte
    
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
        IR_EXT2         => IR_EXT2,
        IS_EXTENDED     => is_extended,
        IS_REGALU_EXT   => is_regalu_ext,
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
        EXT_ALU         => ext_alu,
        EXT_ALU_SIZE    => ext_alu_size,
        EXT_ADDR32      => ext_addr32,
        IS_RSET         => IS_RSET,
        IS_RCLR         => IS_RCLR,
        IS_SB           => IS_SB,
        IS_SVBR         => IS_SVBR,
        IS_CAS          => IS_CAS,
        IS_LLI          => IS_LLI,
        IS_SCI          => IS_SCI,
        ILLEGAL_OP      => ILLEGAL_OP,
        
        IS_REGALU       => IS_REGALU,
        REGALU_OP       => REGALU_OP,
        REGALU_SRC_MODE => REGALU_SRC_MODE,
        REGALU_DEST_DP  => REGALU_DEST_DP,
        
        IS_SHIFTER      => IS_SHIFTER,
        SHIFT_OP        => SHIFT_OP,
        SHIFT_COUNT     => SHIFT_COUNT,
        
        IS_EXTEND       => IS_EXTEND,
        EXTEND_OP       => EXTEND_OP
    );
    
    ---------------------------------------------------------------------------
    -- Wide mode detection
    ---------------------------------------------------------------------------
    
W_mode <= '1' when M_width = WIDTH_32 else '0';
compat_mode <= '1' when M_width = WIDTH_32 else P_reg(P_K);
M_width_eff <= WIDTH_32 when ext_ldq = '1' else
               ext_alu_size when ext_alu = '1' else
               WIDTH_32 when W_mode = '1' else
               M_width;
X_width_eff <= WIDTH_32 when W_mode = '1' else X_width;
    illegal_regalu <= '1' when ((IS_REGALU = '1' or IS_SHIFTER = '1' or IS_EXTEND = '1') and R_mode = '0') else '0';
    
    -- DP alignment check for R_mode: DP address must be multiple of 4
    -- dp_addr_unaligned is computed in dp_reg_index_next process
    illegal_dp_align <= '1' when (R_mode = '1' and dp_addr_unaligned = '1' and
                                  state = ST_ADDR1 and 
                                  (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                        else '0';

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
    timer_mmio_access <= '1' when mmu_bypass = '1' and
                                  unsigned(mem_addr_virt(15 downto 0)) >= unsigned(MMIO_TIMER_CTRL(15 downto 0)) and
                                  unsigned(mem_addr_virt(15 downto 0)) <= unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 3
                         else '0';
    timer_irq <= timer_pending and timer_ctrl(2);
    priv_op <= '1' when S_mode = '0' and
                        (IS_SVBR = '1' or IS_SB = '1' or IS_RSET = '1' or
                         IS_RCLR = '1' or IS_XCE = '1') else '0';
    priv_stp <= '1' when S_mode = '0' and IS_STP = '1' else '0';
    priv_mmio <= '1' when S_mode = '0' and mmu_bypass = '1' and timer_mmio_access = '0' and
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
            IR_EXT2 <= x"00";
            is_extended <= '0';
            is_regalu_ext <= '0';
            regalu_phase <= "00";
            regalu_dest_addr <= (others => '0');
            regalu_dest_data <= (others => '0');
            regalu_src_data <= (others => '0');
            data_buffer <= (others => '0');
            data_byte_count <= (others => '0');
            DR <= (others => '0');
            eff_addr <= (others => '0');
            jsr_return <= (others => '0');
            link_valid <= '0';
            link_addr <= (others => '0');
            dp_reg_index <= (others => '0');
            dp_byte_sel_reg <= "00";
            ldq_high_buffer <= (others => '0');
            ldq_low_buffer <= (others => '0');
            ldq_high_phase <= '0';
            stq_high_reg <= '0';
            f_stq_high_reg <= '0';
            is_fpu_ext <= '0';
            fpu_reg_byte <= (others => '0');
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
                elsif (ILLEGAL_OP = '1' or illegal_regalu = '1' or illegal_dp_align = '1') and ext_fpu_trap = '0' and 
                      (state = ST_DECODE or state = ST_ADDR1) and
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
                        is_regalu_ext <= '0';
                        is_fpu_ext <= '0';
                        regalu_phase <= "00";
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
                        elsif is_extended = '1' and
                              ((IR_EXT >= x"80" and IR_EXT <= x"97") or IR_EXT = EXT_SHIFTER or IR_EXT = EXT_EXTEND) and
                              is_regalu_ext = '0' then
                            -- Extended ALU/Shifter/Extend needs mode/op byte
                            is_regalu_ext <= '1';
                            IR_EXT2 <= DATA_IN;
                            state <= ST_DECODE;
                        elsif is_extended = '1' and
                              ((IR_EXT >= x"B0" and IR_EXT <= x"BB") or   -- FPU load/store
                               (IR_EXT >= x"C0" and IR_EXT <= x"CA") or   -- FPU single-precision
                               (IR_EXT >= x"D0" and IR_EXT <= x"DA") or   -- FPU double-precision
                               (IR_EXT >= x"E0" and IR_EXT <= x"E5") or   -- FPU register transfers
                               (IR_EXT >= x"CB" and IR_EXT <= x"CF") or   -- FPU reserved (single)
                               (IR_EXT >= x"DB" and IR_EXT <= x"DF")) and -- FPU reserved (double)
                              is_fpu_ext = '0' then
                            -- FPU instructions need register byte
                            is_fpu_ext <= '1';
                            fpu_reg_byte <= DATA_IN;
                            state <= ST_DECODE;
                        else
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
                            elsif IS_REGALU = '1' then
                                -- Register-targeted ALU: next byte is dest_dp
                                -- Fetch destination DP address
                                regalu_phase <= "00";
                                state <= ST_ADDR1;
                                data_byte_count <= (others => '0');
                            elsif ext_fpu = '1' or ext_fpu_xfer = '1' then
                                -- FPU arithmetic or register transfer ops
                                state <= ST_EXECUTE;
                            elsif fpu_indirect = '1' then
                                -- FPU register-indirect load/store (address from Rm)
                                eff_addr <= rw_data1;
                                data_byte_count <= (others => '0');
                                ldq_high_phase <= '0';
                                if ext_ldf = '1' or ext_ldf_s = '1' then
                                    state <= ST_READ;
                                else
                                    state <= ST_WRITE;
                                end if;
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
                        
                        -- Register-targeted ALU special handling
                        if IS_REGALU = '1' then
                            if regalu_phase = "00" then
                                -- Phase 0: This byte is dest_dp
                                regalu_dest_addr <= D_reg(31 downto 8) & DATA_IN;
                                
                                -- For source = A/X/Y, we can go directly to read dest + execute
                                if REGALU_SRC_MODE = REGALU_SRC_A or REGALU_SRC_MODE = REGALU_SRC_X or REGALU_SRC_MODE = REGALU_SRC_Y then
                                    -- Source is A/X/Y - read dest value, then execute
                                    if R_mode = '1' then
                                        -- Register window: read dest directly
                                        regalu_dest_data <= rw_data1;
                                        if REGALU_SRC_MODE = REGALU_SRC_X then
                                            regalu_src_data <= X_reg;
                                        elsif REGALU_SRC_MODE = REGALU_SRC_Y then
                                            regalu_src_data <= Y_reg;
                                        else
                                            regalu_src_data <= A_reg;
                                        end if;
                                        state <= ST_EXECUTE;
                                    else
                                        -- Memory: need to read dest
                                        regalu_phase <= "10";
                                        eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                        state <= ST_READ;
                                    end if;
                                else
                                    -- Source is not A - need to fetch source address
                                    regalu_phase <= "01";
                                    state <= ST_ADDR2;
                                end if;
                            elsif regalu_phase = "01" then
                                -- Phase 1: This byte is source address (for dp modes)
                                if REGALU_SRC_MODE = "0001" or REGALU_SRC_MODE = "0101" then
                                    -- dp or dp,X source mode
                                    if REGALU_SRC_MODE = "0101" then
                                        eff_addr <= D_reg(31 downto 8) &
                                                    std_logic_vector(unsigned(DATA_IN) + unsigned(X_reg(7 downto 0)));
                                    else
                                        eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                    end if;
                                    
                                    if R_mode = '1' then
                                        -- Register window: read both source and dest directly
                                        regalu_src_data <= rw_data1;
                                        -- Dest was already loaded in phase 0
                                        state <= ST_EXECUTE;
                                    else
                                        -- Memory: read source first
                                        regalu_phase <= "11";
                                        state <= ST_READ;
                                    end if;
                                elsif REGALU_SRC_MODE = "0110" or REGALU_SRC_MODE = "0111" or REGALU_SRC_MODE = "1000" then
                                    -- abs, abs,X, abs,Y - need second byte
                                    state <= ST_ADDR2;
                                else
                                    -- Other modes (indirect, etc.) - simplified for now
                                    state <= ST_READ;
                                end if;
                            end if;
                        elsif IS_SHIFTER = '1' or IS_EXTEND = '1' then
                            -- Shifter/Extend: $02 $E9/$EA [op|cnt] [dest_dp] [src_dp]
                            if regalu_phase = "00" then
                                -- Phase 0: This byte is dest_dp
                                regalu_dest_addr <= D_reg(31 downto 8) & DATA_IN;
                                regalu_phase <= "01";
                                state <= ST_ADDR2;
                            elsif regalu_phase = "01" then
                                -- Phase 1: This byte is src_dp
                                eff_addr <= D_reg(31 downto 8) & DATA_IN;
                                
                                if R_mode = '1' then
                                    -- Register window: read source directly
                                    shifter_src_data <= rw_data1;
                                    extend_src_data <= rw_data1;
                                    state <= ST_EXECUTE;
                                else
                                    -- Memory: read source
                                    regalu_phase <= "11";
                                    state <= ST_READ;
                                end if;
                            end if;
                        else
                        
                        case ADDR_MODE is
                            when "0010" | "0011" | "0100" =>
                                -- Direct page modes - done after 1 byte
                                -- Effective address = D + offset (with index if needed)
                                if ADDR_MODE = "0011" then
                                    -- Register window ignores D_reg; use offset + X low byte
                                    dp_reg_index <= dp_reg_index_next;
                                    dp_byte_sel_reg <= dp_byte_sel_next;
                                    eff_addr <= D_reg(31 downto 8) &
                                                std_logic_vector(unsigned(DATA_IN) + unsigned(X_reg(7 downto 0)));
                                elsif ADDR_MODE = "0100" then
                                    -- Register window ignores D_reg; use offset + Y low byte
                                    dp_reg_index <= dp_reg_index_next;
                                    dp_byte_sel_reg <= dp_byte_sel_next;
                                    eff_addr <= D_reg(31 downto 8) &
                                                std_logic_vector(unsigned(DATA_IN) + unsigned(Y_reg(7 downto 0)));
                                else
                                    -- Register window ignores D_reg; use offset
                                    dp_reg_index <= dp_reg_index_next;
                                    dp_byte_sel_reg <= dp_byte_sel_next;
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
                                elsif ext_stq = '1' or ext_stf = '1' or ext_stf_s = '1' then
                                    data_byte_count <= (others => '0');
                                    ldq_high_phase <= '0';
                                    state <= ST_WRITE;
                                elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                    -- STX/STY
                                    state <= ST_WRITE;
                                else
                                    if ext_ldq = '1' or ext_ldf = '1' or ext_ldf_s = '1' then
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
                        end if;  -- IS_REGALU else branch
                        
                    when ST_ADDR2 =>
                        -- Handle shifter/extend src_dp in phase 01
                        if (IS_SHIFTER = '1' or IS_EXTEND = '1') and regalu_phase = "01" then
                            -- This byte is src_dp
                            eff_addr <= D_reg(31 downto 8) & DATA_IN;
                            
                            if R_mode = '1' then
                                -- Register window: read source directly
                                -- rw_addr1 should be set combinationally based on DATA_IN
                                shifter_src_data <= rw_data1;
                                extend_src_data <= rw_data1;
                                state <= ST_EXECUTE;
                            else
                                -- Memory: read source
                                regalu_phase <= "11";
                                state <= ST_READ;
                            end if;
                        else
                        -- Second address byte
                        data_buffer(15 downto 8) <= DATA_IN;
                        -- Extended ALU 32-bit absolute addressing
                        if ext_addr32 = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
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
                        
                        if ext_addr32 = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
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
                                    elsif ext_stq = '1' or ext_stf = '1' or ext_stf_s = '1' then
                                        data_byte_count <= (others => '0');
                                        state <= ST_WRITE;
                                    elsif IS_RMW_OP = '1' and RMW_OP = "100" then
                                        state <= ST_WRITE;
                                    else
                                        if ext_ldq = '1' or ext_ldf = '1' or ext_ldf_s = '1' then
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
                        end if;  -- shifter/extend else branch
                        
                    when ST_ADDR3 =>
                        if IS_JMP_d = '1' and ADDR_MODE = "1001" then
                            -- JMP (abs,X): pointer low byte
                            DR <= DATA_IN;
                            state <= ST_ADDR4;
                        elsif ext_addr32 = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
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
                        if ext_addr32 = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
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
                        if ext_addr32 = '1' and (ADDR_MODE = "0101" or ADDR_MODE = "0110" or ADDR_MODE = "0111") then
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
                            elsif ext_stq = '1' or ext_stf = '1' or ext_stf_s = '1' then
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
                        elsif IS_REGALU = '1' then
                            -- Register-targeted ALU: write result to destination
                            -- Result is computed in regalu_result (combinational)
                            if R_mode = '1' then
                                -- Register window write - happens via separate process
                                state <= ST_FETCH;
                            else
                                -- Memory write
                                eff_addr <= regalu_dest_addr;
                                state <= ST_WRITE;
                                data_byte_count <= (others => '0');
                            end if;
                        elsif IS_SHIFTER = '1' then
                            -- Shifter: write result to destination (flags updated via flag logic)
                            if R_mode = '1' then
                                state <= ST_FETCH;
                            else
                                eff_addr <= regalu_dest_addr;
                                state <= ST_WRITE;
                                data_byte_count <= (others => '0');
                            end if;
                        elsif IS_EXTEND = '1' then
                            -- Extend: write result to destination
                            -- Flags updated via flag logic
                            if R_mode = '1' then
                                state <= ST_FETCH;
                            else
                                eff_addr <= regalu_dest_addr;
                                state <= ST_WRITE;
                                data_byte_count <= (others => '0');
                            end if;
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
                        -- Fetch low offset byte
                        if branch_wide = '1' then
                            state <= ST_BRANCH2;
                        else
                            state <= ST_BRANCH3;
                        end if;
                        
                    when ST_BRANCH2 =>
                        -- Fetch high offset byte
                        data_buffer(15 downto 8) <= DATA_IN;
                        state <= ST_BRANCH3;
                        
                    when ST_BRANCH3 =>
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
                            data_byte_count <= (others => '0');
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
            when ST_FETCH | ST_DECODE | ST_BRANCH | ST_BRANCH2 =>
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

    mmio_addr_read <= ADDR;
    mmio_addr_read_lo <= ADDR(15 downto 0);
    
    process(state, ADDR_MODE, mmio_addr_read, mmu_mmucr, mmu_asid, mmu_faultva, mmu_ptbr, mmu_tlbinval, mmu_asid_inval,
            timer_ctrl, timer_cmp, timer_count, timer_count_latched, timer_latched_valid)
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
                    if timer_latched_valid = '1' then
                        mmio_read_data <= timer_count_latched(7 downto 0);
                    elsif timer_cmp /= x"00000000" then
                        mmio_read_data <= timer_cmp(7 downto 0);
                    else
                        mmio_read_data <= timer_count(7 downto 0);
                    end if;
                when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 1) =>
                    mmio_read_hit <= '1';
                    if timer_latched_valid = '1' then
                        mmio_read_data <= timer_count_latched(15 downto 8);
                    elsif timer_cmp /= x"00000000" then
                        mmio_read_data <= timer_cmp(15 downto 8);
                    else
                        mmio_read_data <= timer_count(15 downto 8);
                    end if;
                when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 2) =>
                    mmio_read_hit <= '1';
                    if timer_latched_valid = '1' then
                        mmio_read_data <= timer_count_latched(23 downto 16);
                    elsif timer_cmp /= x"00000000" then
                        mmio_read_data <= timer_cmp(23 downto 16);
                    else
                        mmio_read_data <= timer_count(23 downto 16);
                    end if;
                when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 3) =>
                    mmio_read_hit <= '1';
                    if timer_latched_valid = '1' then
                        mmio_read_data <= timer_count_latched(31 downto 24);
                    elsif timer_cmp /= x"00000000" then
                        mmio_read_data <= timer_cmp(31 downto 24);
                    else
                        mmio_read_data <= timer_count(31 downto 24);
                    end if;
                
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
    process(state, data_byte_count, A_reg, X_reg, Y_reg, T_reg, fp_regs, fpu_reg_byte, fpu_mem_reg,
            IS_ALU_OP, IS_RMW_OP, ALU_OP, RMW_OP, REG_SRC, ALU_RES, stack_write_reg_eff, stack_width_eff,
            ext_stq, ext_stf, ext_stf_s)
        variable write_reg : std_logic_vector(31 downto 0);
        variable f_reg     : std_logic_vector(63 downto 0);
    begin
        -- For STF, select the correct F register based on addressing mode
        f_reg := fp_regs(to_integer(fpu_mem_reg));
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
        elsif ext_stf_s = '1' then
            case data_byte_count(1 downto 0) is
                when "00" => DATA_OUT <= f_reg(7 downto 0);
                when "01" => DATA_OUT <= f_reg(15 downto 8);
                when "10" => DATA_OUT <= f_reg(23 downto 16);
                when others => DATA_OUT <= f_reg(31 downto 24);
            end case;
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
    
    mmio_addr_write <= ADDR;
    mmio_addr_write_lo <= ADDR(15 downto 0);
    
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
            timer_count_latched <= (others => '0');
            timer_latched_valid <= '0';
            timer_pending <= '0';
        elsif rising_edge(CLK) then
            if CE = '1' then
                if mmu_page_fault = '1' then
                    mmu_faultva <= mmu_fault_va;
                    mmu_mmucr(4 downto 2) <= mmu_fault_type;
                end if;

                if timer_ctrl(0) = '1' then
                    if timer_ctrl(2) = '1' and timer_pending = '0' and
                       (timer_ctrl(1) = '1' or timer_latched_valid = '0') and
                       timer_cmp /= x"00000000" and unsigned(timer_count) >= unsigned(timer_cmp) then
                        timer_pending <= '1';
                        timer_count_latched <= timer_cmp;
                        timer_latched_valid <= '1';
                        if timer_ctrl(1) = '1' then
                            timer_count <= (others => '0');
                        end if;
                    elsif timer_pending = '0' or timer_ctrl(1) = '1' then
                        timer_count <= std_logic_vector(unsigned(timer_count) + 1);
                    end if;
                end if;

                if timer_pending = '1' and timer_latched_valid = '0' then
                    timer_count_latched <= timer_cmp;
                    timer_latched_valid <= '1';
                end if;

                if mem_ready = '1' then
                    mmu_tlb_flush <= '0';
                    mmu_tlb_flush_asid <= '0';
                    mmu_tlb_flush_va <= '0';
                end if;

                if (state = ST_WRITE or state = ST_WRITE2 or state = ST_WRITE3 or state = ST_WRITE4) and
                   priv_mmio = '0' then
                    if mmio_addr_write_lo = MMIO_TIMER_CTRL(15 downto 0) or
                       mmio_addr_write_lo = MMIO_TIMER_CMP(15 downto 0) or
                       mmio_addr_write_lo = std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 1) or
                       mmio_addr_write_lo = std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 2) or
                       mmio_addr_write_lo = std_logic_vector(unsigned(MMIO_TIMER_CMP(15 downto 0)) + 3) or
                       mmio_addr_write_lo = MMIO_TIMER_COUNT(15 downto 0) or
                       mmio_addr_write_lo = std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 1) or
                       mmio_addr_write_lo = std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 2) or
                       mmio_addr_write_lo = std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 3) then
                        case mmio_addr_write_lo is
                        when MMIO_TIMER_CTRL(15 downto 0) =>
                            timer_ctrl(2 downto 0) <= DATA_OUT(2 downto 0);
                            if DATA_OUT(3) = '1' then
                                timer_pending <= '0';
                                timer_count <= (others => '0');
                                timer_count_latched <= timer_cmp;
                                timer_latched_valid <= '1';
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
                            timer_count_latched(7 downto 0) <= DATA_OUT;
                            timer_latched_valid <= '0';
                        when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 1) =>
                            timer_count(15 downto 8) <= DATA_OUT;
                            timer_count_latched(15 downto 8) <= DATA_OUT;
                            timer_latched_valid <= '0';
                        when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 2) =>
                            timer_count(23 downto 16) <= DATA_OUT;
                            timer_count_latched(23 downto 16) <= DATA_OUT;
                            timer_latched_valid <= '0';
                        when std_logic_vector(unsigned(MMIO_TIMER_COUNT(15 downto 0)) + 3) =>
                            timer_count(31 downto 24) <= DATA_OUT;
                            timer_count_latched(31 downto 24) <= DATA_OUT;
                            timer_latched_valid <= '0';
                        when others =>
                            null;
                        end case;
                    elsif S_mode = '1' then
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

                        when others =>
                            null;
                    end case;
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
    
    alu_width_eff <= X_width_eff when (IS_ALU_OP = '1' and ALU_OP = "110" and
                                   (REG_SRC = "001" or REG_SRC = "010"))
                     else M_width_eff;
    
    ALU_WIDTH <= alu_width_eff;
    ALU_BCD <= P_reg(P_D);
    ALU_CI <= P_reg(P_C);
    ALU_VI <= P_reg(P_V);
    ALU_SI <= P_reg(P_N);
    
    exec_result <= ext_result when ext_result_valid = '1' else ALU_RES;
    
    process(ext_mul, ext_mulu, ext_div, ext_divu, ext_lea, M_width_eff, A_reg, data_buffer, eff_addr)
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
            if M_width_eff = WIDTH_8 then
                a_s32 := resize(signed(A_reg(7 downto 0)), 32);
                b_s32 := resize(signed(data_buffer(7 downto 0)), 32);
                ext_result <= std_logic_vector(resize(a_s32 * b_s32, 32));
            elsif M_width_eff = WIDTH_16 then
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
            if M_width_eff = WIDTH_8 then
                a_u32 := resize(unsigned(A_reg(7 downto 0)), 32);
                b_u32 := resize(unsigned(data_buffer(7 downto 0)), 32);
                ext_result <= std_logic_vector(resize(a_u32 * b_u32, 32));
            elsif M_width_eff = WIDTH_16 then
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
            if M_width_eff = WIDTH_8 then
                a_s32 := resize(signed(A_reg(7 downto 0)), 32);
                b_s32 := resize(signed(data_buffer(7 downto 0)), 32);
            elsif M_width_eff = WIDTH_16 then
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
            if M_width_eff = WIDTH_8 then
                a_u32 := resize(unsigned(A_reg(7 downto 0)), 32);
                b_u32 := resize(unsigned(data_buffer(7 downto 0)), 32);
            elsif M_width_eff = WIDTH_16 then
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
    -- Register-Targeted ALU Result Computation
    ---------------------------------------------------------------------------
    
    process(IS_REGALU, REGALU_OP, regalu_dest_data, regalu_src_data, P_reg, M_width_eff)
        variable dest_v, src_v, result_v : unsigned(31 downto 0);
        variable carry_in : unsigned(0 downto 0);
        variable sum_v    : unsigned(32 downto 0);
    begin
        regalu_result <= (others => '0');
        dest_v := unsigned(regalu_dest_data);
        src_v := unsigned(regalu_src_data);
        carry_in(0) := P_reg(P_C);
        
        if IS_REGALU = '1' then
            case REGALU_OP is
                when "0000" =>  -- LD: result = source
                    regalu_result <= regalu_src_data;
                    
                when "0001" =>  -- ADC: dest + src + C
                    sum_v := resize(dest_v, 33) + resize(src_v, 33) + resize(carry_in, 33);
                    regalu_result <= std_logic_vector(sum_v(31 downto 0));
                    
                when "0010" =>  -- SBC: dest - src - !C
                    if P_reg(P_C) = '1' then
                        sum_v := resize(dest_v, 33) - resize(src_v, 33);
                    else
                        sum_v := resize(dest_v, 33) - resize(src_v, 33) - 1;
                    end if;
                    regalu_result <= std_logic_vector(sum_v(31 downto 0));
                    
                when "0011" =>  -- AND: dest & src
                    regalu_result <= regalu_dest_data and regalu_src_data;
                    
                when "0100" =>  -- ORA: dest | src
                    regalu_result <= regalu_dest_data or regalu_src_data;
                    
                when "0101" =>  -- EOR: dest ^ src
                    regalu_result <= regalu_dest_data xor regalu_src_data;
                    
                when "0110" =>  -- CMP: compare only, result = dest (no change)
                    regalu_result <= regalu_dest_data;
                    
                when others =>
                    regalu_result <= regalu_dest_data;
            end case;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Shifter Result Computation ($02 $98)
    ---------------------------------------------------------------------------
    
    process(IS_SHIFTER, SHIFT_OP, SHIFT_COUNT, shifter_src_data, A_reg, P_reg)
        variable src_v      : unsigned(31 downto 0);
        variable shift_amt  : integer range 0 to 31;
        variable result_v   : unsigned(31 downto 0);
        variable carry_v    : std_logic;
        variable extended   : unsigned(32 downto 0);
    begin
        shifter_result <= (others => '0');
        shifter_carry <= '0';
        
        if IS_SHIFTER = '1' then
            src_v := unsigned(shifter_src_data);
            
            -- Determine shift amount: immediate or from A (low 5 bits)
            if SHIFT_COUNT = "11111" then
                shift_amt := to_integer(unsigned(A_reg(4 downto 0)));
            else
                shift_amt := to_integer(unsigned(SHIFT_COUNT));
            end if;
            
            case SHIFT_OP is
                when "000" =>  -- SHL: Shift left logical
                    if shift_amt = 0 then
                        result_v := src_v;
                        carry_v := P_reg(P_C);
                    elsif shift_amt < 32 then
                        result_v := shift_left(src_v, shift_amt);
                        carry_v := src_v(32 - shift_amt);
                    else
                        result_v := (others => '0');
                        carry_v := '0';
                    end if;
                    
                when "001" =>  -- SHR: Shift right logical
                    if shift_amt = 0 then
                        result_v := src_v;
                        carry_v := P_reg(P_C);
                    elsif shift_amt < 32 then
                        result_v := shift_right(src_v, shift_amt);
                        carry_v := src_v(shift_amt - 1);
                    else
                        result_v := (others => '0');
                        carry_v := '0';
                    end if;
                    
                when "010" =>  -- SAR: Shift right arithmetic
                    if shift_amt = 0 then
                        result_v := src_v;
                        carry_v := P_reg(P_C);
                    elsif shift_amt < 32 then
                        result_v := unsigned(shift_right(signed(src_v), shift_amt));
                        carry_v := src_v(shift_amt - 1);
                    else
                        -- All sign bits
                        if src_v(31) = '1' then
                            result_v := (others => '1');
                        else
                            result_v := (others => '0');
                        end if;
                        carry_v := src_v(31);
                    end if;
                    
                when "011" =>  -- ROL: Rotate left through carry
                    if shift_amt = 0 then
                        result_v := src_v;
                        carry_v := P_reg(P_C);
                    else
                        -- For each bit rotated, carry goes into LSB, MSB goes into carry
                        extended := src_v & P_reg(P_C);
                        for i in 1 to shift_amt loop
                            extended := extended(31 downto 0) & extended(32);
                        end loop;
                        result_v := extended(31 downto 0);
                        carry_v := extended(32);
                    end if;
                    
                when "100" =>  -- ROR: Rotate right through carry
                    if shift_amt = 0 then
                        result_v := src_v;
                        carry_v := P_reg(P_C);
                    else
                        -- For each bit rotated, carry goes into MSB, LSB goes into carry
                        extended := P_reg(P_C) & src_v;
                        for i in 1 to shift_amt loop
                            extended := extended(0) & extended(32 downto 1);
                        end loop;
                        result_v := extended(31 downto 0);
                        carry_v := extended(32);
                    end if;
                    
                when others =>
                    result_v := src_v;
                    carry_v := P_reg(P_C);
            end case;
            
            shifter_result <= std_logic_vector(result_v);
            shifter_carry <= carry_v;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Extend Result Computation ($02 $EA)
    ---------------------------------------------------------------------------
    
    process(IS_EXTEND, EXTEND_OP, extend_src_data)
        variable src_v    : std_logic_vector(31 downto 0);
        variable result_v : std_logic_vector(31 downto 0);
        
        -- CLZ binary search variables (5 levels for 32 bits)
        variable clz_v    : std_logic_vector(31 downto 0);
        variable clz_cnt  : unsigned(5 downto 0);
        
        -- CTZ binary search variables
        variable ctz_v    : std_logic_vector(31 downto 0);
        variable ctz_cnt  : unsigned(5 downto 0);
        
        -- POPCNT adder tree variables
        variable p2  : unsigned(1 downto 0);   -- 2-bit partial sums (16 of them)
        variable p3  : unsigned(2 downto 0);   -- 3-bit partial sums (8 of them)
        variable p4  : unsigned(3 downto 0);   -- 4-bit partial sums (4 of them)
        variable p5  : unsigned(4 downto 0);   -- 5-bit partial sums (2 of them)
        variable pop : unsigned(5 downto 0);   -- Final 6-bit sum
        
        -- Arrays for adder tree
        type arr2_t is array(0 to 15) of unsigned(1 downto 0);
        type arr3_t is array(0 to 7) of unsigned(2 downto 0);
        type arr4_t is array(0 to 3) of unsigned(3 downto 0);
        type arr5_t is array(0 to 1) of unsigned(4 downto 0);
        variable a2 : arr2_t;
        variable a3 : arr3_t;
        variable a4 : arr4_t;
        variable a5 : arr5_t;
    begin
        extend_result <= (others => '0');
        
        if IS_EXTEND = '1' then
            src_v := extend_src_data;
            
            case EXTEND_OP is
                when "0000" =>  -- SEXT8: Sign extend 8->32
                    if src_v(7) = '1' then
                        result_v := x"FFFFFF" & src_v(7 downto 0);
                    else
                        result_v := x"000000" & src_v(7 downto 0);
                    end if;
                    
                when "0001" =>  -- SEXT16: Sign extend 16->32
                    if src_v(15) = '1' then
                        result_v := x"FFFF" & src_v(15 downto 0);
                    else
                        result_v := x"0000" & src_v(15 downto 0);
                    end if;
                    
                when "0010" =>  -- ZEXT8: Zero extend 8->32
                    result_v := x"000000" & src_v(7 downto 0);
                    
                when "0011" =>  -- ZEXT16: Zero extend 16->32
                    result_v := x"0000" & src_v(15 downto 0);
                    
                when "0100" =>  -- CLZ: Count leading zeros (binary search, 5 levels)
                    clz_cnt := (others => '0');
                    clz_v := src_v;
                    
                    -- Level 1: Check upper 16 bits
                    if clz_v(31 downto 16) = x"0000" then
                        clz_cnt(4) := '1';
                        clz_v := clz_v(15 downto 0) & x"0000";
                    end if;
                    
                    -- Level 2: Check upper 8 bits
                    if clz_v(31 downto 24) = x"00" then
                        clz_cnt(3) := '1';
                        clz_v := clz_v(23 downto 0) & x"00";
                    end if;
                    
                    -- Level 3: Check upper 4 bits
                    if clz_v(31 downto 28) = "0000" then
                        clz_cnt(2) := '1';
                        clz_v := clz_v(27 downto 0) & "0000";
                    end if;
                    
                    -- Level 4: Check upper 2 bits
                    if clz_v(31 downto 30) = "00" then
                        clz_cnt(1) := '1';
                        clz_v := clz_v(29 downto 0) & "00";
                    end if;
                    
                    -- Level 5: Check top bit
                    if clz_v(31) = '0' then
                        clz_cnt(0) := '1';
                    end if;
                    
                    result_v := std_logic_vector(resize(clz_cnt, 32));
                    
                when "0101" =>  -- CTZ: Count trailing zeros (binary search, 5 levels)
                    ctz_cnt := (others => '0');
                    ctz_v := src_v;
                    
                    -- Level 1: Check lower 16 bits
                    if ctz_v(15 downto 0) = x"0000" then
                        ctz_cnt(4) := '1';
                        ctz_v := x"0000" & ctz_v(31 downto 16);
                    end if;
                    
                    -- Level 2: Check lower 8 bits
                    if ctz_v(7 downto 0) = x"00" then
                        ctz_cnt(3) := '1';
                        ctz_v := x"00" & ctz_v(31 downto 8);
                    end if;
                    
                    -- Level 3: Check lower 4 bits
                    if ctz_v(3 downto 0) = "0000" then
                        ctz_cnt(2) := '1';
                        ctz_v := "0000" & ctz_v(31 downto 4);
                    end if;
                    
                    -- Level 4: Check lower 2 bits
                    if ctz_v(1 downto 0) = "00" then
                        ctz_cnt(1) := '1';
                        ctz_v := "00" & ctz_v(31 downto 2);
                    end if;
                    
                    -- Level 5: Check bottom bit
                    if ctz_v(0) = '0' then
                        ctz_cnt(0) := '1';
                    end if;
                    
                    result_v := std_logic_vector(resize(ctz_cnt, 32));
                    
                when "0110" =>  -- POPCNT: Population count (adder tree, 5 levels)
                    -- Level 1: Add pairs of bits -> 16 x 2-bit sums
                    a2(0)  := unsigned'("0" & src_v(1))   + unsigned'("0" & src_v(0));
                    a2(1)  := unsigned'("0" & src_v(3))   + unsigned'("0" & src_v(2));
                    a2(2)  := unsigned'("0" & src_v(5))   + unsigned'("0" & src_v(4));
                    a2(3)  := unsigned'("0" & src_v(7))   + unsigned'("0" & src_v(6));
                    a2(4)  := unsigned'("0" & src_v(9))   + unsigned'("0" & src_v(8));
                    a2(5)  := unsigned'("0" & src_v(11))  + unsigned'("0" & src_v(10));
                    a2(6)  := unsigned'("0" & src_v(13))  + unsigned'("0" & src_v(12));
                    a2(7)  := unsigned'("0" & src_v(15))  + unsigned'("0" & src_v(14));
                    a2(8)  := unsigned'("0" & src_v(17))  + unsigned'("0" & src_v(16));
                    a2(9)  := unsigned'("0" & src_v(19))  + unsigned'("0" & src_v(18));
                    a2(10) := unsigned'("0" & src_v(21))  + unsigned'("0" & src_v(20));
                    a2(11) := unsigned'("0" & src_v(23))  + unsigned'("0" & src_v(22));
                    a2(12) := unsigned'("0" & src_v(25))  + unsigned'("0" & src_v(24));
                    a2(13) := unsigned'("0" & src_v(27))  + unsigned'("0" & src_v(26));
                    a2(14) := unsigned'("0" & src_v(29))  + unsigned'("0" & src_v(28));
                    a2(15) := unsigned'("0" & src_v(31))  + unsigned'("0" & src_v(30));
                    
                    -- Level 2: Add pairs of 2-bit sums -> 8 x 3-bit sums
                    a3(0) := ("0" & a2(0))  + ("0" & a2(1));
                    a3(1) := ("0" & a2(2))  + ("0" & a2(3));
                    a3(2) := ("0" & a2(4))  + ("0" & a2(5));
                    a3(3) := ("0" & a2(6))  + ("0" & a2(7));
                    a3(4) := ("0" & a2(8))  + ("0" & a2(9));
                    a3(5) := ("0" & a2(10)) + ("0" & a2(11));
                    a3(6) := ("0" & a2(12)) + ("0" & a2(13));
                    a3(7) := ("0" & a2(14)) + ("0" & a2(15));
                    
                    -- Level 3: Add pairs of 3-bit sums -> 4 x 4-bit sums
                    a4(0) := ("0" & a3(0)) + ("0" & a3(1));
                    a4(1) := ("0" & a3(2)) + ("0" & a3(3));
                    a4(2) := ("0" & a3(4)) + ("0" & a3(5));
                    a4(3) := ("0" & a3(6)) + ("0" & a3(7));
                    
                    -- Level 4: Add pairs of 4-bit sums -> 2 x 5-bit sums
                    a5(0) := ("0" & a4(0)) + ("0" & a4(1));
                    a5(1) := ("0" & a4(2)) + ("0" & a4(3));
                    
                    -- Level 5: Final sum -> 6-bit result (0-32)
                    pop := ("0" & a5(0)) + ("0" & a5(1));
                    
                    result_v := std_logic_vector(resize(pop, 32));
                    
                when others =>
                    result_v := src_v;
            end case;
            
            extend_result <= result_v;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- FPU Coprocessor Operations (F0-F15, two-operand destructive)
    -- Format: Fd = Fd op Fs (binary) or Fd = op(Fs) (unary)
    -- fpu_dest = destination register (from high nibble of reg byte)
    -- fpu_src  = source register (from low nibble of reg byte)
    ---------------------------------------------------------------------------

    process(IR_EXT, ext_fpu, ext_fpu_xfer, fp_regs, fpu_dest, fpu_src, A_reg, T_reg)
        variable fd_s, fs_s : float32;
        variable fd_d, fs_d : float64;
        variable s_res      : float32;
        variable d_res      : float64;
        variable int32_res  : signed(31 downto 0);
        variable a_int      : integer;
        variable s_bits     : std_logic_vector(31 downto 0);
        variable d_bits     : std_logic_vector(63 downto 0);
        variable fd_reg     : std_logic_vector(63 downto 0);
        variable fs_reg     : std_logic_vector(63 downto 0);
    begin
        fpu_result     <= (others => '0');
        fpu_int_result <= (others => '0');
        fpu_write_fd   <= '0';
        fpu_write_a    <= '0';
        fpu_flag_load  <= '0';
        fpu_flag_c_load <= '0';
        fpu_flag_z     <= '0';
        fpu_flag_n     <= '0';
        fpu_flag_v     <= '0';
        fpu_flag_c     <= '0';

        -- Get source and destination registers
        fd_reg := fp_regs(to_integer(fpu_dest));
        fs_reg := fp_regs(to_integer(fpu_src));

        if ext_fpu = '1' then
            -- Single-precision operations ($C0-$CA)
            if IR_EXT(7 downto 4) = x"C" then
                fd_s := to_float(fd_reg(31 downto 0), 8, 23);
                fs_s := to_float(fs_reg(31 downto 0), 8, 23);
                case IR_EXT is
                    when x"C0" => s_res := fd_s + fs_s;  -- FADD.S Fd, Fs
                    when x"C1" => s_res := fd_s - fs_s;  -- FSUB.S Fd, Fs
                    when x"C2" => s_res := fd_s * fs_s;  -- FMUL.S Fd, Fs
                    when x"C3" => s_res := fd_s / fs_s;  -- FDIV.S Fd, Fs
                    when x"C4" => s_res := -fs_s;        -- FNEG.S Fd, Fs
                    when x"C5" => s_res := abs(fs_s);    -- FABS.S Fd, Fs
                    when x"C6" =>                        -- FCMP.S Fd, Fs
                        null;
                    when x"C7" =>                        -- F2I.S Fd
                        int32_res := to_signed(to_integer(fd_s, IEEE.fixed_float_types.round_zero), 32);
                        fpu_int_result <= std_logic_vector(int32_res);
                        fpu_write_a <= '1';
                    when x"C8" =>                        -- I2F.S Fd
                        a_int := to_integer(signed(A_reg));
                        s_res := to_float(a_int, 8, 23);
                    when x"C9" => s_res := fs_s;         -- FMOV.S Fd, Fs
                    when x"CA" => s_res := sqrt(fs_s);   -- FSQRT.S Fd, Fs
                    when others => null;
                end case;

                if IR_EXT /= x"C6" and IR_EXT /= x"C7" then
                    s_bits := to_slv(s_res);
                    fpu_result(31 downto 0) <= s_bits;
                    fpu_write_fd <= '1';
                end if;

            -- Double-precision operations ($D0-$DA)
            elsif IR_EXT(7 downto 4) = x"D" then
                fd_d := to_float(fd_reg, 11, 52);
                fs_d := to_float(fs_reg, 11, 52);
                case IR_EXT is
                    when x"D0" => d_res := fd_d + fs_d;  -- FADD.D Fd, Fs
                    when x"D1" => d_res := fd_d - fs_d;  -- FSUB.D Fd, Fs
                    when x"D2" => d_res := fd_d * fs_d;  -- FMUL.D Fd, Fs
                    when x"D3" => d_res := fd_d / fs_d;  -- FDIV.D Fd, Fs
                    when x"D4" => d_res := -fs_d;        -- FNEG.D Fd, Fs
                    when x"D5" => d_res := abs(fs_d);    -- FABS.D Fd, Fs
                    when x"D6" =>                        -- FCMP.D Fd, Fs
                        null;
                    when x"D7" =>                        -- F2I.D Fd
                        int32_res := to_signed(to_integer(fd_d, IEEE.fixed_float_types.round_zero), 32);
                        fpu_int_result <= std_logic_vector(int32_res);
                        fpu_write_a <= '1';
                    when x"D8" =>                        -- I2F.D Fd
                        a_int := to_integer(signed(A_reg));
                        d_res := to_float(a_int, 11, 52);
                    when x"D9" => d_res := fs_d;         -- FMOV.D Fd, Fs
                    when x"DA" => d_res := sqrt(fs_d);   -- FSQRT.D Fd, Fs
                    when others => null;
                end case;

                if IR_EXT /= x"D6" and IR_EXT /= x"D7" then
                    d_bits := to_slv(d_res);
                    fpu_result <= d_bits;
                    fpu_write_fd <= '1';
                end if;
            end if;
        elsif ext_fpu_xfer = '1' then
            -- FPU register transfer operations ($E0-$E5)
            case IR_EXT is
                when x"E0" =>                            -- FTOA Fd: A = Fd[31:0]
                    fpu_int_result <= fd_reg(31 downto 0);
                    fpu_write_a <= '1';
                when x"E1" =>                            -- FTOT Fd: T = Fd[63:32]
                    -- T register write handled separately
                    null;
                when x"E2" =>                            -- ATOF Fd: Fd[31:0] = A
                    fpu_result(31 downto 0) <= A_reg;
                    fpu_result(63 downto 32) <= fd_reg(63 downto 32);
                    fpu_write_fd <= '1';
                when x"E3" =>                            -- TTOF Fd: Fd[63:32] = T
                    fpu_result(31 downto 0) <= fd_reg(31 downto 0);
                    fpu_result(63 downto 32) <= T_reg;
                    fpu_write_fd <= '1';
                when x"E4" =>                            -- FCVT.DS Fd, Fs: double = (double)single
                    fs_s := to_float(fs_reg(31 downto 0), 8, 23);
                    d_res := resize(fs_s, 11, 52);
                    fpu_result <= to_slv(d_res);
                    fpu_write_fd <= '1';
                when x"E5" =>                            -- FCVT.SD Fd, Fs: single = (single)double
                    fs_d := to_float(fs_reg, 11, 52);
                    s_res := resize(fs_d, 8, 23);
                    fpu_result(31 downto 0) <= to_slv(s_res);
                    fpu_write_fd <= '1';
                when others => null;
            end case;
        end if;
    end process;

    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            -- Reset all 16 FP registers
            for i in 0 to 15 loop
                fp_regs(i) <= (others => '0');
            end loop;
        elsif rising_edge(CLK) then
            if CE = '1' and mem_ready = '1' then
                if state = ST_EXECUTE then
                    if ext_ldf = '1' then
                        -- Load to register specified by fpu_reg_byte (mode-dependent)
                        fp_regs(to_integer(fpu_mem_reg)) <= ldq_high_buffer & ldq_low_buffer;
                    elsif ext_ldf_s = '1' then
                        fp_regs(to_integer(fpu_mem_reg)) <= x"00000000" & data_buffer;
                    elsif fpu_write_fd = '1' then
                        -- Write result to destination register
                        fp_regs(to_integer(fpu_dest)) <= fpu_result;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    process(ext_result, ext_result_valid, ext_lea, ext_mul, ext_mulu, ext_div, ext_divu, ext_lli, ext_tta, T_reg,
            stack_is_pull, IR, data_buffer, M_width_eff, X_width_eff, IS_SHIFTER, shifter_result, IS_EXTEND, extend_result)
        variable value32 : std_logic_vector(31 downto 0);
        variable width_sel : std_logic_vector(1 downto 0);
    begin
        ext_flag_load <= '0';
        ext_flag_z <= '0';
        ext_flag_n <= '0';
        ext_flag_v <= '0';
        
        if IS_SHIFTER = '1' then
            ext_flag_load <= '1';
            value32 := shifter_result;
            width_sel := WIDTH_32;
        elsif IS_EXTEND = '1' then
            ext_flag_load <= '1';
            value32 := extend_result;
            width_sel := WIDTH_32;
        elsif ext_tta = '1' then
            ext_flag_load <= '1';
            value32 := T_reg;
            width_sel := M_width_eff;
        elsif ext_result_valid = '1' and ext_lea = '0' then
            ext_flag_load <= '1';
            value32 := ext_result;
            width_sel := M_width_eff;
        elsif ext_lli = '1' then
            ext_flag_load <= '1';
            value32 := data_buffer;
            width_sel := M_width_eff;
        elsif stack_is_pull = '1' and (IR = x"68" or IR = x"FA" or IR = x"7A") then
            ext_flag_load <= '1';
            value32 := data_buffer;
            if IR = x"68" then
                width_sel := M_width_eff;
            else
                width_sel := X_width_eff;
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
is_bit_op <= '1' when ((IS_ALU_OP = '1' and ALU_OP = "001" and
                        (IR = x"24" or IR = x"2C" or IR = x"34" or
                         IR = x"3C" or IR = x"89")) or
                       (ext_alu = '1' and IR_EXT = x"88"))
                else '0';
    
    read_width <= WIDTH_32 when (IS_JML = '1' and ADDR_MODE = "1011") else
                  WIDTH_16 when (IS_JMP_d = '1' and (ADDR_MODE = "1000" or ADDR_MODE = "1001")) else
                  WIDTH_16 when (IS_STACK = '1' and (IR = x"F4" or IR = x"D4" or IR = x"62")) else
                  WIDTH_16 when (IS_BLOCK_MOVE = '1') else
                  WIDTH_8 when (IS_REP = '1' or IS_SEP = '1') else
                  WIDTH_8 when (ext_repe = '1' or ext_sepe = '1' or ext_trap = '1') else
                  WIDTH_32 when (ext_ldf_s = '1') else
                  WIDTH_32 when (is_extended = '1' and (IR_EXT = x"20" or IR_EXT = x"22" or IR_EXT = x"24")) else
                  WIDTH_32 when (is_extended = '1' and (IR_EXT = x"21" or IR_EXT = x"23" or IR_EXT = x"25")) else
                  X_width_eff when (IS_RMW_OP = '1' and RMW_OP = "101" and
                                    (REG_DST = "001" or REG_DST = "010")) else
                  X_width_eff when (IS_ALU_OP = '1' and ALU_OP = "110" and
                                    (REG_SRC = "001" or REG_SRC = "010")) else
                  M_width_eff;
    
    write_width <= WIDTH_32 when (ext_stf_s = '1') else
                   X_width_eff when (IS_RMW_OP = '1' and RMW_OP = "100" and
                                     (REG_SRC = "001" or REG_SRC = "010")) else
                   M_width_eff;
    

    process(IR, M_width_eff, X_width_eff, A_reg, X_reg, Y_reg, D_reg, B_reg, VBR_reg, P_reg, PC_reg, data_buffer,
            ext_stack32_push, ext_stack32_pull)
    begin
        stack_width <= WIDTH_8;
        stack_write_reg <= (others => '0');
        
        if ext_stack32_push = '1' or ext_stack32_pull = '1' then
            stack_width <= WIDTH_32;
        elsif IR = x"48" or IR = x"68" then
            stack_width <= M_width_eff;
        elsif IR = x"DA" or IR = x"FA" or IR = x"5A" or IR = x"7A" then
            stack_width <= X_width_eff;
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
    
    process(IS_RMW_OP, RMW_OP, ALU_OP, M_width_eff, is_bit_op)
    begin
        -- Defaults for ALU ops
        ALU_CTRL.fstOp <= ALU_FST_PASS;
        ALU_CTRL.fc <= '0';
        ALU_CTRL.w16 <= '1' when M_width_eff = WIDTH_16 else '0';
        ALU_CTRL.w32 <= '1' when M_width_eff = WIDTH_32 else '0';
        
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
    
    -- rw_addr1: For IS_REGALU/IS_SHIFTER/IS_EXTEND, use dp from DATA_IN; 
    -- for standard DP modes, use dp_reg_index_next; else use registered dp_reg_index
    rw_addr1 <= "00" & fpu_reg_byte(3 downto 0) when (fpu_indirect = '1' and state = ST_DECODE)
                else DATA_IN(7 downto 2) when (state = ST_ADDR1 and IS_REGALU = '1' and regalu_phase = "00")
                else DATA_IN(7 downto 2) when (state = ST_ADDR2 and (IS_SHIFTER = '1' or IS_EXTEND = '1') and regalu_phase = "01")
                else dp_reg_index_next when (state = ST_ADDR1 and
                                        (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                else dp_reg_index;
    rw_addr2 <= dp_reg_index_next_plus1 when ((ext_ldq = '1' or ext_ldf = '1') and R_mode = '1' and state = ST_ADDR1 and
                                              (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                else (others => '0');
    rw_waddr <= dp_reg_index_next_plus1 when ((stq_high_reg = '1' or f_stq_high_reg = '1') and state = ST_EXECUTE)
                else regalu_dest_addr(7 downto 2) when (state = ST_EXECUTE and IS_REGALU = '1')
                else regalu_dest_addr(7 downto 2) when (state = ST_EXECUTE and (IS_SHIFTER = '1' or IS_EXTEND = '1'))
                else dp_reg_index_next when (state = ST_ADDR1 and
                                             (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                else dp_reg_index;
    rw_width <= X_width_eff when (IS_RMW_OP = '1' and RMW_OP = "101" and
                              (REG_DST = "001" or REG_DST = "010")) else
                X_width_eff when (IS_RMW_OP = '1' and RMW_OP = "100" and
                              (REG_SRC = "001" or REG_SRC = "010")) else
                M_width_eff;
    rw_byte_sel <= dp_byte_sel_next when (R_mode = '1' and state = ST_ADDR1 and
                                         (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                   else dp_byte_sel_reg when (R_mode = '1' and
                                              (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100"))
                   else "00";
    
    process(IS_ALU_OP, IS_RMW_OP, ALU_OP, RMW_OP, REG_SRC, A_reg, X_reg, Y_reg, T_reg, ALU_RES, stq_high_reg,
            f_stq_high_reg, ext_stf, fp_regs, fpu_reg_byte, fpu_mem_reg, IS_REGALU, regalu_result,
            IS_SHIFTER, shifter_result, IS_EXTEND, extend_result)
        variable f_reg : std_logic_vector(63 downto 0);
    begin
        -- For STF, select the correct F register based on addressing mode
        f_reg := fp_regs(to_integer(fpu_mem_reg));

        if f_stq_high_reg = '1' then
            rw_wdata <= f_reg(63 downto 32);
        elsif ext_stf = '1' then
            rw_wdata <= f_reg(31 downto 0);
        elsif stq_high_reg = '1' then
            rw_wdata <= T_reg;
        elsif IS_REGALU = '1' then
            rw_wdata <= regalu_result;
        elsif IS_SHIFTER = '1' then
            rw_wdata <= shifter_result;
        elsif IS_EXTEND = '1' then
            rw_wdata <= extend_result;
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
                        (state = ST_ADDR1 and ext_stf_s = '1') or
                        (stq_high_reg = '1' and state = ST_EXECUTE) or
                        (f_stq_high_reg = '1' and state = ST_EXECUTE) or
                        (state = ST_EXECUTE and IS_RMW_OP = '1' and RMW_OP /= "100" and RMW_OP /= "101" and
                         (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100")) or
                        (state = ST_EXECUTE and IS_REGALU = '1' and REGALU_OP /= "0110") or  -- Reg-ALU write (not CMP)
                        (state = ST_EXECUTE and IS_SHIFTER = '1') or  -- Shifter write
                        (state = ST_EXECUTE and IS_EXTEND = '1')))    -- Extend write
             else '0';

    process(state, ADDR_MODE, DATA_IN, X_reg, Y_reg, dp_reg_index, R_mode, ext_ldf, ext_stf, ext_ldf_s, ext_stf_s)
        variable dp_sum   : unsigned(7 downto 0);
        variable dp_index : unsigned(5 downto 0);
    begin
        dp_reg_index_next <= dp_reg_index;
        dp_byte_sel_next <= "00";
        dp_addr_unaligned <= '0';
        if state = ST_ADDR1 and (ADDR_MODE = "0010" or ADDR_MODE = "0011" or ADDR_MODE = "0100") then
            dp_sum := unsigned(DATA_IN);
            if ADDR_MODE = "0011" then
                dp_sum := unsigned(DATA_IN) + unsigned(X_reg(7 downto 0));
            elsif ADDR_MODE = "0100" then
                dp_sum := unsigned(DATA_IN) + unsigned(Y_reg(7 downto 0));
            end if;

            if R_mode = '1' then
                if ext_ldf = '1' or ext_stf = '1' or ext_ldf_s = '1' or ext_stf_s = '1' then
                    -- 64-bit F register pairs require 8-byte alignment
                    if dp_sum(2 downto 0) /= "000" then
                        dp_addr_unaligned <= '1';
                    end if;
                    -- Map DP byte address -> register pair index (dp >> 3) * 2
                    dp_index := unsigned(dp_sum(7 downto 3) & '0');
                    dp_byte_sel_next <= "00";
                else
                    -- DP register window access requires 4-byte alignment
                    if dp_sum(1 downto 0) /= "00" then
                        dp_addr_unaligned <= '1';
                    end if;
                    dp_index := dp_sum(7 downto 2);
                    dp_byte_sel_next <= "00";
                end if;
                dp_reg_index_next <= std_logic_vector(dp_index);
            else
                dp_reg_index_next <= std_logic_vector(resize(dp_sum, 6));
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
    flag_c_in <= shifter_carry when IS_SHIFTER = '1' else
                 fpu_flag_c when fpu_flag_c_load = '1' else
                 '0' when (IS_FLAG_OP = '1' and IR = x"18") else  -- CLC
                 '1' when (IS_FLAG_OP = '1' and IR = x"38") else  -- SEC
                 ALU_CO;
    
    -- Interrupt disable flag input: CLI/SEI
    flag_i_in <= '0' when (IS_FLAG_OP = '1' and IR = x"58") else  -- CLI
                 '1' when (IS_FLAG_OP = '1' and IR = x"78") else  -- SEI
                 P_reg(P_I);
    
    -- Carry flag load: CLC/SEC, ADC/SBC/CMP, or shift/rotate operations
    flag_c_load <= '1' when state = ST_EXECUTE and 
                   (IS_SHIFTER = '1' or
                    fpu_flag_c_load = '1' or
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
    
    load_no_flags <= '1' when (W_mode = '1' and
                               ((IS_ALU_OP = '1' and ALU_OP = "101") or   -- LDA
                                (IS_RMW_OP = '1' and RMW_OP = "101")))    -- LDX/LDY
                    else '0';
    
    flag_nzv_load <= '1' when state = ST_EXECUTE and
                     (fpu_flag_load = '1' or
                      ext_flag_load = '1' or
                      (IS_ALU_OP = '1' and ALU_OP /= "100" and load_no_flags = '0') or  -- ALU except STA
                      (IS_RMW_OP = '1' and RMW_OP /= "100" and load_no_flags = '0'))    -- RMW except STX/STY
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
    
    branch_wide <= '1' when (IR = x"82" or W_mode = '1') else '0';
    
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
    -- FPU arithmetic: $C0-$CA (single), $D0-$DA (double)
    ext_fpu <= '1' when (is_extended = '1' and
                         ((IR_EXT >= x"C0" and IR_EXT <= x"CA") or
                          (IR_EXT >= x"D0" and IR_EXT <= x"DA"))) else '0';
    -- Reserved FPU opcodes trap: $CB-$CF, $DB-$DF
    ext_fpu_trap <= '1' when (is_extended = '1' and
                              ((IR_EXT >= x"CB" and IR_EXT <= x"CF") or
                               (IR_EXT >= x"DB" and IR_EXT <= x"DF"))) else '0';
    
    ext_repe <= '1' when (is_extended = '1' and IR_EXT = x"60") else '0';
    ext_sepe <= '1' when (is_extended = '1' and IR_EXT = x"61") else '0';
    
    ext_stack32_push <= '1' when (is_extended = '1' and (IR_EXT = x"70" or IR_EXT = x"72" or IR_EXT = x"74")) else '0';
    ext_stack32_pull <= '1' when (is_extended = '1' and (IR_EXT = x"71" or IR_EXT = x"73" or IR_EXT = x"75")) else '0';
    
    ext_lea <= '1' when (is_extended = '1' and (IR_EXT = x"A0" or IR_EXT = x"A1" or
                                                IR_EXT = x"A2" or IR_EXT = x"A3")) else '0';
    ext_tta <= '1' when (is_extended = '1' and IR_EXT = x"9A") else '0';
    ext_tat <= '1' when (is_extended = '1' and IR_EXT = x"9B") else '0';
    ext_ldq <= '1' when (IR = x"02" and (IR_EXT = x"9C" or IR_EXT = x"9D")) else '0';
    ext_stq <= '1' when (IR = x"02" and (IR_EXT = x"9E" or IR_EXT = x"9F")) else '0';
    -- FPU load/store: $B0-$BB (dp/abs/(Rm)/abs32, plus .S (Rm))
    ext_ldf <= '1' when (IR = x"02" and (IR_EXT = x"B0" or IR_EXT = x"B1" or IR_EXT = x"B4" or IR_EXT = x"B6")) else '0';
    ext_stf <= '1' when (IR = x"02" and (IR_EXT = x"B2" or IR_EXT = x"B3" or IR_EXT = x"B5" or IR_EXT = x"B7")) else '0';
    ext_ldf_s <= '1' when (IR = x"02" and IR_EXT = x"BA") else '0';
    ext_stf_s <= '1' when (IR = x"02" and IR_EXT = x"BB") else '0';
    fpu_indirect <= '1' when (IR = x"02" and (IR_EXT = x"B4" or IR_EXT = x"B5" or IR_EXT = x"BA" or IR_EXT = x"BB")) else '0';
    fpu_mem_reg <= unsigned(fpu_reg_byte(7 downto 4)) when (IR_EXT = x"B4" or IR_EXT = x"B5" or IR_EXT = x"BA" or IR_EXT = x"BB")
                  else unsigned(fpu_reg_byte(3 downto 0));
    -- FPU register transfers: $E0-$E5
    ext_fpu_xfer <= '1' when (is_extended = '1' and IR_EXT >= x"E0" and IR_EXT <= x"E5") else '0';
    -- FPU register selection from fpu_reg_byte
    fpu_dest <= unsigned(fpu_reg_byte(7 downto 4));  -- High nibble = destination
    fpu_src  <= unsigned(fpu_reg_byte(3 downto 0));  -- Low nibble = source
    
    stack_is_pull <= '1' when (IS_STACK = '1' and
                               (IR = x"28" or IR = x"68" or IR = x"FA" or IR = x"7A" or
                                IR = x"2B" or IR = x"AB" or ext_stack32_pull = '1'))
                     else '0';
    
    sci_success <= '1' when (ext_sci = '1' and link_valid = '1' and link_addr = eff_addr) else '0';
    
    process(ext_cas, M_width_eff, data_buffer, X_reg)
    begin
        cas_match <= '0';
        if ext_cas = '1' then
            if M_width_eff = WIDTH_8 then
                if data_buffer(7 downto 0) = X_reg(7 downto 0) then
                    cas_match <= '1';
                end if;
            elsif M_width_eff = WIDTH_16 then
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
               else "011" when (state = ST_BRANCH3 and branch_taken = '1' and branch_wide = '1') -- Branch taken: add 16-bit offset
               else "100" when (state = ST_BRANCH3 and branch_taken = '1') -- Branch taken: add 8-bit offset
               else "001" when (state = ST_FETCH or
                           state = ST_ADDR1 or 
                           (state = ST_ADDR2 and is_indirect_addr = '0') or 
                           (state = ST_ADDR3 and is_indirect_addr = '0') or
                           (state = ST_ADDR4 and is_indirect_addr = '0') or
                           state = ST_BRANCH or  -- Fetch branch offset
                           (state = ST_BRANCH2 and branch_wide = '1') or  -- Fetch branch offset high
                           ((state = ST_DECODE) and IR = x"02" and is_extended = '0') or
                           ((state = ST_DECODE) and is_extended = '1' and
                            ((IR_EXT >= x"80" and IR_EXT <= x"87") or IR_EXT = EXT_SHIFTER or IR_EXT = EXT_EXTEND) and
                            is_regalu_ext = '0') or
                           ((state = ST_DECODE) and is_extended = '1' and
                            ((IR_EXT >= x"B0" and IR_EXT <= x"BB") or
                             (IR_EXT >= x"C0" and IR_EXT <= x"CA") or
                             (IR_EXT >= x"D0" and IR_EXT <= x"DA") or
                             (IR_EXT >= x"E0" and IR_EXT <= x"E5") or
                             (IR_EXT >= x"CB" and IR_EXT <= x"CF") or
                             (IR_EXT >= x"DB" and IR_EXT <= x"DF")) and
                            is_fpu_ext = '0') or
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
