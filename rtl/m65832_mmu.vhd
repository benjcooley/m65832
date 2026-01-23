-- M65832 Memory Management Unit
-- 2-level page tables, 4KB pages, 65-bit physical address space
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Features:
-- - 32-bit virtual address → 65-bit physical address
-- - 4KB page size (12-bit offset)
-- - 2-level page tables (10+10+12 bits)
-- - 16-entry fully-associative TLB with ASID
-- - User/Supervisor permission checking
-- - Read/Write/Execute permission bits

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_MMU is
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Virtual Address Input
        ---------------------------------------------------------------------------
        VA              : in  std_logic_vector(31 downto 0);
        VA_VALID        : in  std_logic;
        ACCESS_TYPE     : in  std_logic_vector(1 downto 0);  -- "00"=read, "01"=write, "10"=execute
        SUPERVISOR      : in  std_logic;  -- Current privilege level
        
        ---------------------------------------------------------------------------
        -- Physical Address Output
        ---------------------------------------------------------------------------
        PA              : out std_logic_vector(64 downto 0);  -- 65-bit physical
        PA_VALID        : out std_logic;
        PA_READY        : out std_logic;  -- Translation complete
        
        ---------------------------------------------------------------------------
        -- Page Fault
        ---------------------------------------------------------------------------
        PAGE_FAULT      : out std_logic;
        FAULT_TYPE      : out std_logic_vector(2 downto 0);
        -- "000" = Page not present
        -- "001" = Write to read-only
        -- "010" = User access to supervisor page
        -- "011" = Execute on non-executable page
        -- "100" = Page table not present (L1)
        -- "101" = Page table not present (L2)
        FAULT_VA        : out std_logic_vector(31 downto 0);
        
        ---------------------------------------------------------------------------
        -- Control Registers (memory-mapped, directly connected)
        ---------------------------------------------------------------------------
        -- Page Table Base Register (65-bit, 4KB aligned)
        PTBR            : in  std_logic_vector(64 downto 0);
        -- Address Space ID (for TLB tagging)
        ASID            : in  std_logic_vector(7 downto 0);
        -- MMU Control Register
        MMU_ENABLE      : in  std_logic;  -- Paging enabled
        WP_ENABLE       : in  std_logic;  -- Write-protect in supervisor mode
        NX_ENABLE       : in  std_logic;  -- No-execute bit enabled
        
        ---------------------------------------------------------------------------
        -- TLB Management
        ---------------------------------------------------------------------------
        TLB_FLUSH       : in  std_logic;  -- Flush entire TLB
        TLB_FLUSH_ASID  : in  std_logic;  -- Flush only current ASID
        TLB_FLUSH_VA    : in  std_logic;  -- Flush single VA
        TLB_FLUSH_ADDR  : in  std_logic_vector(31 downto 0);  -- VA to flush
        
        ---------------------------------------------------------------------------
        -- Page Table Walk Interface (to memory controller)
        ---------------------------------------------------------------------------
        PTW_ADDR        : out std_logic_vector(64 downto 0);  -- Address to read
        PTW_REQ         : out std_logic;
        PTW_ACK         : in  std_logic;
        PTW_DATA        : in  std_logic_vector(63 downto 0);  -- PTE data (8 bytes)
        
        ---------------------------------------------------------------------------
        -- Statistics (for OS)
        ---------------------------------------------------------------------------
        TLB_HIT_COUNT   : out std_logic_vector(31 downto 0);
        TLB_MISS_COUNT  : out std_logic_vector(31 downto 0)
    );
end M65832_MMU;

