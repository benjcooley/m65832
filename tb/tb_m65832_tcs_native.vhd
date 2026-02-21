-- tb_m65832_tcs_native.vhd
-- Test TCS (Transfer A to SP) in native 32-bit mode

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_TCS_Native is
end tb_M65832_TCS_Native;

architecture sim of tb_M65832_TCS_Native is
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
    -- Test at $8000 - enter 32-bit mode, test TCS, then PHA to verify SP
    signal mem : mem_t := (
        16#8000# => x"02",  -- SEPE #$03 -> W=11 (32-bit)
        16#8001# => x"61",
        16#8002# => x"03",
        -- Now in 32-bit mode. Load A with $0000ABCD
        16#8003# => x"A9",  -- LDA #$0000ABCD
        16#8004# => x"CD",
        16#8005# => x"AB",
        16#8006# => x"00",
        16#8007# => x"00",
        16#8008# => x"1B",  -- TCS -> SP = $0000ABCD
        -- Now load a different value and push it to verify SP location
        16#8009# => x"A9",  -- LDA #$DEADBEEF
        16#800A# => x"EF",
        16#800B# => x"BE",
        16#800C# => x"AD",
        16#800D# => x"DE",
        16#800E# => x"48",  -- PHA -> push to $ABCD-4 = $ABC9
        -- TSC and store to verify SP
        16#800F# => x"3B",  -- TSC -> A = SP
        16#8010# => x"8D",  -- STA $0200
        16#8011# => x"00",
        16#8012# => x"02",
        16#8013# => x"DB",  -- STP
        others => x"00"
    );
    
    -- Test result tracking
    signal test_passed : std_logic := '0';
    signal test_done   : std_logic := '0';
    signal pha_addr    : std_logic_vector(15 downto 0) := (others => '0');
    
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
                
                -- Capture first PHA write address (should be $ABCD if TCS worked)
                if pha_addr = x"0000" and addr(15 downto 8) /= x"02" then
                    pha_addr <= addr(15 downto 0);
                    report "First PHA write at addr=0x" & to_hstring(addr(15 downto 0)) severity note;
                end if;
                
                -- Check for result write to $0200
                if addr(15 downto 0) = x"0200" then
                    test_done <= '1';
                    report "TSC stored SP low byte = 0x" & to_hstring(data_out) severity note;
                    -- After TCS with $ABCD, PHA decrements by 4 -> SP = $ABC9
                    if data_out = x"C9" then
                        test_passed <= '1';
                        report "TEST PASSED - SP correctly set by TCS" severity note;
                    else
                        report "TEST FAILED - SP not as expected. First PHA was at 0x" & 
                               to_hstring(pha_addr) severity note;
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
            if rst_n = '1' and sync_out = '1' and cycle_count < 150 then
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
            report "TCS native test TIMEOUT" severity failure;
        elsif test_passed = '0' then
            report "TCS native test FAILED" severity failure;
        else
            report "TCS native test PASSED" severity note;
        end if;
        
        wait;
    end process;
end sim;
