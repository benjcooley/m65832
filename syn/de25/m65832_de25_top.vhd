-- M65832 DE25-Nano Top Level
-- SoC wrapper for FPGA bring-up
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Memory Map:
--   0x00000000 - 0x07FFFFFF : Main RAM (128MB SDRAM)
--   0xFFFF0000 - 0xFFFF0FFF : Boot ROM (4KB BRAM)
--   0xFFFFF000 - 0xFFFFF0FF : System registers (MMU, timer)
--   0xFFFFF100 - 0xFFFFF10F : UART
--
-- Initial bring-up features:
--   - M65832 core
--   - Boot ROM (BRAM)
--   - UART console
--   - Simple RAM (BRAM for initial testing)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.M65832_pkg.all;

entity M65832_DE25_Top is
    generic(
        SIM_MODE    : boolean := false;  -- Simulation mode (faster UART)
        CLK_FREQ    : integer := 50000000;
        BAUD_RATE   : integer := 115200
    );
    port(
        ---------------------------------------------------------------------------
        -- Clock and Reset
        ---------------------------------------------------------------------------
        CLK_50M     : in  std_logic;     -- 50 MHz input clock
        RST_N       : in  std_logic;     -- Active-low reset button
        
        ---------------------------------------------------------------------------
        -- UART (directly on M65832)
        ---------------------------------------------------------------------------
        UART_TXD    : out std_logic;
        UART_RXD    : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- LEDs for status
        ---------------------------------------------------------------------------
        LED         : out std_logic_vector(7 downto 0);
        
        ---------------------------------------------------------------------------
        -- SDRAM Interface (directly exposed for later use)
        ---------------------------------------------------------------------------
        SDRAM_CLK   : out std_logic;
        SDRAM_CKE   : out std_logic;
        SDRAM_CS_N  : out std_logic;
        SDRAM_RAS_N : out std_logic;
        SDRAM_CAS_N : out std_logic;
        SDRAM_WE_N  : out std_logic;
        SDRAM_BA    : out std_logic_vector(1 downto 0);
        SDRAM_ADDR  : out std_logic_vector(12 downto 0);
        SDRAM_DQ    : inout std_logic_vector(15 downto 0);
        SDRAM_DQM   : out std_logic_vector(1 downto 0)
    );
end M65832_DE25_Top;

