-- M65832 MMU TLB Flush Testbench (MMU-only)
-- Verifies full TLB flush behavior via TLB_FLUSH
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.M65832_pkg.all;

entity tb_M65832_TLB_Flush is
end entity tb_M65832_TLB_Flush;

architecture sim of tb_M65832_TLB_Flush is

    constant CLK_PERIOD : time := 20 ns;
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';

    signal va           : std_logic_vector(31 downto 0);
    signal va_valid     : std_logic;
    signal access_type  : std_logic_vector(1 downto 0);
    signal supervisor   : std_logic;

    signal pa           : std_logic_vector(64 downto 0);
    signal pa_valid     : std_logic;
    signal pa_ready     : std_logic;

    signal page_fault   : std_logic;
    signal fault_type   : std_logic_vector(2 downto 0);
    signal fault_va     : std_logic_vector(31 downto 0);

    signal ptbr         : std_logic_vector(64 downto 0);
    signal asid         : std_logic_vector(7 downto 0);
    signal mmu_enable   : std_logic;
    signal wp_enable    : std_logic;
    signal nx_enable    : std_logic;

    signal tlb_flush    : std_logic;
    signal tlb_flush_asid : std_logic;
    signal tlb_flush_va : std_logic;
    signal tlb_flush_addr : std_logic_vector(31 downto 0);

    signal ptw_addr     : std_logic_vector(64 downto 0);
    signal ptw_req      : std_logic;
    signal ptw_ack      : std_logic;
    signal ptw_data     : std_logic_vector(63 downto 0);

    signal hit_count    : std_logic_vector(31 downto 0);
    signal miss_count   : std_logic_vector(31 downto 0);

    signal l2_ppn       : std_logic_vector(63 downto 12);
    signal ptw_pending  : std_logic;
    signal ptw_addr_lat : std_logic_vector(64 downto 0);

begin

    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    DUT: entity work.M65832_MMU
        port map(
            CLK             => clk,
            RST_N           => rst_n,
            VA              => va,
            VA_VALID        => va_valid,
            ACCESS_TYPE     => access_type,
            SUPERVISOR      => supervisor,
            PA              => pa,
            PA_VALID        => pa_valid,
            PA_READY        => pa_ready,
            PAGE_FAULT      => page_fault,
            FAULT_TYPE      => fault_type,
            FAULT_VA        => fault_va,
            PTBR            => ptbr,
            ASID            => asid,
            MMU_ENABLE      => mmu_enable,
            WP_ENABLE       => wp_enable,
            NX_ENABLE       => nx_enable,
            TLB_FLUSH       => tlb_flush,
            TLB_FLUSH_ASID  => tlb_flush_asid,
            TLB_FLUSH_VA    => tlb_flush_va,
            TLB_FLUSH_ADDR  => tlb_flush_addr,
            PTW_ADDR        => ptw_addr,
            PTW_REQ         => ptw_req,
            PTW_ACK         => ptw_ack,
            PTW_DATA        => ptw_data,
            TLB_HIT_COUNT   => hit_count,
            TLB_MISS_COUNT  => miss_count
        );

    -- Simple PTW responder (one-cycle delayed ACK)
    process(clk, rst_n)
        variable l1_pte : std_logic_vector(63 downto 0);
        variable l2_pte : std_logic_vector(63 downto 0);
    begin
        if rst_n = '0' then
            ptw_ack <= '0';
            ptw_pending <= '0';
            ptw_addr_lat <= (others => '0');
        elsif rising_edge(clk) then
            ptw_ack <= '0';
            if ptw_pending = '1' then
                ptw_ack <= '1';
                ptw_pending <= '0';
            elsif ptw_req = '1' then
                ptw_addr_lat <= ptw_addr;
                ptw_pending <= '1';
            end if;
        end if;

        -- L1 PTE points to L2 base at 0x00002000 (present)
        l1_pte := x"0000000000002001";
        -- L2 PTE uses current l2_ppn (present, writable, user)
        l2_pte := l2_ppn & std_logic_vector(to_unsigned(7, 12));

        if ptw_addr_lat(31 downto 0) = x"00001000" then
            ptw_data <= l1_pte;
        else
            ptw_data <= l2_pte;
        end if;
    end process;

    stimulus: process
        variable pa_lo : std_logic_vector(31 downto 0);
    begin
        -- Defaults
        va <= (others => '0');
        va_valid <= '0';
        access_type <= "00";
        supervisor <= '1';
        ptbr <= (others => '0');
        asid <= (others => '0');
        mmu_enable <= '0';
        wp_enable <= '0';
        nx_enable <= '0';
        tlb_flush <= '0';
        tlb_flush_asid <= '0';
        tlb_flush_va <= '0';
        tlb_flush_addr <= (others => '0');
        l2_ppn <= x"0000000000004";

        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 40 ns;

        ptbr <= (64 downto 32 => '0') & x"00001000";
        mmu_enable <= '1';

        -- First translation (populate TLB)
        va <= x"00003000";
        va_valid <= '1';
        wait until rising_edge(clk);
        va_valid <= '0';
        wait until pa_valid = '1';
        pa_lo := pa(31 downto 0);
        assert pa_lo = x"00004000" report "TLB fill PA mismatch" severity error;

        -- Change L2 mapping (should NOT be visible without flush)
        l2_ppn <= x"0000000000005";
        wait until rising_edge(clk);

        va_valid <= '1';
        wait until rising_edge(clk);
        va_valid <= '0';
        wait until pa_valid = '1';
        pa_lo := pa(31 downto 0);
        assert pa_lo = x"00004000" report "TLB hit did not cache old PA" severity error;

        -- Full flush, then retry
        tlb_flush <= '1';
        wait until rising_edge(clk);
        tlb_flush <= '0';

        va_valid <= '1';
        wait until rising_edge(clk);
        va_valid <= '0';
        wait until pa_valid = '1';
        pa_lo := pa(31 downto 0);
        assert pa_lo = x"00005000" report "TLB flush did not reload new PA" severity error;

        report "TLB flush test complete" severity note;
        wait;
    end process;

end architecture sim;
