-- M65832 UART Peripheral
-- Matches the emulator's UART register interface
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Register Map (from emulator uart.h):
--   Base: 0xFFFFF100
--   +0x00  STATUS   (R)   - Status register
--   +0x04  TX_DATA  (W)   - Transmit data
--   +0x08  RX_DATA  (R)   - Receive data
--   +0x0C  CTRL     (R/W) - Control register
--
-- Status bits:
--   [0] TX_READY   - TX buffer empty, ready to send
--   [1] RX_AVAIL   - RX data available
--   [2] TX_BUSY    - TX in progress
--   [3] RX_OVERRUN - RX buffer overrun
--
-- Control bits:
--   [0] RX_IRQ_EN  - Enable RX interrupt
--   [1] TX_IRQ_EN  - Enable TX interrupt
--   [2] LOOPBACK   - Loopback mode (for testing)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_UART is
    generic(
        CLK_FREQ    : integer := 50000000;  -- System clock frequency
        BAUD_RATE   : integer := 115200     -- Baud rate
    );
    port(
        ---------------------------------------------------------------------------
        -- Clock and Reset
        ---------------------------------------------------------------------------
        CLK         : in  std_logic;
        RST_N       : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- CPU Bus Interface (directly mapped)
        ---------------------------------------------------------------------------
        CS          : in  std_logic;                      -- Chip select
        ADDR        : in  std_logic_vector(3 downto 0);   -- Register offset
        DATA_IN     : in  std_logic_vector(7 downto 0);   -- Write data
        DATA_OUT    : out std_logic_vector(7 downto 0);   -- Read data
        WE          : in  std_logic;                      -- Write enable
        RE          : in  std_logic;                      -- Read enable
        
        ---------------------------------------------------------------------------
        -- Serial Interface
        ---------------------------------------------------------------------------
        UART_TXD    : out std_logic;
        UART_RXD    : in  std_logic;
        
        ---------------------------------------------------------------------------
        -- Interrupt
        ---------------------------------------------------------------------------
        IRQ         : out std_logic
    );
end M65832_UART;

architecture rtl of M65832_UART is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    
    -- Register offsets (match emulator)
    constant REG_STATUS  : std_logic_vector(3 downto 0) := x"0";
    constant REG_TX_DATA : std_logic_vector(3 downto 0) := x"4";
    constant REG_RX_DATA : std_logic_vector(3 downto 0) := x"8";
    constant REG_CTRL    : std_logic_vector(3 downto 0) := x"C";
    
    -- Status bits
    constant STATUS_TX_READY   : integer := 0;
    constant STATUS_RX_AVAIL   : integer := 1;
    constant STATUS_TX_BUSY    : integer := 2;
    constant STATUS_RX_OVERRUN : integer := 3;
    
    -- Control bits
    constant CTRL_RX_IRQ_EN : integer := 0;
    constant CTRL_TX_IRQ_EN : integer := 1;
    constant CTRL_LOOPBACK  : integer := 2;
    
    -- Baud rate divisor (16x oversampling)
    constant DIVISOR : integer := CLK_FREQ / (16 * BAUD_RATE);
    
    ---------------------------------------------------------------------------
    -- Registers
    ---------------------------------------------------------------------------
    
    signal ctrl_reg     : std_logic_vector(7 downto 0);
    signal rx_data_reg  : std_logic_vector(7 downto 0);
    signal rx_avail     : std_logic;
    signal rx_overrun   : std_logic;
    signal tx_busy      : std_logic;
    
    ---------------------------------------------------------------------------
    -- TX State Machine
    ---------------------------------------------------------------------------
    
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state     : tx_state_t;
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_bit_cnt   : unsigned(2 downto 0);
    signal tx_clk_cnt   : unsigned(15 downto 0);
    signal tx_start     : std_logic;
    
    ---------------------------------------------------------------------------
    -- RX State Machine
    ---------------------------------------------------------------------------
    
    type rx_state_t is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state     : rx_state_t;
    signal rx_shift     : std_logic_vector(7 downto 0);
    signal rx_bit_cnt   : unsigned(2 downto 0);
    signal rx_clk_cnt   : unsigned(15 downto 0);
    
    -- RX synchronizer and edge detect
    signal rxd_sync     : std_logic_vector(2 downto 0);
    signal rxd_filtered : std_logic;
    
    ---------------------------------------------------------------------------
    -- Internal Signals
    ---------------------------------------------------------------------------
    
    signal loopback_en  : std_logic;
    signal loopback_txd : std_logic;
    
