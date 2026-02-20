-- tb_m65832_native_width.vhd
-- Test native mode width switching (8-bit, 16-bit, 32-bit)
--
-- Verifies:
--   1. M/X flags control data width in native non-32-bit mode
--   2. In W_mode (M=10), all standard instructions are 32-bit
--   3. In W_mode, X_width is forced to 32-bit regardless of X flags
--
-- Test sequence:
--   T1: Enter native mode (CLC;XCE) -> M=01,X=01 (16-bit)
--       LDA #$1234 -> store $0200 (expect 16-bit store: 34 12)
--   T2: REPE #$40 -> M=00 (8-bit)
--       LDA #$AB -> store $0204 (expect 8-bit store: AB)
--   T3: SEPE #$80 -> M=10 (32-bit, W_mode active)
--       LDA #$DEADBEEF -> store $0208 (expect 32-bit store)
--   T4: While M=10 (W_mode), set X flags to 00 (8-bit)
--       LDX #$CAFEBABE -> store $020C (expect 32-bit: X forced by W_mode)
--   T5: Switch M back to 01 (16-bit), exit W_mode
--       LDA #$AABB -> store $0210 (expect 16-bit store: BB AA)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_M65832_Native_Width is
end tb_M65832_Native_Width;

architecture sim of tb_M65832_Native_Width is
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
    signal x_flag   : std_logic_vector(1 downto 0);

    type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (
        -- ===== Test program at $8000 =====

        -- T1: Enter native mode, test 16-bit LDA
        16#8000# => x"18",  -- CLC
        16#8001# => x"FB",  -- XCE -> native mode, M=01 (16-bit), X=01 (16-bit)
        16#8002# => x"A9",  -- LDA #$1234 (16-bit imm, M=01)
        16#8003# => x"34",
        16#8004# => x"12",
        16#8005# => x"8D",  -- STA $0200 (16-bit store)
        16#8006# => x"00",
        16#8007# => x"02",

        -- T2: Switch to 8-bit, test 8-bit LDA
        16#8008# => x"02",  -- REPE #$40 (clear M0: M goes 01->00 = 8-bit)
        16#8009# => x"60",
        16#800A# => x"40",
        16#800B# => x"A9",  -- LDA #$AB (8-bit imm, M=00)
        16#800C# => x"AB",
        16#800D# => x"8D",  -- STA $0204 (8-bit store)
        16#800E# => x"04",
        16#800F# => x"02",

        -- T3: Switch to 32-bit (W_mode), test 32-bit LDA
        16#8010# => x"02",  -- SEPE #$80 (set M1: M goes 00->10 = 32-bit)
        16#8011# => x"61",
        16#8012# => x"80",
        16#8013# => x"A9",  -- LDA #$DEADBEEF (32-bit imm, W_mode)
        16#8014# => x"EF",
        16#8015# => x"BE",
        16#8016# => x"AD",
        16#8017# => x"DE",
        16#8018# => x"8D",  -- STA $0208 (32-bit store)
        16#8019# => x"08",
        16#801A# => x"02",

        -- T4: While M=10 (W_mode active), set X flags to 00 (would be 8-bit)
        --     but X should be FORCED to 32-bit by W_mode
        16#801B# => x"02",  -- REPE #$30 (clear X1 and X0: X goes to 00)
        16#801C# => x"60",
        16#801D# => x"30",  -- #$30 = bits 5,4 = X1,X0
        16#801E# => x"A2",  -- LDX #$CAFEBABE (32-bit: X forced by W_mode)
        16#801F# => x"BE",
        16#8020# => x"BA",
        16#8021# => x"FE",
        16#8022# => x"CA",
        16#8023# => x"8E",  -- STX $020C (32-bit store)
        16#8024# => x"0C",
        16#8025# => x"02",

        -- T5: Exit W_mode: clear M1, set M0 -> M=01 (16-bit)
        16#8026# => x"02",  -- REPE #$80 (clear M1: M goes 10->00)
        16#8027# => x"60",
        16#8028# => x"80",
        16#8029# => x"02",  -- SEPE #$40 (set M0: M goes 00->01 = 16-bit)
        16#802A# => x"61",
        16#802B# => x"40",
        16#802C# => x"A9",  -- LDA #$AABB (16-bit imm, M=01)
        16#802D# => x"BB",
        16#802E# => x"AA",
        16#802F# => x"8D",  -- STA $0210 (16-bit store)
        16#8030# => x"10",
        16#8031# => x"02",

        -- Completion: write marker to $0300
        16#8032# => x"02",  -- SEPE #$80 (set M1: back to 32-bit for marker)
        16#8033# => x"61",
        16#8034# => x"80",
        16#8035# => x"02",  -- REPE #$40 (clear M0: M=10)
        16#8036# => x"60",
        16#8037# => x"40",
        16#8038# => x"A9",  -- LDA #$00000042 (32-bit)
        16#8039# => x"42",
        16#803A# => x"00",
        16#803B# => x"00",
        16#803C# => x"00",
        16#803D# => x"8D",  -- STA $0300
        16#803E# => x"00",
        16#803F# => x"03",
        16#8040# => x"DB",  -- STP

        others => x"00"
    );

    signal cycle_count : integer := 0;

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
            X_FLAG  => x_flag,
            SYNC    => sync_out
        );

    data_in <= mem(to_integer(unsigned(addr(15 downto 0))));

    -- Memory write process
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
            end if;
        end if;
    end process;

    -- Debug trace
    process(clk)
    begin
        if rising_edge(clk) then
            cycle_count <= cycle_count + 1;
            if rst_n = '1' and sync_out = '1' and cycle_count < 800 then
                report "SYNC addr=0x" & to_hstring(addr(15 downto 0)) &
                       " op=0x" & to_hstring(mem(to_integer(unsigned(addr(15 downto 0))))) &
                       " E=" & std_logic'image(e_flag)(2) &
                       " M=" & to_hstring(m_flag) &
                       " X=" & to_hstring(x_flag) &
                       " cycle=" & integer'image(cycle_count)
                    severity note;
            end if;
            if we = '1' and rdy = '1' and rst_n = '1' then
                report "WRITE addr=0x" & to_hstring(addr(15 downto 0)) &
                       " data=0x" & to_hstring(data_out) &
                       " cycle=" & integer'image(cycle_count)
                    severity note;
            end if;
        end if;
    end process;

    -- Main test process
    process
        variable failures : integer := 0;
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';

        wait for 800 us;

        report "=== Native Width Test Results ===" severity note;

        -- T1: 16-bit LDA #$1234 at $0200-$0201
        if mem(16#0200#) = x"34" and mem(16#0201#) = x"12" then
            report "PASS T1: 16-bit LDA #$1234 at $0200 = $1234" severity note;
        else
            report "FAIL T1: 16-bit LDA #$1234 at $0200 = " &
                   to_hstring(mem(16#0201#)) & to_hstring(mem(16#0200#)) &
                   " (expected $1234)" severity error;
            failures := failures + 1;
        end if;

        -- T2: 8-bit LDA #$AB at $0204
        if mem(16#0204#) = x"AB" then
            report "PASS T2: 8-bit LDA #$AB at $0204 = $AB" severity note;
        else
            report "FAIL T2: 8-bit LDA #$AB at $0204 = " &
                   to_hstring(mem(16#0204#)) &
                   " (expected $AB)" severity error;
            failures := failures + 1;
        end if;

        -- T3: 32-bit LDA #$DEADBEEF at $0208-$020B
        if mem(16#0208#) = x"EF" and mem(16#0209#) = x"BE" and
           mem(16#020A#) = x"AD" and mem(16#020B#) = x"DE" then
            report "PASS T3: 32-bit LDA #$DEADBEEF at $0208 = $DEADBEEF" severity note;
        else
            report "FAIL T3: 32-bit LDA at $0208 = " &
                   to_hstring(mem(16#020B#)) & to_hstring(mem(16#020A#)) &
                   to_hstring(mem(16#0209#)) & to_hstring(mem(16#0208#)) &
                   " (expected $DEADBEEF)" severity error;
            failures := failures + 1;
        end if;

        -- T4: W_mode forces X to 32-bit (LDX #$CAFEBABE despite X flags=00)
        if mem(16#020C#) = x"BE" and mem(16#020D#) = x"BA" and
           mem(16#020E#) = x"FE" and mem(16#020F#) = x"CA" then
            report "PASS T4: W_mode forces 32-bit LDX #$CAFEBABE at $020C" severity note;
        else
            report "FAIL T4: W_mode LDX at $020C = " &
                   to_hstring(mem(16#020F#)) & to_hstring(mem(16#020E#)) &
                   to_hstring(mem(16#020D#)) & to_hstring(mem(16#020C#)) &
                   " (expected $CAFEBABE)" severity error;
            failures := failures + 1;
        end if;

        -- T5: Back to 16-bit (M=01), LDA #$AABB at $0210-$0211
        if mem(16#0210#) = x"BB" and mem(16#0211#) = x"AA" then
            report "PASS T5: 16-bit LDA #$AABB at $0210 = $AABB" severity note;
        else
            report "FAIL T5: 16-bit LDA at $0210 = " &
                   to_hstring(mem(16#0211#)) & to_hstring(mem(16#0210#)) &
                   " (expected $AABB)" severity error;
            failures := failures + 1;
        end if;

        -- Completion check
        if mem(16#0300#) = x"42" then
            report "Completion marker found" severity note;
        else
            report "FAIL: Test did not complete (no marker at $0300)" severity error;
            failures := failures + 1;
        end if;

        if failures = 0 then
            report "=== ALL NATIVE WIDTH TESTS PASSED ===" severity note;
        else
            report "=== NATIVE WIDTH TESTS: " & integer'image(failures) & " FAILURES ===" severity failure;
        end if;

        wait;
    end process;
end sim;
