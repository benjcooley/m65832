-- tb_m65832_tcs_debug.vhd
-- Minimal test to verify TCS (Transfer A to SP) works

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_TCS_Debug is
end tb_M65832_TCS_Debug;

architecture sim of tb_M65832_TCS_Debug is
    constant CLK_PERIOD : time := 20 ns;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal addr     : std_logic_vector(31 downto 0);
    signal data_out : std_logic_vector(7 downto 0);
    signal data_in  : std_logic_vector(7 downto 0);
    signal we       : std_logic;
    signal rdy      : std_logic := '1';

    signal irq_n    : std_logic := '1';
    signal nmi_n    : std_logic := '1';
    signal abort_n  : std_logic := '1';
    signal sync_out : std_logic;
    signal e_flag   : std_logic;
    signal m_flag   : std_logic_vector(1 downto 0);

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    -- Simple test at $8000 - in emulation mode, test TCS
    -- $8000: LDA #$42     ; A9 42 - load 8-bit value $42
    -- $8002: TCS          ; 1B - transfer A to SP (in emulation mode, only low byte)
    -- $8003: TSC          ; 3B - transfer SP to A
    -- $8004: STA $0200    ; 8D 00 02 - store A (should be $0142 in emulation)
    -- $8007: STP          ; DB
    signal mem : mem_t := (
        16#8000# => x"A9",  -- LDA #$42
        16#8001# => x"42",
        16#8002# => x"1B",  -- TCS
        16#8003# => x"3B",  -- TSC
        16#8004# => x"8D",  -- STA $0200
        16#8005# => x"00",
        16#8006# => x"02",
        16#8007# => x"DB",  -- STP
        others => x"00"
    );
    
    -- Test result tracking
    signal test_passed : std_logic := '0';
    signal test_done   : std_logic := '0';
    
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.M65832_Core
        port map (
            CLK     => clk,
            RST_N   => rst_n,
            CE      => '1',
            ADDR    => addr,
            DATA_OUT=> data_out,
            DATA_IN => data_in,
            WE      => we,
            RDY     => rdy,
            VPA     => open,
            VDA     => open,
            VPB     => open,
            MLB     => open,
            NMI_N   => nmi_n,
            IRQ_N   => irq_n,
            ABORT_N => abort_n,
            E_FLAG  => e_flag,
            M_FLAG  => m_flag,
            X_FLAG  => open,
            SYNC    => sync_out
        );

    data_in <= mem(to_integer(unsigned(addr(15 downto 0))));

    -- Memory write and result checking
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                
                report "WRITE addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(data_out) severity note;
                
                -- Check for result write to $0200
                if addr(15 downto 0) = x"0200" then
                    test_done <= '1';
                    report "TEST: Value at $0200 = 0x" & to_hstring(data_out) & 
                           " (expected 0x42 for SP low byte)" severity note;
                    -- In emulation mode, SP high byte is locked to $01
                    -- So after TCS with A=$42, SP=$0142
                    -- TSC then puts $0142 into A (or just $42 in 8-bit mode)
                    if data_out = x"42" then
                        test_passed <= '1';
                        report "TEST PASSED" severity note;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Debug output
    process(clk)
        variable cycle_count : integer := 0;
    begin
        if rising_edge(clk) then
            cycle_count := cycle_count + 1;
            if rst_n = '1' and sync_out = '1' and cycle_count < 100 then
                report "SYNC at addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(data_in) &
                       " E=" & std_logic'image(e_flag)(2) &
                       " M=" & to_hstring(m_flag) &
                       " cycle=" & integer'image(cycle_count)
                    severity note;
            end if;
        end if;
    end process;

    -- Main test process
    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';

        -- Wait for test completion or timeout
        wait for 50 us;
        
        if test_done = '0' then
            report "TCS debug test TIMEOUT" severity failure;
        elsif test_passed = '0' then
            report "TCS debug test FAILED" severity failure;
        else
            report "TCS debug test PASSED" severity note;
        end if;
        
        wait;
    end process;
end sim;
