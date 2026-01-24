-- M65832 Core Smoke Testbench

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_Core_Smoke is
end tb_M65832_Core_Smoke;

architecture sim of tb_M65832_Core_Smoke is
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

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => x"00");
    signal init_done : std_logic := '0';
    signal wrote_ok  : std_logic := '0';
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
            E_FLAG  => open,
            M_FLAG  => open,
            X_FLAG  => open,
            SYNC    => open
        );

    data_in <= mem(to_integer(unsigned(addr(15 downto 0))));

    process(clk)
    begin
        if rising_edge(clk) then
            if init_done = '0' then
                mem <= (others => x"00");
                -- Program at $8000:
                -- LDA #$AA
                -- STA $0200
                -- JMP $8000
                mem(16#8000#) <= x"A9";
                mem(16#8001#) <= x"AA";
                mem(16#8002#) <= x"8D";
                mem(16#8003#) <= x"00";
                mem(16#8004#) <= x"02";
                mem(16#8005#) <= x"4C";
                mem(16#8006#) <= x"00";
                mem(16#8007#) <= x"80";
                -- Reset vector -> $8000
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"80";
                init_done <= '1';
            end if;

            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                if addr(15 downto 0) = x"0200" and data_out = x"AA" then
                    wrote_ok <= '1';
                end if;
            end if;
        end if;
    end process;

    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';

        wait for 2 ms;
        assert wrote_ok = '1'
            report "Core smoke test failed: no write to $0200"
            severity failure;
        report "Core smoke test PASSED" severity note;
        wait;
    end process;
end sim;
