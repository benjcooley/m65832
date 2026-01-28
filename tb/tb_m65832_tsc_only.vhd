-- tb_m65832_tsc_only.vhd
-- Minimal test for TSC in native mode

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_TSC_Only is
end tb_M65832_TSC_Only;

architecture sim of tb_M65832_TSC_Only is
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
    -- Minimal test: enter native mode, load A, then TSC should overwrite it
    signal mem : mem_t := (
        16#8000# => x"18",  -- CLC
        16#8001# => x"FB",  -- XCE -> native 16-bit
        16#8002# => x"A9",  -- LDA #$BEEF (16-bit)
        16#8003# => x"EF",
        16#8004# => x"BE",
        16#8005# => x"3B",  -- TSC -> A = SP (should overwrite $BEEF with $01FF)
        16#8006# => x"8D",  -- STA $0200
        16#8007# => x"00",
        16#8008# => x"02",
        16#8009# => x"DB",  -- STP
        others => x"00"
    );
    
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

    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                
                report "WRITE addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(data_out) severity note;
                
                if addr(15 downto 0) = x"0200" then
                    test_done <= '1';
                    -- SP should be $01FF, low byte = $FF
                    report "TSC result (low byte): 0x" & to_hstring(data_out) & 
                           " (expected 0xFF)" severity note;
                    if data_out = x"FF" then
                        test_passed <= '1';
                        report "TEST PASSED" severity note;
                    else
                        report "TEST FAILED" severity note;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk)
        variable cycle_count : integer := 0;
    begin
        if rising_edge(clk) then
            cycle_count := cycle_count + 1;
            if rst_n = '1' and sync_out = '1' and cycle_count < 50 then
                report "SYNC at addr=0x" & to_hstring(addr(15 downto 0)) & 
                       " data=0x" & to_hstring(data_in) &
                       " E=" & std_logic'image(e_flag)(2) &
                       " M=" & to_hstring(m_flag) &
                       " cycle=" & integer'image(cycle_count)
                    severity note;
            end if;
        end if;
    end process;

    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';
        wait for 20 us;
        
        if test_done = '0' then
            report "TSC only test TIMEOUT" severity failure;
        elsif test_passed = '0' then
            report "TSC only test FAILED" severity failure;
        else
            report "TSC only test PASSED" severity note;
        end if;
        
        wait;
    end process;
end sim;