architecture rtl of M65832_MMU is

    ---------------------------------------------------------------------------
    -- Page Table Entry Format (64 bits)
    ---------------------------------------------------------------------------
    -- Bits 63:12 = Physical Page Number (52 bits → 64-bit PA with 12-bit offset)
    -- Bit  11    = Global (not flushed on ASID change)
    -- Bit  10    = Accessed (set by hardware on access)
    -- Bit  9     = Dirty (set by hardware on write)
    -- Bit  8     = Reserved
    -- Bit  7     = PAT (Page Attribute Table index)
    -- Bit  6     = Reserved
    -- Bit  5     = Reserved
    -- Bit  4     = PCD (Page Cache Disable)
    -- Bit  3     = PWT (Page Write-Through)
    -- Bit  2     = U/S (User/Supervisor: 1=user accessible)
    -- Bit  1     = R/W (Read/Write: 1=writable)
    -- Bit  0     = P (Present)
    --
    -- Extended for 65-bit PA: bit 64 stored separately (1 extra bit)
    
    constant PTE_PRESENT    : integer := 0;
    constant PTE_WRITABLE   : integer := 1;
    constant PTE_USER       : integer := 2;
    constant PTE_PWT        : integer := 3;
    constant PTE_PCD        : integer := 4;
    constant PTE_ACCESSED   : integer := 9;
    constant PTE_DIRTY      : integer := 10;
    constant PTE_GLOBAL     : integer := 11;
    constant PTE_NX         : integer := 63;  -- No-execute (top bit)
    
    ---------------------------------------------------------------------------
    -- TLB Entry
    ---------------------------------------------------------------------------
    
    type tlb_entry_t is record
        valid       : std_logic;
        asid        : std_logic_vector(7 downto 0);
        vpn         : std_logic_vector(19 downto 0);   -- Virtual page number
        ppn         : std_logic_vector(52 downto 0);   -- Physical page number (53 bits for 65-bit PA)
        global      : std_logic;
        writable    : std_logic;
        user        : std_logic;
        executable  : std_logic;
        dirty       : std_logic;
        accessed    : std_logic;
    end record;
    
    type tlb_array_t is array (0 to 15) of tlb_entry_t;
    signal tlb : tlb_array_t;
    
    -- TLB replacement (round-robin)
    signal tlb_replace_idx : unsigned(3 downto 0);
    
    ---------------------------------------------------------------------------
    -- Page Table Walker State Machine
    ---------------------------------------------------------------------------
    
    type ptw_state_t is (
        PTW_IDLE,
        PTW_L1_REQ,     -- Request L1 PTE
        PTW_L1_WAIT,    -- Wait for L1 PTE
        PTW_L2_REQ,     -- Request L2 PTE
        PTW_L2_WAIT,    -- Wait for L2 PTE
        PTW_DONE,       -- Translation complete
        PTW_FAULT       -- Page fault
    );
    
    signal ptw_state : ptw_state_t;
    
    -- Saved translation info
    signal saved_va     : std_logic_vector(31 downto 0);
    signal saved_access : std_logic_vector(1 downto 0);
    signal saved_super  : std_logic;
    
    -- Page table walk intermediate values
    signal l1_pte       : std_logic_vector(63 downto 0);
    signal l2_pte       : std_logic_vector(63 downto 0);
    
    ---------------------------------------------------------------------------
    -- Statistics
    ---------------------------------------------------------------------------
    
    signal hit_count    : unsigned(31 downto 0);
    signal miss_count   : unsigned(31 downto 0);
    
    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    
    signal tlb_hit      : std_logic;
    signal tlb_hit_idx  : integer range 0 to 15;
    signal fault_reg    : std_logic;
    signal fault_type_reg : std_logic_vector(2 downto 0);
    signal pa_reg       : std_logic_vector(64 downto 0);
    signal pa_valid_reg : std_logic;

