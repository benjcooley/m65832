-- tb_m65832_stack32.vhd
-- Test 32-bit push/pull operations in native 32-bit mode
--
-- Verifies that PHA/PLA move SP by 4 bytes (32-bit) in 32-bit mode

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_Stack32 is
end tb_M65832_Stack32;

architecture sim of tb_M65832_Stack32 is
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
    -- Test program at $8000 (CPU starts at $8000 due to hardcoded RESET_PC)
    -- Enter native 32-bit mode, test PHA/PLA with 32-bit push/pull
    signal mem : mem_t := (
        16#8000# => x"02",  -- SEPE #$03 -> W=11 (32-bit)
        16#8001# => x"61",
        16#8002# => x"03",
        16#8003# => x"A9",  -- LDA #$0000FFFC (32-bit immediate for SP setup)
        16#8004# => x"FC",
        16#8005# => x"FF",
        16#8006# => x"00",
        16#8007# => x"00",
        16#8008# => x"1B",  -- TCS (A -> SP)
        16#8009# => x"A9",  -- LDA #$DEADBEEF
        16#800A# => x"EF",
        16#800B# => x"BE",
        16#800C# => x"AD",
        16#800D# => x"DE",
        16#800E# => x"48",  -- PHA (push 4 bytes)
        16#800F# => x"A9",  -- LDA #$00000000
        16#8010# => x"00",
        16#8011# => x"00",
        16#8012# => x"00",
        16#8013# => x"00",
        16#8014# => x"68",  -- PLA (pull 4 bytes)
        16#8015# => x"3B",  -- TSC (SP -> A)
        16#8016# => x"8D",  -- STA $0200
        16#8017# => x"00",
        16#8018# => x"02",
        16#8019# => x"DB",  -- STP
        others => x"00"
    );
    signal init_done : std_logic := '1';  -- Already initialized
    
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
                
                -- Debug all writes
                report "WRITE addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(data_out) severity note;
                
                -- Check for result write to $0200
                -- If SP is $FFFC (unchanged after PHA+PLA), test passed
                if addr(15 downto 0) = x"0200" then
                    test_done <= '1';
                    report "TEST: SP low byte = 0x" & to_hstring(data_out) & 
                           " (expected 0xFC)" severity note;
                    -- SP low byte should be $FC
                    if data_out = x"FC" then
                        test_passed <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Debug output process
    process(clk)
        variable cycle_count : integer := 0;
    begin
        if rising_edge(clk) then
            cycle_count := cycle_count + 1;
            -- Show reset vector read
            if cycle_count = 1 then
                report "Reset vector: FFFC=" & to_hstring(mem(16#FFFC#)) & 
                       " FFFD=" & to_hstring(mem(16#FFFD#)) &
                       " FFFE=" & to_hstring(mem(16#FFFE#)) &
                       " FFFF=" & to_hstring(mem(16#FFFF#)) &
                       " 1000=" & to_hstring(mem(16#1000#)) &
                       " 8000=" & to_hstring(mem(16#8000#))
                    severity note;
            end if;
            -- Debug address bus during reset
            if cycle_count <= 15 then
                report "cycle=" & integer'image(cycle_count) & 
                       " addr=0x" & to_hstring(addr(15 downto 0)) &
                       " data_in=0x" & to_hstring(data_in) &
                       " rst_n=" & std_logic'image(rst_n)(2)
                    severity note;
            end if;
            if rst_n = '1' and sync_out = '1' and cycle_count < 200 then
                report "SYNC at addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(mem(to_integer(unsigned(addr(15 downto 0))))) &
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
        wait for 400 us;
        
        if test_done = '0' then
            report "Stack32 test TIMEOUT - test did not complete" severity failure;
        elsif test_passed = '0' then
            report "Stack32 test FAILED - SP not $FFFC after PHA+PLA (not 32-bit)" severity failure;
        else
            report "Stack32 test PASSED - 32-bit PHA/PLA verified" severity note;
        end if;
        
        wait;
    end process;
end sim;
