-- tb_m65832_xce_debug.vhd
-- Minimal test to verify CLC + XCE works correctly

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_XCE_Debug is
end tb_M65832_XCE_Debug;

architecture sim of tb_M65832_XCE_Debug is
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
    signal mem : mem_t := (others => x"00");
    signal init_done : std_logic := '0';
    
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

    -- Memory and result process (exactly like working smoke test)
    process(clk)
    begin
        if rising_edge(clk) then
            if init_done = '0' then
                mem <= (others => x"00");
                -- Minimal test program at $8000:
                -- $8000: CLC          ; 18  - clear carry
                -- $8001: XCE          ; FB  - exchange carry and emulation -> enter native
                -- $8002: LDA #$42     ; A9 42 00 - load 16-bit immediate (native mode)
                -- $8005: STA $0200    ; 8D 00 02 - store to $0200
                -- $8008: DB           ; STP - stop
                
                -- CLC
                mem(16#8000#) <= x"18";
                -- XCE (enter native mode)
                mem(16#8001#) <= x"FB";
                -- LDA #$0042 (16-bit immediate in native mode)
                mem(16#8002#) <= x"A9";
                mem(16#8003#) <= x"42";
                mem(16#8004#) <= x"00";
                -- STA $0200
                mem(16#8005#) <= x"8D";
                mem(16#8006#) <= x"00";
                mem(16#8007#) <= x"02";
                -- STP
                mem(16#8008#) <= x"DB";
                
                -- Reset vector -> $8000
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"80";
                
                init_done <= '1';
            end if;

            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                
                -- Debug: report all writes
                report "WRITE addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(data_out) severity note;
                
                -- Check for result write to $0200
                if addr(15 downto 0) = x"0200" then
                    report "TEST: Write to $0200 detected, data=" & to_hstring(data_out) severity note;
                    test_done <= '1';
                    if data_out = x"42" then
                        report "TEST: Correct value 0x42 written - PASS" severity note;
                        test_passed <= '1';
                    else
                        report "TEST: Wrong value written - FAIL" severity note;
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
            if rst_n = '1' then
                if sync_out = '1' then
                    report "SYNC at addr=0x" & to_hstring(addr(15 downto 0)) & 
                           " data=0x" & to_hstring(data_in) &
                           " E=" & std_logic'image(e_flag)(2) &
                           " M=" & to_hstring(m_flag) &
                           " cycle=" & integer'image(cycle_count)
                        severity note;
                elsif cycle_count < 100 then
                    report "READ addr=0x" & to_hstring(addr(15 downto 0)) & 
                           " data=0x" & to_hstring(data_in) &
                           " we=" & std_logic'image(we)(2) &
                           " cycle=" & integer'image(cycle_count)
                        severity note;
                end if;
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
        wait for 100 us;
        
        if test_done = '0' then
            report "XCE debug test TIMEOUT - test did not complete" severity failure;
        elsif test_passed = '0' then
            report "XCE debug test FAILED - incorrect value at $0200" severity failure;
        else
            report "XCE debug test PASSED - XCE/native mode entry works" severity note;
        end if;
        
        wait;
    end process;
end sim;
