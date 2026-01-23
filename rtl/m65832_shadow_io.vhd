-- M65832 Shadow I/O Registers and Write FIFO
-- Captures cycle-accurate I/O writes for classic system emulation
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This module:
-- 1. Shadows hardware register writes from the 6502 core
-- 2. Records writes with cycle timestamps for frame-accurate rendering
-- 3. Provides immediate read values for the servicer
-- 4. Signals the servicer when I/O reads need computed responses

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_Shadow_IO is
    generic(
        -- Number of shadow register banks (e.g., VIC-II, SID, CIA1, CIA2)
        NUM_BANKS       : integer := 4;
        -- Registers per bank
        REGS_PER_BANK   : integer := 64;
        -- FIFO depth (entries)
        FIFO_DEPTH      : integer := 256
    );
    port(
        CLK             : in  std_logic;
        RST_N           : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- 6502 Core I/O Interface
        ---------------------------------------------------------------------------
        IO_ADDR         : in  std_logic_vector(15 downto 0);  -- 6502 I/O address
        IO_DATA_IN      : in  std_logic_vector(7 downto 0);   -- Write data
        IO_DATA_OUT     : out std_logic_vector(7 downto 0);   -- Read data
        IO_WE           : in  std_logic;                      -- Write enable
        IO_RE           : in  std_logic;                      -- Read enable
        IO_ACK          : out std_logic;                      -- Access complete
        
        ---------------------------------------------------------------------------
        -- Cycle Timing
        ---------------------------------------------------------------------------
        CYCLE_COUNT     : in  std_logic_vector(19 downto 0);  -- Current 6502 cycle
        FRAME_NUMBER    : in  std_logic_vector(15 downto 0);  -- Current frame
        
        ---------------------------------------------------------------------------
        -- Servicer Interface
        ---------------------------------------------------------------------------
        -- Signal servicer when read needs computed response
        SERVICER_REQ    : out std_logic;
        SERVICER_ADDR   : out std_logic_vector(15 downto 0);
        -- Servicer provides computed read value
        SERVICER_DATA   : in  std_logic_vector(7 downto 0);
        SERVICER_VALID  : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Linux/M65832 Read Interface (for rendering process)
        ---------------------------------------------------------------------------
        -- Direct shadow register access
        SHADOW_BANK     : in  std_logic_vector(1 downto 0);   -- Which bank
        SHADOW_REG      : in  std_logic_vector(5 downto 0);   -- Which register
        SHADOW_DATA     : out std_logic_vector(7 downto 0);   -- Current value
        
        -- FIFO read interface
        FIFO_RD         : in  std_logic;
        FIFO_EMPTY      : out std_logic;
        FIFO_DATA       : out std_logic_vector(47 downto 0);  -- frame:cycle:bank:reg:value
        FIFO_COUNT      : out std_logic_vector(8 downto 0);   -- Entries in FIFO
        
        ---------------------------------------------------------------------------
        -- I/O Address Decode Configuration
        ---------------------------------------------------------------------------
        -- Base addresses for each bank (set by Linux)
        BANK0_BASE      : in  std_logic_vector(15 downto 0);  -- e.g., $D000 (VIC-II)
        BANK1_BASE      : in  std_logic_vector(15 downto 0);  -- e.g., $D400 (SID)
        BANK2_BASE      : in  std_logic_vector(15 downto 0);  -- e.g., $DC00 (CIA1)
        BANK3_BASE      : in  std_logic_vector(15 downto 0);  -- e.g., $DD00 (CIA2)
        
        ---------------------------------------------------------------------------
        -- Status
        ---------------------------------------------------------------------------
        FIFO_OVERFLOW   : out std_logic  -- FIFO overflowed (lost writes)
    );
end M65832_Shadow_IO;