begin

    ---------------------------------------------------------------------------
    -- Loopback Mode
    ---------------------------------------------------------------------------
    
    loopback_en <= ctrl_reg(CTRL_LOOPBACK);
    
    ---------------------------------------------------------------------------
    -- RX Input Synchronization (3-stage for metastability)
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            rxd_sync <= (others => '1');
        elsif rising_edge(CLK) then
            if loopback_en = '1' then
                rxd_sync <= rxd_sync(1 downto 0) & loopback_txd;
            else
                rxd_sync <= rxd_sync(1 downto 0) & UART_RXD;
            end if;
        end if;
    end process;
    
    rxd_filtered <= rxd_sync(2);
    
    ---------------------------------------------------------------------------
    -- Bus Read
    ---------------------------------------------------------------------------
    
    process(all)
    begin
        DATA_OUT <= (others => '0');
        
        if CS = '1' and RE = '1' then
            case ADDR is
                when REG_STATUS =>
                    DATA_OUT(STATUS_TX_READY) <= not tx_busy;
                    DATA_OUT(STATUS_RX_AVAIL) <= rx_avail;
                    DATA_OUT(STATUS_TX_BUSY) <= tx_busy;
                    DATA_OUT(STATUS_RX_OVERRUN) <= rx_overrun;
                    
                when REG_RX_DATA =>
                    DATA_OUT <= rx_data_reg;
                    
                when REG_CTRL =>
                    DATA_OUT <= ctrl_reg;
                    
                when others =>
                    DATA_OUT <= (others => '0');
            end case;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Bus Write and TX Start
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            ctrl_reg <= (others => '0');
            tx_start <= '0';
            tx_data <= (others => '0');
        elsif rising_edge(CLK) then
            tx_start <= '0';  -- Default: clear start pulse
            
            if CS = '1' and WE = '1' then
                case ADDR is
                    when REG_TX_DATA =>
                        -- Write to TX register starts transmission
                        if tx_busy = '0' then
                            tx_data <= DATA_IN;
                            tx_start <= '1';
                        end if;
                        
                    when REG_CTRL =>
                        ctrl_reg <= DATA_IN;
                        
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Clear RX flags on read
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
        variable rx_read : std_logic;
    begin
        if RST_N = '0' then
            rx_avail <= '0';
            rx_overrun <= '0';
            rx_data_reg <= (others => '0');
            rx_read := '0';
        elsif rising_edge(CLK) then
            -- Capture new RX data from receiver
            if rx_state = RX_STOP and rx_clk_cnt = to_unsigned(DIVISOR * 16 - 1, 16) then
                if rx_avail = '1' then
                    rx_overrun <= '1';  -- Overrun: new data before old was read
                end if;
                rx_data_reg <= rx_shift;
                rx_avail <= '1';
            end if;
            
            -- Clear flags when RX_DATA is read
            if CS = '1' and RE = '1' and ADDR = REG_RX_DATA then
                rx_avail <= '0';
                rx_overrun <= '0';
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- TX State Machine
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            tx_state <= TX_IDLE;
            tx_bit_cnt <= (others => '0');
            tx_clk_cnt <= (others => '0');
            tx_busy <= '0';
            loopback_txd <= '1';
            UART_TXD <= '1';
        elsif rising_edge(CLK) then
            case tx_state is
                when TX_IDLE =>
                    UART_TXD <= '1';
                    loopback_txd <= '1';
                    tx_busy <= '0';
                    
                    if tx_start = '1' then
                        tx_state <= TX_START;
                        tx_clk_cnt <= (others => '0');
                        tx_busy <= '1';
                    end if;
                    
                when TX_START =>
                    -- Send start bit (low)
                    UART_TXD <= '0';
                    loopback_txd <= '0';
                    
                    if tx_clk_cnt = to_unsigned(DIVISOR * 16 - 1, 16) then
                        tx_clk_cnt <= (others => '0');
                        tx_bit_cnt <= (others => '0');
                        tx_state <= TX_DATA;
                    else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end if;
                    
                when TX_DATA =>
                    -- Send data bits (LSB first)
                    UART_TXD <= tx_data(to_integer(tx_bit_cnt));
                    loopback_txd <= tx_data(to_integer(tx_bit_cnt));
                    
                    if tx_clk_cnt = to_unsigned(DIVISOR * 16 - 1, 16) then
                        tx_clk_cnt <= (others => '0');
                        if tx_bit_cnt = 7 then
                            tx_state <= TX_STOP;
                        else
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        end if;
                    else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end if;
                    
                when TX_STOP =>
                    -- Send stop bit (high)
                    UART_TXD <= '1';
                    loopback_txd <= '1';
                    
                    if tx_clk_cnt = to_unsigned(DIVISOR * 16 - 1, 16) then
                        tx_state <= TX_IDLE;
                    else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end if;
            end case;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- RX State Machine
    ---------------------------------------------------------------------------
    
    process(CLK, RST_N)
    begin
        if RST_N = '0' then
            rx_state <= RX_IDLE;
            rx_bit_cnt <= (others => '0');
            rx_clk_cnt <= (others => '0');
            rx_shift <= (others => '0');
        elsif rising_edge(CLK) then
            case rx_state is
                when RX_IDLE =>
                    -- Wait for start bit (falling edge)
                    if rxd_filtered = '0' then
                        rx_state <= RX_START;
                        rx_clk_cnt <= (others => '0');
                    end if;
                    
                when RX_START =>
                    -- Sample at mid-bit to verify start bit
                    if rx_clk_cnt = to_unsigned(DIVISOR * 8 - 1, 16) then
                        if rxd_filtered = '0' then
                            -- Valid start bit, proceed to data
                            rx_clk_cnt <= (others => '0');
                            rx_bit_cnt <= (others => '0');
                            rx_state <= RX_DATA;
                        else
                            -- False start, return to idle
                            rx_state <= RX_IDLE;
                        end if;
                    else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end if;
                    
                when RX_DATA =>
                    -- Sample each data bit at center
                    if rx_clk_cnt = to_unsigned(DIVISOR * 16 - 1, 16) then
                        rx_clk_cnt <= (others => '0');
                        rx_shift(to_integer(rx_bit_cnt)) <= rxd_filtered;
                        
                        if rx_bit_cnt = 7 then
                            rx_state <= RX_STOP;
                        else
                            rx_bit_cnt <= rx_bit_cnt + 1;
                        end if;
                    else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end if;
                    
                when RX_STOP =>
                    -- Wait for stop bit, then back to idle
                    if rx_clk_cnt = to_unsigned(DIVISOR * 16 - 1, 16) then
                        -- Note: rx_data_reg and rx_avail updated in separate process
                        rx_state <= RX_IDLE;
                    else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end if;
            end case;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- IRQ Generation
    ---------------------------------------------------------------------------
    
    IRQ <= (ctrl_reg(CTRL_RX_IRQ_EN) and rx_avail) or
           (ctrl_reg(CTRL_TX_IRQ_EN) and not tx_busy);

end rtl;
