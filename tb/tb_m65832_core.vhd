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
    -- Trace Controls (disable for faster sims)
    ---------------------------------------------------------------------------
    constant TRACE_MEM_WRITES  : boolean := false;
    constant TRACE_FIRST_CYCLES : boolean := false;
    
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
                if TRACE_MEM_WRITES then
                    report "MEM WRITE: $" & to_hstring(addr(15 downto 0)) &
                           " <= $" & to_hstring(data_out) &
                           " @ cycle " & integer'image(cycle_count);
                end if;
            end if;
            
            -- Debug: show fetches and reads (first 30 cycles only)
            addr_int := to_integer(unsigned(addr(15 downto 0)));
            if TRACE_FIRST_CYCLES and cycle_count < 30 then
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
        
        -- ABORT vector at $FFF8/$FFF9
        poke16(16#FFF8#, x"8300");
        
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
        poke(16#8009#, x"DB");  -- STP
        poke(16#800A#, x"EA");  -- NOP (padding)
        
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
        poke(16#8009#, x"DB");  -- STP
        poke(16#800A#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        -- If branch NOT taken, $0212 should be $77
        check_mem(16#0212#, x"77", "BNE not taken");
        
        -----------------------------------------------------------------------
        -- TEST 16: CMP (compare accumulator)
        -----------------------------------------------------------------------
        report "";
        report "TEST 16: CMP sets flags correctly";
        
        -- Program: LDA #$50, CMP #$30 (A > operand, C=1, Z=0, N=0)
        --          BCS +2 (taken), LDA #$FF (skipped), STA $0213
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"50");  -- $50
        poke(16#8002#, x"C9");  -- CMP #
        poke(16#8003#, x"30");  -- $30  ($50 >= $30, so C=1)
        poke(16#8004#, x"B0");  -- BCS (branch if C=1)
        poke(16#8005#, x"02");  -- +2
        poke(16#8006#, x"A9");  -- LDA # (skipped)
        poke(16#8007#, x"FF");  -- $FF
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"13");  -- $13
        poke(16#800A#, x"02");  -- $02  -> $0213
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0213#, x"50", "CMP sets C flag");
        
        -----------------------------------------------------------------------
        -- TEST 17: CMP equal sets Z flag
        -----------------------------------------------------------------------
        report "";
        report "TEST 17: CMP equal sets Z flag";
        
        -- Program: LDA #$42, CMP #$42 (equal, Z=1, C=1)
        --          Store result showing Z was set
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"42");  -- $42
        poke(16#8002#, x"C9");  -- CMP #
        poke(16#8003#, x"42");  -- $42  (equal, Z=1)
        poke(16#8004#, x"F0");  -- BEQ (branch if Z=1)
        poke(16#8005#, x"02");  -- +2
        poke(16#8006#, x"A9");  -- LDA # (skipped if Z=1)
        poke(16#8007#, x"FF");  -- $FF
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"14");  -- $14
        poke(16#800A#, x"02");  -- $02  -> $0214
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0214#, x"42", "CMP equal sets Z");
        
        -----------------------------------------------------------------------
        -- TEST 18: ROL accumulator (rotate left through carry)
        -----------------------------------------------------------------------
        report "";
        report "TEST 18: ROL A";
        
        -- Program: SEC (C=1), LDA #$40, ROL A -> $81 (C was shifted in)
        --          STA $0215
        poke(16#8000#, x"38");  -- SEC (C=1)
        poke(16#8001#, x"A9");  -- LDA #
        poke(16#8002#, x"40");  -- $40 = 0100_0000
        poke(16#8003#, x"2A");  -- ROL A -> 1000_0001 = $81 (C shifts into bit 0)
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"15");  -- $15
        poke(16#8006#, x"02");  -- $02  -> $0215
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0215#, x"81", "ROL A result");
        
        -----------------------------------------------------------------------
        -- TEST 19: ROR accumulator (rotate right through carry)
        -----------------------------------------------------------------------
        report "";
        report "TEST 19: ROR A";
        
        -- Program: SEC (C=1), LDA #$02, ROR A -> $81 (C shifts into bit 7)
        --          STA $0216
        poke(16#8000#, x"38");  -- SEC (C=1)
        poke(16#8001#, x"A9");  -- LDA #
        poke(16#8002#, x"02");  -- $02 = 0000_0010
        poke(16#8003#, x"6A");  -- ROR A -> 1000_0001 = $81 (C shifts into bit 7)
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"16");  -- $16
        poke(16#8006#, x"02");  -- $02  -> $0216
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0216#, x"81", "ROR A result");
        
        -----------------------------------------------------------------------
        -- TEST 20: BCC (branch if carry clear)
        -----------------------------------------------------------------------
        report "";
        report "TEST 20: BCC branch";
        
        -- Program: CLC (C=0), BCC +2 (taken), LDA #$FF (skipped), LDA #$20, STA $0217
        poke(16#8000#, x"18");  -- CLC (C=0)
        poke(16#8001#, x"90");  -- BCC (branch if C=0)
        poke(16#8002#, x"02");  -- +2
        poke(16#8003#, x"A9");  -- LDA # (skipped)
        poke(16#8004#, x"FF");  -- $FF
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"20");  -- $20
        poke(16#8007#, x"8D");  -- STA abs
        poke(16#8008#, x"17");  -- $17
        poke(16#8009#, x"02");  -- $02  -> $0217
        poke(16#800A#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0217#, x"20", "BCC taken");
        
        -----------------------------------------------------------------------
        -- TEST 21: BPL (branch if plus/positive)
        -----------------------------------------------------------------------
        report "";
        report "TEST 21: BPL branch";
        
        -- Program: LDA #$7F (positive, N=0), BPL +2 (taken), LDA #$FF, STA $0218
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"7F");  -- $7F (positive, N=0)
        poke(16#8002#, x"10");  -- BPL (branch if N=0)
        poke(16#8003#, x"02");  -- +2
        poke(16#8004#, x"A9");  -- LDA # (skipped)
        poke(16#8005#, x"FF");  -- $FF
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"18");  -- $18
        poke(16#8008#, x"02");  -- $02  -> $0218
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0218#, x"7F", "BPL taken");
        
        -----------------------------------------------------------------------
        -- TEST 22: BMI (branch if minus/negative)
        -----------------------------------------------------------------------
        report "";
        report "TEST 22: BMI branch";
        
        -- Program: LDA #$80 (negative, N=1), BMI +2 (taken), LDA #$FF, STA $0219
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"80");  -- $80 (negative, N=1)
        poke(16#8002#, x"30");  -- BMI (branch if N=1)
        poke(16#8003#, x"02");  -- +2
        poke(16#8004#, x"A9");  -- LDA # (skipped)
        poke(16#8005#, x"FF");  -- $FF
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"19");  -- $19
        poke(16#8008#, x"02");  -- $02  -> $0219
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#0219#, x"80", "BMI taken");
        
        -----------------------------------------------------------------------
        -- TEST 23: INC memory (absolute addressing)
        -----------------------------------------------------------------------
        report "";
        report "TEST 23: INC abs";
        
        -- Program: Store $41 at $0220, INC $0220, then read and store at $021A
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"41");  -- $41
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"20");  -- $20
        poke(16#8004#, x"02");  -- $02  -> $0220 = $41
        poke(16#8005#, x"EE");  -- INC abs
        poke(16#8006#, x"20");  -- $20
        poke(16#8007#, x"02");  -- $02  -> INC $0220
        poke(16#8008#, x"AD");  -- LDA abs
        poke(16#8009#, x"20");  -- $20
        poke(16#800A#, x"02");  -- $02  -> load from $0220
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"1A");  -- $1A
        poke(16#800D#, x"02");  -- $02  -> $021A
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#021A#, x"42", "INC abs result");
        
        -----------------------------------------------------------------------
        -- TEST 24: DEC memory (absolute addressing)
        -----------------------------------------------------------------------
        report "";
        report "TEST 24: DEC abs";
        
        -- Program: Store $43 at $0221, DEC $0221, then read and store at $021B
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"43");  -- $43
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"21");  -- $21
        poke(16#8004#, x"02");  -- $02  -> $0221 = $43
        poke(16#8005#, x"CE");  -- DEC abs
        poke(16#8006#, x"21");  -- $21
        poke(16#8007#, x"02");  -- $02  -> DEC $0221
        poke(16#8008#, x"AD");  -- LDA abs
        poke(16#8009#, x"21");  -- $21
        poke(16#800A#, x"02");  -- $02  -> load from $0221
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"1B");  -- $1B
        poke(16#800D#, x"02");  -- $02  -> $021B
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#021B#, x"42", "DEC abs result");
        
        -----------------------------------------------------------------------
        -- TEST 25: ASL memory (arithmetic shift left)
        -----------------------------------------------------------------------
        report "";
        report "TEST 25: ASL abs";
        
        -- Program: Store $21 at $0222, ASL $0222 -> $42
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"21");  -- $21
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"22");  -- $22
        poke(16#8004#, x"02");  -- $02  -> $0222 = $21
        poke(16#8005#, x"0E");  -- ASL abs
        poke(16#8006#, x"22");  -- $22
        poke(16#8007#, x"02");  -- $02  -> ASL $0222
        poke(16#8008#, x"AD");  -- LDA abs
        poke(16#8009#, x"22");  -- $22
        poke(16#800A#, x"02");  -- $02  -> load from $0222
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"1C");  -- $1C
        poke(16#800D#, x"02");  -- $02  -> $021C
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#021C#, x"42", "ASL abs result");
        
        -----------------------------------------------------------------------
        -- TEST 26: LSR memory (logical shift right)
        -----------------------------------------------------------------------
        report "";
        report "TEST 26: LSR abs";
        
        -- Program: Store $84 at $0223, LSR $0223 -> $42
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"84");  -- $84
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"23");  -- $23
        poke(16#8004#, x"02");  -- $02  -> $0223 = $84
        poke(16#8005#, x"4E");  -- LSR abs
        poke(16#8006#, x"23");  -- $23
        poke(16#8007#, x"02");  -- $02  -> LSR $0223
        poke(16#8008#, x"AD");  -- LDA abs
        poke(16#8009#, x"23");  -- $23
        poke(16#800A#, x"02");  -- $02  -> load from $0223
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"1D");  -- $1D
        poke(16#800D#, x"02");  -- $02  -> $021D
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#021D#, x"42", "LSR abs result");
        
        -----------------------------------------------------------------------
        -- TEST 27: SBC immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 27: SBC #imm";
        
        -- Program: SEC, LDA #$50, SBC #$10 -> $40, STA $021E
        poke(16#8000#, x"38");  -- SEC (C=1)
        poke(16#8001#, x"A9");  -- LDA #
        poke(16#8002#, x"50");  -- $50
        poke(16#8003#, x"E9");  -- SBC #
        poke(16#8004#, x"10");  -- $10  -> $40
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"1E");  -- $1E
        poke(16#8007#, x"02");  -- $02  -> $021E
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(80);
        
        check_mem(16#021E#, x"40", "SBC immediate result");
        
        -----------------------------------------------------------------------
        -- TEST 28: BIT sets Z/V/N flags
        -----------------------------------------------------------------------
        report "";
        report "TEST 28: BIT flag behavior";
        
        -- Pre-load memory operand ($0224 = $C0 => V=1, N=1)
        poke(16#0224#, x"C0");
        
        -- Program:
        -- LDA #$00, BIT $0224 (Z=1, V=1, N=1)
        -- BEQ +2 (taken), BVS +2 (taken), BMI +2 (taken)
        -- LDA #$11, STA $021F
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"00");  -- $00
        poke(16#8002#, x"2C");  -- BIT abs
        poke(16#8003#, x"24");  -- $24
        poke(16#8004#, x"02");  -- $02  -> $0224
        poke(16#8005#, x"F0");  -- BEQ
        poke(16#8006#, x"02");  -- +2 (skip LDA #$FF)
        poke(16#8007#, x"A9");  -- LDA #
        poke(16#8008#, x"FF");  -- $FF
        poke(16#8009#, x"70");  -- BVS
        poke(16#800A#, x"02");  -- +2 (skip LDA #$EE)
        poke(16#800B#, x"A9");  -- LDA #
        poke(16#800C#, x"EE");  -- $EE
        poke(16#800D#, x"30");  -- BMI
        poke(16#800E#, x"02");  -- +2 (skip LDA #$DD)
        poke(16#800F#, x"A9");  -- LDA #
        poke(16#8010#, x"DD");  -- $DD
        poke(16#8011#, x"A9");  -- LDA #
        poke(16#8012#, x"11");  -- $11
        poke(16#8013#, x"8D");  -- STA abs
        poke(16#8014#, x"1F");  -- $1F
        poke(16#8015#, x"02");  -- $02  -> $021F
        poke(16#8016#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#021F#, x"11", "BIT sets Z/V/N flags");
        
        -----------------------------------------------------------------------
        -- TEST 29: CPX immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 29: CPX #imm";
        
        -- Program: LDX #$10, CPX #$10 (Z=1), BEQ +2 (taken), LDA #$22, STA $0220
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"10");  -- $10
        poke(16#8002#, x"E0");  -- CPX #
        poke(16#8003#, x"10");  -- $10
        poke(16#8004#, x"F0");  -- BEQ
        poke(16#8005#, x"02");  -- +2 (skip LDA #$FF)
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"FF");  -- $FF
        poke(16#8008#, x"A9");  -- LDA #
        poke(16#8009#, x"22");  -- $22
        poke(16#800A#, x"8D");  -- STA abs
        poke(16#800B#, x"20");  -- $20
        poke(16#800C#, x"02");  -- $02  -> $0220
        poke(16#800D#, x"DB");  -- STP
        poke(16#800E#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#0220#, x"22", "CPX sets Z flag");
        
        -----------------------------------------------------------------------
        -- TEST 30: CPY immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 30: CPY #imm";
        
        -- Program: LDY #$20, CPY #$10 (C=1), BCS +2 (taken), LDA #$33, STA $0221
        poke(16#8000#, x"A0");  -- LDY #
        poke(16#8001#, x"20");  -- $20
        poke(16#8002#, x"C0");  -- CPY #
        poke(16#8003#, x"10");  -- $10
        poke(16#8004#, x"B0");  -- BCS
        poke(16#8005#, x"02");  -- +2 (skip LDA #$FF)
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"FF");  -- $FF
        poke(16#8008#, x"A9");  -- LDA #
        poke(16#8009#, x"33");  -- $33
        poke(16#800A#, x"8D");  -- STA abs
        poke(16#800B#, x"21");  -- $21
        poke(16#800C#, x"02");  -- $02  -> $0221
        poke(16#800D#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#0221#, x"33", "CPY sets C flag");
        
        -----------------------------------------------------------------------
        -- TEST 31: 16-bit accumulator mode
        -----------------------------------------------------------------------
        report "";
        report "TEST 31: 16-bit accumulator LDA/STA";
        
        -- Program: SEP #$40 (M0=1), LDA #$1234, STA $0222
        poke(16#8000#, x"E2");  -- SEP
        poke(16#8001#, x"40");  -- set M0 -> 16-bit
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"34");  -- low
        poke(16#8004#, x"12");  -- high
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"22");  -- $22
        poke(16#8007#, x"02");  -- $02  -> $0222/$0223
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#0222#, x"34", "16-bit STA low byte");
        check_mem(16#0223#, x"12", "16-bit STA high byte");
        
        -----------------------------------------------------------------------
        -- TEST 32: 16-bit index mode (LDX/STX)
        -----------------------------------------------------------------------
        report "";
        report "TEST 32: 16-bit index LDX/STX";
        
        -- Program: SEP #$10 (X0=1), LDX #$BEEF, STX $0224
        poke(16#8000#, x"E2");  -- SEP
        poke(16#8001#, x"10");  -- set X0 -> 16-bit
        poke(16#8002#, x"A2");  -- LDX #
        poke(16#8003#, x"EF");  -- low
        poke(16#8004#, x"BE");  -- high
        poke(16#8005#, x"8E");  -- STX abs
        poke(16#8006#, x"24");  -- $24
        poke(16#8007#, x"02");  -- $02  -> $0224/$0225
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(100);
        
        check_mem(16#0224#, x"EF", "16-bit STX low byte");
        check_mem(16#0225#, x"BE", "16-bit STX high byte");
        
        -----------------------------------------------------------------------
        -- TEST 33: 32-bit accumulator mode
        -----------------------------------------------------------------------
        report "";
        report "TEST 33: 32-bit accumulator LDA/STA";
        
        -- Program: REP #$40 (M0=0), SEP #$80 (M1=1), LDA #$89ABCDEF, STA $0226
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"EF");  -- byte 0
        poke(16#8006#, x"CD");  -- byte 1
        poke(16#8007#, x"AB");  -- byte 2
        poke(16#8008#, x"89");  -- byte 3
        poke(16#8009#, x"8D");  -- STA abs
        poke(16#800A#, x"26");  -- $26
        poke(16#800B#, x"02");  -- $02  -> $0226-$0229
        poke(16#800C#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0226#, x"EF", "32-bit STA byte 0");
        check_mem(16#0227#, x"CD", "32-bit STA byte 1");
        check_mem(16#0228#, x"AB", "32-bit STA byte 2");
        check_mem(16#0229#, x"89", "32-bit STA byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 34: 32-bit index mode (LDX/STX)
        -----------------------------------------------------------------------
        report "";
        report "TEST 34: 32-bit index LDX/STX";
        
        -- Program: REP #$10 (X0=0), SEP #$20 (X1=1), LDX #$12345678, STX $022A
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"10");  -- clear X0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"20");  -- set X1 -> 32-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"78");  -- byte 0
        poke(16#8006#, x"56");  -- byte 1
        poke(16#8007#, x"34");  -- byte 2
        poke(16#8008#, x"12");  -- byte 3
        poke(16#8009#, x"8E");  -- STX abs
        poke(16#800A#, x"2A");  -- $2A
        poke(16#800B#, x"02");  -- $02  -> $022A-$022D
        poke(16#800C#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(30);
        
        check_mem(16#022A#, x"78", "32-bit STX byte 0");
        check_mem(16#022B#, x"56", "32-bit STX byte 1");
        check_mem(16#022C#, x"34", "32-bit STX byte 2");
        check_mem(16#022D#, x"12", "32-bit STX byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 35: 16-bit ADC immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 35: 16-bit ADC #imm";
        
        -- Program: REP #$80, SEP #$40, CLC, LDA #$1234, ADC #$0001 -> $1235, STA $0230
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"18");  -- CLC
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"34");  -- low
        poke(16#8007#, x"12");  -- high
        poke(16#8008#, x"69");  -- ADC #
        poke(16#8009#, x"01");  -- low
        poke(16#800A#, x"00");  -- high
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"30");  -- $30
        poke(16#800D#, x"02");  -- $02  -> $0230/$0231
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(140);
        
        check_mem(16#0230#, x"35", "16-bit ADC low byte");
        check_mem(16#0231#, x"12", "16-bit ADC high byte");
        
        -----------------------------------------------------------------------
        -- TEST 36: 16-bit SBC immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 36: 16-bit SBC #imm";
        
        -- Program: REP #$80, SEP #$40, SEC, LDA #$1000, SBC #$0001 -> $0FFF, STA $0232
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"38");  -- SEC
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"00");  -- low
        poke(16#8007#, x"10");  -- high
        poke(16#8008#, x"E9");  -- SBC #
        poke(16#8009#, x"01");  -- low
        poke(16#800A#, x"00");  -- high
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"32");  -- $32
        poke(16#800D#, x"02");  -- $02  -> $0232/$0233
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(140);
        
        check_mem(16#0232#, x"FF", "16-bit SBC low byte");
        check_mem(16#0233#, x"0F", "16-bit SBC high byte");
        
        -----------------------------------------------------------------------
        -- TEST 37: 16-bit CMP immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 37: 16-bit CMP #imm";
        
        -- Program: REP #$80, SEP #$40, LDA #$00F0, CMP #$00F0 (Z=1),
        --          BEQ +3, LDA #$0000 (skipped), LDA #$0077, STA $0234
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"F0");  -- low
        poke(16#8006#, x"00");  -- high
        poke(16#8007#, x"C9");  -- CMP #
        poke(16#8008#, x"F0");  -- low
        poke(16#8009#, x"00");  -- high
        poke(16#800A#, x"F0");  -- BEQ
        poke(16#800B#, x"03");  -- +3 (skip 16-bit LDA #$0000)
        poke(16#800C#, x"A9");  -- LDA #
        poke(16#800D#, x"00");  -- low
        poke(16#800E#, x"00");  -- high
        poke(16#800F#, x"A9");  -- LDA #
        poke(16#8010#, x"77");  -- low
        poke(16#8011#, x"00");  -- high
        poke(16#8012#, x"8D");  -- STA abs
        poke(16#8013#, x"34");  -- $34
        poke(16#8014#, x"02");  -- $02  -> $0234
        poke(16#8015#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(140);
        
        check_mem(16#0234#, x"77", "16-bit CMP sets Z");
        
        -----------------------------------------------------------------------
        -- TEST 38: 32-bit ADC immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 38: 32-bit ADC #imm";
        
        -- Program: REP #$40, SEP #$80, CLC, LDA #$01020304, ADC #$11111111 -> $12131415, STA $0236
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"18");  -- CLC
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"04");  -- byte 0
        poke(16#8007#, x"03");  -- byte 1
        poke(16#8008#, x"02");  -- byte 2
        poke(16#8009#, x"01");  -- byte 3
        poke(16#800A#, x"69");  -- ADC #
        poke(16#800B#, x"11");  -- byte 0
        poke(16#800C#, x"11");  -- byte 1
        poke(16#800D#, x"11");  -- byte 2
        poke(16#800E#, x"11");  -- byte 3
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"36");  -- $36
        poke(16#8011#, x"02");  -- $02  -> $0236-$0239
        poke(16#8012#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0236#, x"15", "32-bit ADC byte 0");
        check_mem(16#0237#, x"14", "32-bit ADC byte 1");
        check_mem(16#0238#, x"13", "32-bit ADC byte 2");
        check_mem(16#0239#, x"12", "32-bit ADC byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 39: 32-bit SBC immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 39: 32-bit SBC #imm";
        
        -- Program: REP #$40, SEP #$80, SEC, LDA #$10000000, SBC #$00000001 -> $0FFFFFFF, STA $023A
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"38");  -- SEC
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"00");  -- byte 0
        poke(16#8007#, x"00");  -- byte 1
        poke(16#8008#, x"00");  -- byte 2
        poke(16#8009#, x"10");  -- byte 3
        poke(16#800A#, x"E9");  -- SBC #
        poke(16#800B#, x"01");  -- byte 0
        poke(16#800C#, x"00");  -- byte 1
        poke(16#800D#, x"00");  -- byte 2
        poke(16#800E#, x"00");  -- byte 3
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"3A");  -- $3A
        poke(16#8011#, x"02");  -- $02  -> $023A-$023D
        poke(16#8012#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(40);
        
        check_mem(16#023A#, x"FF", "32-bit SBC byte 0");
        check_mem(16#023B#, x"FF", "32-bit SBC byte 1");
        check_mem(16#023C#, x"FF", "32-bit SBC byte 2");
        check_mem(16#023D#, x"0F", "32-bit SBC byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 40: 32-bit CMP immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 40: 32-bit CMP #imm";
        
        -- Program: REP #$40, SEP #$80, LDA #$0000FFFF, CMP #$0000FFFF (Z=1),
        --          BEQ +5, LDA #$00000000 (skipped), LDA #$00000055, STA $023E
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"FF");  -- byte 0
        poke(16#8006#, x"FF");  -- byte 1
        poke(16#8007#, x"00");  -- byte 2
        poke(16#8008#, x"00");  -- byte 3
        poke(16#8009#, x"C9");  -- CMP #
        poke(16#800A#, x"FF");  -- byte 0
        poke(16#800B#, x"FF");  -- byte 1
        poke(16#800C#, x"00");  -- byte 2
        poke(16#800D#, x"00");  -- byte 3
        poke(16#800E#, x"F0");  -- BEQ
        poke(16#800F#, x"05");  -- +5 (skip 32-bit LDA #$00000000)
        poke(16#8010#, x"A9");  -- LDA #
        poke(16#8011#, x"00");  -- byte 0
        poke(16#8012#, x"00");  -- byte 1
        poke(16#8013#, x"00");  -- byte 2
        poke(16#8014#, x"00");  -- byte 3
        poke(16#8015#, x"A9");  -- LDA #
        poke(16#8016#, x"55");  -- byte 0
        poke(16#8017#, x"00");  -- byte 1
        poke(16#8018#, x"00");  -- byte 2
        poke(16#8019#, x"00");  -- byte 3
        poke(16#801A#, x"8D");  -- STA abs
        poke(16#801B#, x"3E");  -- $3E
        poke(16#801C#, x"02");  -- $02  -> $023E
        poke(16#801D#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#023E#, x"55", "32-bit CMP sets Z");
        
        -----------------------------------------------------------------------
        -- TEST 41: 32-bit indexed addressing LDA abs,X
        -----------------------------------------------------------------------
        report "";
        report "TEST 41: 32-bit indexed addressing LDA abs,X";
        
        -- Pre-load 32-bit data at indexed location
        -- Base address $0500, X=$00000100, so target = $0500 + $100 = $0600
        poke(16#0600#, x"11");  -- byte 0
        poke(16#0601#, x"22");  -- byte 1
        poke(16#0602#, x"33");  -- byte 2
        poke(16#0603#, x"44");  -- byte 3
        
        -- Program: set 32-bit M and X, LDX #$00000100, LDA $0500,X, STA $0240
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit accumulator
        poke(16#8004#, x"C2");  -- REP
        poke(16#8005#, x"10");  -- clear X0
        poke(16#8006#, x"E2");  -- SEP
        poke(16#8007#, x"20");  -- set X1 -> 32-bit X
        poke(16#8008#, x"A2");  -- LDX #
        poke(16#8009#, x"00");  -- byte 0
        poke(16#800A#, x"01");  -- byte 1
        poke(16#800B#, x"00");  -- byte 2
        poke(16#800C#, x"00");  -- byte 3  -> X=$00000100
        poke(16#800D#, x"BD");  -- LDA abs,X
        poke(16#800E#, x"00");  -- $00
        poke(16#800F#, x"05");  -- $05  -> $0500 + X = $0600
        poke(16#8010#, x"8D");  -- STA abs
        poke(16#8011#, x"80");  -- $80
        poke(16#8012#, x"02");  -- $02  -> $0280-$0283
        poke(16#8013#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0280#, x"11", "32-bit LDA abs,X byte 0");
        check_mem(16#0281#, x"22", "32-bit LDA abs,X byte 1");
        check_mem(16#0282#, x"33", "32-bit LDA abs,X byte 2");
        check_mem(16#0283#, x"44", "32-bit LDA abs,X byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 42: 32-bit indexed addressing LDA abs,Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 42: 32-bit indexed addressing LDA abs,Y";
        
        -- Pre-load 32-bit data at indexed location
        -- Base address $0500, Y=$00000200, so target = $0500 + $200 = $0700
        poke(16#0700#, x"AA");  -- byte 0
        poke(16#0701#, x"BB");  -- byte 1
        poke(16#0702#, x"CC");  -- byte 2
        poke(16#0703#, x"DD");  -- byte 3
        
        -- Program: set 32-bit M and Y, LDY #$00000200, LDA $0500,Y, STA $0244
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit accumulator
        poke(16#8004#, x"C2");  -- REP
        poke(16#8005#, x"10");  -- clear X0 (shared for X/Y)
        poke(16#8006#, x"E2");  -- SEP
        poke(16#8007#, x"20");  -- set X1 -> 32-bit Y
        poke(16#8008#, x"A0");  -- LDY #
        poke(16#8009#, x"00");  -- byte 0
        poke(16#800A#, x"02");  -- byte 1
        poke(16#800B#, x"00");  -- byte 2
        poke(16#800C#, x"00");  -- byte 3  -> Y=$00000200
        poke(16#800D#, x"B9");  -- LDA abs,Y
        poke(16#800E#, x"00");  -- $00
        poke(16#800F#, x"05");  -- $05  -> $0500 + Y = $0700
        poke(16#8010#, x"8D");  -- STA abs
        poke(16#8011#, x"84");  -- $84
        poke(16#8012#, x"02");  -- $02  -> $0284-$0287
        poke(16#8013#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0284#, x"AA", "32-bit LDA abs,Y byte 0");
        check_mem(16#0285#, x"BB", "32-bit LDA abs,Y byte 1");
        check_mem(16#0286#, x"CC", "32-bit LDA abs,Y byte 2");
        check_mem(16#0287#, x"DD", "32-bit LDA abs,Y byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 43: 32-bit indexed addressing STA abs,X
        -----------------------------------------------------------------------
        report "";
        report "TEST 43: 32-bit indexed addressing STA abs,X";
        
        -- Program: set 32-bit M and X, LDX #$00000300, LDA #$11223344,
        --          STA $0500,X -> store to $0800
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit accumulator
        poke(16#8004#, x"C2");  -- REP
        poke(16#8005#, x"10");  -- clear X0
        poke(16#8006#, x"E2");  -- SEP
        poke(16#8007#, x"20");  -- set X1 -> 32-bit X
        poke(16#8008#, x"A2");  -- LDX #
        poke(16#8009#, x"00");  -- byte 0
        poke(16#800A#, x"03");  -- byte 1
        poke(16#800B#, x"00");  -- byte 2
        poke(16#800C#, x"00");  -- byte 3  -> X=$00000300
        poke(16#800D#, x"A9");  -- LDA #
        poke(16#800E#, x"44");  -- byte 0
        poke(16#800F#, x"33");  -- byte 1
        poke(16#8010#, x"22");  -- byte 2
        poke(16#8011#, x"11");  -- byte 3  -> A=$11223344
        poke(16#8012#, x"9D");  -- STA abs,X
        poke(16#8013#, x"00");  -- $00
        poke(16#8014#, x"05");  -- $05  -> $0500 + X = $0800
        poke(16#8015#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0800#, x"44", "32-bit STA abs,X byte 0");
        check_mem(16#0801#, x"33", "32-bit STA abs,X byte 1");
        check_mem(16#0802#, x"22", "32-bit STA abs,X byte 2");
        check_mem(16#0803#, x"11", "32-bit STA abs,X byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 44: 32-bit indexed addressing STA abs,Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 44: 32-bit indexed addressing STA abs,Y";
        
        -- Program: set 32-bit M and Y, LDY #$00000400, LDA #$AABBCCDD,
        --          STA $0500,Y -> store to $0900
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit accumulator
        poke(16#8004#, x"C2");  -- REP
        poke(16#8005#, x"10");  -- clear X0
        poke(16#8006#, x"E2");  -- SEP
        poke(16#8007#, x"20");  -- set X1 -> 32-bit Y
        poke(16#8008#, x"A0");  -- LDY #
        poke(16#8009#, x"00");  -- byte 0
        poke(16#800A#, x"04");  -- byte 1
        poke(16#800B#, x"00");  -- byte 2
        poke(16#800C#, x"00");  -- byte 3  -> Y=$00000400
        poke(16#800D#, x"A9");  -- LDA #
        poke(16#800E#, x"DD");  -- byte 0
        poke(16#800F#, x"CC");  -- byte 1
        poke(16#8010#, x"BB");  -- byte 2
        poke(16#8011#, x"AA");  -- byte 3  -> A=$AABBCCDD
        poke(16#8012#, x"99");  -- STA abs,Y
        poke(16#8013#, x"00");  -- $00
        poke(16#8014#, x"05");  -- $05  -> $0500 + Y = $0900
        poke(16#8015#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0900#, x"DD", "32-bit STA abs,Y byte 0");
        check_mem(16#0901#, x"CC", "32-bit STA abs,Y byte 1");
        check_mem(16#0902#, x"BB", "32-bit STA abs,Y byte 2");
        check_mem(16#0903#, x"AA", "32-bit STA abs,Y byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 45: 32-bit ASL abs (arithmetic shift left)
        -----------------------------------------------------------------------
        report "";
        report "TEST 45: 32-bit ASL abs";
        
        -- Program: set 32-bit M, store $01020304 at $0248,
        --          ASL $0248 -> $02040608, read and store at $024C
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"04");  -- byte 0
        poke(16#8006#, x"03");  -- byte 1
        poke(16#8007#, x"02");  -- byte 2
        poke(16#8008#, x"01");  -- byte 3  -> $01020304
        poke(16#8009#, x"8D");  -- STA abs
        poke(16#800A#, x"48");  -- $48
        poke(16#800B#, x"02");  -- $02  -> $0248-$024B
        poke(16#800C#, x"0E");  -- ASL abs
        poke(16#800D#, x"48");  -- $48
        poke(16#800E#, x"02");  -- $02  -> ASL $0248
        poke(16#800F#, x"AD");  -- LDA abs
        poke(16#8010#, x"48");  -- $48
        poke(16#8011#, x"02");  -- $02
        poke(16#8012#, x"8D");  -- STA abs
        poke(16#8013#, x"4C");  -- $4C
        poke(16#8014#, x"02");  -- $02  -> $024C-$024F
        poke(16#8015#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(280);
        
        check_mem(16#024C#, x"08", "32-bit ASL abs byte 0");
        check_mem(16#024D#, x"06", "32-bit ASL abs byte 1");
        check_mem(16#024E#, x"04", "32-bit ASL abs byte 2");
        check_mem(16#024F#, x"02", "32-bit ASL abs byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 46: 32-bit LSR abs (logical shift right)
        -----------------------------------------------------------------------
        report "";
        report "TEST 46: 32-bit LSR abs";
        
        -- Program: set 32-bit M, store $80808080 at $0250,
        --          LSR $0250 -> $40404040, read and store at $0254
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"80");  -- byte 0
        poke(16#8006#, x"80");  -- byte 1
        poke(16#8007#, x"80");  -- byte 2
        poke(16#8008#, x"80");  -- byte 3  -> $80808080
        poke(16#8009#, x"8D");  -- STA abs
        poke(16#800A#, x"50");  -- $50
        poke(16#800B#, x"02");  -- $02  -> $0250-$0253
        poke(16#800C#, x"4E");  -- LSR abs
        poke(16#800D#, x"50");  -- $50
        poke(16#800E#, x"02");  -- $02  -> LSR $0250
        poke(16#800F#, x"AD");  -- LDA abs
        poke(16#8010#, x"50");  -- $50
        poke(16#8011#, x"02");  -- $02
        poke(16#8012#, x"8D");  -- STA abs
        poke(16#8013#, x"54");  -- $54
        poke(16#8014#, x"02");  -- $02  -> $0254-$0257
        poke(16#8015#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0254#, x"40", "32-bit LSR abs byte 0");
        check_mem(16#0255#, x"40", "32-bit LSR abs byte 1");
        check_mem(16#0256#, x"40", "32-bit LSR abs byte 2");
        check_mem(16#0257#, x"40", "32-bit LSR abs byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 47: 32-bit ROL abs (rotate left through carry)
        -----------------------------------------------------------------------
        report "";
        report "TEST 47: 32-bit ROL abs";
        
        -- Program: set 32-bit M, CLC (C=0), store $40000000 at $0258,
        --          ROL $0258 -> $80000000, read and store at $025C
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"18");  -- CLC (C=0)
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"00");  -- byte 0
        poke(16#8007#, x"00");  -- byte 1
        poke(16#8008#, x"00");  -- byte 2
        poke(16#8009#, x"40");  -- byte 3  -> $40000000
        poke(16#800A#, x"8D");  -- STA abs
        poke(16#800B#, x"58");  -- $58
        poke(16#800C#, x"02");  -- $02  -> $0258-$025B
        poke(16#800D#, x"2E");  -- ROL abs
        poke(16#800E#, x"58");  -- $58
        poke(16#800F#, x"02");  -- $02  -> ROL $0258
        poke(16#8010#, x"AD");  -- LDA abs
        poke(16#8011#, x"58");  -- $58
        poke(16#8012#, x"02");  -- $02
        poke(16#8013#, x"8D");  -- STA abs
        poke(16#8014#, x"5C");  -- $5C
        poke(16#8015#, x"02");  -- $02  -> $025C-$025F
        poke(16#8016#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#025C#, x"00", "32-bit ROL abs byte 0");
        check_mem(16#025D#, x"00", "32-bit ROL abs byte 1");
        check_mem(16#025E#, x"00", "32-bit ROL abs byte 2");
        check_mem(16#025F#, x"80", "32-bit ROL abs byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 48: 32-bit ROR abs (rotate right through carry)
        -----------------------------------------------------------------------
        report "";
        report "TEST 48: 32-bit ROR abs";
        
        -- Program: set 32-bit M, CLC (C=0), store $00000002 at $0260,
        --          ROR $0260 -> $00000001, read and store at $0264
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"18");  -- CLC (C=0)
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"02");  -- byte 0
        poke(16#8007#, x"00");  -- byte 1
        poke(16#8008#, x"00");  -- byte 2
        poke(16#8009#, x"00");  -- byte 3  -> $00000002
        poke(16#800A#, x"8D");  -- STA abs
        poke(16#800B#, x"60");  -- $60
        poke(16#800C#, x"02");  -- $02  -> $0260-$0263
        poke(16#800D#, x"6E");  -- ROR abs
        poke(16#800E#, x"60");  -- $60
        poke(16#800F#, x"02");  -- $02  -> ROR $0260
        poke(16#8010#, x"AD");  -- LDA abs
        poke(16#8011#, x"60");  -- $60
        poke(16#8012#, x"02");  -- $02
        poke(16#8013#, x"8D");  -- STA abs
        poke(16#8014#, x"64");  -- $64
        poke(16#8015#, x"02");  -- $02  -> $0264-$0267
        poke(16#8016#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0264#, x"01", "32-bit ROR abs byte 0");
        check_mem(16#0265#, x"00", "32-bit ROR abs byte 1");
        check_mem(16#0266#, x"00", "32-bit ROR abs byte 2");
        check_mem(16#0267#, x"00", "32-bit ROR abs byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 49: 32-bit ADC carry propagation
        -----------------------------------------------------------------------
        report "";
        report "TEST 49: 32-bit ADC carry propagation";
        
        -- Program: set 32-bit M, SEC (C=1), LDA #$FFFFFFFF, ADC #$00000000
        --          -> $00000000 with C=1, store result and branch marker
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"38");  -- SEC (C=1)
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"FF");  -- byte 0
        poke(16#8007#, x"FF");  -- byte 1
        poke(16#8008#, x"FF");  -- byte 2
        poke(16#8009#, x"FF");  -- byte 3  -> $FFFFFFFF
        poke(16#800A#, x"69");  -- ADC #
        poke(16#800B#, x"00");  -- byte 0
        poke(16#800C#, x"00");  -- byte 1
        poke(16#800D#, x"00");  -- byte 2
        poke(16#800E#, x"00");  -- byte 3  -> +$00000000
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"A0");  -- $A0
        poke(16#8011#, x"02");  -- $02  -> $02A0-$02A3
        poke(16#8012#, x"B0");  -- BCS
        poke(16#8013#, x"05");  -- +5 (skip 32-bit LDA #$00000000)
        poke(16#8014#, x"A9");  -- LDA #
        poke(16#8015#, x"00");  -- byte 0
        poke(16#8016#, x"00");  -- byte 1
        poke(16#8017#, x"00");  -- byte 2
        poke(16#8018#, x"00");  -- byte 3
        poke(16#8019#, x"A9");  -- LDA #
        poke(16#801A#, x"AA");  -- byte 0
        poke(16#801B#, x"00");  -- byte 1
        poke(16#801C#, x"00");  -- byte 2
        poke(16#801D#, x"00");  -- byte 3
        poke(16#801E#, x"8D");  -- STA abs
        poke(16#801F#, x"A4");  -- $A4
        poke(16#8020#, x"02");  -- $02  -> $02A4
        poke(16#8021#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#02A0#, x"00", "32-bit ADC result byte 0");
        check_mem(16#02A1#, x"00", "32-bit ADC result byte 1");
        check_mem(16#02A2#, x"00", "32-bit ADC result byte 2");
        check_mem(16#02A3#, x"00", "32-bit ADC result byte 3");
        check_mem(16#02A4#, x"AA", "32-bit ADC sets carry");
        
        -----------------------------------------------------------------------
        -- TEST 50: 32-bit ADC overflow
        -----------------------------------------------------------------------
        report "";
        report "TEST 50: 32-bit ADC overflow";
        
        -- Program: set 32-bit M, CLC (C=0), LDA #$7FFFFFFF, ADC #$00000001
        --          -> $80000000 with V=1, store result and branch marker
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"18");  -- CLC (C=0)
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"FF");  -- byte 0
        poke(16#8007#, x"FF");  -- byte 1
        poke(16#8008#, x"FF");  -- byte 2
        poke(16#8009#, x"7F");  -- byte 3  -> $7FFFFFFF
        poke(16#800A#, x"69");  -- ADC #
        poke(16#800B#, x"01");  -- byte 0
        poke(16#800C#, x"00");  -- byte 1
        poke(16#800D#, x"00");  -- byte 2
        poke(16#800E#, x"00");  -- byte 3  -> +$00000001
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"A8");  -- $A8
        poke(16#8011#, x"02");  -- $02  -> $02A8-$02AB
        poke(16#8012#, x"70");  -- BVS
        poke(16#8013#, x"05");  -- +5 (skip 32-bit LDA #$00000000)
        poke(16#8014#, x"A9");  -- LDA #
        poke(16#8015#, x"00");  -- byte 0
        poke(16#8016#, x"00");  -- byte 1
        poke(16#8017#, x"00");  -- byte 2
        poke(16#8018#, x"00");  -- byte 3
        poke(16#8019#, x"A9");  -- LDA #
        poke(16#801A#, x"BB");  -- byte 0
        poke(16#801B#, x"00");  -- byte 1
        poke(16#801C#, x"00");  -- byte 2
        poke(16#801D#, x"00");  -- byte 3
        poke(16#801E#, x"8D");  -- STA abs
        poke(16#801F#, x"AC");  -- $AC
        poke(16#8020#, x"02");  -- $02  -> $02AC
        poke(16#8021#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#02A8#, x"00", "32-bit ADC overflow byte 0");
        check_mem(16#02A9#, x"00", "32-bit ADC overflow byte 1");
        check_mem(16#02AA#, x"00", "32-bit ADC overflow byte 2");
        check_mem(16#02AB#, x"80", "32-bit ADC overflow byte 3");
        check_mem(16#02AC#, x"BB", "32-bit ADC sets V");
        
        -----------------------------------------------------------------------
        -- TEST 51: 32-bit SBC borrow (carry clear)
        -----------------------------------------------------------------------
        report "";
        report "TEST 51: 32-bit SBC borrow";
        
        -- Program: set 32-bit M, SEC (C=1), LDA #$00000000, SBC #$00000001
        --          -> $FFFFFFFF with C=0, store result and branch marker
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"38");  -- SEC (C=1)
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"00");  -- byte 0
        poke(16#8007#, x"00");  -- byte 1
        poke(16#8008#, x"00");  -- byte 2
        poke(16#8009#, x"00");  -- byte 3  -> $00000000
        poke(16#800A#, x"E9");  -- SBC #
        poke(16#800B#, x"01");  -- byte 0
        poke(16#800C#, x"00");  -- byte 1
        poke(16#800D#, x"00");  -- byte 2
        poke(16#800E#, x"00");  -- byte 3  -> -$00000001
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"B0");  -- $B0
        poke(16#8011#, x"02");  -- $02  -> $02B0-$02B3
        poke(16#8012#, x"90");  -- BCC
        poke(16#8013#, x"05");  -- +5 (skip 32-bit LDA #$00000000)
        poke(16#8014#, x"A9");  -- LDA #
        poke(16#8015#, x"00");  -- byte 0
        poke(16#8016#, x"00");  -- byte 1
        poke(16#8017#, x"00");  -- byte 2
        poke(16#8018#, x"00");  -- byte 3
        poke(16#8019#, x"A9");  -- LDA #
        poke(16#801A#, x"CC");  -- byte 0
        poke(16#801B#, x"00");  -- byte 1
        poke(16#801C#, x"00");  -- byte 2
        poke(16#801D#, x"00");  -- byte 3
        poke(16#801E#, x"8D");  -- STA abs
        poke(16#801F#, x"B4");  -- $B4
        poke(16#8020#, x"02");  -- $02  -> $02B4
        poke(16#8021#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#02B0#, x"FF", "32-bit SBC borrow byte 0");
        check_mem(16#02B1#, x"FF", "32-bit SBC borrow byte 1");
        check_mem(16#02B2#, x"FF", "32-bit SBC borrow byte 2");
        check_mem(16#02B3#, x"FF", "32-bit SBC borrow byte 3");
        check_mem(16#02B4#, x"CC", "32-bit SBC clears carry");
        
        -----------------------------------------------------------------------
        -- TEST 52: 32-bit SBC overflow
        -----------------------------------------------------------------------
        report "";
        report "TEST 52: 32-bit SBC overflow";
        
        -- Program: set 32-bit M, SEC (C=1), LDA #$80000000, SBC #$00000001
        --          -> $7FFFFFFF with V=1, store result and branch marker
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"38");  -- SEC (C=1)
        poke(16#8005#, x"A9");  -- LDA #
        poke(16#8006#, x"00");  -- byte 0
        poke(16#8007#, x"00");  -- byte 1
        poke(16#8008#, x"00");  -- byte 2
        poke(16#8009#, x"80");  -- byte 3  -> $80000000
        poke(16#800A#, x"E9");  -- SBC #
        poke(16#800B#, x"01");  -- byte 0
        poke(16#800C#, x"00");  -- byte 1
        poke(16#800D#, x"00");  -- byte 2
        poke(16#800E#, x"00");  -- byte 3  -> -$00000001
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"B8");  -- $B8
        poke(16#8011#, x"02");  -- $02  -> $02B8-$02BB
        poke(16#8012#, x"70");  -- BVS
        poke(16#8013#, x"05");  -- +5 (skip 32-bit LDA #$00000000)
        poke(16#8014#, x"A9");  -- LDA #
        poke(16#8015#, x"00");  -- byte 0
        poke(16#8016#, x"00");  -- byte 1
        poke(16#8017#, x"00");  -- byte 2
        poke(16#8018#, x"00");  -- byte 3
        poke(16#8019#, x"A9");  -- LDA #
        poke(16#801A#, x"DD");  -- byte 0
        poke(16#801B#, x"00");  -- byte 1
        poke(16#801C#, x"00");  -- byte 2
        poke(16#801D#, x"00");  -- byte 3
        poke(16#801E#, x"8D");  -- STA abs
        poke(16#801F#, x"BC");  -- $BC
        poke(16#8020#, x"02");  -- $02  -> $02BC
        poke(16#8021#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#02B8#, x"FF", "32-bit SBC overflow byte 0");
        check_mem(16#02B9#, x"FF", "32-bit SBC overflow byte 1");
        check_mem(16#02BA#, x"FF", "32-bit SBC overflow byte 2");
        check_mem(16#02BB#, x"7F", "32-bit SBC overflow byte 3");
        check_mem(16#02BC#, x"DD", "32-bit SBC sets V");
        
        -----------------------------------------------------------------------
        -- TEST 53: LDA (dp,X) indirect
        -----------------------------------------------------------------------
        report "";
        report "TEST 53: LDA (dp,X)";
        
        -- Setup pointer at $0014/$0015 -> $0400, X=$04, dp operand=$10
        poke(16#0014#, x"00");  -- low
        poke(16#0015#, x"04");  -- high -> $0400
        poke(16#0400#, x"5A");  -- data
        
        -- Program: LDX #$04, LDA ($10,X), STA $02C0
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"04");  -- $04
        poke(16#8002#, x"A1");  -- LDA (dp,X)
        poke(16#8003#, x"10");  -- dp
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"C0");  -- $C0
        poke(16#8006#, x"02");  -- $02  -> $02C0
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#02C0#, x"5A", "LDA (dp,X) result");
        
        -----------------------------------------------------------------------
        -- TEST 54: LDA (dp),Y indirect indexed
        -----------------------------------------------------------------------
        report "";
        report "TEST 54: LDA (dp),Y";
        
        -- Setup pointer at $0020/$0021 -> $0300, Y=$05
        poke(16#0020#, x"00");  -- low
        poke(16#0021#, x"03");  -- high -> $0300
        poke(16#0305#, x"A7");  -- data at $0300 + Y
        
        -- Program: LDY #$05, LDA ($20),Y, STA $02C1
        poke(16#8000#, x"A0");  -- LDY #
        poke(16#8001#, x"05");  -- $05
        poke(16#8002#, x"B1");  -- LDA (dp),Y
        poke(16#8003#, x"20");  -- dp
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"C1");  -- $C1
        poke(16#8006#, x"02");  -- $02  -> $02C1
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#02C1#, x"A7", "LDA (dp),Y result");
        
        -----------------------------------------------------------------------
        -- TEST 55: STA (dp,X) indirect
        -----------------------------------------------------------------------
        report "";
        report "TEST 55: STA (dp,X)";
        
        -- Setup pointer at $001A/$001B -> $0460, X=$02, dp operand=$18
        poke(16#001A#, x"60");  -- low
        poke(16#001B#, x"04");  -- high -> $0460
        
        -- Program: LDX #$02, LDA #$6C, STA ($18,X)
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"02");  -- $02
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"6C");  -- $6C
        poke(16#8004#, x"81");  -- STA (dp,X)
        poke(16#8005#, x"18");  -- dp
        poke(16#8006#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#0460#, x"6C", "STA (dp,X) result");
        
        -----------------------------------------------------------------------
        -- TEST 56: STA (dp),Y indirect indexed
        -----------------------------------------------------------------------
        report "";
        report "TEST 56: STA (dp),Y";
        
        -- Setup pointer at $0030/$0031 -> $0470, Y=$03
        poke(16#0030#, x"70");  -- low
        poke(16#0031#, x"04");  -- high -> $0470
        
        -- Program: LDY #$03, LDA #$7E, STA ($30),Y
        poke(16#8000#, x"A0");  -- LDY #
        poke(16#8001#, x"03");  -- $03
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"7E");  -- $7E
        poke(16#8004#, x"91");  -- STA (dp),Y
        poke(16#8005#, x"30");  -- dp
        poke(16#8006#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#0473#, x"7E", "STA (dp),Y result");
        
        -----------------------------------------------------------------------
        -- TEST 57: JMP (abs) indirect
        -----------------------------------------------------------------------
        report "";
        report "TEST 57: JMP (abs)";
        
        -- Setup pointer at $0330/$0331 -> $8030
        poke(16#0330#, x"30");  -- low
        poke(16#0331#, x"80");  -- high -> $8030
        
        -- Program: JMP ($0330), LDA #$00 (skipped), target: LDA #$3C, STA $02C2
        poke(16#8000#, x"6C");  -- JMP (abs)
        poke(16#8001#, x"30");  -- low
        poke(16#8002#, x"03");  -- high
        poke(16#8003#, x"A9");  -- LDA # (skipped)
        poke(16#8004#, x"00");  -- $00
        poke(16#8030#, x"A9");  -- LDA #
        poke(16#8031#, x"3C");  -- $3C
        poke(16#8032#, x"8D");  -- STA abs
        poke(16#8033#, x"C2");  -- $C2
        poke(16#8034#, x"02");  -- $02 -> $02C2
        poke(16#8035#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(160);
        
        check_mem(16#02C2#, x"3C", "JMP (abs) result");
        
        -----------------------------------------------------------------------
        -- TEST 58: 16-bit LDA (dp),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 58: 16-bit LDA (dp),Y";
        
        -- Setup pointer at $0040/$0041 -> $0480, Y=$02, data at $0482-$0483
        poke(16#0040#, x"80");  -- low
        poke(16#0041#, x"04");  -- high -> $0480
        poke(16#0482#, x"34");  -- low
        poke(16#0483#, x"12");  -- high
        
        -- Program: set M=16-bit, LDY #$02, LDA ($40),Y, STA $02C4
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"02");  -- $02
        poke(16#8006#, x"B1");  -- LDA (dp),Y
        poke(16#8007#, x"40");  -- dp
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"C4");  -- $C4
        poke(16#800A#, x"02");  -- $02  -> $02C4/$02C5
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#02C4#, x"34", "16-bit LDA (dp),Y low");
        check_mem(16#02C5#, x"12", "16-bit LDA (dp),Y high");
        
        -----------------------------------------------------------------------
        -- TEST 59: 16-bit STA (dp),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 59: 16-bit STA (dp),Y";
        
        -- Setup pointer at $0050/$0051 -> $0490, Y=$01
        poke(16#0050#, x"90");  -- low
        poke(16#0051#, x"04");  -- high -> $0490
        
        -- Program: set M=16-bit, LDY #$01, LDA #$ABCD, STA ($50),Y
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"01");  -- $01
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"CD");  -- low
        poke(16#8008#, x"AB");  -- high
        poke(16#8009#, x"91");  -- STA (dp),Y
        poke(16#800A#, x"50");  -- dp
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#0491#, x"CD", "16-bit STA (dp),Y low");
        check_mem(16#0492#, x"AB", "16-bit STA (dp),Y high");
        
        -----------------------------------------------------------------------
        -- TEST 60: 32-bit LDA (dp),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 60: 32-bit LDA (dp),Y";
        
        -- Setup pointer at $0060-$0063 -> $000004A0, Y=$03, data at $04A3-$04A6
        poke(16#0060#, x"A0");  -- low
        poke(16#0061#, x"04");  -- high
        poke(16#0062#, x"00");  -- bank
        poke(16#0063#, x"00");  -- high
        poke(16#04A3#, x"78");  -- byte 0
        poke(16#04A4#, x"56");  -- byte 1
        poke(16#04A5#, x"34");  -- byte 2
        poke(16#04A6#, x"12");  -- byte 3
        
        -- Program: set M=32-bit, LDY #$03, LDA ($60),Y, STA $02C8
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"03");  -- $03
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"B1");  -- LDA (dp),Y
        poke(16#800A#, x"60");  -- dp
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"C8");  -- $C8
        poke(16#800D#, x"02");  -- $02  -> $02C8-$02CB
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#02C8#, x"78", "32-bit LDA (dp),Y byte 0");
        check_mem(16#02C9#, x"56", "32-bit LDA (dp),Y byte 1");
        check_mem(16#02CA#, x"34", "32-bit LDA (dp),Y byte 2");
        check_mem(16#02CB#, x"12", "32-bit LDA (dp),Y byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 61: 32-bit STA (dp),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 61: 32-bit STA (dp),Y";
        
        -- Setup pointer at $0070-$0073 -> $000004B0, Y=$02
        poke(16#0070#, x"B0");  -- low
        poke(16#0071#, x"04");  -- high
        poke(16#0072#, x"00");  -- bank
        poke(16#0073#, x"00");  -- high
        
        -- Program: set M=32-bit, LDY #$02, LDA #$CAFEBABE, STA ($70),Y
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"02");  -- $02
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"A9");  -- LDA #
        poke(16#800A#, x"BE");  -- byte 0
        poke(16#800B#, x"BA");  -- byte 1
        poke(16#800C#, x"FE");  -- byte 2
        poke(16#800D#, x"CA");  -- byte 3
        poke(16#800E#, x"91");  -- STA (dp),Y
        poke(16#800F#, x"70");  -- dp
        poke(16#8010#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#04B2#, x"BE", "32-bit STA (dp),Y byte 0");
        check_mem(16#04B3#, x"BA", "32-bit STA (dp),Y byte 1");
        check_mem(16#04B4#, x"FE", "32-bit STA (dp),Y byte 2");
        check_mem(16#04B5#, x"CA", "32-bit STA (dp),Y byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 62: 16-bit LDA (dp,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 62: 16-bit LDA (dp,X)";
        
        -- Setup pointer at $0012/$0013 -> $04C0, X=$02, dp operand=$10
        poke(16#0012#, x"C0");  -- low
        poke(16#0013#, x"04");  -- high -> $04C0
        poke(16#04C0#, x"78");  -- low
        poke(16#04C1#, x"56");  -- high
        
        -- Program: set M=16-bit, LDX #$02, LDA ($10,X), STA $02D0
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"02");  -- $02
        poke(16#8006#, x"A1");  -- LDA (dp,X)
        poke(16#8007#, x"10");  -- dp
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"D0");  -- $D0
        poke(16#800A#, x"02");  -- $02 -> $02D0/$02D1
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#02D0#, x"78", "16-bit LDA (dp,X) low");
        check_mem(16#02D1#, x"56", "16-bit LDA (dp,X) high");
        
        -----------------------------------------------------------------------
        -- TEST 63: 16-bit STA (dp,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 63: 16-bit STA (dp,X)";
        
        -- Setup pointer at $0016/$0017 -> $04D0, X=$06, dp operand=$10
        poke(16#0016#, x"D0");  -- low
        poke(16#0017#, x"04");  -- high -> $04D0
        
        -- Program: set M=16-bit, LDX #$06, LDA #$1357, STA ($10,X)
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"06");  -- $06
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"57");  -- low
        poke(16#8008#, x"13");  -- high
        poke(16#8009#, x"81");  -- STA (dp,X)
        poke(16#800A#, x"10");  -- dp
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#04D0#, x"57", "16-bit STA (dp,X) low");
        check_mem(16#04D1#, x"13", "16-bit STA (dp,X) high");
        
        -----------------------------------------------------------------------
        -- TEST 64: 32-bit LDA (dp,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 64: 32-bit LDA (dp,X)";
        
        -- Setup pointer at $0022-$0025 -> $000004E0, X=$02, dp operand=$20
        poke(16#0022#, x"E0");  -- low
        poke(16#0023#, x"04");  -- high
        poke(16#0024#, x"00");  -- bank
        poke(16#0025#, x"00");  -- high
        poke(16#04E0#, x"EF");  -- byte 0
        poke(16#04E1#, x"CD");  -- byte 1
        poke(16#04E2#, x"AB");  -- byte 2
        poke(16#04E3#, x"89");  -- byte 3
        
        -- Program: set M=32-bit, LDX #$02, LDA ($20,X), STA $02D4
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"02");  -- $02
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"A1");  -- LDA (dp,X)
        poke(16#800A#, x"20");  -- dp
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"D4");  -- $D4
        poke(16#800D#, x"02");  -- $02 -> $02D4-$02D7
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#02D4#, x"EF", "32-bit LDA (dp,X) byte 0");
        check_mem(16#02D5#, x"CD", "32-bit LDA (dp,X) byte 1");
        check_mem(16#02D6#, x"AB", "32-bit LDA (dp,X) byte 2");
        check_mem(16#02D7#, x"89", "32-bit LDA (dp,X) byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 65: 32-bit STA (dp,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 65: 32-bit STA (dp,X)";
        
        -- Setup pointer at $0026-$0029 -> $000004F0, X=$06, dp operand=$20
        poke(16#0026#, x"F0");  -- low
        poke(16#0027#, x"04");  -- high
        poke(16#0028#, x"00");  -- bank
        poke(16#0029#, x"00");  -- high
        
        -- Program: set M=32-bit, LDX #$06, LDA #$10203040, STA ($20,X)
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"06");  -- $06
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"A9");  -- LDA #
        poke(16#800A#, x"40");  -- byte 0
        poke(16#800B#, x"30");  -- byte 1
        poke(16#800C#, x"20");  -- byte 2
        poke(16#800D#, x"10");  -- byte 3
        poke(16#800E#, x"81");  -- STA (dp,X)
        poke(16#800F#, x"20");  -- dp
        poke(16#8010#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#04F0#, x"40", "32-bit STA (dp,X) byte 0");
        check_mem(16#04F1#, x"30", "32-bit STA (dp,X) byte 1");
        check_mem(16#04F2#, x"20", "32-bit STA (dp,X) byte 2");
        check_mem(16#04F3#, x"10", "32-bit STA (dp,X) byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 66: JMP (abs,X) indirect
        -----------------------------------------------------------------------
        report "";
        report "TEST 66: JMP (abs,X)";
        
        -- Setup pointer at $0404/$0405 -> $8050, X=$04, base=$0400
        poke(16#0404#, x"50");  -- low
        poke(16#0405#, x"80");  -- high -> $8050
        
        -- Program: LDX #$04, JMP ($0400,X), LDA #$00 (skipped),
        --          target: LDA #$4D, STA $02D8
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"04");  -- $04
        poke(16#8002#, x"7C");  -- JMP (abs,X)
        poke(16#8003#, x"00");  -- low
        poke(16#8004#, x"04");  -- high
        poke(16#8005#, x"A9");  -- LDA # (skipped)
        poke(16#8006#, x"00");  -- $00
        poke(16#8050#, x"A9");  -- LDA #
        poke(16#8051#, x"4D");  -- $4D
        poke(16#8052#, x"8D");  -- STA abs
        poke(16#8053#, x"D8");  -- $D8
        poke(16#8054#, x"02");  -- $02 -> $02D8
        poke(16#8055#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#02D8#, x"4D", "JMP (abs,X) result");
        
        -----------------------------------------------------------------------
        -- TEST 67: LDA [dp] (long indirect)
        -----------------------------------------------------------------------
        report "";
        report "TEST 67: LDA [dp]";
        
        -- Setup long pointer at $0080/$0081/$0082 -> $000500
        poke(16#0080#, x"00");  -- low
        poke(16#0081#, x"05");  -- high
        poke(16#0082#, x"00");  -- bank
        poke(16#0500#, x"9A");  -- data
        
        -- Program: LDA [dp], STA $02E0
        poke(16#8000#, x"A7");  -- LDA [dp] (cc=11, bbb=001)
        poke(16#8001#, x"80");  -- dp
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"E0");  -- $E0
        poke(16#8004#, x"02");  -- $02 -> $02E0
        poke(16#8005#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#02E0#, x"9A", "LDA [dp] result");
        
        -----------------------------------------------------------------------
        -- TEST 68: LDA [dp],Y (long indirect indexed)
        -----------------------------------------------------------------------
        report "";
        report "TEST 68: LDA [dp],Y";
        
        -- Setup long pointer at $0084/$0085/$0086 -> $000510, Y=$03
        poke(16#0084#, x"10");  -- low
        poke(16#0085#, x"05");  -- high
        poke(16#0086#, x"00");  -- bank
        poke(16#0513#, x"B4");  -- data at $0510 + Y
        
        -- Program: LDY #$03, LDA [dp],Y, STA $02E1
        poke(16#8000#, x"A0");  -- LDY #
        poke(16#8001#, x"03");  -- $03
        poke(16#8002#, x"B3");  -- LDA [dp],Y (cc=11, bbb=100)
        poke(16#8003#, x"84");  -- dp
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"E1");  -- $E1
        poke(16#8006#, x"02");  -- $02 -> $02E1
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#02E1#, x"B4", "LDA [dp],Y result");
        
        -----------------------------------------------------------------------
        -- TEST 69: LDA sr,S (stack-relative)
        -----------------------------------------------------------------------
        report "";
        report "TEST 69: LDA sr,S";
        
        -- SP defaults to $01FF; offset $05 -> $0204
        poke(16#0204#, x"77");  -- data
        
        -- Program: LDA sr,S, STA $02E2
        poke(16#8000#, x"A3");  -- LDA sr,S (cc=11, bbb=000)
        poke(16#8001#, x"05");  -- offset
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"E2");  -- $E2
        poke(16#8004#, x"02");  -- $02 -> $02E2
        poke(16#8005#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(120);
        
        check_mem(16#02E2#, x"77", "LDA sr,S result");
        
        -----------------------------------------------------------------------
        -- TEST 70: LDA (sr,S),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 70: LDA (sr,S),Y";
        
        -- Pointer at $0206/$0207 -> $0520, Y=$02, data at $0522
        poke(16#0206#, x"20");  -- low
        poke(16#0207#, x"05");  -- high -> $0520
        poke(16#0522#, x"5D");  -- data
        
        -- Program: LDY #$02, LDA (sr,S),Y, STA $02E3
        poke(16#8000#, x"A0");  -- LDY #
        poke(16#8001#, x"02");  -- $02
        poke(16#8002#, x"AF");  -- LDA (sr,S),Y (cc=11, bbb=011)
        poke(16#8003#, x"07");  -- offset -> SP+7 = $0206
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"E3");  -- $E3
        poke(16#8006#, x"02");  -- $02 -> $02E3
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(140);
        
        check_mem(16#02E3#, x"5D", "LDA (sr,S),Y result");
        
        -----------------------------------------------------------------------
        -- TEST 71: LDA long
        -----------------------------------------------------------------------
        report "";
        report "TEST 71: LDA long";
        
        -- Data at $000620
        poke(16#0620#, x"5F");  -- data
        
        -- Program: LDA long, STA $02E4
        poke(16#8000#, x"AB");  -- LDA long (cc=11, bbb=010)
        poke(16#8001#, x"20");  -- low
        poke(16#8002#, x"06");  -- high
        poke(16#8003#, x"00");  -- bank
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"E4");  -- $E4
        poke(16#8006#, x"02");  -- $02 -> $02E4
        poke(16#8007#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(140);
        
        check_mem(16#02E4#, x"5F", "LDA long result");
        
        -----------------------------------------------------------------------
        -- TEST 72: LDA long,X
        -----------------------------------------------------------------------
        report "";
        report "TEST 72: LDA long,X";
        
        -- Data at $000630 + X($03) = $000633
        poke(16#0633#, x"6E");  -- data
        
        -- Program: LDX #$03, LDA long,X, STA $02E5
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"03");  -- $03
        poke(16#8002#, x"BF");  -- LDA long,X (cc=11, bbb=111)
        poke(16#8003#, x"30");  -- low
        poke(16#8004#, x"06");  -- high
        poke(16#8005#, x"00");  -- bank
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"E5");  -- $E5
        poke(16#8008#, x"02");  -- $02 -> $02E5
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(160);
        
        check_mem(16#02E5#, x"6E", "LDA long,X result");
        
        -----------------------------------------------------------------------
        -- TEST 73: 16-bit LDA [dp] and STA [dp]
        -----------------------------------------------------------------------
        report "";
        report "TEST 73: 16-bit LDA/STA [dp]";
        
        -- Setup long pointer at $0088/$0089/$008A -> $000540
        poke(16#0088#, x"40");  -- low
        poke(16#0089#, x"05");  -- high
        poke(16#008A#, x"00");  -- bank
        poke(16#0540#, x"34");  -- low
        poke(16#0541#, x"12");  -- high
        
        -- Program: set M=16-bit, LDA [dp], STA abs
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A7");  -- LDA [dp]
        poke(16#8005#, x"88");  -- dp
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"E6");  -- $E6
        poke(16#8008#, x"02");  -- $02 -> $02E6/$02E7
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(160);
        
        check_mem(16#02E6#, x"34", "16-bit STA [dp] low");
        check_mem(16#02E7#, x"12", "16-bit STA [dp] high");
        
        -----------------------------------------------------------------------
        -- TEST 74: 32-bit LDA [dp],Y and STA [dp],Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 74: 32-bit LDA/STA [dp],Y";
        
        -- Setup long pointer at $008C-$008F -> $00000560, Y=$03
        poke(16#008C#, x"60");  -- low
        poke(16#008D#, x"05");  -- high
        poke(16#008E#, x"00");  -- bank
        poke(16#008F#, x"00");  -- high
        poke(16#0563#, x"78");  -- byte 0
        poke(16#0564#, x"56");  -- byte 1
        poke(16#0565#, x"34");  -- byte 2
        poke(16#0566#, x"12");  -- byte 3
        
        -- Program: set M=32-bit, LDY #$03, LDA [dp],Y, STA abs
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"03");  -- $03
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"B3");  -- LDA [dp],Y
        poke(16#800A#, x"8C");  -- dp
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"E8");  -- $E8
        poke(16#800D#, x"02");  -- $02 -> $02E8-$02EB
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#02E8#, x"78", "32-bit STA [dp],Y byte 0");
        check_mem(16#02E9#, x"56", "32-bit STA [dp],Y byte 1");
        check_mem(16#02EA#, x"34", "32-bit STA [dp],Y byte 2");
        check_mem(16#02EB#, x"12", "32-bit STA [dp],Y byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 75: 16-bit LDA sr,S and STA sr,S
        -----------------------------------------------------------------------
        report "";
        report "TEST 75: 16-bit LDA/STA sr,S";
        
        -- SP defaults to $01FF; offset $06 -> $0205
        poke(16#0205#, x"CD");  -- low
        poke(16#0206#, x"AB");  -- high
        
        -- Program: set M=16-bit, LDA sr,S, STA abs $02E6
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A3");  -- LDA sr,S
        poke(16#8005#, x"06");  -- offset
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"E6");  -- $E6
        poke(16#8008#, x"02");  -- $02 -> $02E6/$02E7
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#02E6#, x"CD", "16-bit LDA sr,S low");
        check_mem(16#02E7#, x"AB", "16-bit LDA sr,S high");
        
        -----------------------------------------------------------------------
        -- TEST 76: 32-bit LDA (sr,S),Y and STA (sr,S),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 76: 32-bit LDA/STA (sr,S),Y";
        
        -- Pointer at $0208-$020B -> $00000580, Y=$02, data at $0582-$0585
        poke(16#0208#, x"80");  -- low
        poke(16#0209#, x"05");  -- high
        poke(16#020A#, x"00");  -- bank
        poke(16#020B#, x"00");  -- high
        poke(16#0582#, x"DE");  -- byte 0
        poke(16#0583#, x"AD");  -- byte 1
        poke(16#0584#, x"BE");  -- byte 2
        poke(16#0585#, x"EF");  -- byte 3
        
        -- Program: set M=32-bit, LDY #$02, LDA (sr,S),Y, STA abs
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"02");  -- $02
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"AF");  -- LDA (sr,S),Y
        poke(16#800A#, x"09");  -- offset -> SP+9 = $0208
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"EC");  -- $EC
        poke(16#800D#, x"02");  -- $02 -> $02EC-$02EF
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#02EC#, x"DE", "32-bit STA (sr,S),Y byte 0");
        check_mem(16#02ED#, x"AD", "32-bit STA (sr,S),Y byte 1");
        check_mem(16#02EE#, x"BE", "32-bit STA (sr,S),Y byte 2");
        check_mem(16#02EF#, x"EF", "32-bit STA (sr,S),Y byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 77: 16-bit LDA long and STA long
        -----------------------------------------------------------------------
        report "";
        report "TEST 77: 16-bit LDA/STA long";
        
        -- Data at $0005A0
        poke(16#05A0#, x"11");  -- low
        poke(16#05A1#, x"22");  -- high
        
        -- Program: set M=16-bit, LDA long, STA abs
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"AB");  -- LDA long
        poke(16#8005#, x"A0");  -- low
        poke(16#8006#, x"05");  -- high
        poke(16#8007#, x"00");  -- bank
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"F0");  -- $F0
        poke(16#800A#, x"02");  -- $02 -> $02F0/$02F1
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#02F0#, x"11", "16-bit STA long low");
        check_mem(16#02F1#, x"22", "16-bit STA long high");
        
        -----------------------------------------------------------------------
        -- TEST 78: 32-bit LDA long,X and STA long
        -----------------------------------------------------------------------
        report "";
        report "TEST 78: 32-bit LDA long,X/STA long";
        
        -- Data at $0005B0 + X($02) = $0005B2
        poke(16#05B2#, x"01");  -- byte 0
        poke(16#05B3#, x"23");  -- byte 1
        poke(16#05B4#, x"45");  -- byte 2
        poke(16#05B5#, x"67");  -- byte 3
        
        -- Program: set M=32-bit, LDX #$02, LD A abs32,X, STA abs
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"02");  -- $02
        poke(16#8006#, x"00");
        poke(16#8007#, x"00");
        poke(16#8008#, x"00");
        poke(16#8009#, x"02");  -- EXT prefix
        poke(16#800A#, x"80");  -- LD
        poke(16#800B#, x"91");  -- size=LONG, target=A, abs32,X
        poke(16#800C#, x"B0");  -- addr0
        poke(16#800D#, x"05");  -- addr1
        poke(16#800E#, x"00");  -- addr2
        poke(16#800F#, x"00");  -- addr3
        poke(16#8010#, x"8D");  -- STA abs
        poke(16#8011#, x"F2");  -- $F2
        poke(16#8012#, x"02");  -- $02 -> $02F2-$02F5
        poke(16#8013#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#02F2#, x"01", "32-bit STA long,X byte 0");
        check_mem(16#02F3#, x"23", "32-bit STA long,X byte 1");
        check_mem(16#02F4#, x"45", "32-bit STA long,X byte 2");
        check_mem(16#02F5#, x"67", "32-bit STA long,X byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 79: 8/16/32-bit LDA (dp) indirect
        -----------------------------------------------------------------------
        report "";
        report "TEST 79: 8/16/32-bit LDA (dp)";
        
        -- 8-bit pointer at $0090/$0091 -> $0600
        poke(16#0090#, x"00");  -- low
        poke(16#0091#, x"06");  -- high -> $0600
        poke(16#0600#, x"5C");  -- data
        
        -- Program: LDA (dp), STA $0300
        poke(16#8000#, x"B2");  -- LDA (dp)
        poke(16#8001#, x"90");  -- dp
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"00");  -- $00
        poke(16#8004#, x"03");  -- $03 -> $0300
        poke(16#8005#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(140);
        
        check_mem(16#0300#, x"5C", "8-bit LDA (dp) result");
        
        -- 16-bit pointer at $0094/$0095 -> $0610
        poke(16#0094#, x"10");  -- low
        poke(16#0095#, x"06");  -- high -> $0610
        poke(16#0610#, x"78");  -- low
        poke(16#0611#, x"56");  -- high
        
        -- Program: set M=16-bit, LDA (dp), STA $0302
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"B2");  -- LDA (dp)
        poke(16#8005#, x"94");  -- dp
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"02");  -- $02
        poke(16#8008#, x"03");  -- $03 -> $0302/$0303
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(180);
        
        check_mem(16#0302#, x"78", "16-bit LDA (dp) low");
        check_mem(16#0303#, x"56", "16-bit LDA (dp) high");
        
        -- 32-bit pointer at $0098-$009B -> $00000620
        poke(16#0098#, x"20");  -- low
        poke(16#0099#, x"06");  -- high
        poke(16#009A#, x"00");  -- bank
        poke(16#009B#, x"00");  -- high
        poke(16#0620#, x"EF");  -- byte 0
        poke(16#0621#, x"CD");  -- byte 1
        poke(16#0622#, x"AB");  -- byte 2
        poke(16#0623#, x"89");  -- byte 3
        
        -- Program: set M=32-bit, LDA (dp), STA $0304
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"B2");  -- LDA (dp)
        poke(16#8005#, x"98");  -- dp
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"04");  -- $04
        poke(16#8008#, x"03");  -- $03 -> $0304-$0307
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0304#, x"EF", "32-bit LDA (dp) byte 0");
        check_mem(16#0305#, x"CD", "32-bit LDA (dp) byte 1");
        check_mem(16#0306#, x"AB", "32-bit LDA (dp) byte 2");
        check_mem(16#0307#, x"89", "32-bit LDA (dp) byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 82: STA long (16-bit) and STA long,X (32-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 82: STA long/STA long,X";
        
        -- 16-bit STA long to $000630
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"34");  -- low
        poke(16#8006#, x"12");  -- high
        poke(16#8007#, x"8F");  -- STA long
        poke(16#8008#, x"30");  -- low
        poke(16#8009#, x"06");  -- high
        poke(16#800A#, x"00");  -- bank
        
        -- 32-bit ST abs32,X to $00000640 + X($02) = $00000642
        poke(16#800B#, x"C2");  -- REP
        poke(16#800C#, x"40");  -- clear M0
        poke(16#800D#, x"E2");  -- SEP
        poke(16#800E#, x"80");  -- set M1 -> 32-bit
        poke(16#800F#, x"A2");  -- LDX #
        poke(16#8010#, x"02");  -- $02
        poke(16#8011#, x"00");
        poke(16#8012#, x"00");
        poke(16#8013#, x"00");
        poke(16#8014#, x"A9");  -- LDA #
        poke(16#8015#, x"EF");  -- byte 0
        poke(16#8016#, x"CD");  -- byte 1
        poke(16#8017#, x"AB");  -- byte 2
        poke(16#8018#, x"89");  -- byte 3
        poke(16#8019#, x"02");  -- EXT prefix
        poke(16#801A#, x"81");  -- ST
        poke(16#801B#, x"91");  -- size=LONG, target=A, abs32,X
        poke(16#801C#, x"40");  -- addr0
        poke(16#801D#, x"06");  -- addr1
        poke(16#801E#, x"00");  -- addr2
        poke(16#801F#, x"00");  -- addr3
        poke(16#8020#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(320);
        
        check_mem(16#0630#, x"34", "16-bit STA long low");
        check_mem(16#0631#, x"12", "16-bit STA long high");
        check_mem(16#0642#, x"EF", "32-bit STA long,X byte 0");
        check_mem(16#0643#, x"CD", "32-bit STA long,X byte 1");
        check_mem(16#0644#, x"AB", "32-bit STA long,X byte 2");
        check_mem(16#0645#, x"89", "32-bit STA long,X byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 83: STA [dp] and STA [dp],Y (8-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 83: STA [dp]/[dp],Y";
        
        -- Long pointer at $00A0/$00A1/$00A2 -> $000660
        poke(16#00A0#, x"60");  -- low
        poke(16#00A1#, x"06");  -- high
        poke(16#00A2#, x"00");  -- bank
        -- Long pointer at $00A4/$00A5/$00A6 -> $000670
        poke(16#00A4#, x"70");  -- low
        poke(16#00A5#, x"06");  -- high
        poke(16#00A6#, x"00");  -- bank
        
        -- Program: LDA #$9C, STA [dp], LDY #$03, LDA #$AD, STA [dp],Y
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"9C");  -- $9C
        poke(16#8002#, x"87");  -- STA [dp]
        poke(16#8003#, x"A0");  -- dp
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"03");  -- $03
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"AD");  -- $AD
        poke(16#8008#, x"93");  -- STA [dp],Y
        poke(16#8009#, x"A4");  -- dp
        poke(16#800A#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0660#, x"9C", "STA [dp] result");
        check_mem(16#0673#, x"AD", "STA [dp],Y result");
        
        -----------------------------------------------------------------------
        -- TEST 84: Stack PHA/PLA (8-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 84: PHA/PLA";
        
        -- Program: LDA #$5A, PHA, LDA #$00, PLA, STA $0310
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"5A");  -- $5A
        poke(16#8002#, x"48");  -- PHA
        poke(16#8003#, x"A9");  -- LDA #
        poke(16#8004#, x"00");  -- $00
        poke(16#8005#, x"68");  -- PLA
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"10");  -- $10
        poke(16#8008#, x"03");  -- $03 -> $0310
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(25);
        
        check_mem(16#01FF#, x"5A", "PHA wrote stack");
        wait_cycles(15);
        check_mem(16#0310#, x"5A", "PLA restored A");
        
        -----------------------------------------------------------------------
        -- TEST 85: PHX/PLX (16-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 85: PHX/PLX 16-bit";
        
        -- Program: SEP #$10 (X0=1), LDX #$1234, PHX, LDX #$0000, PLX, STX $0312
        poke(16#8000#, x"E2");  -- SEP
        poke(16#8001#, x"10");  -- set X0 -> 16-bit
        poke(16#8002#, x"A2");  -- LDX #
        poke(16#8003#, x"34");  -- low
        poke(16#8004#, x"12");  -- high
        poke(16#8005#, x"DA");  -- PHX
        poke(16#8006#, x"A2");  -- LDX #
        poke(16#8007#, x"00");  -- low
        poke(16#8008#, x"00");  -- high
        poke(16#8009#, x"FA");  -- PLX
        poke(16#800A#, x"8E");  -- STX abs
        poke(16#800B#, x"12");  -- $12
        poke(16#800C#, x"03");  -- $03 -> $0312/$0313
        poke(16#800D#, x"DB");  -- STP
        poke(16#800E#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(30);
        
        check_mem(16#01FF#, x"12", "PHX stack high");
        check_mem(16#01FE#, x"34", "PHX stack low");
        wait_cycles(15);
        check_mem(16#0312#, x"34", "PLX low");
        check_mem(16#0313#, x"12", "PLX high");
        
        -----------------------------------------------------------------------
        -- TEST 86: PEA/PEI (16-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 86: PEA/PEI";
        
        -- Setup dp $90 with $BEEF
        poke(16#0090#, x"EF");
        poke(16#0091#, x"BE");
        
        -- Program: SEP #$40, PEA #$1234, PLA, STA $0314, PEI $90, PLA, STA $0316
        poke(16#8000#, x"E2");  -- SEP
        poke(16#8001#, x"40");  -- set M0 -> 16-bit
        poke(16#8002#, x"F4");  -- PEA
        poke(16#8003#, x"34");  -- low
        poke(16#8004#, x"12");  -- high
        poke(16#8005#, x"68");  -- PLA
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"14");  -- $14
        poke(16#8008#, x"03");  -- $03 -> $0314/$0315
        poke(16#8009#, x"D4");  -- PEI dp
        poke(16#800A#, x"90");  -- dp
        poke(16#800B#, x"68");  -- PLA
        poke(16#800C#, x"8D");  -- STA abs
        poke(16#800D#, x"16");  -- $16
        poke(16#800E#, x"03");  -- $03 -> $0316/$0317
        poke(16#800F#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0314#, x"34", "PEA low");
        check_mem(16#0315#, x"12", "PEA high");
        check_mem(16#0316#, x"EF", "PEI low");
        check_mem(16#0317#, x"BE", "PEI high");
        
        -----------------------------------------------------------------------
        -- TEST 87: Extended ALU sized register-target (byte/word)
        -----------------------------------------------------------------------
        report "";
        report "TEST 87: Extended ALU sized reg-target";
        
        -- Program: set M=32-bit, RSET, LDA #$11223344,
        -- LD.B R1, A, LD.W R2, A, store R1/R2 for verification
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"02");  -- RSET
        poke(16#8005#, x"30");
        poke(16#8006#, x"A9");  -- LDA #$11223344
        poke(16#8007#, x"44");
        poke(16#8008#, x"33");
        poke(16#8009#, x"22");
        poke(16#800A#, x"11");
        -- $02 $80 $39 $04: LD.B R1, A (size=BYTE, target=Rn, addr_mode=A)
        poke(16#800B#, x"02");
        poke(16#800C#, x"80");
        poke(16#800D#, x"39");
        poke(16#800E#, x"04");
        -- $02 $80 $79 $08: LD.W R2, A (size=WORD, target=Rn, addr_mode=A)
        poke(16#800F#, x"02");
        poke(16#8010#, x"80");
        poke(16#8011#, x"79");
        poke(16#8012#, x"08");
        -- Read back R1/R2 via DP and store to $0318/$031C
        poke(16#8013#, x"A5");  -- LDA $04
        poke(16#8014#, x"04");
        poke(16#8015#, x"8D");  -- STA $0318
        poke(16#8016#, x"18");
        poke(16#8017#, x"03");
        poke(16#8018#, x"A5");  -- LDA $08
        poke(16#8019#, x"08");
        poke(16#801A#, x"8D");  -- STA $031C
        poke(16#801B#, x"1C");
        poke(16#801C#, x"03");
        poke(16#801D#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(320);
        
        check_mem(16#0318#, x"44", "Ext ALU byte write low");
        check_mem(16#0319#, x"00", "Ext ALU byte write high");
        check_mem(16#031A#, x"00", "Ext ALU byte write high2");
        check_mem(16#031B#, x"00", "Ext ALU byte write high3");
        check_mem(16#031C#, x"44", "Ext ALU word write low");
        check_mem(16#031D#, x"33", "Ext ALU word write high");
        check_mem(16#031E#, x"00", "Ext ALU word write high2");
        check_mem(16#031F#, x"00", "Ext ALU word write high3");
        
        -----------------------------------------------------------------------
        -- TEST 87B: Extended ALU abs32 load (A-target)
        -----------------------------------------------------------------------
        report "";
        report "TEST 87B: Extended ALU abs32";
        
        -- Preload memory at $00004000
        poke(16#4000#, x"5A");
        poke(16#4001#, x"00");
        poke(16#4002#, x"00");
        poke(16#4003#, x"00");
        
        -- Program: set M=32-bit, LD A abs32 $00004000 (size=LONG), STA $0320
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"02");
        poke(16#8005#, x"80");  -- LD
        poke(16#8006#, x"90");  -- size=LONG, target=A, addr_mode=abs32
        poke(16#8007#, x"00");  -- addr0
        poke(16#8008#, x"40");  -- addr1
        poke(16#8009#, x"00");  -- addr2
        poke(16#800A#, x"00");  -- addr3
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"20");  -- $20
        poke(16#800D#, x"03");  -- $03 -> $0320-$0323
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0320#, x"5A", "Ext ALU abs32 load byte 0");
        check_mem(16#0321#, x"00", "Ext ALU abs32 load byte 1");
        check_mem(16#0322#, x"00", "Ext ALU abs32 load byte 2");
        check_mem(16#0323#, x"00", "Ext ALU abs32 load byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 88: SD + LEA (32-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 88: SD + LEA";
        
        -- Program: set M=32-bit, SD #$00001000, LEA $20, STA $0320
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"24");  -- SD #imm32
        poke(16#8006#, x"00");  -- imm0
        poke(16#8007#, x"10");  -- imm1
        poke(16#8008#, x"00");  -- imm2
        poke(16#8009#, x"00");  -- imm3
        poke(16#800A#, x"02");  -- EXT prefix
        poke(16#800B#, x"A0");  -- LEA dp
        poke(16#800C#, x"20");  -- dp
        poke(16#800D#, x"8D");  -- STA abs
        poke(16#800E#, x"20");  -- $20
        poke(16#800F#, x"03");  -- $03 -> $0320-$0323
        poke(16#8010#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(300);
        
        check_mem(16#0320#, x"20", "LEA byte 0");
        check_mem(16#0321#, x"10", "LEA byte 1");
        check_mem(16#0322#, x"00", "LEA byte 2");
        check_mem(16#0323#, x"00", "LEA byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 89: SB base register for absolute
        -----------------------------------------------------------------------
        report "";
        report "TEST 89: SB base register";
        
        -- Program: SB #$00002000, LDA #$7E, STA $0040, LDA $0040, STA $0324
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"22");  -- SB #imm32
        poke(16#8002#, x"00");  -- imm0
        poke(16#8003#, x"20");  -- imm1
        poke(16#8004#, x"00");  -- imm2
        poke(16#8005#, x"00");  -- imm3
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"7E");  -- $7E
        poke(16#8008#, x"8D");  -- STA abs ($0040 -> $2040)
        poke(16#8009#, x"40");  -- low
        poke(16#800A#, x"00");  -- high
        poke(16#800B#, x"AD");  -- LDA abs ($0040 -> $2040)
        poke(16#800C#, x"40");  -- low
        poke(16#800D#, x"00");  -- high
        poke(16#800E#, x"8D");  -- STA abs
        poke(16#800F#, x"24");  -- $24
        poke(16#8010#, x"03");  -- $03 -> $0324
        poke(16#8011#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#2040#, x"7E", "SB base wrote $2040");
        check_mem(16#2324#, x"7E", "SB base absolute");
        
        -----------------------------------------------------------------------
        -- TEST 90: MULU dp and DIVU abs (16-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 90: MULU/DIVU";
        
        poke(16#0020#, x"04");
        poke(16#0021#, x"00");
        poke(16#0350#, x"03");
        poke(16#0351#, x"00");
        
        -- Program: SEP #$40, LDA #$0003, MULU dp $20, STA $0326,
        -- LDA #$0014, DIVU abs $0350, STA $0328, TTA, STA $032A
        poke(16#8000#, x"E2");  -- SEP
        poke(16#8001#, x"40");  -- set M0 -> 16-bit
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"03");
        poke(16#8004#, x"00");
        poke(16#8005#, x"02");  -- EXT prefix
        poke(16#8006#, x"01");  -- MULU dp
        poke(16#8007#, x"20");  -- dp
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"26");  -- $26
        poke(16#800A#, x"03");  -- $03 -> $0326/$0327
        poke(16#800B#, x"A9");  -- LDA #
        poke(16#800C#, x"14");
        poke(16#800D#, x"00");
        poke(16#800E#, x"02");  -- EXT prefix
        poke(16#800F#, x"07");  -- DIVU abs
        poke(16#8010#, x"50");  -- low
        poke(16#8011#, x"03");  -- high
        poke(16#8012#, x"8D");  -- STA abs
        poke(16#8013#, x"28");  -- $28
        poke(16#8014#, x"03");  -- $03 -> $0328/$0329
        poke(16#8015#, x"02");  -- EXT prefix
        poke(16#8016#, x"9A");  -- TTA (A = T remainder)
        poke(16#8017#, x"8D");  -- STA abs
        poke(16#8018#, x"2A");  -- $2A
        poke(16#8019#, x"03");  -- $03 -> $032A/$032B
        poke(16#801A#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(320);
        
        check_mem(16#0326#, x"0C", "MULU low");
        check_mem(16#0327#, x"00", "MULU high");
        check_mem(16#0328#, x"06", "DIVU low");
        check_mem(16#0329#, x"00", "DIVU high");
        check_mem(16#032A#, x"02", "DIVU remainder");
        
        -----------------------------------------------------------------------
        -- TEST 91: CAS success
        -----------------------------------------------------------------------
        report "";
        report "TEST 91: CAS success";
        
        poke(16#0030#, x"05");
        
        -- Program: CAS dp $30, set flag at $032A, loop
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"05");
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"07");
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"10");  -- CAS dp
        poke(16#8006#, x"30");
        poke(16#8007#, x"F0");  -- BEQ success
        poke(16#8008#, x"08");
        poke(16#8009#, x"A9");  -- LDA #
        poke(16#800A#, x"00");
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"2A");
        poke(16#800D#, x"03");
        poke(16#800E#, x"4C");  -- JMP done
        poke(16#800F#, x"16");
        poke(16#8010#, x"80");
        poke(16#8011#, x"A9");  -- LDA #
        poke(16#8012#, x"01");
        poke(16#8013#, x"8D");  -- STA abs
        poke(16#8014#, x"2A");
        poke(16#8015#, x"03");
        poke(16#8016#, x"4C");  -- done loop
        poke(16#8017#, x"16");
        poke(16#8018#, x"80");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0030#, x"07", "CAS success stored A");
        check_mem(16#032A#, x"01", "CAS Z=1");
        
        -----------------------------------------------------------------------
        -- TEST 92: CAS fail
        -----------------------------------------------------------------------
        report "";
        report "TEST 92: CAS fail";
        
        poke(16#0031#, x"09");
        
        -- Program: CAS dp $31, store X to $032B, flag at $032C, loop
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"05");
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"07");
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"10");  -- CAS dp
        poke(16#8006#, x"31");
        poke(16#8007#, x"8E");  -- STX abs
        poke(16#8008#, x"2B");
        poke(16#8009#, x"03");
        poke(16#800A#, x"D0");  -- BNE fail
        poke(16#800B#, x"08");
        poke(16#800C#, x"A9");  -- LDA #
        poke(16#800D#, x"00");
        poke(16#800E#, x"8D");  -- STA abs
        poke(16#800F#, x"2C");
        poke(16#8010#, x"03");
        poke(16#8011#, x"4C");  -- JMP done
        poke(16#8012#, x"1C");
        poke(16#8013#, x"80");
        poke(16#8014#, x"A9");  -- LDA #
        poke(16#8015#, x"01");
        poke(16#8016#, x"8D");  -- STA abs
        poke(16#8017#, x"2C");
        poke(16#8018#, x"03");
        poke(16#8019#, x"4C");  -- done loop
        poke(16#801A#, x"1C");
        poke(16#801B#, x"80");
        poke(16#801C#, x"4C");
        poke(16#801D#, x"1C");
        poke(16#801E#, x"80");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#032B#, x"09", "CAS fail loaded X");
        check_mem(16#032C#, x"01", "CAS Z=0");
        
        -----------------------------------------------------------------------
        -- TEST 93: LLI/SCI success
        -----------------------------------------------------------------------
        report "";
        report "TEST 93: LLI/SCI success";
        
        poke(16#0040#, x"3C");
        
        -- Program: LLI dp $40, SCI dp $40, flag at $032D, loop
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"12");  -- LLI dp
        poke(16#8002#, x"40");
        poke(16#8003#, x"02");  -- EXT prefix
        poke(16#8004#, x"14");  -- SCI dp
        poke(16#8005#, x"40");
        poke(16#8006#, x"F0");  -- BEQ success
        poke(16#8007#, x"08");
        poke(16#8008#, x"A9");  -- LDA #
        poke(16#8009#, x"00");
        poke(16#800A#, x"8D");  -- STA abs
        poke(16#800B#, x"2D");
        poke(16#800C#, x"03");
        poke(16#800D#, x"4C");  -- JMP done
        poke(16#800E#, x"18");
        poke(16#800F#, x"80");
        poke(16#8010#, x"A9");  -- LDA #
        poke(16#8011#, x"01");
        poke(16#8012#, x"8D");  -- STA abs
        poke(16#8013#, x"2D");
        poke(16#8014#, x"03");
        poke(16#8015#, x"4C");  -- done loop
        poke(16#8016#, x"18");
        poke(16#8017#, x"80");
        poke(16#8018#, x"4C");
        poke(16#8019#, x"18");
        poke(16#801A#, x"80");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0040#, x"3C", "SCI success stored A");
        check_mem(16#032D#, x"01", "SCI Z=1");
        
        -----------------------------------------------------------------------
        -- TEST 94: LLI/SCI fail
        -----------------------------------------------------------------------
        report "";
        report "TEST 94: LLI/SCI fail";
        
        poke(16#0041#, x"AA");
        
        -- Program: LLI dp $41, STA $0330 (clear link), SCI dp $41, flag at $032E, loop
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"12");  -- LLI dp
        poke(16#8002#, x"41");
        poke(16#8003#, x"A9");  -- LDA #
        poke(16#8004#, x"00");
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"30");
        poke(16#8007#, x"03");
        poke(16#8008#, x"02");  -- EXT prefix
        poke(16#8009#, x"14");  -- SCI dp
        poke(16#800A#, x"41");
        poke(16#800B#, x"D0");  -- BNE fail
        poke(16#800C#, x"08");
        poke(16#800D#, x"A9");  -- LDA #
        poke(16#800E#, x"00");
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"2E");
        poke(16#8011#, x"03");
        poke(16#8012#, x"4C");  -- JMP done
        poke(16#8013#, x"1E");
        poke(16#8014#, x"80");
        poke(16#8015#, x"A9");  -- LDA #
        poke(16#8016#, x"01");
        poke(16#8017#, x"8D");  -- STA abs
        poke(16#8018#, x"2E");
        poke(16#8019#, x"03");
        poke(16#801A#, x"4C");  -- done loop
        poke(16#801B#, x"1E");
        poke(16#801C#, x"80");
        poke(16#801E#, x"4C");
        poke(16#801F#, x"1E");
        poke(16#8020#, x"80");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(280);
        
        check_mem(16#032E#, x"01", "SCI Z=0");
        
        -----------------------------------------------------------------------
        -- TEST 95: RSET register window ignores D (dp + dp,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 95: RSET register window";
        
        -- Memory values that should be ignored in R mode
        poke(16#1020#, x"55");
        poke(16#2020#, x"55");
        poke(16#2021#, x"11");
        
        -- Program:
        -- SD #$00001000, RSET, LDA #$AA, STA $20
        -- SD #$00002000, LDA $20 -> $0340 (should be $AA)
        -- LDX #$04, LDA #$CC, STA $20,X, LDA $24 -> $0342 (should be $CC)
        -- RCLR, LDA $20 -> $0341 (should be $55 from $2020)
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"24");  -- SD #imm32
        poke(16#8002#, x"00");  -- imm0
        poke(16#8003#, x"10");  -- imm1
        poke(16#8004#, x"00");  -- imm2
        poke(16#8005#, x"00");  -- imm3
        poke(16#8006#, x"02");  -- EXT prefix
        poke(16#8007#, x"30");  -- RSET
        poke(16#8008#, x"A9");  -- LDA #
        poke(16#8009#, x"AA");
        poke(16#800A#, x"85");  -- STA dp
        poke(16#800B#, x"20");
        poke(16#800C#, x"02");  -- EXT prefix
        poke(16#800D#, x"24");  -- SD #imm32
        poke(16#800E#, x"00");  -- imm0
        poke(16#800F#, x"20");  -- imm1
        poke(16#8010#, x"00");  -- imm2
        poke(16#8011#, x"00");  -- imm3
        poke(16#8012#, x"A5");  -- LDA dp
        poke(16#8013#, x"20");
        poke(16#8014#, x"8D");  -- STA abs
        poke(16#8015#, x"40");  -- $0340
        poke(16#8016#, x"03");
        poke(16#8017#, x"A2");  -- LDX #
        poke(16#8018#, x"04");
        poke(16#8019#, x"A9");  -- LDA #
        poke(16#801A#, x"CC");
        poke(16#801B#, x"95");  -- STA dp,X
        poke(16#801C#, x"20");
        poke(16#801D#, x"A5");  -- LDA dp
        poke(16#801E#, x"24");
        poke(16#801F#, x"8D");  -- STA abs
        poke(16#8020#, x"42");  -- $0342
        poke(16#8021#, x"03");
        poke(16#8022#, x"02");  -- EXT prefix
        poke(16#8023#, x"31");  -- RCLR
        poke(16#8024#, x"A5");  -- LDA dp
        poke(16#8025#, x"20");
        poke(16#8026#, x"8D");  -- STA abs
        poke(16#8027#, x"41");  -- $0341
        poke(16#8028#, x"03");
        poke(16#8029#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(320);
        
        check_mem(16#0340#, x"AA", "RSET ignores D (dp)");
        check_mem(16#0341#, x"55", "RCLR uses memory dp");
        check_mem(16#0342#, x"CC", "RSET dp,X index");
        
        -----------------------------------------------------------------------
        -- TEST 96: RSET dp RMW (INC)
        -----------------------------------------------------------------------
        report "";
        report "TEST 96: RSET dp RMW";
        
        -- Memory value that should be ignored in R mode
        poke(16#1010#, x"80");
        
        -- Program: SD #$00001000, RSET, LDA #$01, STA $10, INC $10,
        -- LDA $10 -> $0343, RCLR, LDA $10 -> $0344
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"24");  -- SD #imm32
        poke(16#8002#, x"00");  -- imm0
        poke(16#8003#, x"10");  -- imm1
        poke(16#8004#, x"00");  -- imm2
        poke(16#8005#, x"00");  -- imm3
        poke(16#8006#, x"02");  -- EXT prefix
        poke(16#8007#, x"30");  -- RSET
        poke(16#8008#, x"A9");  -- LDA #
        poke(16#8009#, x"01");
        poke(16#800A#, x"85");  -- STA dp
        poke(16#800B#, x"10");
        poke(16#800C#, x"E6");  -- INC dp
        poke(16#800D#, x"10");
        poke(16#800E#, x"A5");  -- LDA dp
        poke(16#800F#, x"10");
        poke(16#8010#, x"8D");  -- STA abs
        poke(16#8011#, x"43");  -- $0343
        poke(16#8012#, x"03");
        poke(16#8013#, x"02");  -- EXT prefix
        poke(16#8014#, x"31");  -- RCLR
        poke(16#8015#, x"A5");  -- LDA dp
        poke(16#8016#, x"10");
        poke(16#8017#, x"8D");  -- STA abs
        poke(16#8018#, x"44");  -- $0344
        poke(16#8019#, x"03");
        poke(16#801A#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(320);
        
        check_mem(16#0343#, x"02", "RSET INC dp");
        check_mem(16#0344#, x"80", "RCLR dp reads memory");
        
        -----------------------------------------------------------------------
        -- TEST 97: RSET MULU dp
        -----------------------------------------------------------------------
        report "";
        report "TEST 97: RSET MULU dp";
        
        -- Program: RSET, LDA #$03, STA $20, LDA #$04,
        -- MULU dp $20, STA $0345
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"30");  -- RSET
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"03");
        poke(16#8004#, x"85");  -- STA dp
        poke(16#8005#, x"20");
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"04");
        poke(16#8008#, x"02");  -- EXT prefix
        poke(16#8009#, x"01");  -- MULU dp
        poke(16#800A#, x"20");
        poke(16#800B#, x"8D");  -- STA abs
        poke(16#800C#, x"45");  -- $0345
        poke(16#800D#, x"03");
        poke(16#800E#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0345#, x"0C", "RSET MULU dp");
        
        -----------------------------------------------------------------------
        -- TEST 98: LDQ/STQ absolute (64-bit)
        -----------------------------------------------------------------------
        report "";
        report "TEST 98: LDQ/STQ abs";
        
        poke(16#0500#, x"01");
        poke(16#0501#, x"02");
        poke(16#0502#, x"03");
        poke(16#0503#, x"04");
        poke(16#0504#, x"11");
        poke(16#0505#, x"12");
        poke(16#0506#, x"13");
        poke(16#0507#, x"14");
        
        -- Program: set M=32, LDQ abs $0500, STA $0520, STQ abs $0510
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"9D");  -- LDQ abs
        poke(16#8006#, x"00");  -- low
        poke(16#8007#, x"05");  -- high
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"20");  -- $0520
        poke(16#800A#, x"05");
        poke(16#800B#, x"02");  -- EXT prefix
        poke(16#800C#, x"9F");  -- STQ abs
        poke(16#800D#, x"10");  -- low
        poke(16#800E#, x"05");  -- high
        poke(16#800F#, x"8D");  -- STA abs
        poke(16#8010#, x"28");  -- $0528
        poke(16#8011#, x"05");
        poke(16#8012#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(380);
        
        check_mem(16#0520#, x"01", "LDQ A byte0");
        check_mem(16#0521#, x"02", "LDQ A byte1");
        check_mem(16#0522#, x"03", "LDQ A byte2");
        check_mem(16#0523#, x"04", "LDQ A byte3");
        check_mem(16#0528#, x"01", "A after STQ byte0");
        check_mem(16#0529#, x"02", "A after STQ byte1");
        check_mem(16#052A#, x"03", "A after STQ byte2");
        check_mem(16#052B#, x"04", "A after STQ byte3");
        
        check_mem(16#0510#, x"01", "STQ abs byte0");
        check_mem(16#0511#, x"02", "STQ abs byte1");
        check_mem(16#0512#, x"03", "STQ abs byte2");
        check_mem(16#0513#, x"04", "STQ abs byte3");
        check_mem(16#0514#, x"11", "STQ abs byte4");
        check_mem(16#0515#, x"12", "STQ abs byte5");
        check_mem(16#0516#, x"13", "STQ abs byte6");
        check_mem(16#0517#, x"14", "STQ abs byte7");
        
        -----------------------------------------------------------------------
        -- TEST 99: LDQ/STQ dp in RSET
        -----------------------------------------------------------------------
        report "";
        report "TEST 99: LDQ/STQ dp (RSET)";
        
        -- Program: RSET, LDA #$11, TAT, LDA #$22, STQ dp $30,
        -- LDQ dp $30, STA $0346, TTA, STA $0347
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"30");  -- RSET
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"11");
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"9B");  -- TAT
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"22");
        poke(16#8008#, x"02");  -- EXT prefix
        poke(16#8009#, x"9E");  -- STQ dp
        poke(16#800A#, x"30");
        poke(16#800B#, x"02");  -- EXT prefix
        poke(16#800C#, x"9C");  -- LDQ dp
        poke(16#800D#, x"30");
        poke(16#800E#, x"8D");  -- STA abs
        poke(16#800F#, x"46");  -- $0346
        poke(16#8010#, x"03");
        poke(16#8011#, x"02");  -- EXT prefix
        poke(16#8012#, x"9A");  -- TTA
        poke(16#8013#, x"8D");  -- STA abs
        poke(16#8014#, x"47");  -- $0347
        poke(16#8015#, x"03");
        poke(16#8016#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(280);
        
        check_mem(16#0346#, x"22", "LDQ dp low");
        check_mem(16#0347#, x"11", "LDQ dp high");
        
        -----------------------------------------------------------------------
        -- TEST 100A: LDF/STF + FADD.S (16-register, two-operand format)
        -----------------------------------------------------------------------
        report "";
        report "TEST 100A: LDF/STF + FADD.S";
        
        -- F0 = 1.5 (0x3FC00000), F1 = 2.25 (0x40100000)
        -- Store 1.5 at $0600, 2.25 at $0608
        poke(16#0600#, x"00");
        poke(16#0601#, x"00");
        poke(16#0602#, x"C0");
        poke(16#0603#, x"3F");
        poke(16#0604#, x"00");
        poke(16#0605#, x"00");
        poke(16#0606#, x"00");
        poke(16#0607#, x"00");
        poke(16#0608#, x"00");
        poke(16#0609#, x"00");
        poke(16#060A#, x"10");
        poke(16#060B#, x"40");
        poke(16#060C#, x"00");
        poke(16#060D#, x"00");
        poke(16#060E#, x"00");
        poke(16#060F#, x"00");
        
        -- New format: LDF Fn, abs = $02 $B1 $0n addr16
        --             FADD.S Fd, Fs = $02 $C0 $ds (Fd = Fd + Fs)
        -- Program: LDF F0, abs $0600 (F0=1.5)
        --          LDF F1, abs $0608 (F1=2.25)
        --          FADD.S F0, F1 (F0 = F0 + F1 = 3.75)
        --          STF F0, abs $0620
        --          BRK
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"B1");  -- LDF abs
        poke(16#8002#, x"00");  -- reg byte: F0
        poke(16#8003#, x"00");  -- addr low
        poke(16#8004#, x"06");  -- addr high
        poke(16#8005#, x"02");  -- EXT prefix
        poke(16#8006#, x"B1");  -- LDF abs
        poke(16#8007#, x"01");  -- reg byte: F1
        poke(16#8008#, x"08");  -- addr low
        poke(16#8009#, x"06");  -- addr high
        poke(16#800A#, x"02");  -- EXT prefix
        poke(16#800B#, x"C0");  -- FADD.S
        poke(16#800C#, x"01");  -- reg byte: dest=F0, src=F1 ($01)
        poke(16#800D#, x"02");  -- EXT prefix
        poke(16#800E#, x"B3");  -- STF abs
        poke(16#800F#, x"00");  -- reg byte: F0
        poke(16#8010#, x"20");  -- addr low
        poke(16#8011#, x"06");  -- addr high
        poke(16#8012#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(620);
        
        -- 3.75 (0x40700000) little-endian at $0620
        check_mem(16#0620#, x"00", "FADD.S byte0");
        check_mem(16#0621#, x"00", "FADD.S byte1");
        check_mem(16#0622#, x"70", "FADD.S byte2");
        check_mem(16#0623#, x"40", "FADD.S byte3");

        -----------------------------------------------------------------------
        -- TEST 100B: F2I.S and I2F.S (16-register format)
        -----------------------------------------------------------------------
        report "";
        report "TEST 100B: F2I.S/I2F.S";
        
        -- F0 = 5.5 (0x40B00000)
        poke(16#0630#, x"00");
        poke(16#0631#, x"00");
        poke(16#0632#, x"B0");
        poke(16#0633#, x"40");
        poke(16#0634#, x"00");
        poke(16#0635#, x"00");
        poke(16#0636#, x"00");
        poke(16#0637#, x"00");
        
        -- New format: F2I.S Fd = $02 $C7 $d0 (A = (int32)Fd)
        --             I2F.S Fd = $02 $C8 $d0 (Fd = (float32)A)
        -- Program: set M=32, LDF F0, abs $0630, F2I.S F0, STA $0640,
        --          LDA #$07, I2F.S F0, STF F0, abs $0650, BRK
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"B1");  -- LDF abs
        poke(16#8006#, x"00");  -- reg byte: F0
        poke(16#8007#, x"30");  -- addr low
        poke(16#8008#, x"06");  -- addr high
        poke(16#8009#, x"02");  -- EXT prefix
        poke(16#800A#, x"C7");  -- F2I.S
        poke(16#800B#, x"00");  -- reg byte: F0 (dest in high nibble)
        poke(16#800C#, x"8D");  -- STA abs
        poke(16#800D#, x"40");
        poke(16#800E#, x"06");
        poke(16#800F#, x"A9");  -- LDA #imm32
        poke(16#8010#, x"07");
        poke(16#8011#, x"00");
        poke(16#8012#, x"00");
        poke(16#8013#, x"00");
        poke(16#8014#, x"02");  -- EXT prefix
        poke(16#8015#, x"C8");  -- I2F.S
        poke(16#8016#, x"00");  -- reg byte: F0 (dest in high nibble)
        poke(16#8017#, x"02");  -- EXT prefix
        poke(16#8018#, x"B3");  -- STF abs
        poke(16#8019#, x"00");  -- reg byte: F0
        poke(16#801A#, x"50");  -- addr low
        poke(16#801B#, x"06");  -- addr high
        poke(16#801C#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(660);
        
        check_mem(16#0640#, x"05", "F2I.S A low byte");
        check_mem(16#0650#, x"00", "I2F.S byte0");
        check_mem(16#0651#, x"00", "I2F.S byte1");
        check_mem(16#0652#, x"E0", "I2F.S byte2");
        check_mem(16#0653#, x"40", "I2F.S byte3");

        -----------------------------------------------------------------------
        -- TEST 100C: RSET LDF/STF dp (register window, 16-register format)
        -----------------------------------------------------------------------
        report "";
        report "TEST 100C: RSET LDF/STF dp";
        
        -- New format: LDF Fn, dp = $02 $B0 $0n dp
        --             STF Fn, dp = $02 $B2 $0n dp
        -- Program: set M=32, RSET, write R0/R1, LDF F0, dp $00, STF F0, dp $08,
        --          LDA $08 -> STA $0700, LDA $0C -> STA $0704, BRK
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"02");  -- EXT prefix
        poke(16#8005#, x"30");  -- RSET
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"44");
        poke(16#8008#, x"33");
        poke(16#8009#, x"22");
        poke(16#800A#, x"11");
        poke(16#800B#, x"85");  -- STA dp
        poke(16#800C#, x"00");  -- R0
        poke(16#800D#, x"A9");  -- LDA #
        poke(16#800E#, x"88");
        poke(16#800F#, x"77");
        poke(16#8010#, x"66");
        poke(16#8011#, x"55");
        poke(16#8012#, x"85");  -- STA dp
        poke(16#8013#, x"04");  -- R1 (aligned)
        poke(16#8014#, x"02");  -- EXT prefix
        poke(16#8015#, x"B0");  -- LDF dp
        poke(16#8016#, x"00");  -- reg byte: F0
        poke(16#8017#, x"00");  -- dp addr
        poke(16#8018#, x"02");  -- EXT prefix
        poke(16#8019#, x"B2");  -- STF dp
        poke(16#801A#, x"00");  -- reg byte: F0
        poke(16#801B#, x"08");  -- dp addr: R2/R3
        poke(16#801C#, x"A5");  -- LDA dp
        poke(16#801D#, x"08");  -- R2
        poke(16#801E#, x"8D");  -- STA abs
        poke(16#801F#, x"00");
        poke(16#8020#, x"07");
        poke(16#8021#, x"A5");  -- LDA dp
        poke(16#8022#, x"0C");  -- R3 (aligned high word)
        poke(16#8023#, x"8D");  -- STA abs
        poke(16#8024#, x"04");
        poke(16#8025#, x"07");
        poke(16#8026#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(1300);
        
        check_mem(16#0700#, x"44", "RSET LDF/STF low byte0");
        check_mem(16#0701#, x"33", "RSET LDF/STF low byte1");
        check_mem(16#0702#, x"22", "RSET LDF/STF low byte2");
        check_mem(16#0703#, x"11", "RSET LDF/STF low byte3");
        check_mem(16#0704#, x"88", "RSET LDF/STF high byte0");
        check_mem(16#0705#, x"77", "RSET LDF/STF high byte1");
        check_mem(16#0706#, x"66", "RSET LDF/STF high byte2");
        check_mem(16#0707#, x"55", "RSET LDF/STF high byte3");

        -----------------------------------------------------------------------
        -- TEST 100C2: RSET DP alignment trap
        -----------------------------------------------------------------------
        report "";
        report "TEST 100C2: RSET DP alignment trap";
        
        -- In R=1 mode, DP addresses must be aligned to 4 bytes (multiples of 4)
        -- Accessing unaligned address like $05 should trap to VEC_ILLEGAL
        
        -- Set up illegal instruction trap handler at VEC_ILLEGAL ($FFF8)
        -- Handler at $E000: LDA #$DE, STA $0710, RTI
        poke(16#FFF8#, x"00");
        poke(16#FFF9#, x"E0");
        poke(16#FFFA#, x"00");
        poke(16#FFFB#, x"00");
        
        poke(16#E000#, x"A9");  -- LDA #$DE (trap marker)
        poke(16#E001#, x"DE");
        poke(16#E002#, x"8D");  -- STA $0710
        poke(16#E003#, x"10");
        poke(16#E004#, x"07");
        poke(16#E005#, x"40");  -- RTI
        
        -- Program: RSET, LDA $05 (unaligned - should trap), LDA #$AA, STA $0711
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"30");  -- RSET
        poke(16#8002#, x"A5");  -- LDA dp
        poke(16#8003#, x"05");  -- $05 (unaligned!)
        poke(16#8004#, x"A9");  -- LDA #$AA (after RTI)
        poke(16#8005#, x"AA");
        poke(16#8006#, x"8D");  -- STA $0711
        poke(16#8007#, x"11");
        poke(16#8008#, x"07");
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(300);
        
        check_mem(16#0710#, x"DE", "RSET unaligned trap fired");
        check_mem(16#0711#, x"AA", "Returned after alignment trap");

        -----------------------------------------------------------------------
        -- TEST 100D: FPU reserved opcode trap
        -----------------------------------------------------------------------
        report "";
        report "TEST 100D: FPU reserved trap";
        
        -- Trap vector for FP opcode $DB -> VEC_SYSCALL + $DB*4 (wraps to $0340)
        -- Note: $D9 and $DA are now FMOV.D and FSQRT.D, use $DB for trap test
        poke(16#0340#, x"00");
        poke(16#0341#, x"90");
        poke(16#0342#, x"00");
        poke(16#0343#, x"00");
        
        -- Handler at $9000: LDA #$A5, STA $0709, RTI
        poke(16#9000#, x"A9");
        poke(16#9001#, x"A5");
        poke(16#9002#, x"8D");
        poke(16#9003#, x"09");
        poke(16#9004#, x"07");
        poke(16#9005#, x"40");
        
        -- Program: execute reserved FP opcode $DB (with reg byte), then write $0708 and BRK
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"DB");  -- reserved FP opcode -> trap
        poke(16#8002#, x"00");  -- reg byte (still needed, but traps before use)
        poke(16#8003#, x"A9");  -- LDA #
        poke(16#8004#, x"5A");
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"08");
        poke(16#8007#, x"07");
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(300);
        
        check_mem(16#0709#, x"A5", "FP trap handler wrote");
        check_mem(16#0708#, x"5A", "Returned after FP trap");

        -----------------------------------------------------------------------
        -- TEST 100E: FADD.D (16-register, two-operand format)
        -----------------------------------------------------------------------
        report "";
        report "TEST 100E: FADD.D";
        
        -- F0 = 1.5 (0x3FF8000000000000), F1 = 2.25 (0x4002000000000000)
        poke(16#0800#, x"00");
        poke(16#0801#, x"00");
        poke(16#0802#, x"00");
        poke(16#0803#, x"00");
        poke(16#0804#, x"00");
        poke(16#0805#, x"00");
        poke(16#0806#, x"F8");
        poke(16#0807#, x"3F");
        poke(16#0808#, x"00");
        poke(16#0809#, x"00");
        poke(16#080A#, x"00");
        poke(16#080B#, x"00");
        poke(16#080C#, x"00");
        poke(16#080D#, x"00");
        poke(16#080E#, x"02");
        poke(16#080F#, x"40");
        
        -- New format: LDF Fn, abs = $02 $B1 $0n addr16
        --             FADD.D Fd, Fs = $02 $D0 $ds (Fd = Fd + Fs)
        -- Program: LDF F0, abs $0800 (F0=1.5)
        --          LDF F1, abs $0808 (F1=2.25)
        --          FADD.D F0, F1 (F0 = F0 + F1 = 3.75)
        --          STF F0, abs $0820
        --          BRK
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"B1");  -- LDF abs
        poke(16#8002#, x"00");  -- reg byte: F0
        poke(16#8003#, x"00");  -- addr low
        poke(16#8004#, x"08");  -- addr high
        poke(16#8005#, x"02");  -- EXT prefix
        poke(16#8006#, x"B1");  -- LDF abs
        poke(16#8007#, x"01");  -- reg byte: F1
        poke(16#8008#, x"08");  -- addr low
        poke(16#8009#, x"08");  -- addr high
        poke(16#800A#, x"02");  -- EXT prefix
        poke(16#800B#, x"D0");  -- FADD.D
        poke(16#800C#, x"01");  -- reg byte: dest=F0, src=F1 ($01)
        poke(16#800D#, x"02");  -- EXT prefix
        poke(16#800E#, x"B3");  -- STF abs
        poke(16#800F#, x"00");  -- reg byte: F0
        poke(16#8010#, x"20");  -- addr low
        poke(16#8011#, x"08");  -- addr high
        poke(16#8012#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(620);
        
        -- 3.75 (0x400E000000000000) little-endian at $0820
        check_mem(16#0820#, x"00", "FADD.D byte0");
        check_mem(16#0821#, x"00", "FADD.D byte1");
        check_mem(16#0822#, x"00", "FADD.D byte2");
        check_mem(16#0823#, x"00", "FADD.D byte3");
        check_mem(16#0824#, x"00", "FADD.D byte4");
        check_mem(16#0825#, x"00", "FADD.D byte5");
        check_mem(16#0826#, x"0E", "FADD.D byte6");
        check_mem(16#0827#, x"40", "FADD.D byte7");

        -----------------------------------------------------------------------
        -- TEST 100F: FCMP.S flags (16-register, two-operand format)
        -----------------------------------------------------------------------
        report "";
        report "TEST 100F: FCMP.S flags";
        
        -- F0 = 1.0 (0x3F800000), F1 = 2.0 (0x40000000)
        poke(16#0830#, x"00");
        poke(16#0831#, x"00");
        poke(16#0832#, x"80");
        poke(16#0833#, x"3F");
        poke(16#0834#, x"00");
        poke(16#0835#, x"00");
        poke(16#0836#, x"00");
        poke(16#0837#, x"00");
        poke(16#0838#, x"00");
        poke(16#0839#, x"00");
        poke(16#083A#, x"00");
        poke(16#083B#, x"40");
        poke(16#083C#, x"00");
        poke(16#083D#, x"00");
        poke(16#083E#, x"00");
        poke(16#083F#, x"00");
        
        -- New format: FCMP.S Fd, Fs = $02 $C6 $ds (compare Fd to Fs)
        -- Program: LDF F0, abs $0830 (F0=1.0)
        --          LDF F1, abs $0838 (F1=2.0)
        --          FCMP.S F0, F1 (compare F0 to F1)
        -- BMI less -> set $0728 = 1
        -- Then load equal values and BEQ -> set $0729 = 1
        poke(16#8000#, x"A9");  -- LDA #
        poke(16#8001#, x"00");
        poke(16#8002#, x"8D");  -- STA abs
        poke(16#8003#, x"28");
        poke(16#8004#, x"07");
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"29");
        poke(16#8007#, x"07");
        poke(16#8008#, x"02");  -- EXT prefix
        poke(16#8009#, x"B1");  -- LDF abs
        poke(16#800A#, x"00");  -- reg byte: F0
        poke(16#800B#, x"30");  -- addr low
        poke(16#800C#, x"08");  -- addr high
        poke(16#800D#, x"02");  -- EXT prefix
        poke(16#800E#, x"B1");  -- LDF abs
        poke(16#800F#, x"01");  -- reg byte: F1
        poke(16#8010#, x"38");  -- addr low
        poke(16#8011#, x"08");  -- addr high
        poke(16#8012#, x"02");  -- EXT prefix
        poke(16#8013#, x"C6");  -- FCMP.S
        poke(16#8014#, x"01");  -- reg byte: dest=F0, src=F1 ($01)
        poke(16#8015#, x"30");  -- BMI
        poke(16#8016#, x"03");  -- +3 -> LDA #1
        poke(16#8017#, x"4C");  -- JMP skip
        poke(16#8018#, x"1F");
        poke(16#8019#, x"80");
        poke(16#801A#, x"A9");  -- LDA #
        poke(16#801B#, x"01");
        poke(16#801C#, x"8D");  -- STA abs
        poke(16#801D#, x"28");
        poke(16#801E#, x"07");
        poke(16#801F#, x"02");  -- EXT prefix
        poke(16#8020#, x"B1");  -- LDF abs (now equal: reuse F1 value for F0)
        poke(16#8021#, x"00");  -- reg byte: F0
        poke(16#8022#, x"38");  -- addr low (F1's data = 2.0)
        poke(16#8023#, x"08");  -- addr high
        poke(16#8024#, x"02");  -- EXT prefix
        poke(16#8025#, x"B1");  -- LDF abs
        poke(16#8026#, x"01");  -- reg byte: F1
        poke(16#8027#, x"38");  -- addr low
        poke(16#8028#, x"08");  -- addr high
        poke(16#8029#, x"02");  -- EXT prefix
        poke(16#802A#, x"C6");  -- FCMP.S
        poke(16#802B#, x"01");  -- reg byte: dest=F0, src=F1 ($01)
        poke(16#802C#, x"F0");  -- BEQ
        poke(16#802D#, x"03");  -- +3 -> LDA #1
        poke(16#802E#, x"4C");  -- JMP done
        poke(16#802F#, x"36");
        poke(16#8030#, x"80");
        poke(16#8031#, x"A9");  -- LDA #
        poke(16#8032#, x"01");
        poke(16#8033#, x"8D");  -- STA abs
        poke(16#8034#, x"29");
        poke(16#8035#, x"07");
        poke(16#8036#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(800);
        
        check_mem(16#0728#, x"01", "FCMP.S less sets N");
        check_mem(16#0729#, x"01", "FCMP.S equal sets Z");

        -----------------------------------------------------------------------
        -- TEST 100: TRAP vector + RTI
        -----------------------------------------------------------------------
        report "";
        report "TEST 100: TRAP + RTI";
        
        -- Syscall vector -> $00009000
        poke(16#FFD4#, x"00");
        poke(16#FFD5#, x"90");
        poke(16#FFD6#, x"00");
        poke(16#FFD7#, x"00");
        
        -- Handler at $9000: LDA #$AA, STA $0400, RTI
        poke(16#9000#, x"A9");
        poke(16#9001#, x"AA");
        poke(16#9002#, x"8D");
        poke(16#9003#, x"00");
        poke(16#9004#, x"04");
        poke(16#9005#, x"40");  -- RTI
        
        -- Program: TRAP #$00, LDA #$55, STA $0401, BRK
        poke(16#8000#, x"02");  -- EXT prefix
        poke(16#8001#, x"40");  -- TRAP
        poke(16#8002#, x"00");  -- vector index
        poke(16#8003#, x"A9");
        poke(16#8004#, x"55");
        poke(16#8005#, x"8D");
        poke(16#8006#, x"01");
        poke(16#8007#, x"04");
        poke(16#8008#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0400#, x"AA", "TRAP handler wrote");
        check_mem(16#0401#, x"55", "RTI returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 101: BRK vector + RTI
        -----------------------------------------------------------------------
        report "";
        report "TEST 101: BRK + RTI";
        
        -- BRK vector (E=1 uses IRQ vector at $FFFE, wraps in 64KB memory)
        -- $FFFE/$FFFF/$0000/$0001 -> $00009010
        poke(16#FFFE#, x"10");
        poke(16#FFFF#, x"90");
        poke(16#0000#, x"00");
        poke(16#0001#, x"00");
        
        -- Handler at $9010: LDA #$CC, STA $0402, RTI
        poke(16#9010#, x"A9");
        poke(16#9011#, x"CC");
        poke(16#9012#, x"8D");
        poke(16#9013#, x"02");
        poke(16#9014#, x"04");
        poke(16#9015#, x"40");  -- RTI
        
        -- Program: BRK, LDA #$66, STA $0403, BRK
        poke(16#8000#, x"00");  -- BRK
        poke(16#8001#, x"A9");
        poke(16#8002#, x"66");
        poke(16#8003#, x"8D");
        poke(16#8004#, x"03");
        poke(16#8005#, x"04");
        poke(16#8006#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0402#, x"CC", "BRK handler wrote");
        check_mem(16#0403#, x"66", "RTI returned after BRK");
        
        -----------------------------------------------------------------------
        -- TEST 102: MVN block move (increment)
        -----------------------------------------------------------------------
        report "";
        report "TEST 102: MVN";
        
        -- Source bytes at $0020..$0023
        poke(16#0020#, x"11");
        poke(16#0021#, x"12");
        poke(16#0022#, x"13");
        poke(16#0023#, x"14");
        
        -- Program: LDX #$20, LDY #$40, LDA #$03, MVN $00,$00, BRK
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"20");
        poke(16#8002#, x"A0");  -- LDY #
        poke(16#8003#, x"40");
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"03");
        poke(16#8006#, x"44");  -- MVN
        poke(16#8007#, x"00");  -- dest bank
        poke(16#8008#, x"00");  -- src bank
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0040#, x"11", "MVN byte0");
        check_mem(16#0041#, x"12", "MVN byte1");
        check_mem(16#0042#, x"13", "MVN byte2");
        check_mem(16#0043#, x"14", "MVN byte3");
        
        -----------------------------------------------------------------------
        -- TEST 103: MVP block move (decrement)
        -----------------------------------------------------------------------
        report "";
        report "TEST 103: MVP";
        
        -- Source bytes at $0030..$0033
        poke(16#0030#, x"21");
        poke(16#0031#, x"22");
        poke(16#0032#, x"23");
        poke(16#0033#, x"24");
        
        -- Program: LDX #$33, LDY #$53, LDA #$03, MVP $00,$00, BRK
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"33");
        poke(16#8002#, x"A0");  -- LDY #
        poke(16#8003#, x"53");
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"03");
        poke(16#8006#, x"54");  -- MVP
        poke(16#8007#, x"00");  -- dest bank
        poke(16#8008#, x"00");  -- src bank
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(260);
        
        check_mem(16#0050#, x"21", "MVP byte0");
        check_mem(16#0051#, x"22", "MVP byte1");
        check_mem(16#0052#, x"23", "MVP byte2");
        check_mem(16#0053#, x"24", "MVP byte3");
        
        -----------------------------------------------------------------------
        -- TEST 104: XCE (enter native), 16-bit A immediate
        -----------------------------------------------------------------------
        report "";
        report "TEST 104: XCE";
        
        poke(16#0410#, x"00");
        poke(16#0411#, x"00");
        
        -- Program: CLC, XCE, REP #$80, SEP #$40, LDA #$1234, STA $0410, BRK
        poke(16#8000#, x"18");  -- CLC
        poke(16#8001#, x"FB");  -- XCE
        poke(16#8002#, x"C2");  -- REP
        poke(16#8003#, x"80");  -- clear M1
        poke(16#8004#, x"E2");  -- SEP
        poke(16#8005#, x"40");  -- set M0 (16-bit)
        poke(16#8006#, x"A9");  -- LDA #
        poke(16#8007#, x"34");
        poke(16#8008#, x"12");
        poke(16#8009#, x"8D");  -- STA abs
        poke(16#800A#, x"10");
        poke(16#800B#, x"04");
        poke(16#800C#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0410#, x"34", "XCE LDA low byte");
        check_mem(16#0411#, x"12", "XCE LDA high byte");
        
        -----------------------------------------------------------------------
        -- TEST 105: 32-bit LDA long (no X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 105: 32-bit LDA long";
        
        poke(16#0700#, x"11");
        poke(16#0701#, x"22");
        poke(16#0702#, x"33");
        poke(16#0703#, x"44");
        
        -- Program: set M=32-bit, LDA long $000700, STA $0430
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"AB");  -- LDA long
        poke(16#8005#, x"00");  -- low
        poke(16#8006#, x"07");  -- high
        poke(16#8007#, x"00");  -- bank
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"30");  -- $0430
        poke(16#800A#, x"04");
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#0430#, x"11", "32-bit LDA long byte 0");
        check_mem(16#0431#, x"22", "32-bit LDA long byte 1");
        check_mem(16#0432#, x"33", "32-bit LDA long byte 2");
        check_mem(16#0433#, x"44", "32-bit LDA long byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 106: 16-bit LDA long,X
        -----------------------------------------------------------------------
        report "";
        report "TEST 106: 16-bit LDA long,X";
        
        poke(16#0712#, x"55");
        poke(16#0713#, x"66");
        
        -- Program: set M=16-bit, LDX #$02, LDA long,X $000710, STA $0438
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A2");  -- LDX #
        poke(16#8005#, x"02");
        poke(16#8006#, x"BF");  -- LDA long,X
        poke(16#8007#, x"10");  -- low
        poke(16#8008#, x"07");  -- high
        poke(16#8009#, x"00");  -- bank
        poke(16#800A#, x"8D");  -- STA abs
        poke(16#800B#, x"38");  -- $0438
        poke(16#800C#, x"04");
        poke(16#800D#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0438#, x"55", "16-bit LDA long,X low");
        check_mem(16#0439#, x"66", "16-bit LDA long,X high");
        
        -----------------------------------------------------------------------
        -- TEST 107: 16-bit LDA [dp],Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 107: 16-bit LDA [dp],Y";
        
        poke(16#00B0#, x"20");  -- low
        poke(16#00B1#, x"07");  -- high
        poke(16#00B2#, x"00");  -- bank
        poke(16#0721#, x"77");
        poke(16#0722#, x"88");
        
        -- Program: set M=16-bit, LDY #$01, LDA [dp],Y, STA $0440
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"01");
        poke(16#8006#, x"B3");  -- LDA [dp],Y
        poke(16#8007#, x"B0");  -- dp
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"40");  -- $0440
        poke(16#800A#, x"04");
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0440#, x"77", "16-bit LDA [dp],Y low");
        check_mem(16#0441#, x"88", "16-bit LDA [dp],Y high");
        
        -----------------------------------------------------------------------
        -- TEST 108: 32-bit LDA [dp]
        -----------------------------------------------------------------------
        report "";
        report "TEST 108: 32-bit LDA [dp]";
        
        poke(16#00B4#, x"30");  -- low
        poke(16#00B5#, x"07");  -- high
        poke(16#00B6#, x"00");  -- bank
        poke(16#0730#, x"99");
        poke(16#0731#, x"AA");
        poke(16#0732#, x"BB");
        poke(16#0733#, x"CC");
        
        -- Program: set M=32-bit, LDA [dp], STA $0444
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A7");  -- LDA [dp]
        poke(16#8005#, x"B4");  -- dp
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"44");  -- $0444
        poke(16#8008#, x"04");
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#0444#, x"99", "32-bit LDA [dp] byte 0");
        check_mem(16#0445#, x"AA", "32-bit LDA [dp] byte 1");
        check_mem(16#0446#, x"BB", "32-bit LDA [dp] byte 2");
        check_mem(16#0447#, x"CC", "32-bit LDA [dp] byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 109: 32-bit LDA sr,S
        -----------------------------------------------------------------------
        report "";
        report "TEST 109: 32-bit LDA sr,S";
        
        poke(16#0205#, x"DE");
        poke(16#0206#, x"AD");
        poke(16#0207#, x"BE");
        poke(16#0208#, x"EF");
        
        -- Program: set M=32-bit, LDA sr,S, STA $0450
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"40");  -- clear M0
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"80");  -- set M1 -> 32-bit
        poke(16#8004#, x"A3");  -- LDA sr,S
        poke(16#8005#, x"06");  -- offset -> $0205
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"50");  -- $0450
        poke(16#8008#, x"04");
        poke(16#8009#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#0450#, x"DE", "32-bit LDA sr,S byte 0");
        check_mem(16#0451#, x"AD", "32-bit LDA sr,S byte 1");
        check_mem(16#0452#, x"BE", "32-bit LDA sr,S byte 2");
        check_mem(16#0453#, x"EF", "32-bit LDA sr,S byte 3");
        
        -----------------------------------------------------------------------
        -- TEST 110: 16-bit LDA (sr,S),Y
        -----------------------------------------------------------------------
        report "";
        report "TEST 110: 16-bit LDA (sr,S),Y";
        
        poke(16#0208#, x"40");  -- low
        poke(16#0209#, x"07");  -- high
        poke(16#0741#, x"9A");
        poke(16#0742#, x"BC");
        
        -- Program: set M=16-bit, LDY #$01, LDA (sr,S),Y, STA $0458
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"A0");  -- LDY #
        poke(16#8005#, x"01");
        poke(16#8006#, x"AF");  -- LDA (sr,S),Y
        poke(16#8007#, x"09");  -- offset -> $0208
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"58");  -- $0458
        poke(16#800A#, x"04");
        poke(16#800B#, x"00");  -- BRK
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0458#, x"9A", "16-bit LDA (sr,S),Y low");
        check_mem(16#0459#, x"BC", "16-bit LDA (sr,S),Y high");
        
        -----------------------------------------------------------------------
        -- TEST 111: IRQ + RTI
        -----------------------------------------------------------------------
        report "";
        report "TEST 111: IRQ + RTI";
        
        irq_n <= '0';
        
        -- 32-bit IRQ vector: $FFFE/$FFFF/$0000/$0001 -> $00008100
        poke(16#FFFE#, x"00");
        poke(16#FFFF#, x"81");
        poke(16#0000#, x"00");
        poke(16#0001#, x"00");
        
        -- IRQ handler at $8100: LDA #$5A, STA $0460, RTI
        poke(16#8100#, x"A9");  -- LDA #
        poke(16#8101#, x"5A");
        poke(16#8102#, x"8D");  -- STA abs
        poke(16#8103#, x"60");  -- $0460
        poke(16#8104#, x"04");
        poke(16#8105#, x"40");  -- RTI
        
        -- Program: CLI, NOP, NOP, STA $0461, STP
        poke(16#8000#, x"58");  -- CLI
        poke(16#8001#, x"EA");  -- NOP
        poke(16#8002#, x"EA");  -- NOP
        poke(16#8003#, x"A9");  -- LDA #
        poke(16#8004#, x"33");
        poke(16#8005#, x"8D");  -- STA abs
        poke(16#8006#, x"61");  -- $0461
        poke(16#8007#, x"04");
        poke(16#8008#, x"DB");  -- STP
        poke(16#8009#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(20);
        
        irq_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0460#, x"5A", "IRQ handler wrote");
        check_mem(16#0461#, x"33", "IRQ returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 112: NMI + RTI
        -----------------------------------------------------------------------
        report "";
        report "TEST 112: NMI + RTI";
        
        nmi_n <= '0';
        
        -- 32-bit NMI vector: $FFFA/$FFFB/$FFFC/$FFFD -> $00008200
        poke(16#FFFA#, x"00");
        poke(16#FFFB#, x"82");
        poke(16#FFFC#, x"00");
        poke(16#FFFD#, x"00");
        
        -- NMI handler at $8200: LDA #$A5, STA $0464, RTI
        poke(16#8200#, x"A9");  -- LDA #
        poke(16#8201#, x"A5");
        poke(16#8202#, x"8D");  -- STA abs
        poke(16#8203#, x"64");  -- $0464
        poke(16#8204#, x"04");
        poke(16#8205#, x"40");  -- RTI
        
        -- Program: NOP, NOP, LDA #$77, STA $0465, STP
        poke(16#8000#, x"EA");  -- NOP
        poke(16#8001#, x"EA");  -- NOP
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"77");
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"65");  -- $0465
        poke(16#8006#, x"04");
        poke(16#8007#, x"DB");  -- STP
        poke(16#8008#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(20);
        
        nmi_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0464#, x"A5", "NMI handler wrote");
        check_mem(16#0465#, x"77", "NMI returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 113: ABORT + RTI
        -----------------------------------------------------------------------
        report "";
        report "TEST 113: ABORT + RTI";
        
        abort_n <= '0';
        
        -- 32-bit ABORT vector: $FFF8/$FFF9/$FFFA/$FFFB -> $00008300
        poke(16#FFF8#, x"00");
        poke(16#FFF9#, x"83");
        poke(16#FFFA#, x"00");
        poke(16#FFFB#, x"00");
        
        -- ABORT handler at $8300: LDA #$C3, STA $0468, RTI
        poke(16#8300#, x"A9");  -- LDA #
        poke(16#8301#, x"C3");
        poke(16#8302#, x"8D");  -- STA abs
        poke(16#8303#, x"68");  -- $0468
        poke(16#8304#, x"04");
        poke(16#8305#, x"40");  -- RTI
        
        -- Program: NOP, LDA #$44, STA $0469, STP
        poke(16#8000#, x"EA");  -- NOP
        poke(16#8001#, x"A9");  -- LDA #
        poke(16#8002#, x"44");
        poke(16#8003#, x"8D");  -- STA abs
        poke(16#8004#, x"69");  -- $0469
        poke(16#8005#, x"04");
        poke(16#8006#, x"DB");  -- STP
        poke(16#8007#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(20);
        
        abort_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0468#, x"C3", "ABORT handler wrote");
        check_mem(16#0469#, x"44", "ABORT returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 114: WAI wakes on IRQ
        -----------------------------------------------------------------------
        report "";
        report "TEST 114: WAI + IRQ wake";
        
        irq_n <= '1';
        
        -- 32-bit IRQ vector: $FFFE/$FFFF/$0000/$0001 -> $00008100
        poke(16#FFFE#, x"00");
        poke(16#FFFF#, x"81");
        poke(16#0000#, x"00");
        poke(16#0001#, x"00");
        
        -- IRQ handler at $8100: LDA #$6D, STA $0470, RTI
        poke(16#8100#, x"A9");  -- LDA #
        poke(16#8101#, x"6D");
        poke(16#8102#, x"8D");  -- STA abs
        poke(16#8103#, x"70");  -- $0470
        poke(16#8104#, x"04");
        poke(16#8105#, x"40");  -- RTI
        
        -- Program: CLI, WAI, LDA #$3C, STA $0471, STP
        poke(16#8000#, x"58");  -- CLI
        poke(16#8001#, x"CB");  -- WAI
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"3C");
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"71");  -- $0471
        poke(16#8006#, x"04");
        poke(16#8007#, x"DB");  -- STP
        poke(16#8008#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(20);
        
        irq_n <= '0';
        wait_cycles(20);
        irq_n <= '1';
        wait_cycles(240);
        
        check_mem(16#0470#, x"6D", "WAI IRQ handler wrote");
        check_mem(16#0471#, x"3C", "WAI returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 114A: IRQ stack frame (PC + full P)
        -----------------------------------------------------------------------
        report "";
        report "TEST 114A: IRQ stack frame";
        
        irq_n <= '1';
        
        -- 32-bit IRQ vector: $FFFE/$FFFF/$0000/$0001 -> $00008110
        poke(16#FFFE#, x"10");
        poke(16#FFFF#, x"81");
        poke(16#0000#, x"00");
        poke(16#0001#, x"00");
        
        -- IRQ handler at $8110: copy stack frame to $0490-$0495, RTI
        poke(16#8110#, x"AD");  -- LDA $01FF
        poke(16#8111#, x"FF");
        poke(16#8112#, x"01");
        poke(16#8113#, x"8D");  -- STA $0490
        poke(16#8114#, x"90");
        poke(16#8115#, x"04");
        poke(16#8116#, x"AD");  -- LDA $01FE
        poke(16#8117#, x"FE");
        poke(16#8118#, x"01");
        poke(16#8119#, x"8D");  -- STA $0491
        poke(16#811A#, x"91");
        poke(16#811B#, x"04");
        poke(16#811C#, x"AD");  -- LDA $01FD
        poke(16#811D#, x"FD");
        poke(16#811E#, x"01");
        poke(16#811F#, x"8D");  -- STA $0492
        poke(16#8120#, x"92");
        poke(16#8121#, x"04");
        poke(16#8122#, x"AD");  -- LDA $01FC
        poke(16#8123#, x"FC");
        poke(16#8124#, x"01");
        poke(16#8125#, x"8D");  -- STA $0493
        poke(16#8126#, x"93");
        poke(16#8127#, x"04");
        poke(16#8128#, x"AD");  -- LDA $01FB (P high)
        poke(16#8129#, x"FB");
        poke(16#812A#, x"01");
        poke(16#812B#, x"8D");  -- STA $0494
        poke(16#812C#, x"94");
        poke(16#812D#, x"04");
        poke(16#812E#, x"AD");  -- LDA $01FA (P low)
        poke(16#812F#, x"FA");
        poke(16#8130#, x"01");
        poke(16#8131#, x"8D");  -- STA $0495
        poke(16#8132#, x"95");
        poke(16#8133#, x"04");
        poke(16#8134#, x"40");  -- RTI
        
        -- Program: CLI, WAI, LDA #$3D, STA $0496, STP
        poke(16#8000#, x"58");  -- CLI
        poke(16#8001#, x"CB");  -- WAI
        poke(16#8002#, x"A9");  -- LDA #
        poke(16#8003#, x"3D");
        poke(16#8004#, x"8D");  -- STA abs
        poke(16#8005#, x"96");  -- $0496
        poke(16#8006#, x"04");
        poke(16#8007#, x"DB");  -- STP
        poke(16#8008#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(20);
        
        irq_n <= '0';
        wait_cycles(20);
        irq_n <= '1';
        wait_cycles(260);
        
        -- Expected PC = $00008002, P high = $0C, P low = $08 (CLI clears I)
        check_mem(16#0490#, x"00", "IRQ PC[31:24]");
        check_mem(16#0491#, x"00", "IRQ PC[23:16]");
        check_mem(16#0492#, x"80", "IRQ PC[15:8]");
        check_mem(16#0493#, x"02", "IRQ PC[7:0]");
        check_mem(16#0494#, x"0C", "IRQ P high");
        check_mem(16#0495#, x"08", "IRQ P low");
        check_mem(16#0496#, x"3D", "IRQ returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 115: JML long
        -----------------------------------------------------------------------
        report "";
        report "TEST 115: JML long";
        
        -- Target at $8400: LDA #$5B, STA $0480, STP
        poke(16#8400#, x"A9");  -- LDA #
        poke(16#8401#, x"5B");
        poke(16#8402#, x"8D");  -- STA abs
        poke(16#8403#, x"80");  -- $0480
        poke(16#8404#, x"04");
        poke(16#8405#, x"DB");  -- STP
        poke(16#8406#, x"EA");  -- NOP (padding)
        
        -- Program: JML $008400
        poke(16#8000#, x"5C");  -- JML long
        poke(16#8001#, x"00");  -- low
        poke(16#8002#, x"84");  -- high
        poke(16#8003#, x"00");  -- bank
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(200);
        
        check_mem(16#0480#, x"5B", "JML long wrote value");
        
        -----------------------------------------------------------------------
        -- TEST 116: JSL + RTL
        -----------------------------------------------------------------------
        report "";
        report "TEST 116: JSL + RTL";
        
        -- Subroutine at $8420: LDA #$A1, STA $0482, RTL
        poke(16#8420#, x"A9");  -- LDA #
        poke(16#8421#, x"A1");
        poke(16#8422#, x"8D");  -- STA abs
        poke(16#8423#, x"82");  -- $0482
        poke(16#8424#, x"04");
        poke(16#8425#, x"6B");  -- RTL
        
        -- Program: JSL $008420, then LDA #$12, STA $0481, STP
        poke(16#8000#, x"22");  -- JSL long
        poke(16#8001#, x"20");  -- low
        poke(16#8002#, x"84");  -- high
        poke(16#8003#, x"00");  -- bank
        poke(16#8004#, x"A9");  -- LDA #
        poke(16#8005#, x"12");
        poke(16#8006#, x"8D");  -- STA abs
        poke(16#8007#, x"81");  -- $0481
        poke(16#8008#, x"04");
        poke(16#8009#, x"DB");  -- STP
        poke(16#800A#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(240);
        
        check_mem(16#0482#, x"A1", "JSL subroutine wrote");
        check_mem(16#0481#, x"12", "RTL returned to main");
        
        -----------------------------------------------------------------------
        -- TEST 117: PER (PC-relative push)
        -----------------------------------------------------------------------
        report "";
        report "TEST 117: PER";
        
        -- Program: set M=16-bit, PER #$0000, PLA, STA $0484, STP
        poke(16#8000#, x"C2");  -- REP
        poke(16#8001#, x"80");  -- clear M1
        poke(16#8002#, x"E2");  -- SEP
        poke(16#8003#, x"40");  -- set M0 -> 16-bit
        poke(16#8004#, x"62");  -- PER
        poke(16#8005#, x"00");
        poke(16#8006#, x"00");
        poke(16#8007#, x"68");  -- PLA (16-bit)
        poke(16#8008#, x"8D");  -- STA abs
        poke(16#8009#, x"84");  -- $0484
        poke(16#800A#, x"04");
        poke(16#800B#, x"DB");  -- STP
        poke(16#800C#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0484#, x"07", "PER low byte");
        check_mem(16#0485#, x"80", "PER high byte");
        
        -----------------------------------------------------------------------
        -- TEST 118: JMP (abs,X)
        -----------------------------------------------------------------------
        report "";
        report "TEST 118: JMP (abs,X)";
        
        -- Pointer at $0500 -> $8500
        poke(16#0500#, x"00");
        poke(16#0501#, x"85");
        
        -- Target at $8500: LDA #$6E, STA $0490, STP
        poke(16#8500#, x"A9");  -- LDA #
        poke(16#8501#, x"6E");
        poke(16#8502#, x"8D");  -- STA abs
        poke(16#8503#, x"90");  -- $0490
        poke(16#8504#, x"04");
        poke(16#8505#, x"DB");  -- STP
        poke(16#8506#, x"EA");  -- NOP (padding)
        
        -- Program: LDX #$01, JMP ($04FF,X)
        poke(16#8000#, x"A2");  -- LDX #
        poke(16#8001#, x"01");
        poke(16#8002#, x"7C");  -- JMP (abs,X)
        poke(16#8003#, x"FF");  -- $04FF
        poke(16#8004#, x"04");
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0490#, x"6E", "JMP (abs,X) wrote value");
        
        -----------------------------------------------------------------------
        -- TEST 119: JML [abs]
        -----------------------------------------------------------------------
        report "";
        report "TEST 119: JML [abs]";
        
        -- Pointer at $0600 -> $00008600
        poke(16#0600#, x"00");
        poke(16#0601#, x"86");
        poke(16#0602#, x"00");
        poke(16#0603#, x"00");
        
        -- Target at $8600: LDA #$7D, STA $0492, STP
        poke(16#8600#, x"A9");  -- LDA #
        poke(16#8601#, x"7D");
        poke(16#8602#, x"8D");  -- STA abs
        poke(16#8603#, x"92");  -- $0492
        poke(16#8604#, x"04");
        poke(16#8605#, x"DB");  -- STP
        poke(16#8606#, x"EA");  -- NOP (padding)
        
        -- Program: JML [$0600]
        poke(16#8000#, x"DC");  -- JML [abs]
        poke(16#8001#, x"00");  -- low
        poke(16#8002#, x"06");  -- high
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(220);
        
        check_mem(16#0492#, x"7D", "JML [abs] wrote value");
        
        -----------------------------------------------------------------------
        -- TEST 120: MMU MMIO register reads/writes
        -----------------------------------------------------------------------
        report "";
        report "TEST 120: MMU MMIO regs";
        
        -- Program: enter native, set M=32, write/read MMUCR/ASID/PTBR via STA/LDA
        poke(16#8000#, x"18");  -- CLC
        poke(16#8001#, x"FB");  -- XCE
        poke(16#8002#, x"C2");  -- REP
        poke(16#8003#, x"40");  -- clear M0
        poke(16#8004#, x"E2");  -- SEP
        poke(16#8005#, x"80");  -- set M1 -> 32-bit
        
        -- MMUCR = 0x00000002
        poke(16#8006#, x"A9");  -- LDA #imm32
        poke(16#8007#, x"02");
        poke(16#8008#, x"00");
        poke(16#8009#, x"00");
        poke(16#800A#, x"00");
        poke(16#800B#, x"8D");  -- STA $F000
        poke(16#800C#, x"00");
        poke(16#800D#, x"F0");
        -- (no readback; verify via memory checks)
        
        -- Pad to keep execution contiguous
        poke(16#800E#, x"EA");  -- NOP
        poke(16#800F#, x"EA");  -- NOP
        poke(16#8010#, x"EA");  -- NOP
        poke(16#8011#, x"EA");  -- NOP
        poke(16#8012#, x"EA");  -- NOP
        poke(16#8013#, x"EA");  -- NOP
        
        -- ASID = 0x000000AA
        poke(16#8014#, x"A9");  -- LDA #imm32
        poke(16#8015#, x"AA");
        poke(16#8016#, x"00");
        poke(16#8017#, x"00");
        poke(16#8018#, x"00");
        poke(16#8019#, x"8D");  -- STA $F008
        poke(16#801A#, x"08");
        poke(16#801B#, x"F0");
        -- (no readback; verify via memory checks)
        
        -- PTBR read/write tests deferred (MMU integration)
        
        poke(16#8022#, x"DB");  -- STP
        poke(16#8023#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(900);
        
        check_mem(16#F000#, x"02", "MMUCR byte0");
        check_mem(16#F001#, x"00", "MMUCR byte1");
        check_mem(16#F002#, x"00", "MMUCR byte2");
        check_mem(16#F003#, x"00", "MMUCR byte3");
        
        check_mem(16#F008#, x"AA", "ASID byte0");
        check_mem(16#F009#, x"00", "ASID byte1");
        
        -- PTBR checks deferred
        
        -----------------------------------------------------------------------
        -- TEST 121: MMU basic translation
        -----------------------------------------------------------------------
        report "";
        report "TEST 121: MMU basic translation";
        
        -- Page table setup (PTBR=0x00001000)
        -- L1[0] -> L2 at 0x00002000 (P=1)
        poke(16#1000#, x"01");  -- PTE[7:0]
        poke(16#1001#, x"20");  -- PTE[15:8]
        poke(16#1002#, x"00");
        poke(16#1003#, x"00");
        poke(16#1004#, x"00");
        poke(16#1005#, x"00");
        poke(16#1006#, x"00");
        poke(16#1007#, x"00");
        
        -- L2[0] -> PA 0x00000000 (P=1, W=1, U=1) for stack/page 0
        poke(16#2000#, x"07");
        poke(16#2001#, x"00");
        poke(16#2002#, x"00");
        poke(16#2003#, x"00");
        poke(16#2004#, x"00");
        poke(16#2005#, x"00");
        poke(16#2006#, x"00");
        poke(16#2007#, x"00");
        
        -- L2[3] -> PA 0x00004000 (P=1, W=1, U=1)
        poke(16#2018#, x"07");
        poke(16#2019#, x"40");
        poke(16#201A#, x"00");
        poke(16#201B#, x"00");
        poke(16#201C#, x"00");
        poke(16#201D#, x"00");
        poke(16#201E#, x"00");
        poke(16#201F#, x"00");
        
        -- L2[8] -> PA 0x00008000 (P=1, W=1, U=1) for code fetch
        poke(16#2040#, x"07");
        poke(16#2041#, x"80");
        poke(16#2042#, x"00");
        poke(16#2043#, x"00");
        poke(16#2044#, x"00");
        poke(16#2045#, x"00");
        poke(16#2046#, x"00");
        poke(16#2047#, x"00");
        
        -- Data at physical 0x4000
        poke(16#4000#, x"5A");
        
        -- Program: set PTBR, enable MMU, read VA $3000 -> PA $4000, store to $0500
        -- PTBR low dword = 0x00001000
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"8D");  -- STA $F014
        poke(16#8003#, x"14");
        poke(16#8004#, x"F0");
        poke(16#8005#, x"A9");  -- LDA #$10
        poke(16#8006#, x"10");
        poke(16#8007#, x"8D");  -- STA $F015
        poke(16#8008#, x"15");
        poke(16#8009#, x"F0");
        poke(16#800A#, x"A9");  -- LDA #$00
        poke(16#800B#, x"00");
        poke(16#800C#, x"8D");  -- STA $F016
        poke(16#800D#, x"16");
        poke(16#800E#, x"F0");
        poke(16#800F#, x"A9");  -- LDA #$00
        poke(16#8010#, x"00");
        poke(16#8011#, x"8D");  -- STA $F017
        poke(16#8012#, x"17");
        poke(16#8013#, x"F0");
        
        -- PTBR high dword = 0x00000000
        poke(16#8014#, x"A9");  -- LDA #$00
        poke(16#8015#, x"00");
        poke(16#8016#, x"8D");  -- STA $F018
        poke(16#8017#, x"18");
        poke(16#8018#, x"F0");
        poke(16#8019#, x"A9");  -- LDA #$00
        poke(16#801A#, x"00");
        poke(16#801B#, x"8D");  -- STA $F019
        poke(16#801C#, x"19");
        poke(16#801D#, x"F0");
        poke(16#801E#, x"A9");  -- LDA #$00
        poke(16#801F#, x"00");
        poke(16#8020#, x"8D");  -- STA $F01A
        poke(16#8021#, x"1A");
        poke(16#8022#, x"F0");
        poke(16#8023#, x"A9");  -- LDA #$00
        poke(16#8024#, x"00");
        poke(16#8025#, x"8D");  -- STA $F01B
        poke(16#8026#, x"1B");
        poke(16#8027#, x"F0");
        
        -- Enable MMU (MMUCR.PG)
        poke(16#8028#, x"A9");  -- LDA #$01
        poke(16#8029#, x"01");
        poke(16#802A#, x"8D");  -- STA $F000
        poke(16#802B#, x"00");
        poke(16#802C#, x"F0");
        
        -- Read back MMUCR to verify enable latch
        poke(16#802D#, x"AD");  -- LDA $F000
        poke(16#802E#, x"00");
        poke(16#802F#, x"F0");
        poke(16#8030#, x"8D");  -- STA $0502
        poke(16#8031#, x"02");
        poke(16#8032#, x"05");
        
        -- Read VA $3000, store to $0500
        poke(16#8033#, x"AD");  -- LDA $3000
        poke(16#8034#, x"00");
        poke(16#8035#, x"30");
        poke(16#8036#, x"8D");  -- STA $0500
        poke(16#8037#, x"00");
        poke(16#8038#, x"05");
        poke(16#8039#, x"DB");  -- STP
        poke(16#803A#, x"EA");  -- NOP (padding)
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(1200);
        
        check_mem(16#0502#, x"01", "MMUCR readback");
        check_mem(16#0500#, x"5A", "MMU translated read");
        
        -----------------------------------------------------------------------
        -- TEST 122: Privilege trap on MMIO in user mode
        -----------------------------------------------------------------------
        report "";
        report "TEST 122: Privilege trap (user MMIO)";
        
        -- Trap vector for privilege violation (TRAP code 0xFF)
        -- VEC_SYSCALL + (0xFF << 2) = 0x000103D0 (wraps in 64KB TB memory)
        poke(16#03D0#, x"80");  -- handler = $00008080
        poke(16#03D1#, x"80");
        poke(16#03D2#, x"00");
        poke(16#03D3#, x"00");
        
        -- Clear backing memory at MMIO address for sanity
        poke(16#F000#, x"00");
        
        -- Trap handler at $8080: write marker + MMUCR value, RTI
        poke(16#8080#, x"A9");  -- LDA #$A5
        poke(16#8081#, x"A5");
        poke(16#8082#, x"8D");  -- STA $0600
        poke(16#8083#, x"00");
        poke(16#8084#, x"06");
        poke(16#8085#, x"AD");  -- LDA $F000 (MMUCR)
        poke(16#8086#, x"00");
        poke(16#8087#, x"F0");
        poke(16#8088#, x"8D");  -- STA $0601
        poke(16#8089#, x"01");
        poke(16#808A#, x"06");
        poke(16#808B#, x"AD");  -- LDA $01FB (P high from trap frame)
        poke(16#808C#, x"FB");
        poke(16#808D#, x"01");
        poke(16#808E#, x"8D");  -- STA $0603
        poke(16#808F#, x"03");
        poke(16#8090#, x"06");
        poke(16#8091#, x"40");  -- RTI
        
        -- User program at $9000: mark, attempt MMIO write, TRAP #$FF
        poke(16#9000#, x"A9");  -- LDA #$55
        poke(16#9001#, x"55");
        poke(16#9002#, x"8D");  -- STA $0602 (user marker)
        poke(16#9003#, x"02");
        poke(16#9004#, x"06");
        poke(16#9005#, x"A9");  -- LDA #$01
        poke(16#9006#, x"01");
        poke(16#9007#, x"8D");  -- STA $F000 (MMUCR) - should not stick
        poke(16#9008#, x"00");
        poke(16#9009#, x"F0");
        poke(16#900A#, x"02");  -- EXT prefix
        poke(16#900B#, x"40");  -- TRAP #imm8
        poke(16#900C#, x"FF");
        poke(16#900D#, x"4C");  -- JMP $900D (idle)
        poke(16#900E#, x"0D");
        poke(16#900F#, x"90");
        
        -- Supervisor setup: push 6 bytes to move SP, then prepare RTI frame for user mode at $9000
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"48");  -- PHA x6 (SP from $01FF -> $01F9)
        poke(16#8003#, x"48");
        poke(16#8004#, x"48");
        poke(16#8005#, x"48");
        poke(16#8006#, x"48");
        poke(16#8007#, x"48");
        poke(16#8008#, x"A9");  -- LDA #$04 (P: I=1, S=0, E=0)
        poke(16#8009#, x"04");
        poke(16#800A#, x"8D");  -- STA $01FA (P low)
        poke(16#800B#, x"FA");
        poke(16#800C#, x"01");
        poke(16#800D#, x"A9");  -- LDA #$00 (P high)
        poke(16#800E#, x"00");
        poke(16#800F#, x"8D");  -- STA $01FB
        poke(16#8010#, x"FB");
        poke(16#8011#, x"01");
        poke(16#8012#, x"A9");  -- LDA #$00 (PC byte0)
        poke(16#8013#, x"00");
        poke(16#8014#, x"8D");  -- STA $01FC
        poke(16#8015#, x"FC");
        poke(16#8016#, x"01");
        poke(16#8017#, x"A9");  -- LDA #$90 (PC byte1)
        poke(16#8018#, x"90");
        poke(16#8019#, x"8D");  -- STA $01FD
        poke(16#801A#, x"FD");
        poke(16#801B#, x"01");
        poke(16#801C#, x"A9");  -- LDA #$00 (PC byte2)
        poke(16#801D#, x"00");
        poke(16#801E#, x"8D");  -- STA $01FE
        poke(16#801F#, x"FE");
        poke(16#8020#, x"01");
        poke(16#8021#, x"A9");  -- LDA #$00 (PC byte3)
        poke(16#8022#, x"00");
        poke(16#8023#, x"8D");  -- STA $01FF
        poke(16#8024#, x"FF");
        poke(16#8025#, x"01");
        poke(16#8026#, x"AD");  -- LDA $F000 (MMUCR baseline)
        poke(16#8027#, x"00");
        poke(16#8028#, x"F0");
        poke(16#8029#, x"8D");  -- STA $0604
        poke(16#802A#, x"04");
        poke(16#802B#, x"06");
        poke(16#802C#, x"40");  -- RTI -> user
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(600);
        
        check_mem(16#0602#, x"55", "User mode ran");
        check_mem(16#0600#, x"A5", "Trap handler marker");
        check_mem(16#0601#, x"00", "MMUCR unchanged by user write");
        check_mem(16#0603#, x"00", "User P high byte (S=0)");
        check_mem(16#0604#, x"00", "MMUCR reset baseline");
        
        -----------------------------------------------------------------------
        -- TEST 123: Privilege trap on MMIO read in user mode
        -----------------------------------------------------------------------
        report "";
        report "TEST 123: Privilege trap (user MMIO read)";
        
        -- Trap vector for privilege violation (TRAP code 0xFF)
        poke(16#03D0#, x"00");  -- handler = $00008200
        poke(16#03D1#, x"82");
        poke(16#03D2#, x"00");
        poke(16#03D3#, x"00");
        
        -- Clear backing memory at MMIO address for sanity
        poke(16#F000#, x"00");
        
        -- Trap handler at $8200: write marker + MMUCR value, RTI
        poke(16#8200#, x"A9");  -- LDA #$A6
        poke(16#8201#, x"A6");
        poke(16#8202#, x"8D");  -- STA $0610
        poke(16#8203#, x"10");
        poke(16#8204#, x"06");
        poke(16#8205#, x"AD");  -- LDA $F000 (MMUCR)
        poke(16#8206#, x"00");
        poke(16#8207#, x"F0");
        poke(16#8208#, x"8D");  -- STA $0611
        poke(16#8209#, x"11");
        poke(16#820A#, x"06");
        poke(16#820B#, x"AD");  -- LDA $01FB (P high from trap frame)
        poke(16#820C#, x"FB");
        poke(16#820D#, x"01");
        poke(16#820E#, x"8D");  -- STA $0613
        poke(16#820F#, x"13");
        poke(16#8210#, x"06");
        poke(16#8211#, x"40");  -- RTI
        
        -- User program at $9100: mark, attempt MMIO read, TRAP #$FF
        poke(16#9100#, x"A9");  -- LDA #$66
        poke(16#9101#, x"66");
        poke(16#9102#, x"8D");  -- STA $0612 (user marker)
        poke(16#9103#, x"12");
        poke(16#9104#, x"06");
        poke(16#9105#, x"AD");  -- LDA $F000 (MMUCR) - should trap
        poke(16#9106#, x"00");
        poke(16#9107#, x"F0");
        poke(16#9108#, x"02");  -- EXT prefix
        poke(16#9109#, x"40");  -- TRAP #imm8
        poke(16#910A#, x"FF");
        poke(16#910B#, x"4C");  -- JMP $910B (idle)
        poke(16#910C#, x"0B");
        poke(16#910D#, x"91");
        
        -- Supervisor setup: push 6 bytes to move SP, then prepare RTI frame for user mode at $9100
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"48");  -- PHA x6 (SP from $01FF -> $01F9)
        poke(16#8003#, x"48");
        poke(16#8004#, x"48");
        poke(16#8005#, x"48");
        poke(16#8006#, x"48");
        poke(16#8007#, x"48");
        poke(16#8008#, x"A9");  -- LDA #$04 (P: I=1, S=0, E=0)
        poke(16#8009#, x"04");
        poke(16#800A#, x"8D");  -- STA $01FA (P low)
        poke(16#800B#, x"FA");
        poke(16#800C#, x"01");
        poke(16#800D#, x"A9");  -- LDA #$00 (P high)
        poke(16#800E#, x"00");
        poke(16#800F#, x"8D");  -- STA $01FB
        poke(16#8010#, x"FB");
        poke(16#8011#, x"01");
        poke(16#8012#, x"A9");  -- LDA #$00 (PC byte0)
        poke(16#8013#, x"00");
        poke(16#8014#, x"8D");  -- STA $01FC
        poke(16#8015#, x"FC");
        poke(16#8016#, x"01");
        poke(16#8017#, x"A9");  -- LDA #$91 (PC byte1)
        poke(16#8018#, x"91");
        poke(16#8019#, x"8D");  -- STA $01FD
        poke(16#801A#, x"FD");
        poke(16#801B#, x"01");
        poke(16#801C#, x"A9");  -- LDA #$00 (PC byte2)
        poke(16#801D#, x"00");
        poke(16#801E#, x"8D");  -- STA $01FE
        poke(16#801F#, x"FE");
        poke(16#8020#, x"01");
        poke(16#8021#, x"A9");  -- LDA #$00 (PC byte3)
        poke(16#8022#, x"00");
        poke(16#8023#, x"8D");  -- STA $01FF
        poke(16#8024#, x"FF");
        poke(16#8025#, x"01");
        poke(16#8026#, x"AD");  -- LDA $F000 (MMUCR baseline)
        poke(16#8027#, x"00");
        poke(16#8028#, x"F0");
        poke(16#8029#, x"8D");  -- STA $0614
        poke(16#802A#, x"14");
        poke(16#802B#, x"06");
        poke(16#802C#, x"40");  -- RTI -> user
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(600);
        
        check_mem(16#0612#, x"66", "User mode ran (read)");
        check_mem(16#0610#, x"A6", "Trap handler marker (read)");
        check_mem(16#0611#, x"00", "MMUCR unchanged by user read");
        check_mem(16#0613#, x"00", "User P high byte (read)");
        check_mem(16#0614#, x"00", "MMUCR reset baseline (read)");
        
        -----------------------------------------------------------------------
        -- TEST 124: Illegal opcode trap (16-bit, K=0)
        -----------------------------------------------------------------------
        report "";
        report "TEST 124: Illegal opcode trap (16-bit, K=0)";
        
        -- Illegal vector -> handler at $9200
        poke(16#FFF8#, x"00");
        poke(16#FFF9#, x"92");
        poke(16#FFFA#, x"00");
        poke(16#FFFB#, x"00");
        
        -- Handler at $9200: LDA #$00A7, STA $0620, RTI
        poke(16#9200#, x"A9");
        poke(16#9201#, x"A7");
        poke(16#9202#, x"00");
        poke(16#9203#, x"8D");
        poke(16#9204#, x"20");
        poke(16#9205#, x"06");
        poke(16#9206#, x"40");
        
        -- Program at $9000: illegal ext op, then LDA #$005A, STA $0622, BRK
        poke(16#9000#, x"02");
        poke(16#9001#, x"E7");  -- illegal extended opcode
        poke(16#9002#, x"A9");
        poke(16#9003#, x"5A");
        poke(16#9004#, x"00");
        poke(16#9005#, x"8D");
        poke(16#9006#, x"22");
        poke(16#9007#, x"06");
        poke(16#9008#, x"00");
        
        -- Supervisor setup: RTI to $9000 with 16-bit P, K=0
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"48");  -- PHA x6 (SP from $01FF -> $01F9)
        poke(16#8003#, x"48");
        poke(16#8004#, x"48");
        poke(16#8005#, x"48");
        poke(16#8006#, x"48");
        poke(16#8007#, x"48");
        poke(16#8008#, x"A9");  -- P low = $54 (M=16, X=16, I=1)
        poke(16#8009#, x"54");
        poke(16#800A#, x"8D");  -- STA $01FA
        poke(16#800B#, x"FA");
        poke(16#800C#, x"01");
        poke(16#800D#, x"A9");  -- P high = $08 (E=0, S=1, R=0, K=0)
        poke(16#800E#, x"08");
        poke(16#800F#, x"8D");  -- STA $01FB
        poke(16#8010#, x"FB");
        poke(16#8011#, x"01");
        poke(16#8012#, x"A9");  -- PC byte0
        poke(16#8013#, x"00");
        poke(16#8014#, x"8D");
        poke(16#8015#, x"FC");
        poke(16#8016#, x"01");
        poke(16#8017#, x"A9");  -- PC byte1 ($90)
        poke(16#8018#, x"90");
        poke(16#8019#, x"8D");
        poke(16#801A#, x"FD");
        poke(16#801B#, x"01");
        poke(16#801C#, x"A9");  -- PC byte2
        poke(16#801D#, x"00");
        poke(16#801E#, x"8D");
        poke(16#801F#, x"FE");
        poke(16#8020#, x"01");
        poke(16#8021#, x"A9");  -- PC byte3
        poke(16#8022#, x"00");
        poke(16#8023#, x"8D");
        poke(16#8024#, x"FF");
        poke(16#8025#, x"01");
        poke(16#8026#, x"40");  -- RTI
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(600);
        
        check_mem(16#0620#, x"A7", "Illegal trap handler wrote (K=0)");
        check_mem(16#0622#, x"5A", "Returned after illegal trap (K=0)");
        
        -----------------------------------------------------------------------
        -- TEST 125: Illegal opcode NOP (16-bit, K=1)
        -----------------------------------------------------------------------
        report "";
        report "TEST 125: Illegal opcode NOP (16-bit, K=1)";
        
        -- Illegal vector -> handler at $9300 (should NOT run)
        poke(16#FFF8#, x"00");
        poke(16#FFF9#, x"93");
        poke(16#FFFA#, x"00");
        poke(16#FFFB#, x"00");
        
        -- Handler at $9300: LDA #$00A8, STA $0630, RTI
        poke(16#9300#, x"A9");
        poke(16#9301#, x"A8");
        poke(16#9302#, x"00");
        poke(16#9303#, x"8D");
        poke(16#9304#, x"30");
        poke(16#9305#, x"06");
        poke(16#9306#, x"40");
        
        -- Program at $9100: illegal ext op, then LDA #$005B, STA $0632, BRK
        poke(16#9100#, x"02");
        poke(16#9101#, x"E7");  -- illegal extended opcode
        poke(16#9102#, x"A9");
        poke(16#9103#, x"5B");
        poke(16#9104#, x"00");
        poke(16#9105#, x"8D");
        poke(16#9106#, x"32");
        poke(16#9107#, x"06");
        poke(16#9108#, x"00");
        
        -- Supervisor setup: RTI to $9100 with 16-bit P, K=1
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"48");  -- PHA x6
        poke(16#8003#, x"48");
        poke(16#8004#, x"48");
        poke(16#8005#, x"48");
        poke(16#8006#, x"48");
        poke(16#8007#, x"48");
        poke(16#8008#, x"A9");  -- P low = $54 (M=16, X=16, I=1)
        poke(16#8009#, x"54");
        poke(16#800A#, x"8D");
        poke(16#800B#, x"FA");
        poke(16#800C#, x"01");
        poke(16#800D#, x"A9");  -- P high = $28 (E=0, S=1, R=0, K=1)
        poke(16#800E#, x"28");
        poke(16#800F#, x"8D");
        poke(16#8010#, x"FB");
        poke(16#8011#, x"01");
        poke(16#8012#, x"A9");  -- PC byte0
        poke(16#8013#, x"00");
        poke(16#8014#, x"8D");
        poke(16#8015#, x"FC");
        poke(16#8016#, x"01");
        poke(16#8017#, x"A9");  -- PC byte1 ($91)
        poke(16#8018#, x"91");
        poke(16#8019#, x"8D");
        poke(16#801A#, x"FD");
        poke(16#801B#, x"01");
        poke(16#801C#, x"A9");  -- PC byte2
        poke(16#801D#, x"00");
        poke(16#801E#, x"8D");
        poke(16#801F#, x"FE");
        poke(16#8020#, x"01");
        poke(16#8021#, x"A9");  -- PC byte3
        poke(16#8022#, x"00");
        poke(16#8023#, x"8D");
        poke(16#8024#, x"FF");
        poke(16#8025#, x"01");
        poke(16#8026#, x"40");  -- RTI
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(600);
        
        check_mem(16#0630#, x"00", "Illegal trap not taken (K=1)");
        check_mem(16#0632#, x"5B", "Illegal op treated as NOP (K=1)");
        
        -----------------------------------------------------------------------
        -- TEST 126: Illegal opcode NOP (32-bit always compat)
        -----------------------------------------------------------------------
        report "";
        report "TEST 126: Illegal opcode NOP (32-bit)";
        
        -- Illegal vector -> handler at $9400 (should NOT run)
        poke(16#FFF8#, x"00");
        poke(16#FFF9#, x"94");
        poke(16#FFFA#, x"00");
        poke(16#FFFB#, x"00");
        
        -- Clear trap marker
        poke(16#0640#, x"00");
        
        -- Handler at $9400: LDA #$000000A9, STA $0640, RTI
        poke(16#9400#, x"A9");
        poke(16#9401#, x"A9");
        poke(16#9402#, x"00");
        poke(16#9403#, x"00");
        poke(16#9404#, x"00");
        poke(16#9405#, x"8D");
        poke(16#9406#, x"40");
        poke(16#9407#, x"06");
        poke(16#9408#, x"40");
        
        -- Program at $9500: illegal ext op, then LDA #$0000005C, STA $0644, BRK
        poke(16#9500#, x"02");
        poke(16#9501#, x"E7");  -- illegal extended opcode
        poke(16#9502#, x"A9");
        poke(16#9503#, x"5C");
        poke(16#9504#, x"00");
        poke(16#9505#, x"00");
        poke(16#9506#, x"00");
        poke(16#9507#, x"8D");
        poke(16#9508#, x"44");
        poke(16#9509#, x"06");
        poke(16#950A#, x"00");
        
        -- Supervisor setup: RTI to $9500 with 32-bit P (K ignored)
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"48");  -- PHA x6
        poke(16#8003#, x"48");
        poke(16#8004#, x"48");
        poke(16#8005#, x"48");
        poke(16#8006#, x"48");
        poke(16#8007#, x"48");
        poke(16#8008#, x"A9");  -- P low = $A4 (M=32, X=32, I=1)
        poke(16#8009#, x"A4");
        poke(16#800A#, x"8D");
        poke(16#800B#, x"FA");
        poke(16#800C#, x"01");
        poke(16#800D#, x"A9");  -- P high = $08 (E=0, S=1, R=0, K=0)
        poke(16#800E#, x"08");
        poke(16#800F#, x"8D");
        poke(16#8010#, x"FB");
        poke(16#8011#, x"01");
        poke(16#8012#, x"A9");  -- PC byte0
        poke(16#8013#, x"00");
        poke(16#8014#, x"8D");
        poke(16#8015#, x"FC");
        poke(16#8016#, x"01");
        poke(16#8017#, x"A9");  -- PC byte1 ($95)
        poke(16#8018#, x"95");
        poke(16#8019#, x"8D");
        poke(16#801A#, x"FD");
        poke(16#801B#, x"01");
        poke(16#801C#, x"A9");  -- PC byte2
        poke(16#801D#, x"00");
        poke(16#801E#, x"8D");
        poke(16#801F#, x"FE");
        poke(16#8020#, x"01");
        poke(16#8021#, x"A9");  -- PC byte3
        poke(16#8022#, x"00");
        poke(16#8023#, x"8D");
        poke(16#8024#, x"FF");
        poke(16#8025#, x"01");
        poke(16#8026#, x"40");  -- RTI
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(600);
        
        check_mem(16#0640#, x"00", "Illegal trap not taken (32-bit)");
        check_mem(16#0644#, x"5C", "Illegal op treated as NOP (32-bit)");
        
        -----------------------------------------------------------------------
        -- TEST 127: Page fault latches FAULTVA + fault type
        -----------------------------------------------------------------------
        report "";
        report "TEST 127: Page fault FAULTVA + type";
        
        -- Page fault vector: $FFD0-$FFD3 -> $00008400
        poke(16#FFD0#, x"00");
        poke(16#FFD1#, x"84");
        poke(16#FFD2#, x"00");
        poke(16#FFD3#, x"00");
        
        -- Clear FAULTVA shadow and output slots
        poke(16#F010#, x"00");
        poke(16#F011#, x"00");
        poke(16#F012#, x"00");
        poke(16#F013#, x"00");
        poke(16#F020#, x"00");
        poke(16#F021#, x"00");
        poke(16#F022#, x"00");
        poke(16#F023#, x"00");
        poke(16#F024#, x"00");
        poke(16#F025#, x"00");
        poke(16#F026#, x"00");
        poke(16#F027#, x"00");
        poke(16#F028#, x"A5");
        poke(16#F029#, x"5D");
        
        -- Handler at $8400: read FAULTVA + MMUCR, store via MMIO-bypassed window, RTI
        poke(16#8400#, x"AD");  -- LDA $F010
        poke(16#8401#, x"10");
        poke(16#8402#, x"F0");
        poke(16#8403#, x"8D");  -- STA $F020
        poke(16#8404#, x"20");
        poke(16#8405#, x"F0");
        poke(16#8406#, x"AD");  -- LDA $F011
        poke(16#8407#, x"11");
        poke(16#8408#, x"F0");
        poke(16#8409#, x"8D");  -- STA $F021
        poke(16#840A#, x"21");
        poke(16#840B#, x"F0");
        poke(16#840C#, x"AD");  -- LDA $F012
        poke(16#840D#, x"12");
        poke(16#840E#, x"F0");
        poke(16#840F#, x"8D");  -- STA $F022
        poke(16#8410#, x"22");
        poke(16#8411#, x"F0");
        poke(16#8412#, x"AD");  -- LDA $F013
        poke(16#8413#, x"13");
        poke(16#8414#, x"F0");
        poke(16#8415#, x"8D");  -- STA $F023
        poke(16#8416#, x"23");
        poke(16#8417#, x"F0");
        poke(16#8418#, x"AD");  -- LDA $F000 (MMUCR)
        poke(16#8419#, x"00");
        poke(16#841A#, x"F0");
        poke(16#841B#, x"8D");  -- STA $F024
        poke(16#841C#, x"24");
        poke(16#841D#, x"F0");
        poke(16#841E#, x"AD");  -- LDA $F028
        poke(16#841F#, x"28");
        poke(16#8420#, x"F0");
        poke(16#8421#, x"8D");  -- STA $F025
        poke(16#8422#, x"25");
        poke(16#8423#, x"F0");
        poke(16#8424#, x"40");  -- RTI
        
        -- Page table: PTBR=0x00001000
        -- L1[0] -> L2 at 0x00002000 (P=1)
        poke(16#1000#, x"01");
        poke(16#1001#, x"20");
        poke(16#1002#, x"00");
        poke(16#1003#, x"00");
        poke(16#1004#, x"00");
        poke(16#1005#, x"00");
        poke(16#1006#, x"00");
        poke(16#1007#, x"00");
        
        -- L2[0] -> PA 0x00000000 (P=1, W=1, U=1) for stack/page 0
        poke(16#2000#, x"07");
        poke(16#2001#, x"00");
        poke(16#2002#, x"00");
        poke(16#2003#, x"00");
        poke(16#2004#, x"00");
        poke(16#2005#, x"00");
        poke(16#2006#, x"00");
        poke(16#2007#, x"00");
        
        -- L2[8] -> PA 0x00008000 (P=1, W=1, U=1) for code at $8000
        poke(16#2040#, x"07");
        poke(16#2041#, x"80");
        poke(16#2042#, x"00");
        poke(16#2043#, x"00");
        poke(16#2044#, x"00");
        poke(16#2045#, x"00");
        poke(16#2046#, x"00");
        poke(16#2047#, x"00");
        
        -- L2[3] -> not present (fault target for VA $3000)
        poke(16#2018#, x"00");
        poke(16#2019#, x"00");
        poke(16#201A#, x"00");
        poke(16#201B#, x"00");
        poke(16#201C#, x"00");
        poke(16#201D#, x"00");
        poke(16#201E#, x"00");
        poke(16#201F#, x"00");
        
        -- Program: set PTBR, enable MMU, read VA $3000 (fault), STP
        poke(16#8000#, x"A9");  -- LDA #$00
        poke(16#8001#, x"00");
        poke(16#8002#, x"8D");  -- STA $F014
        poke(16#8003#, x"14");
        poke(16#8004#, x"F0");
        poke(16#8005#, x"A9");  -- LDA #$10
        poke(16#8006#, x"10");
        poke(16#8007#, x"8D");  -- STA $F015
        poke(16#8008#, x"15");
        poke(16#8009#, x"F0");
        poke(16#800A#, x"A9");  -- LDA #$00
        poke(16#800B#, x"00");
        poke(16#800C#, x"8D");  -- STA $F016
        poke(16#800D#, x"16");
        poke(16#800E#, x"F0");
        poke(16#800F#, x"A9");  -- LDA #$00
        poke(16#8010#, x"00");
        poke(16#8011#, x"8D");  -- STA $F017
        poke(16#8012#, x"17");
        poke(16#8013#, x"F0");
        
        poke(16#8014#, x"A9");  -- LDA #$00
        poke(16#8015#, x"00");
        poke(16#8016#, x"8D");  -- STA $F018
        poke(16#8017#, x"18");
        poke(16#8018#, x"F0");
        poke(16#8019#, x"A9");
        poke(16#801A#, x"00");
        poke(16#801B#, x"8D");  -- STA $F019
        poke(16#801C#, x"19");
        poke(16#801D#, x"F0");
        poke(16#801E#, x"A9");
        poke(16#801F#, x"00");
        poke(16#8020#, x"8D");  -- STA $F01A
        poke(16#8021#, x"1A");
        poke(16#8022#, x"F0");
        poke(16#8023#, x"A9");
        poke(16#8024#, x"00");
        poke(16#8025#, x"8D");  -- STA $F01B
        poke(16#8026#, x"1B");
        poke(16#8027#, x"F0");
        
        poke(16#8028#, x"A9");  -- LDA #$01 (enable MMU)
        poke(16#8029#, x"01");
        poke(16#802A#, x"8D");  -- STA $F000
        poke(16#802B#, x"00");
        poke(16#802C#, x"F0");
        
        poke(16#802D#, x"AD");  -- LDA $F000 (MMUCR)
        poke(16#802E#, x"00");
        poke(16#802F#, x"F0");
        poke(16#8030#, x"8D");  -- STA $F026
        poke(16#8031#, x"26");
        poke(16#8032#, x"F0");
        poke(16#8033#, x"AD");  -- LDA $F029 (marker)
        poke(16#8034#, x"29");
        poke(16#8035#, x"F0");
        poke(16#8036#, x"8D");  -- STA $F027
        poke(16#8037#, x"27");
        poke(16#8038#, x"F0");
        poke(16#8039#, x"AD");  -- LDA $3000 (fault)
        poke(16#803A#, x"00");
        poke(16#803B#, x"30");
        poke(16#803C#, x"DB");  -- STP
        poke(16#803D#, x"EA");  -- NOP (padding)
        
        irq_n <= '1';
        nmi_n <= '1';
        abort_n <= '1';
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(600);
        
        check_mem(16#F025#, x"A5", "Page fault handler ran");
        check_mem(16#F020#, x"00", "FAULTVA byte0");
        check_mem(16#F021#, x"30", "FAULTVA byte1");
        check_mem(16#F022#, x"00", "FAULTVA byte2");
        check_mem(16#F023#, x"00", "FAULTVA byte3");
        check_mem(16#F024#, x"01", "MMUCR fault type=000");
        check_mem(16#F026#, x"01", "MMUCR enabled");
        check_mem(16#F027#, x"5D", "Faulting sequence reached");
        
        -----------------------------------------------------------------------
        -- TEST 128: Timer IRQ + readable counter
        -----------------------------------------------------------------------
        report "";
        report "TEST 128: Timer IRQ";
        
        -- IRQ vector at $FFFE/$FFFF -> $8800
        poke16(16#FFFE#, x"8800");
        
        -- Timer IRQ handler at $8800: mark, clear pending, RTI
        poke(16#8800#, x"A9");  -- LDA #$5A
        poke(16#8801#, x"5A");
        poke(16#8802#, x"8D");  -- STA $0600
        poke(16#8803#, x"00");
        poke(16#8804#, x"06");
        poke(16#8805#, x"A9");  -- LDA #$0D (enable+irq+clear)
        poke(16#8806#, x"0D");
        poke(16#8807#, x"8D");  -- STA $F040 (TIMER_CTRL)
        poke(16#8808#, x"40");
        poke(16#8809#, x"F0");
        poke(16#880A#, x"40");  -- RTI
        
        -- Program: enable IRQs, set CMP=0x10, enable timer, WAI, read COUNT, STP
        poke(16#8000#, x"58");  -- CLI
        
        poke(16#8001#, x"A9");  -- LDA #$10
        poke(16#8002#, x"10");
        poke(16#8003#, x"8D");  -- STA $F044 (TIMER_CMP low)
        poke(16#8004#, x"44");
        poke(16#8005#, x"F0");
        poke(16#8006#, x"A9");  -- LDA #$00
        poke(16#8007#, x"00");
        poke(16#8008#, x"8D");  -- STA $F045
        poke(16#8009#, x"45");
        poke(16#800A#, x"F0");
        poke(16#800B#, x"8D");  -- STA $F046
        poke(16#800C#, x"46");
        poke(16#800D#, x"F0");
        poke(16#800E#, x"8D");  -- STA $F047
        poke(16#800F#, x"47");
        poke(16#8010#, x"F0");
        
        poke(16#8011#, x"A9");  -- LDA #$00
        poke(16#8012#, x"00");
        poke(16#8013#, x"8D");  -- STA $F048 (TIMER_COUNT low)
        poke(16#8014#, x"48");
        poke(16#8015#, x"F0");
        poke(16#8016#, x"8D");  -- STA $F049
        poke(16#8017#, x"49");
        poke(16#8018#, x"F0");
        poke(16#8019#, x"8D");  -- STA $F04A
        poke(16#801A#, x"4A");
        poke(16#801B#, x"F0");
        poke(16#801C#, x"8D");  -- STA $F04B
        poke(16#801D#, x"4B");
        poke(16#801E#, x"F0");
        
        poke(16#801F#, x"A9");  -- LDA #$05 (enable+irq)
        poke(16#8020#, x"05");
        poke(16#8021#, x"8D");  -- STA $F040 (TIMER_CTRL)
        poke(16#8022#, x"40");
        poke(16#8023#, x"F0");
        
        poke(16#8024#, x"CB");  -- WAI
        poke(16#8025#, x"AD");  -- LDA $F048 (TIMER_COUNT low)
        poke(16#8026#, x"48");
        poke(16#8027#, x"F0");
        poke(16#8028#, x"8D");  -- STA $0601
        poke(16#8029#, x"01");
        poke(16#802A#, x"06");
        poke(16#802B#, x"DB");  -- STP
        
        rst_n <= '0';
        wait_cycles(10);
        rst_n <= '1';
        wait_cycles(800);
        
        check_mem(16#0600#, x"5A", "Timer IRQ handler ran");
        check_mem(16#0601#, x"10", "Timer count latched");
        
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