architecture rtl of M65832_DE25_Top is

    ---------------------------------------------------------------------------
    -- Clock and Reset
    ---------------------------------------------------------------------------
    
    signal sys_clk      : std_logic;
    signal sys_rst_n    : std_logic;
    signal pll_locked   : std_logic;
    
    -- Reset synchronizer
    signal rst_sync     : std_logic_vector(3 downto 0);
    
    ---------------------------------------------------------------------------
    -- CPU Signals
    ---------------------------------------------------------------------------
    
    signal cpu_addr     : std_logic_vector(31 downto 0);
    signal cpu_data_out : std_logic_vector(7 downto 0);
    signal cpu_data_in  : std_logic_vector(7 downto 0);
    signal cpu_we       : std_logic;
    signal cpu_rdy      : std_logic;
    signal cpu_vpa      : std_logic;
    signal cpu_vda      : std_logic;
    signal cpu_vpb      : std_logic;
    signal cpu_mlb      : std_logic;
    signal cpu_sync     : std_logic;
    signal cpu_e_flag   : std_logic;
    signal cpu_m_flag   : std_logic_vector(1 downto 0);
    signal cpu_x_flag   : std_logic_vector(1 downto 0);
    
    signal cpu_nmi_n    : std_logic;
    signal cpu_irq_n    : std_logic;
    signal cpu_abort_n  : std_logic;
    
    ---------------------------------------------------------------------------
    -- Memory Map Decode
    ---------------------------------------------------------------------------
    
    signal sel_ram      : std_logic;
    signal sel_bootrom  : std_logic;
    signal sel_uart     : std_logic;
    signal sel_sysreg   : std_logic;
    
    -- Address regions
    constant RAM_BASE     : unsigned(31 downto 0) := x"00000000";
    constant RAM_SIZE     : unsigned(31 downto 0) := x"00010000";  -- 64KB for BRAM test
    constant BOOTROM_BASE : unsigned(31 downto 0) := x"FFFF0000";
    constant BOOTROM_SIZE : unsigned(31 downto 0) := x"00001000";  -- 4KB
    constant SYSREG_BASE  : unsigned(31 downto 0) := x"FFFFF000";
    constant UART_BASE    : unsigned(31 downto 0) := x"FFFFF100";
    
    ---------------------------------------------------------------------------
    -- RAM (BRAM for initial testing)
    ---------------------------------------------------------------------------
    
    type ram_t is array(0 to 16383) of std_logic_vector(7 downto 0);  -- 16KB
    signal ram : ram_t := (others => x"00");
    signal ram_data : std_logic_vector(7 downto 0);
    
    ---------------------------------------------------------------------------
    -- Boot ROM
    ---------------------------------------------------------------------------
    
    signal bootrom_addr : std_logic_vector(11 downto 0);
    signal bootrom_data : std_logic_vector(7 downto 0);
    
    ---------------------------------------------------------------------------
    -- UART
    ---------------------------------------------------------------------------
    
    signal uart_data_out : std_logic_vector(7 downto 0);
    signal uart_irq      : std_logic;
    
    ---------------------------------------------------------------------------
    -- Status
    ---------------------------------------------------------------------------
    
    signal heartbeat_cnt : unsigned(25 downto 0);
    signal heartbeat_led : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    -- For initial bring-up, use input clock directly
    -- TODO: Add PLL for higher speeds
    ---------------------------------------------------------------------------
    
    sys_clk <= CLK_50M;
    pll_locked <= '1';  -- No PLL yet
    
    ---------------------------------------------------------------------------
    -- Reset Synchronizer
    ---------------------------------------------------------------------------
    
    process(sys_clk, RST_N)
    begin
        if RST_N = '0' then
            rst_sync <= (others => '0');
        elsif rising_edge(sys_clk) then
            if pll_locked = '1' then
                rst_sync <= rst_sync(2 downto 0) & '1';
            else
                rst_sync <= (others => '0');
            end if;
        end if;
    end process;
    
    sys_rst_n <= rst_sync(3);
    
    ---------------------------------------------------------------------------
    -- M65832 CPU Core
    ---------------------------------------------------------------------------
    
    u_cpu : entity work.M65832_Core
        port map(
            CLK         => sys_clk,
            RST_N       => sys_rst_n,
            CE          => '1',
            
            ADDR        => cpu_addr,
            DATA_OUT    => cpu_data_out,
            DATA_IN     => cpu_data_in,
            WE          => cpu_we,
            RDY         => cpu_rdy,
            
            VPA         => cpu_vpa,
            VDA         => cpu_vda,
            VPB         => cpu_vpb,
            MLB         => cpu_mlb,
            
            NMI_N       => cpu_nmi_n,
            IRQ_N       => cpu_irq_n,
            ABORT_N     => cpu_abort_n,
            
            E_FLAG      => cpu_e_flag,
            M_FLAG      => cpu_m_flag,
            X_FLAG      => cpu_x_flag,
            
            SYNC        => cpu_sync
        );
    
    -- Tie off unused interrupt inputs
    cpu_nmi_n <= '1';
    cpu_irq_n <= not uart_irq;  -- UART IRQ active high
    cpu_abort_n <= '1';
    
    -- Always ready for now (single-cycle memory)
    cpu_rdy <= '1';
    
    ---------------------------------------------------------------------------
    -- Address Decode
    ---------------------------------------------------------------------------
    
    process(cpu_addr)
        variable addr : unsigned(31 downto 0);
    begin
        addr := unsigned(cpu_addr);
        
        sel_ram <= '0';
        sel_bootrom <= '0';
        sel_uart <= '0';
        sel_sysreg <= '0';
        
        -- Boot ROM: 0xFFFF0000 - 0xFFFF0FFF
        if addr >= BOOTROM_BASE and addr < (BOOTROM_BASE + BOOTROM_SIZE) then
            sel_bootrom <= '1';
        -- UART: 0xFFFFF100 - 0xFFFFF10F
        elsif addr >= UART_BASE and addr < (UART_BASE + x"10") then
            sel_uart <= '1';
        -- System registers: 0xFFFFF000 - 0xFFFFF0FF
        elsif addr >= SYSREG_BASE and addr < UART_BASE then
            sel_sysreg <= '1';
        -- RAM: 0x00000000 - 0x0000FFFF (for BRAM test)
        elsif addr < RAM_SIZE then
            sel_ram <= '1';
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Data Mux
    ---------------------------------------------------------------------------
    
    process(sel_ram, sel_bootrom, sel_uart, sel_sysreg,
            ram_data, bootrom_data, uart_data_out)
    begin
        cpu_data_in <= x"00";
        
        if sel_bootrom = '1' then
            cpu_data_in <= bootrom_data;
        elsif sel_uart = '1' then
            cpu_data_in <= uart_data_out;
        elsif sel_ram = '1' then
            cpu_data_in <= ram_data;
        elsif sel_sysreg = '1' then
            cpu_data_in <= x"00";  -- TODO: System registers
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- RAM (BRAM)
    ---------------------------------------------------------------------------
    
    process(sys_clk)
    begin
        if rising_edge(sys_clk) then
            if sel_ram = '1' then
                if cpu_we = '1' then
                    ram(to_integer(unsigned(cpu_addr(13 downto 0)))) <= cpu_data_out;
                end if;
                ram_data <= ram(to_integer(unsigned(cpu_addr(13 downto 0))));
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Boot ROM
    ---------------------------------------------------------------------------
    
    bootrom_addr <= cpu_addr(11 downto 0);
    
    u_bootrom : entity work.M65832_BootROM
        generic map(
            ADDR_WIDTH => 12
        )
        port map(
            CLK      => sys_clk,
            ADDR     => bootrom_addr,
            DATA_OUT => bootrom_data
        );
    
    ---------------------------------------------------------------------------
    -- UART
    ---------------------------------------------------------------------------
    
    u_uart : entity work.M65832_UART
        generic map(
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map(
            CLK      => sys_clk,
            RST_N    => sys_rst_n,
            
            CS       => sel_uart,
            ADDR     => cpu_addr(3 downto 0),
            DATA_IN  => cpu_data_out,
            DATA_OUT => uart_data_out,
            WE       => cpu_we,
            RE       => not cpu_we,
            
            UART_TXD => UART_TXD,
            UART_RXD => UART_RXD,
            
            IRQ      => uart_irq
        );
    
    ---------------------------------------------------------------------------
    -- Heartbeat LED
    ---------------------------------------------------------------------------
    
    process(sys_clk, sys_rst_n)
    begin
        if sys_rst_n = '0' then
            heartbeat_cnt <= (others => '0');
            heartbeat_led <= '0';
        elsif rising_edge(sys_clk) then
            heartbeat_cnt <= heartbeat_cnt + 1;
            if heartbeat_cnt = 0 then
                heartbeat_led <= not heartbeat_led;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- LED Status
    ---------------------------------------------------------------------------
    
    LED(0) <= heartbeat_led;        -- Heartbeat
    LED(1) <= sys_rst_n;            -- Reset released
    LED(2) <= cpu_e_flag;           -- Emulation mode
    LED(3) <= cpu_sync;             -- Opcode fetch
    LED(4) <= sel_bootrom;          -- Boot ROM access
    LED(5) <= sel_uart;             -- UART access
    LED(6) <= sel_ram;              -- RAM access
    LED(7) <= uart_irq;             -- UART IRQ pending
    
    ---------------------------------------------------------------------------
    -- SDRAM (directly exposed but disabled for initial BRAM-only testing)
    -- TODO: Add SDRAM controller for full memory access
    ---------------------------------------------------------------------------
    
    SDRAM_CLK   <= '0';
    SDRAM_CKE   <= '0';
    SDRAM_CS_N  <= '1';  -- Disabled
    SDRAM_RAS_N <= '1';
    SDRAM_CAS_N <= '1';
    SDRAM_WE_N  <= '1';
    SDRAM_BA    <= (others => '0');
    SDRAM_ADDR  <= (others => '0');
    SDRAM_DQ    <= (others => 'Z');
    SDRAM_DQM   <= (others => '1');

end rtl;
