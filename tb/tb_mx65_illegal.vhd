library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_MX65_Illegal is
end entity;

architecture sim of tb_MX65_Illegal is
    constant CLK_PERIOD : time := 20 ns;

    function is_clean(v : std_logic_vector) return boolean is
    begin
        for i in v'range loop
            if v(i) /= '0' and v(i) /= '1' then
                return false;
            end if;
        end loop;
        return true;
    end function;

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '1';
    signal ce      : std_logic := '1';
    signal compat  : std_logic_vector(7 downto 0) := "00000111";
    signal data_in : std_logic_vector(7 downto 0);
    signal data_out: std_logic_vector(7 downto 0);
    signal address : std_logic_vector(15 downto 0);
    signal rw      : std_logic;
    signal sync    : std_logic;
    signal nmi     : std_logic := '1';
    signal irq     : std_logic := '1';

    type int_array is array (natural range <>) of integer;
    type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
    constant expected_cycles : int_array := (
        2,  -- LDX #imm
        2,  -- LDA #imm
        2,  -- ANC #imm
        2,  -- ALR #imm
        2,  -- ARR #imm
        2,  -- SBX #imm
        3,  -- LAX zp
        3,  -- SAX zp
        5,  -- SLO zp
        5,  -- RLA zp
        5,  -- SRE zp
        5,  -- RRA zp
        5,  -- DCP zp
        5,  -- ISC zp
        5,  -- TRB zp
        5,  -- TSB zp
        2,  -- BIT #imm
        4,  -- BIT zp,X
        4,  -- BIT abs,X
        3,  -- PHX
        4,  -- PLX
        3,  -- BRA (taken)
        6,  -- JMP (abs,X)
        5,  -- LDA (zp)
        3,  -- STZ zp
        4,  -- STZ abs
        2,  -- INC A
        2   -- DEC A
    );
    constant expected_opcodes : byte_array := (
        x"A2", -- LDX #imm
        x"A9", -- LDA #imm
        x"0B", -- ANC #imm
        x"4B", -- ALR #imm
        x"6B", -- ARR #imm
        x"CB", -- SBX #imm
        x"A7", -- LAX zp
        x"87", -- SAX zp
        x"07", -- SLO zp
        x"27", -- RLA zp
        x"47", -- SRE zp
        x"67", -- RRA zp
        x"C7", -- DCP zp
        x"E7", -- ISC zp
        x"14", -- TRB zp
        x"04", -- TSB zp
        x"89", -- BIT #imm
        x"34", -- BIT zp,X
        x"3C", -- BIT abs,X
        x"DA", -- PHX
        x"FA", -- PLX
        x"80", -- BRA
        x"7C", -- JMP (abs,X)
        x"B2", -- LDA (zp)
        x"64", -- STZ zp
        x"9C", -- STZ abs
        x"1A", -- INC A
        x"3A"  -- DEC A
    );

    signal cycle_count : integer := 0;
    signal instr_index : integer := 0;
    signal started     : std_logic := '0';
    signal done        : std_logic := '0';

    function rom_data(addr : std_logic_vector(15 downto 0)) return std_logic_vector is
        variable a : integer;
    begin
        if not is_clean(addr) then
            return x"00";
        end if;
        a := to_integer(unsigned(addr));
        case a is
            when 16#FFFC# => return x"00";
            when 16#FFFD# => return x"00";
            when 16#FFFE# => return x"00";
            when 16#FFFF# => return x"00";

            when 16#0080# => return x"12";
            when 16#0081# => return x"34";
            when 16#0082# => return x"55";
            when 16#0083# => return x"0F";
            when 16#0084# => return x"F0";
            when 16#0085# => return x"80";
            when 16#0086# => return x"01";
            when 16#0087# => return x"7F";
            when 16#0088# => return x"AA";
            when 16#0089# => return x"55";
            when 16#008A# => return x"80";
            when 16#008C# => return x"00";
            when 16#008D# => return x"05";
            when 16#0500# => return x"99";

            when 16#3000# => return x"2F";
            when 16#3001# => return x"00";

            when 16#0000# => return x"A2";
            when 16#0001# => return x"00";
            when 16#0002# => return x"A9";
            when 16#0003# => return x"3C";
            when 16#0004# => return x"0B";
            when 16#0005# => return x"0F";
            when 16#0006# => return x"4B";
            when 16#0007# => return x"03";
            when 16#0008# => return x"6B";
            when 16#0009# => return x"FF";
            when 16#000A# => return x"CB";
            when 16#000B# => return x"01";
            when 16#000C# => return x"A7";
            when 16#000D# => return x"80";
            when 16#000E# => return x"87";
            when 16#000F# => return x"81";
            when 16#0010# => return x"07";
            when 16#0011# => return x"82";
            when 16#0012# => return x"27";
            when 16#0013# => return x"83";
            when 16#0014# => return x"47";
            when 16#0015# => return x"84";
            when 16#0016# => return x"67";
            when 16#0017# => return x"85";
            when 16#0018# => return x"C7";
            when 16#0019# => return x"86";
            when 16#001A# => return x"E7";
            when 16#001B# => return x"87";
            when 16#001C# => return x"14";
            when 16#001D# => return x"88";
            when 16#001E# => return x"04";
            when 16#001F# => return x"89";
            when 16#0020# => return x"89";
            when 16#0021# => return x"80";
            when 16#0022# => return x"34";
            when 16#0023# => return x"8A";
            when 16#0024# => return x"3C";
            when 16#0025# => return x"00";
            when 16#0026# => return x"30";
            when 16#0027# => return x"DA";
            when 16#0028# => return x"FA";
            when 16#0029# => return x"80";
            when 16#002A# => return x"01";
            when 16#002B# => return x"EA";
            when 16#002C# => return x"7C";
            when 16#002D# => return x"00";
            when 16#002E# => return x"30";

            when 16#002F# => return x"B2";
            when 16#0030# => return x"8C";
            when 16#0031# => return x"64";
            when 16#0032# => return x"8E";
            when 16#0033# => return x"9C";
            when 16#0034# => return x"02";
            when 16#0035# => return x"40";
            when 16#0036# => return x"1A";
            when 16#0037# => return x"3A";
            when others => return x"00";
        end case;
    end function;