begin

    ---------------------------------------------------------------------------
    -- TLB Lookup (combinational)
    ---------------------------------------------------------------------------
    
    process(all)
        variable vpn : std_logic_vector(19 downto 0);
        variable hit : std_logic;
        variable idx : integer range 0 to 15;
    begin
        vpn := VA(31 downto 12);
        hit := '0';
        idx := 0;
        
        for i in 0 to 15 loop
            if tlb(i).valid = '1' and
               tlb(i).vpn = vpn and
               (tlb(i).global = '1' or tlb(i).asid = ASID) then
                hit := '1';
                idx := i;
                exit;
            end if;
        end loop;
        
        tlb_hit <= hit;
        tlb_hit_idx <= idx;
    end process;
    
    ---------------------------------------------------------------------------
    -- Main Translation Logic
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
        variable vpn        : std_logic_vector(19 downto 0);
        variable l1_index   : std_logic_vector(9 downto 0);
        variable l2_index   : std_logic_vector(9 downto 0);
        variable offset     : std_logic_vector(11 downto 0);
        variable pte_addr   : std_logic_vector(64 downto 0);
        variable check_fail : std_logic;
    begin
        if RST_N = '0' then
            ptw_state <= PTW_IDLE;
            pa_reg <= (others => '0');
            pa_valid_reg <= '0';
            fault_reg <= '0';
            fault_type_reg <= "000";
            saved_va <= (others => '0');
            saved_access <= "00";
            saved_super <= '0';
            l1_pte <= (others => '0');
            l2_pte <= (others => '0');
            tlb_replace_idx <= (others => '0');
            hit_count <= (others => '0');
            miss_count <= (others => '0');
            
            -- Initialize TLB
            for i in 0 to 15 loop
                tlb(i).valid <= '0';
                tlb(i).asid <= (others => '0');
                tlb(i).vpn <= (others => '0');
                tlb(i).ppn <= (others => '0');
                tlb(i).global <= '0';
                tlb(i).writable <= '0';
                tlb(i).user <= '0';
                tlb(i).executable <= '0';
                tlb(i).dirty <= '0';
                tlb(i).accessed <= '0';
            end loop;
            
        elsif rising_edge(CLK) then
            -- Default outputs
            fault_reg <= '0';
            pa_valid_reg <= '0';
            PTW_REQ <= '0';
            
            -- TLB Flush handling
            if TLB_FLUSH = '1' then
                for i in 0 to 15 loop
                    tlb(i).valid <= '0';
                end loop;
            elsif TLB_FLUSH_ASID = '1' then
                for i in 0 to 15 loop
                    if tlb(i).asid = ASID and tlb(i).global = '0' then
                        tlb(i).valid <= '0';
                    end if;
                end loop;
            elsif TLB_FLUSH_VA = '1' then
                for i in 0 to 15 loop
                    if tlb(i).vpn = TLB_FLUSH_ADDR(31 downto 12) and
                       (tlb(i).asid = ASID or tlb(i).global = '1') then
                        tlb(i).valid <= '0';
                    end if;
                end loop;
            end if;
            
            -- Address decomposition
            vpn := VA(31 downto 12);
            l1_index := VA(31 downto 22);
            l2_index := VA(21 downto 12);
            offset := VA(11 downto 0);
            
            case ptw_state is
                when PTW_IDLE =>
                    if VA_VALID = '1' then
                        if MMU_ENABLE = '0' then
                            -- MMU disabled: VA = PA (identity mapping)
                            pa_reg <= '0' & VA;  -- Extend to 65 bits
                            pa_valid_reg <= '1';
                            
                        elsif tlb_hit = '1' then
                            -- TLB hit: check permissions
                            check_fail := '0';
                            
                            -- User accessing supervisor page?
                            if SUPERVISOR = '0' and tlb(tlb_hit_idx).user = '0' then
                                check_fail := '1';
                                fault_type_reg <= "010";
                            -- Write to read-only?
                            elsif ACCESS_TYPE = "01" and tlb(tlb_hit_idx).writable = '0' then
                                if SUPERVISOR = '0' or WP_ENABLE = '1' then
                                    check_fail := '1';
                                    fault_type_reg <= "001";
                                end if;
                            -- Execute on non-executable?
                            elsif ACCESS_TYPE = "10" and NX_ENABLE = '1' and 
                                  tlb(tlb_hit_idx).executable = '0' then
                                check_fail := '1';
                                fault_type_reg <= "011";
                            end if;
                            
                            if check_fail = '1' then
                                fault_reg <= '1';
                                FAULT_VA <= VA;
                            else
                                -- Success: construct physical address
                                pa_reg <= tlb(tlb_hit_idx).ppn & offset;
                                pa_valid_reg <= '1';
                                hit_count <= hit_count + 1;
                            end if;
                            
                        else
                            -- TLB miss: start page table walk
                            saved_va <= VA;
                            saved_access <= ACCESS_TYPE;
                            saved_super <= SUPERVISOR;
                            miss_count <= miss_count + 1;
                            ptw_state <= PTW_L1_REQ;
                        end if;
                    end if;
                    
                when PTW_L1_REQ =>
                    -- Calculate L1 PTE address
                    -- PTBR + (l1_index * 8)
                    -- l1_index is 10 bits, shift left 3 = multiply by 8
                    pte_addr := std_logic_vector(unsigned(PTBR) + 
                                resize(unsigned(l1_index) & "000", 65));
                    PTW_ADDR <= pte_addr;
                    PTW_REQ <= '1';
                    ptw_state <= PTW_L1_WAIT;
                    
                when PTW_L1_WAIT =>
                    if PTW_ACK = '1' then
                        l1_pte <= PTW_DATA;
                        if PTW_DATA(PTE_PRESENT) = '0' then
                            -- L1 not present
                            fault_reg <= '1';
                            fault_type_reg <= "100";
                            FAULT_VA <= saved_va;
                            ptw_state <= PTW_IDLE;
                        else
                            ptw_state <= PTW_L2_REQ;
                        end if;
                    end if;
                    
                when PTW_L2_REQ =>
                    -- Calculate L2 PTE address
                    -- L1_PTE[63:12] gives L2 table base, add l2_index * 8
                    l2_index := saved_va(21 downto 12);
                    pte_addr := '0' & l1_pte(63 downto 12) & "000000000000";
                    pte_addr := std_logic_vector(unsigned(pte_addr) + 
                                resize(unsigned(l2_index) & "000", 65));
                    PTW_ADDR <= pte_addr;
                    PTW_REQ <= '1';
                    ptw_state <= PTW_L2_WAIT;
                    
                when PTW_L2_WAIT =>
                    if PTW_ACK = '1' then
                        l2_pte <= PTW_DATA;
                        if PTW_DATA(PTE_PRESENT) = '0' then
                            -- L2 not present
                            fault_reg <= '1';
                            fault_type_reg <= "000";
                            FAULT_VA <= saved_va;
                            ptw_state <= PTW_IDLE;
                        else
                            ptw_state <= PTW_DONE;
                        end if;
                    end if;
                    
                when PTW_DONE =>
                    -- Check permissions on final PTE
                    check_fail := '0';
                    
                    if saved_super = '0' and l2_pte(PTE_USER) = '0' then
                        check_fail := '1';
                        fault_type_reg <= "010";
                    elsif saved_access = "01" and l2_pte(PTE_WRITABLE) = '0' then
                        if saved_super = '0' or WP_ENABLE = '1' then
                            check_fail := '1';
                            fault_type_reg <= "001";
                        end if;
                    elsif saved_access = "10" and NX_ENABLE = '1' and l2_pte(PTE_NX) = '1' then
                        check_fail := '1';
                        fault_type_reg <= "011";
                    end if;
                    
                    if check_fail = '1' then
                        fault_reg <= '1';
                        FAULT_VA <= saved_va;
                    else
                        -- Install in TLB
                        tlb(to_integer(tlb_replace_idx)).valid <= '1';
                        tlb(to_integer(tlb_replace_idx)).asid <= ASID;
                        tlb(to_integer(tlb_replace_idx)).vpn <= saved_va(31 downto 12);
                        tlb(to_integer(tlb_replace_idx)).ppn <= '0' & l2_pte(63 downto 12);
                        tlb(to_integer(tlb_replace_idx)).global <= l2_pte(PTE_GLOBAL);
                        tlb(to_integer(tlb_replace_idx)).writable <= l2_pte(PTE_WRITABLE);
                        tlb(to_integer(tlb_replace_idx)).user <= l2_pte(PTE_USER);
                        tlb(to_integer(tlb_replace_idx)).executable <= not l2_pte(PTE_NX);
                        tlb(to_integer(tlb_replace_idx)).dirty <= l2_pte(PTE_DIRTY);
                        tlb(to_integer(tlb_replace_idx)).accessed <= l2_pte(PTE_ACCESSED);
                        
                        tlb_replace_idx <= tlb_replace_idx + 1;
                        
                        -- Output physical address
                        pa_reg <= '0' & l2_pte(63 downto 12) & saved_va(11 downto 0);
                        pa_valid_reg <= '1';
                    end if;
                    
                    ptw_state <= PTW_IDLE;
                    
                when PTW_FAULT =>
                    ptw_state <= PTW_IDLE;
                    
                when others =>
                    ptw_state <= PTW_IDLE;
            end case;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    
    PA <= pa_reg;
    PA_VALID <= pa_valid_reg;
    PA_READY <= '1' when ptw_state = PTW_IDLE else '0';
    PAGE_FAULT <= fault_reg;
    FAULT_TYPE <= fault_type_reg;
    TLB_HIT_COUNT <= std_logic_vector(hit_count);
    TLB_MISS_COUNT <= std_logic_vector(miss_count);

end rtl;
