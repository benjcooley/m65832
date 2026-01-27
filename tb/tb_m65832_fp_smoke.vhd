-- M65832 FPU Smoke Testbench
-- Tests: I2F.S, FADD.S, F2I.S with 16-register two-operand format

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_FP_Smoke is
end tb_M65832_FP_Smoke;

architecture sim of tb_M65832_FP_Smoke is
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
    signal result_ok_abs32 : std_logic := '0';
    signal result_ok_ind   : std_logic := '0';
    signal result_ok_ind_s : std_logic := '0';
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
                -- Program at $8000 (8-bit emulation mode):
                -- Tests: FPU load/store abs32 and (Rm) addressing modes
                
                -- SEP #$30 (set 8-bit M and X)
                mem(16#8000#) <= x"E2";
                mem(16#8001#) <= x"30";
                
                -- LDA #$05 (8-bit immediate)
                mem(16#8002#) <= x"A9";
                mem(16#8003#) <= x"05";
                
                -- I2F.S F0 ($02 $C8 $00) - convert A(5) to F0
                mem(16#8004#) <= x"02";
                mem(16#8005#) <= x"C8";
                mem(16#8006#) <= x"00";
                
                -- STF F0, $00002000 (abs32)
                mem(16#8007#) <= x"02";
                mem(16#8008#) <= x"B7";
                mem(16#8009#) <= x"00";
                mem(16#800A#) <= x"00";
                mem(16#800B#) <= x"20";
                mem(16#800C#) <= x"00";
                mem(16#800D#) <= x"00";
                
                -- LDF F1, $00002000 (abs32)
                mem(16#800E#) <= x"02";
                mem(16#800F#) <= x"B6";
                mem(16#8010#) <= x"01";
                mem(16#8011#) <= x"00";
                mem(16#8012#) <= x"20";
                mem(16#8013#) <= x"00";
                mem(16#8014#) <= x"00";
                
                -- F2I.S F1 ($02 $C7 $10) - convert F1 back to A
                mem(16#8015#) <= x"02";
                mem(16#8016#) <= x"C7";
                mem(16#8017#) <= x"10";
                
                -- STA $0200 (16-bit abs)
                mem(16#8018#) <= x"8D";
                mem(16#8019#) <= x"00";
                mem(16#801A#) <= x"02";
                
                -- RSET (enable register window)
                mem(16#801B#) <= x"02";
                mem(16#801C#) <= x"30";
                
                -- LD R0, #$00002010 (ext ALU)
                mem(16#801D#) <= x"02";
                mem(16#801E#) <= x"80";
                mem(16#801F#) <= x"B8";
                mem(16#8020#) <= x"00";
                mem(16#8021#) <= x"10";
                mem(16#8022#) <= x"20";
                mem(16#8023#) <= x"00";
                mem(16#8024#) <= x"00";
                
                -- STF F0, (R0)
                mem(16#8025#) <= x"02";
                mem(16#8026#) <= x"B5";
                mem(16#8027#) <= x"00";
                
                -- LDF F2, (R0)
                mem(16#8028#) <= x"02";
                mem(16#8029#) <= x"B4";
                mem(16#802A#) <= x"20";
                
                -- F2I.S F2 ($02 $C7 $20) - convert F2 back to A
                mem(16#802B#) <= x"02";
                mem(16#802C#) <= x"C7";
                mem(16#802D#) <= x"20";
                
                -- STA $0201 (16-bit abs)
                mem(16#802E#) <= x"8D";
                mem(16#802F#) <= x"01";
                mem(16#8030#) <= x"02";

                -- STF.S F0, (R0)
                mem(16#8031#) <= x"02";
                mem(16#8032#) <= x"BB";
                mem(16#8033#) <= x"00";

                -- LDF.S F3, (R0)
                mem(16#8034#) <= x"02";
                mem(16#8035#) <= x"BA";
                mem(16#8036#) <= x"30";

                -- F2I.S F3 ($02 $C7 $30) - convert F3 back to A
                mem(16#8037#) <= x"02";
                mem(16#8038#) <= x"C7";
                mem(16#8039#) <= x"30";

                -- STA $0202 (16-bit abs)
                mem(16#803A#) <= x"8D";
                mem(16#803B#) <= x"02";
                mem(16#803C#) <= x"02";
                
                -- STP
                mem(16#803D#) <= x"DB";
                
                -- Reset vector -> $8000
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"80";
                init_done <= '1';
            end if;

            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                -- Check if results are 5 at $0200, $0201, and $0202
                if addr(15 downto 0) = x"0200" and data_out = x"05" then
                    result_ok_abs32 <= '1';
                elsif addr(15 downto 0) = x"0201" and data_out = x"05" then
                    result_ok_ind <= '1';
                elsif addr(15 downto 0) = x"0202" and data_out = x"05" then
                    result_ok_ind_s <= '1';
                end if;
            end if;
        end if;
    end process;

    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';

        wait for 5 ms;
        assert result_ok_abs32 = '1' and result_ok_ind = '1' and result_ok_ind_s = '1'
            report "FPU smoke test FAILED: expected 5 at $0200, $0201, $0202"
            severity failure;
        report "FPU smoke test PASSED: abs32 + (Rm) + (Rm) .S load/store" severity note;
        wait;
    end process;
end sim;