architecture rtl of M65832_Shadow_IO is

    ---------------------------------------------------------------------------
    -- Shadow Register Storage
    ---------------------------------------------------------------------------
    
    type shadow_bank_t is array (0 to REGS_PER_BANK-1) of std_logic_vector(7 downto 0);
    type shadow_regs_t is array (0 to NUM_BANKS-1) of shadow_bank_t;
    signal shadow_regs : shadow_regs_t;
    
    ---------------------------------------------------------------------------
    -- Write FIFO
    ---------------------------------------------------------------------------
    -- Entry format: frame[15:0] : cycle[19:0] : bank[1:0] : reg[5:0] : value[7:0]
    -- Total: 16 + 20 + 2 + 6 + 8 = 52 bits, stored in 64-bit words
    
    type fifo_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(47 downto 0);
    signal fifo : fifo_t;
    
    signal fifo_wr_ptr  : unsigned(7 downto 0);
    signal fifo_rd_ptr  : unsigned(7 downto 0);
    signal fifo_count_r : unsigned(8 downto 0);
    signal fifo_full    : std_logic;
    signal overflow_r   : std_logic;
    
    ---------------------------------------------------------------------------
    -- Address Decode
    ---------------------------------------------------------------------------
    
    signal bank_select  : integer range 0 to NUM_BANKS-1;
    signal reg_select   : std_logic_vector(5 downto 0);
    signal io_hit       : std_logic;
    signal needs_service: std_logic;
    
    ---------------------------------------------------------------------------
    -- Registers that need servicer computation on read
    ---------------------------------------------------------------------------
    -- VIC-II sprite collision registers, raster counter, etc.
    
    type service_mask_t is array (0 to REGS_PER_BANK-1) of std_logic;
    type service_masks_t is array (0 to NUM_BANKS-1) of service_mask_t;
    signal service_masks : service_masks_t;
    
    ---------------------------------------------------------------------------
    -- Read State
    ---------------------------------------------------------------------------
    
    type read_state_t is (
        RD_IDLE,
        RD_SERVICE_WAIT,
        RD_DONE
    );
    signal read_state : read_state_t;
    signal read_data_r : std_logic_vector(7 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Address Decode
    ---------------------------------------------------------------------------
    
    process(IO_ADDR, BANK0_BASE, BANK1_BASE, BANK2_BASE, BANK3_BASE)
        variable addr_offset : unsigned(15 downto 0);
    begin
        io_hit <= '0';
        bank_select <= 0;
        reg_select <= (others => '0');
        
        -- Check Bank 0 (VIC-II: $D000-$D03F)
        if IO_ADDR(15 downto 6) = BANK0_BASE(15 downto 6) then
            io_hit <= '1';
            bank_select <= 0;
            reg_select <= IO_ADDR(5 downto 0);
        -- Check Bank 1 (SID: $D400-$D43F)
        elsif IO_ADDR(15 downto 6) = BANK1_BASE(15 downto 6) then
            io_hit <= '1';
            bank_select <= 1;
            reg_select <= IO_ADDR(5 downto 0);
        -- Check Bank 2 (CIA1: $DC00-$DC3F)
        elsif IO_ADDR(15 downto 6) = BANK2_BASE(15 downto 6) then
            io_hit <= '1';
            bank_select <= 2;
            reg_select <= IO_ADDR(5 downto 0);
        -- Check Bank 3 (CIA2: $DD00-$DD3F)
        elsif IO_ADDR(15 downto 6) = BANK3_BASE(15 downto 6) then
            io_hit <= '1';
            bank_select <= 3;
            reg_select <= IO_ADDR(5 downto 0);
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Service Mask Initialization
    ---------------------------------------------------------------------------
    -- These registers return computed values (not just shadow values)
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            -- Initialize all to not needing service
            for b in 0 to NUM_BANKS-1 loop
                for r in 0 to REGS_PER_BANK-1 loop
                    service_masks(b)(r) <= '0';
                end loop;
            end loop;
            
            -- VIC-II (Bank 0) registers that need computation:
            -- $D011 bit 7 (raster bit 8)
            -- $D012 (raster counter)
            -- $D019 (interrupt register)
            -- $D01E (sprite-sprite collision)
            -- $D01F (sprite-background collision)
            service_masks(0)(16#11#) <= '1';  -- $D011
            service_masks(0)(16#12#) <= '1';  -- $D012
            service_masks(0)(16#19#) <= '1';  -- $D019
            service_masks(0)(16#1E#) <= '1';  -- $D01E
            service_masks(0)(16#1F#) <= '1';  -- $D01F
            
            -- CIA1 (Bank 2) registers:
            -- $DC01 (keyboard column)
            -- $DC04-$DC05 (Timer A)
            -- $DC06-$DC07 (Timer B)
            -- $DC0D (Interrupt control)
            service_masks(2)(16#01#) <= '1';
            service_masks(2)(16#04#) <= '1';
            service_masks(2)(16#05#) <= '1';
            service_masks(2)(16#06#) <= '1';
            service_masks(2)(16#07#) <= '1';
            service_masks(2)(16#0D#) <= '1';
            
            -- CIA2 (Bank 3) similar
            service_masks(3)(16#04#) <= '1';
            service_masks(3)(16#05#) <= '1';
            service_masks(3)(16#06#) <= '1';
            service_masks(3)(16#07#) <= '1';
            service_masks(3)(16#0D#) <= '1';
            
        elsif rising_edge(CLK) then
            -- Service masks are static after reset
            null;
        end if;
    end process;
    
    -- Does current read need servicer?
    needs_service <= service_masks(bank_select)(to_integer(unsigned(reg_select))) 
                     when io_hit = '1' else '0';
    
    ---------------------------------------------------------------------------
    -- Write Handling
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
        variable fifo_entry : std_logic_vector(47 downto 0);
    begin
        if RST_N = '0' then
            -- Clear shadow registers
            for b in 0 to NUM_BANKS-1 loop
                for r in 0 to REGS_PER_BANK-1 loop
                    shadow_regs(b)(r) <= (others => '0');
                end loop;
            end loop;
            
            fifo_wr_ptr <= (others => '0');
            overflow_r <= '0';
            
        elsif rising_edge(CLK) then
            overflow_r <= '0';
            
            if IO_WE = '1' and io_hit = '1' then
                -- Update shadow register
                shadow_regs(bank_select)(to_integer(unsigned(reg_select))) <= IO_DATA_IN;
                
                -- Write to FIFO (if not full)
                if fifo_full = '0' then
                    -- Pack entry: frame:cycle:bank:reg:value
                    fifo_entry := FRAME_NUMBER & 
                                  CYCLE_COUNT(19 downto 0) &
                                  std_logic_vector(to_unsigned(bank_select, 2)) &
                                  reg_select &
                                  IO_DATA_IN;
                    fifo(to_integer(fifo_wr_ptr)) <= fifo_entry;
                    fifo_wr_ptr <= fifo_wr_ptr + 1;
                else
                    overflow_r <= '1';
                end if;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Read Handling with Servicer
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            read_state <= RD_IDLE;
            read_data_r <= (others => '0');
            SERVICER_REQ <= '0';
            SERVICER_ADDR <= (others => '0');
            IO_ACK <= '0';
            
        elsif rising_edge(CLK) then
            IO_ACK <= '0';
            SERVICER_REQ <= '0';
            
            case read_state is
                when RD_IDLE =>
                    if IO_RE = '1' and io_hit = '1' then
                        if needs_service = '1' then
                            -- Need servicer to compute value
                            SERVICER_REQ <= '1';
                            SERVICER_ADDR <= IO_ADDR;
                            read_state <= RD_SERVICE_WAIT;
                        else
                            -- Return shadow register value immediately
                            read_data_r <= shadow_regs(bank_select)(to_integer(unsigned(reg_select)));
                            IO_ACK <= '1';
                        end if;
                    elsif IO_WE = '1' and io_hit = '1' then
                        -- Write acknowledged immediately
                        IO_ACK <= '1';
                    end if;
                    
                when RD_SERVICE_WAIT =>
                    if SERVICER_VALID = '1' then
                        read_data_r <= SERVICER_DATA;
                        IO_ACK <= '1';
                        read_state <= RD_IDLE;
                    end if;
                    
                when RD_DONE =>
                    read_state <= RD_IDLE;
                    
                when others =>
                    read_state <= RD_IDLE;
            end case;
        end if;
    end process;
    
    IO_DATA_OUT <= read_data_r;
    
    ---------------------------------------------------------------------------
    -- FIFO Read (Linux side)
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            fifo_rd_ptr <= (others => '0');
            fifo_count_r <= (others => '0');
            
        elsif rising_edge(CLK) then
            -- Update count
            if IO_WE = '1' and io_hit = '1' and fifo_full = '0' then
                if FIFO_RD = '1' and fifo_count_r > 0 then
                    -- Write and read: count unchanged
                    fifo_rd_ptr <= fifo_rd_ptr + 1;
                else
                    -- Write only
                    fifo_count_r <= fifo_count_r + 1;
                end if;
            elsif FIFO_RD = '1' and fifo_count_r > 0 then
                -- Read only
                fifo_rd_ptr <= fifo_rd_ptr + 1;
                fifo_count_r <= fifo_count_r - 1;
            end if;
        end if;
    end process;
    
    fifo_full <= '1' when fifo_count_r >= FIFO_DEPTH else '0';
    FIFO_EMPTY <= '1' when fifo_count_r = 0 else '0';
    FIFO_DATA <= fifo(to_integer(fifo_rd_ptr));
    FIFO_COUNT <= std_logic_vector(fifo_count_r);
    FIFO_OVERFLOW <= overflow_r;
    
    ---------------------------------------------------------------------------
    -- Direct Shadow Register Access (for Linux)
    ---------------------------------------------------------------------------
    
    SHADOW_DATA <= shadow_regs(to_integer(unsigned(SHADOW_BANK)))
                              (to_integer(unsigned(SHADOW_REG)));

end rtl;
