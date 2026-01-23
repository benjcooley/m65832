-- M65832 Core Testbench
-- Verifies basic CPU operation with simulated memory
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;
use IEEE.std_logic_textio.all;

library work;
use work.M65832_pkg.all;

entity tb_M65832_Core is
end entity tb_M65832_Core;

architecture sim of tb_M65832_Core is

    ---------------------------------------------------------------------------
    -- Clock and Reset
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal sim_done     : boolean := false;
    
    ---------------------------------------------------------------------------
    -- CPU Interface Signals
    ---------------------------------------------------------------------------
    signal addr         : std_logic_vector(31 downto 0);
    signal data_out     : std_logic_vector(7 downto 0);
    signal data_in      : std_logic_vector(7 downto 0);
    signal we           : std_logic;
    signal ce           : std_logic := '1';
    signal vda          : std_logic;
    signal vpa          : std_logic;
    signal vpb          : std_logic;
    signal mlb          : std_logic;
    signal rdy          : std_logic := '1';
    signal irq_n        : std_logic := '1';
    signal nmi_n        : std_logic := '1';
    signal abort_n      : std_logic := '1';
    signal e_flag       : std_logic;
    signal m_flag       : std_logic_vector(1 downto 0);
    signal x_flag       : std_logic_vector(1 downto 0);
    signal sync_out     : std_logic;
    
    ---------------------------------------------------------------------------
    -- Simulated Memory (64KB for now)
    ---------------------------------------------------------------------------
    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal memory : memory_t := (others => x"00");
    
    -- Test memory write interface (directly sets memory)
    signal test_wr_addr : integer range 0 to 65535 := 0;
    signal test_wr_data : std_logic_vector(7 downto 0) := x"00";
    signal test_wr_en   : std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal test_number  : integer := 0;
    signal test_passed  : integer := 0;
    signal test_failed  : integer := 0;
    signal cycle_count  : integer := 0;
    
    ---------------------------------------------------------------------------
    -- CPU State Monitoring (directly from core internals via signals)
    ---------------------------------------------------------------------------
    -- These would ideally come from the core but for now we track externally

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk_process: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;
    
    ---------------------------------------------------------------------------
    -- Cycle Counter
    ---------------------------------------------------------------------------
    cycle_counter: process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                cycle_count <= 0;
            else
                cycle_count <= cycle_count + 1;
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Device Under Test
    ---------------------------------------------------------------------------
    DUT: entity work.M65832_Core
        port map (
            CLK         => clk,
            RST_N       => rst_n,
            CE          => ce,
            ADDR        => addr,
            DATA_OUT    => data_out,
            DATA_IN     => data_in,
            WE          => we,
            RDY         => rdy,
            VPA         => vpa,
            VDA         => vda,
            VPB         => vpb,
            MLB         => mlb,
            NMI_N       => nmi_n,
            IRQ_N       => irq_n,
            ABORT_N     => abort_n,
            E_FLAG      => e_flag,
            M_FLAG      => m_flag,
            X_FLAG      => x_flag,
            SYNC        => sync_out
        );
    
    ---------------------------------------------------------------------------
    -- Memory Model
    ---------------------------------------------------------------------------
    -- Asynchronous read for CPU (critical for correct timing!)
    data_in <= memory(to_integer(unsigned(addr(15 downto 0))));
    
    -- Single memory process (handles both CPU writes and test writes)
    memory_process: process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            -- Test writes have priority (used for initialization)
            if test_wr_en = '1' then
                memory(test_wr_addr) <= test_wr_data;
            -- CPU writes
            elsif we = '1' then
                addr_int := to_integer(unsigned(addr(15 downto 0)));
                memory(addr_int) <= data_out;
                report "MEM WRITE: $" & to_hstring(addr(15 downto 0)) & 
                       " <= $" & to_hstring(data_out) &
                       " @ cycle " & integer'image(cycle_count);
            end if;
            
            -- Debug: show fetches and reads (first 30 cycles only)
            addr_int := to_integer(unsigned(addr(15 downto 0)));
            if cycle_count < 30 then
                report "CYCLE " & integer'image(cycle_count) & 
                       ": ADDR=$" & to_hstring(addr) &
                       " DATA=$" & to_hstring(memory(addr_int)) &
                       " WE=" & std_logic'image(we) &
                       " SYNC=" & std_logic'image(sync_out) &
                       " E=" & std_logic'image(e_flag);
            end if;
        end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Test Stimulus
    ---------------------------------------------------------------------------
    test_process: process
        
        -- Helper procedure to load a byte into memory (via test write interface)
        procedure poke(addr_val : integer; data_val : std_logic_vector(7 downto 0)) is
        begin
            test_wr_addr <= addr_val;
            test_wr_data <= data_val;
            test_wr_en <= '1';
            wait until rising_edge(clk);
            test_wr_en <= '0';
        end procedure;
        
        -- Helper to load 16-bit value (little-endian)
        procedure poke16(addr_val : integer; data_val : std_logic_vector(15 downto 0)) is
        begin
            poke(addr_val, data_val(7 downto 0));
            poke(addr_val + 1, data_val(15 downto 8));
        end procedure;
        
        -- Wait for N clock cycles
        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
        
        -- Check memory value
        procedure check_mem(addr_val : integer; expected : std_logic_vector(7 downto 0); msg : string) is
            variable addr_slv : std_logic_vector(15 downto 0);
        begin
            test_number <= test_number + 1;
            addr_slv := std_logic_vector(to_unsigned(addr_val, 16));
            if memory(addr_val) = expected then
                test_passed <= test_passed + 1;
                report "PASS: " & msg & " - $" & to_hstring(addr_slv) & 
                       " = $" & to_hstring(memory(addr_val));
            else
                test_failed <= test_failed + 1;
                report "FAIL: " & msg & " - $" & to_hstring(addr_slv) & 
                       " = $" & to_hstring(memory(addr_val)) &
                       " expected $" & to_hstring(expected)
                    severity error;
            end if;
        end procedure;
        
    begin
        report "========================================";
        report "M65832 Core Testbench Starting";
        report "========================================";
        
        -----------------------------------------------------------------------
        -- Initialize Memory with Reset Vector
        -----------------------------------------------------------------------
        -- Reset vector at $FFFC/$FFFD points to $8000
        poke16(16#FFFC#, x"8000");
        
        -- IRQ vector at $FFFE/$FFFF
        poke16(16#FFFE#, x"8100");
        
        -- NMI vector at $FFFA/$FFFB
        poke16(16#FFFA#, x"8200");
        
        -- Debug: verify memory initialization
        wait for 1 ns;
        report "MEMORY CHECK: $FFFC = $" & to_hstring(memory(16#FFFC#)) & 
               ", $FFFD = $" & to_hstring(memory(16#FFFD#));
        
        -----------------------------------------------------------------------
        -- TEST 1: Simple LDA immediate, STA absolute
        -----------------------------------------------------------------------
        report "";
        report "TEST 1: LDA #$42, STA $0200";
        
        -- Program at $8000:
        -- LDA #$42    ; A9 42
        -- STA $0200   ; 8D 00 02
        -- STP         ; DB (stop - we'll use BRK for now)
        -- BRK         ; 00
        
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"42");  -- $42
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"00");  -- $00
        poke(16#8004#, x"02");  -- $02  -> $0200
        poke(16#8005#, x"00");  -- BRK
        
        -- Apply reset
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        
        -- Run for enough cycles
        wait_cycles(50);
        
        -- Check result
        check_mem(16#0200#, x"42", "LDA #$42, STA $0200");
        
        -----------------------------------------------------------------------
        -- TEST 2: LDX, LDY, STX, STY
        -----------------------------------------------------------------------
        report "";
        report "TEST 2: LDX #$10, LDY #$20, STX $0201, STY $0202";
        
        -- Program at $8000:
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"10");  -- $10
        poke(16#8002#, x"A0");  -- LDY #
        poke(16#8003#, x"20");  -- $20
        poke(16#8004#, x"8E");  -- STX abs
        poke(16#8005#, x"01");  -- $01
        poke(16#8006#, x"02");  -- $02  -> $0201
        poke(16#8007#, x"8C");  -- STY abs
        poke(16#8008#, x"02");  -- $02
        poke(16#8009#, x"02");  -- $02  -> $0202
        poke(16#800A#, x"00");  -- BRK
        
        -- Reset and run
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0201#, x"10", "STX $0201");
        check_mem(16#0202#, x"20", "STY $0202");
        
        -----------------------------------------------------------------------
        -- TEST 3: ADC (add with carry)
        -----------------------------------------------------------------------
        report "";
        report "TEST 3: CLC, LDA #$30, ADC #$12 -> $42";
        
        -- Program at $8000:
        poke(16#8000#, x"18");  -- CLC
        poke(16#8001#, x"A9");  -- LDA #
        poke(16#8002#, x"30");  -- $30
        poke(16#8003#, x"69");  -- ADC #
        poke(16#8004#, x"12");  -- $12  -> A = $42
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"03");  -- $03
        poke(16#8007#, x"02");  -- $02  -> $0203
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0203#, x"42", "ADC #$12 result");
        
        -----------------------------------------------------------------------
        -- TEST 4: Zero page addressing
        -----------------------------------------------------------------------
        report "";
        report "TEST 4: Zero page - LDA $10, STA $11";
        
        -- Pre-load zero page
        poke(16#0010#, x"AA");
        
        -- Program:
        poke(16#8000#, x"A5");  -- LDA zp
        poke(16#8001#, x"10");  -- $10
        poke(16#8002#, x"85");  -- STA zp
        poke(16#8003#, x"11");  -- $11
        poke(16#8004#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(50);
        
        check_mem(16#0011#, x"AA", "Zero page STA $11");
        
        -----------------------------------------------------------------------
        -- TEST 5: INC / DEC
        -----------------------------------------------------------------------
        report "";
        report "TEST 5: INC and DEC";
        
        poke(16#0020#, x"05");  -- Initial value
        
        -- Program:
        poke(16#8000#, x"E6");  -- INC zp
        poke(16#8001#, x"20");  -- $20 (5 -> 6)
        poke(16#8002#, x"E6");  -- INC zp
        poke(16#8003#, x"20");  -- $20 (6 -> 7)
        poke(16#8004#, x"C6");  -- DEC zp
        poke(16#8005#, x"20");  -- $20 (7 -> 6)
        poke(16#8006#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0020#, x"06", "INC/DEC result");
        
        -----------------------------------------------------------------------
        -- TEST 6: Branch (BEQ/BNE)
        -----------------------------------------------------------------------
        report "";
        report "TEST 6: Branch instructions";
        
        -- Program: Load 0, branch if equal, store marker
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"00");  -- $00
        poke(16#8002#, x"F0");  -- BEQ
        poke(16#8003#, x"02");  -- +2 (skip next 2 bytes)
        poke(16#8004#, x"A9");  -- LDA # (skipped)
        poke(16#8005#, x"FF");  -- $FF  (skipped)
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"04");  -- $04
        poke(16#8008#, x"02");  -- $02  -> $0204
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        -- If branch worked, $0204 should be $00 (not $FF)
        check_mem(16#0204#, x"00", "BEQ branch taken");
        
        -----------------------------------------------------------------------
        -- TEST 7: JSR/RTS
        -----------------------------------------------------------------------
        report "";
        report "TEST 7: JSR and RTS";
        
        -- Initialize stack pointer area
        poke(16#01FF#, x"00");
        poke(16#01FE#, x"00");
        
        -- Program at $8000:
        -- JSR $8010   ; Jump to subroutine
        -- STA $0205   ; Store result
        -- BRK
        --
        -- Subroutine at $8010:
        -- LDA #$99
        -- RTS
        
        poke(16#8000#, x"20");  -- JSR
        poke(16#8001#, x"10");  -- $10
        poke(16#8002#, x"80");  -- $80  -> $8010
        poke(16#8003#, x"8D");  -- STA abs
        poke(16#8004#, x"05");  -- $05
        poke(16#8005#, x"02");  -- $02  -> $0205
        poke(16#8006#, x"00");  -- BRK
        
        -- Subroutine
        poke(16#8010#, x"A9");  -- LDA #
        poke(16#8011#, x"99");  -- $99
        poke(16#8012#, x"60");  -- RTS
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#0205#, x"99", "JSR/RTS result");
        
        -----------------------------------------------------------------------
        -- TEST 8: Indexed addressing (LDA abs,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 8: Indexed addressing LDA $0300,X";
        
        -- Pre-load data
        poke(16#0305#, x"BB");
        
        -- Program:
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"05");  -- $05
        poke(16#8002#, x"BD");  -- LDA abs,X
        poke(16#8003#, x"00");  -- $00
        poke(16#8004#, x"03");  -- $03  -> $0300 + X = $0305
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"06");  -- $06
        poke(16#8007#, x"02");  -- $02  -> $0206
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0206#, x"BB", "LDA abs,X result");
        
        -----------------------------------------------------------------------
        -- TEST 9: INX, DEX, INY, DEY
        -----------------------------------------------------------------------
        report "";
        report "TEST 9: INX, DEX, INY, DEY";
        
        -- Program: LDX #$10, INX, INX, DEX -> X=$11
        --          LDY #$20, INY, DEY, DEY -> Y=$1F
        --          STX $0207, STY $0208
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"10");  -- $10
        poke(16#8002#, x"E8");  -- INX  -> $11
        poke(16#8003#, x"E8");  -- INX  -> $12
        poke(16#8004#, x"CA");  -- DEX  -> $11
        poke(16#8005#, x"A0");  -- LDY #
        poke(16#8006#, x"20");  -- $20
        poke(16#8007#, x"C8");  -- INY  -> $21
        poke(16#8008#, x"88");  -- DEY  -> $20
        poke(16#8009#, x"88");  -- DEY  -> $1F
        poke(16#800A#, x"8E");  -- STX abs
        poke(16#800B#, x"07");  -- $07
        poke(16#800C#, x"02");  -- $02  -> $0207
        poke(16#800D#, x"8C");  -- STY abs
        poke(16#800E#, x"08");  -- $08
        poke(16#800F#, x"02");  -- $02  -> $0208
        poke(16#8010#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#0207#, x"11", "INX/DEX result");
        check_mem(16#0208#, x"1F", "INY/DEY result");
        
        -----------------------------------------------------------------------
        -- TEST 10: Register transfers TAX, TXA, TAY, TYA
        -----------------------------------------------------------------------
        report "";
        report "TEST 10: Register transfers";
        
        -- Program: LDA #$55, TAX, LDA #$AA, TAY, TXA, STA $0209
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"55");  -- $55
        poke(16#8002#, x"AA");  -- TAX  -> X=$55
        poke(16#8003#, x"A9");  -- LDA #
        poke(16#8004#, x"AA");  -- $AA
        poke(16#8005#, x"A8");  -- TAY  -> Y=$AA
        poke(16#8006#, x"8A");  -- TXA  -> A=$55
        poke(16#8007#, x"8D");  -- STA abs
        poke(16#8008#, x"09");  -- $09
        poke(16#8009#, x"02");  -- $02  -> $0209
        poke(16#800A#, x"98");  -- TYA  -> A=$AA
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"0A");  -- $0A
        poke(16#800D#, x"02");  -- $02  -> $020A
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#0209#, x"55", "TXA result");
        check_mem(16#020A#, x"AA", "TYA result");
        
        -----------------------------------------------------------------------
        -- TEST 11: Logical operations ORA, AND, EOR
        -----------------------------------------------------------------------
        report "";
        report "TEST 11: ORA, AND, EOR";
        
        -- Program: LDA #$0F, ORA #$F0 -> $FF, STA $020B
        --          LDA #$FF, AND #$0F -> $0F, STA $020C
        --          LDA #$FF, EOR #$AA -> $55, STA $020D
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"0F");  -- $0F
        poke(16#8002#, x"09");  -- ORA #
        poke(16#8003#, x"F0");  -- $F0  -> A=$FF
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"0B");  -- $0B
        poke(16#8006#, x"02");  -- $02  -> $020B
        poke(16#8007#, x"A9");  -- LDA #
        poke(16#8008#, x"FF");  -- $FF
        poke(16#8009#, x"29");  -- AND #
        poke(16#800A#, x"0F");  -- $0F  -> A=$0F
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"0C");  -- $0C
        poke(16#800D#, x"02");  -- $02  -> $020C
        poke(16#800E#, x"A9");  -- LDA #
        poke(16#800F#, x"FF");  -- $FF
        poke(16#8010#, x"49");  -- EOR #
        poke(16#8011#, x"AA");  -- $AA  -> A=$55
        poke(16#8012#, x"8D");  -- STA abs
        poke(16#8013#, x"0D");  -- $0D
        poke(16#8014#, x"02");  -- $02  -> $020D
        poke(16#8015#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#020B#, x"FF", "ORA result");
        check_mem(16#020C#, x"0F", "AND result");
        check_mem(16#020D#, x"55", "EOR result");
        
        -----------------------------------------------------------------------
        -- TEST 12: SBC (subtract with carry)
        -----------------------------------------------------------------------
        report "";
        report "TEST 12: SBC";
        
        -- Program: SEC, LDA #$50, SBC #$10 -> $40, STA $020E
        poke(16#8000#, x"38");  -- SEC
        poke(16#8001#, x"A9");  -- LDA #
        poke(16#8002#, x"50");  -- $50
        poke(16#8003#, x"E9");  -- SBC #
        poke(16#8004#, x"10");  -- $10  -> A=$40
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"0E");  -- $0E
        poke(16#8007#, x"02");  -- $02  -> $020E
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#020E#, x"40", "SBC result");
        
        -----------------------------------------------------------------------
        -- TEST 13: Accumulator shifts ASL A, LSR A
        -----------------------------------------------------------------------
        report "";
        report "TEST 13: ASL A, LSR A";
        
        -- Program: LDA #$11, ASL A -> $22, ASL A -> $44, STA $020F
        --          LDA #$80, LSR A -> $40, LSR A -> $20, STA $0210
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"11");  -- $11
        poke(16#8002#, x"0A");  -- ASL A  -> $22
        poke(16#8003#, x"0A");  -- ASL A  -> $44
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"0F");  -- $0F
        poke(16#8006#, x"02");  -- $02  -> $020F
        poke(16#8007#, x"A9");  -- LDA #
        poke(16#8008#, x"80");  -- $80
        poke(16#8009#, x"4A");  -- LSR A  -> $40
        poke(16#800A#, x"4A");  -- LSR A  -> $20
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"10");  -- $10
        poke(16#800D#, x"02");  -- $02  -> $0210
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#020F#, x"44", "ASL A result");
        check_mem(16#0210#, x"20", "LSR A result");
        
        -----------------------------------------------------------------------
        -- TEST 14: LDA abs,Y addressing
        -----------------------------------------------------------------------
        report "";
        report "TEST 14: LDA abs,Y";
        
        -- Pre-load data
        poke(16#0403#, x"CC");
        
        -- Program: LDY #$03, LDA $0400,Y -> load from $0403, STA $0211
        poke(16#8000#, x"A0");  -- LDY #
        poke(16#8001#, x"03");  -- $03
        poke(16#8002#, x"B9");  -- LDA abs,Y
        poke(16#8003#, x"00");  -- $00
        poke(16#8004#, x"04");  -- $04  -> $0400 + Y = $0403
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"11");  -- $11
        poke(16#8007#, x"02");  -- $02  -> $0211
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0211#, x"CC", "LDA abs,Y result");
        
        -----------------------------------------------------------------------
        -- TEST 15: BNE not taken (Z=1)
        -----------------------------------------------------------------------
        report "";
        report "TEST 15: BNE not taken";
        
        -- Program: LDA #$00 (sets Z), BNE +2 (not taken), LDA #$77, STA $0212
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"00");  -- $00  (Z=1)
        poke(16#8002#, x"D0");  -- BNE
        poke(16#8003#, x"02");  -- +2 (skip next 2 bytes) - should NOT be taken
        poke(16#8004#, x"A9");  -- LDA # (executed)
        poke(16#8005#, x"77");  -- $77
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"12");  -- $12
        poke(16#8008#, x"02");  -- $02  -> $0212
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        -- If branch NOT taken, $0212 should be $77
        check_mem(16#0212#, x"77", "BNE not taken");
        
        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        report "";
        report "========================================";
        report "TEST SUMMARY";
        report "========================================";
        report "Total tests: " & integer'image(test_number);
        report "Passed:      " & integer'image(test_passed);
        report "Failed:      " & integer'image(test_failed);
        report "========================================";
        
        if test_failed = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;
        
        -- End simulation
        wait_cycles(10);
        sim_done <= true;
        wait;
        
    end process;

end architecture sim;
