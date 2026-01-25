-------------------------------------------------------------------------------
-- tb_m65832_irq_stack.vhd
-- Isolated testbench for IRQ stack frame debugging
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_M65832_IRQ_Stack is
end entity tb_M65832_IRQ_Stack;

architecture sim of tb_M65832_IRQ_Stack is
    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal ce        : std_logic := '1';
    signal rdy       : std_logic := '1';
    signal addr      : std_logic_vector(31 downto 0);
    signal data_in   : std_logic_vector(7 downto 0);
    signal data_out  : std_logic_vector(7 downto 0);
    signal we        : std_logic;
    signal vpa       : std_logic;
    signal vda       : std_logic;
    signal vpb       : std_logic;
    signal mlb       : std_logic;
    signal irq_n     : std_logic := '1';
    signal nmi_n     : std_logic := '1';
    signal abort_n   : std_logic := '1';
    signal e_flag    : std_logic;
    signal m_flag    : std_logic_vector(1 downto 0);
    signal x_flag    : std_logic_vector(1 downto 0);

    constant CLK_PERIOD : time := 100 ns;
    
    type mem_t is array(0 to 65535) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => x"EA");
    
    signal cycle_count : integer := 0;
    signal init_done   : std_logic := '0';

begin
    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.M65832_Core
        port map (
            CLK      => clk,
            RST_N    => rst_n,
            CE       => ce,
            RDY      => rdy,
            ADDR     => addr,
            DATA_IN  => data_in,
            DATA_OUT => data_out,
            WE       => we,
            VPA      => vpa,
            VDA      => vda,
            VPB      => vpb,
            MLB      => mlb,
            IRQ_N    => irq_n,
            NMI_N    => nmi_n,
            ABORT_N  => abort_n,
            E_FLAG   => e_flag,
            M_FLAG   => m_flag,
            X_FLAG   => x_flag
        );

    -- Memory read
    data_in <= mem(to_integer(unsigned(addr(15 downto 0))));

    -- Memory model
    process(clk)
        variable pc : integer;
    begin
        if rising_edge(clk) then
            cycle_count <= cycle_count + 1;
            
            if init_done = '0' then
                mem <= (others => x"EA");  -- Fill with NOPs
                pc := 16#8000#;
                
                -- Test program: CLI, WAI, LDA #$3D, STA $0496, STP
                -- After IRQ, we should see the stack frame at $01FA-$01FF
                mem(pc) <= x"58"; pc := pc + 1;  -- CLI (clear I flag)
                mem(pc) <= x"CB"; pc := pc + 1;  -- WAI
                mem(pc) <= x"A9"; pc := pc + 1;  -- LDA #$3D
                mem(pc) <= x"3D"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0496
                mem(pc) <= x"96"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                mem(pc) <= x"DB"; pc := pc + 1;  -- STP
                
                -- IRQ handler at $8110: copy stack frame to $0490-$0495, RTI
                pc := 16#8110#;
                -- Copy $01FF (PC byte3) to $0490
                mem(pc) <= x"AD"; pc := pc + 1;  -- LDA $01FF
                mem(pc) <= x"FF"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0490
                mem(pc) <= x"90"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                -- Copy $01FE (PC byte2) to $0491
                mem(pc) <= x"AD"; pc := pc + 1;  -- LDA $01FE
                mem(pc) <= x"FE"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0491
                mem(pc) <= x"91"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                -- Copy $01FD (PC byte1) to $0492
                mem(pc) <= x"AD"; pc := pc + 1;  -- LDA $01FD
                mem(pc) <= x"FD"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0492
                mem(pc) <= x"92"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                -- Copy $01FC (PC byte0) to $0493
                mem(pc) <= x"AD"; pc := pc + 1;  -- LDA $01FC
                mem(pc) <= x"FC"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0493
                mem(pc) <= x"93"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                -- Copy $01FB (P high) to $0494
                mem(pc) <= x"AD"; pc := pc + 1;  -- LDA $01FB
                mem(pc) <= x"FB"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0494
                mem(pc) <= x"94"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                -- Copy $01FA (P low) to $0495
                mem(pc) <= x"AD"; pc := pc + 1;  -- LDA $01FA
                mem(pc) <= x"FA"; pc := pc + 1;
                mem(pc) <= x"01"; pc := pc + 1;
                mem(pc) <= x"8D"; pc := pc + 1;  -- STA $0495
                mem(pc) <= x"95"; pc := pc + 1;
                mem(pc) <= x"04"; pc := pc + 1;
                mem(pc) <= x"40"; pc := pc + 1;  -- RTI
                
                -- IRQ vector -> $8110 (32-bit: $FFFE-$0001)
                mem(16#FFFE#) <= x"10";
                mem(16#FFFF#) <= x"81";
                mem(16#0000#) <= x"00";
                mem(16#0001#) <= x"00";
                
                -- Reset vector -> $8000
                mem(16#FFFC#) <= x"00";
                mem(16#FFFD#) <= x"80";
                
                init_done <= '1';
                report "Test program loaded" severity note;
            end if;
            
            if we = '1' and rdy = '1' then
                mem(to_integer(unsigned(addr(15 downto 0)))) <= data_out;
                report "[@" & integer'image(cycle_count) & "] Write $" & 
                       to_hstring(addr(15 downto 0)) & " = $" & to_hstring(data_out)
                    severity note;
            end if;
            
            -- Trace all cycles for debugging
            if cycle_count < 200 and rdy = '1' then
                report "[@" & integer'image(cycle_count) & "] PC=$" & 
                       to_hstring(addr(15 downto 0)) & " D=$" & to_hstring(data_in) &
                       " WE=" & std_logic'image(we) &
                       " E=" & std_logic'image(e_flag) & " M=" & to_hstring(m_flag)
                    severity note;
            end if;
        end if;
    end process;

    -- Main test process
    process
    begin
        report "=== IRQ Stack Frame Test ===" severity note;
        
        rst_n <= '0';
        wait for 1 us;  -- Longer reset to ensure initialization
        rst_n <= '1';
        report "Reset released" severity note;
        
        -- Wait for CPU to reach WAI
        wait for 3 us;
        
        -- Trigger IRQ
        report "Triggering IRQ" severity note;
        irq_n <= '0';
        wait for 200 ns;
        irq_n <= '1';
        
        -- Wait for handler and RTI
        wait for 10 us;
        
        -- Check results
        report "=== Results ===" severity note;
        report "Stack frame at $01FA-$01FF:" severity note;
        report "  $01FA (P low):   $" & to_hstring(mem(16#01FA#)) severity note;
        report "  $01FB (P high):  $" & to_hstring(mem(16#01FB#)) severity note;
        report "  $01FC (PC[7:0]): $" & to_hstring(mem(16#01FC#)) severity note;
        report "  $01FD (PC[15:8]):$" & to_hstring(mem(16#01FD#)) severity note;
        report "  $01FE (PC[23:16]):$" & to_hstring(mem(16#01FE#)) severity note;
        report "  $01FF (PC[31:24]):$" & to_hstring(mem(16#01FF#)) severity note;
        
        report "Copied to $0490-$0495:" severity note;
        report "  $0490 (PC[31:24]): $" & to_hstring(mem(16#0490#)) severity note;
        report "  $0491 (PC[23:16]): $" & to_hstring(mem(16#0491#)) severity note;
        report "  $0492 (PC[15:8]):  $" & to_hstring(mem(16#0492#)) severity note;
        report "  $0493 (PC[7:0]):   $" & to_hstring(mem(16#0493#)) severity note;
        report "  $0494 (P high):    $" & to_hstring(mem(16#0494#)) & " (expected $0C)" severity note;
        report "  $0495 (P low):     $" & to_hstring(mem(16#0495#)) & " (expected $08)" severity note;
        report "  $0496 (returned):  $" & to_hstring(mem(16#0496#)) & " (expected $3D)" severity note;
        
        -- Validation
        if mem(16#0494#) = x"0C" and mem(16#0495#) = x"08" then
            report "=== PASS: P register stack frame correct ===" severity note;
        else
            report "=== FAIL: P register stack frame incorrect ===" severity error;
            report "Expected P high=$0C, P low=$08" severity error;
        end if;
        
        wait;
    end process;

end sim;