begin
    clk <= not clk after CLK_PERIOD/2;

    data_in <= rom_data(address);

    -- Reset
    process
    begin
        reset <= '1';
        wait for 10*CLK_PERIOD;
        reset <= '0';
        wait;
    end process;

    -- Cycle counter/validator
    process(clk)
        variable count_v : integer;
        variable idx_v : integer;
        variable started_v : std_logic;
    begin
        if rising_edge(clk) then
            count_v := cycle_count;
            idx_v := instr_index;
            started_v := started;

            if reset = '1' then
                count_v := 0;
                idx_v := 0;
                started_v := '0';
            elsif ce = '1' then
                if sync = '1' then
                    if started_v = '0' then
                        if is_clean(data_in) and data_in = expected_opcodes(0) then
                            started_v := '1';
                            idx_v := 0;
                            count_v := 0;
                        end if;
                    else
                        if idx_v < expected_opcodes'length then
                            assert data_in = expected_opcodes(idx_v)
                                report "opcode mismatch at index " & integer'image(idx_v) &
                                       " expected " & to_hstring(expected_opcodes(idx_v)) &
                                       " got " & to_hstring(data_in)
                                severity failure;
                            if idx_v > 0 then
                                assert count_v = expected_cycles(idx_v - 1)
                                    report "cycle mismatch at index " & integer'image(idx_v - 1) &
                                           " expected " & integer'image(expected_cycles(idx_v - 1)) &
                                           " got " & integer'image(count_v)
                                    severity failure;
                            end if;
                            idx_v := idx_v + 1;
                        else
                            assert count_v = expected_cycles(expected_cycles'length - 1)
                                report "cycle mismatch at last index " &
                                       integer'image(expected_cycles'length - 1) &
                                       " expected " &
                                       integer'image(expected_cycles(expected_cycles'length - 1)) &
                                       " got " & integer'image(count_v)
                                severity failure;
                            report "MX65 illegal opcode cycle test PASSED" severity note;
                            done <= '1';
                            stop;
                        end if;
                        count_v := 0;
                    end if;
                end if;
                count_v := count_v + 1;
            end if;

            cycle_count <= count_v;
            instr_index <= idx_v;
            started <= started_v;
        end if;
    end process;

    process
    begin
        wait for 100 us;
        if done = '0' then
            assert false report "MX65 illegal opcode cycle test did not complete" severity failure;
        end if;
        wait;
    end process;

    dut: entity work.mx65
        port map (
            clock    => clk,
            reset    => reset,
            ce       => ce,
            compat   => compat,
            data_in  => data_in,
            data_out => data_out,
            address  => address,
            rw       => rw,
            sync     => sync,
            nmi      => nmi,
            irq      => irq
        );
end architecture;
