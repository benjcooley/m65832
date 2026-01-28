-- M65832 Boot ROM
-- Simple synchronous ROM for reset vector and tiny monitor
--
-- Copyright (c) 2026 M65832 Project
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Memory Map:
--   0xFFFF0000 - 0xFFFF0FFF : Boot ROM (4KB)
--   Reset vector at 0xFFFFFFFC points here
--
-- Initial contents: minimal startup code that:
--   1. Initializes stack pointer
--   2. Outputs "M65832" banner over UART
--   3. Enters simple echo loop

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity M65832_BootROM is
    generic(
        ADDR_WIDTH : integer := 12   -- 4KB ROM
    );
    port(
        CLK      : in  std_logic;
        ADDR     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        DATA_OUT : out std_logic_vector(7 downto 0)
    );
end M65832_BootROM;

architecture rtl of M65832_BootROM is

    type rom_t is array(0 to 2**ADDR_WIDTH - 1) of std_logic_vector(7 downto 0);
    
    -- Minimal boot code
    -- This is a placeholder - actual code should be assembled with m65832as
    -- and converted to this format
    --
    -- Assembly pseudocode:
    --   .org $FFFF0000
    --   reset:
    --       clc
    --       xce           ; Enter native mode
    --       rep #$30      ; 16-bit A and X/Y
    --       ldx #$00FF    ; Stack at $00FF
    --       txs
    --       lda #'M'      ; Print banner
    --       jsr putc
    --       lda #'6'
    --       jsr putc
    --       ...
    --   loop:
    --       jsr getc      ; Echo loop
    --       jsr putc
    --       bra loop
    --   putc:
    --       sta $FFF104   ; UART TX
    --       rts
    --   getc:
    --       lda $FFF100   ; UART status
    --       and #$02      ; RX_AVAIL
    --       beq getc
    --       lda $FFF108   ; UART RX
    --       rts
    --
    --   .org $FFFFC       ; Reset vector
    --   .word $FFFF0000
    
    function init_rom return rom_t is
        variable rom : rom_t := (others => x"EA");  -- Fill with NOP
    begin
        -- Reset entry point at offset 0
        -- CLC, XCE sequence to enter native mode
        rom(16#000#) := x"18";  -- CLC
        rom(16#001#) := x"FB";  -- XCE
        
        -- REP #$30 - 16-bit mode
        rom(16#002#) := x"C2";  -- REP
        rom(16#003#) := x"30";  -- #$30
        
        -- LDX #$00FF, TXS - set stack
        rom(16#004#) := x"A2";  -- LDX #imm16
        rom(16#005#) := x"FF";  -- low byte
        rom(16#006#) := x"00";  -- high byte
        rom(16#007#) := x"9A";  -- TXS
        
        -- Print "M65832\r\n" banner using polled UART
        -- LDA #'M', JSR putc
        rom(16#008#) := x"A9";  -- LDA #imm8
        rom(16#009#) := x"4D";  -- 'M'
        rom(16#00A#) := x"20";  -- JSR
        rom(16#00B#) := x"50";  -- putc low  (offset $50)
        rom(16#00C#) := x"00";  -- putc high (bank 0 relative to ROM base)
        
        -- LDA #'6', JSR putc
        rom(16#00D#) := x"A9";
        rom(16#00E#) := x"36";  -- '6'
        rom(16#00F#) := x"20";
        rom(16#010#) := x"50";
        rom(16#011#) := x"00";
        
        -- LDA #'5', JSR putc
        rom(16#012#) := x"A9";
        rom(16#013#) := x"35";  -- '5'
        rom(16#014#) := x"20";
        rom(16#015#) := x"50";
        rom(16#016#) := x"00";
        
        -- LDA #'8', JSR putc
        rom(16#017#) := x"A9";
        rom(16#018#) := x"38";  -- '8'
        rom(16#019#) := x"20";
        rom(16#01A#) := x"50";
        rom(16#01B#) := x"00";
        
        -- LDA #'3', JSR putc
        rom(16#01C#) := x"A9";
        rom(16#01D#) := x"33";  -- '3'
        rom(16#01E#) := x"20";
        rom(16#01F#) := x"50";
        rom(16#020#) := x"00";
        
        -- LDA #'2', JSR putc
        rom(16#021#) := x"A9";
        rom(16#022#) := x"32";  -- '2'
        rom(16#023#) := x"20";
        rom(16#024#) := x"50";
        rom(16#025#) := x"00";
        
        -- LDA #CR, JSR putc
        rom(16#026#) := x"A9";
        rom(16#027#) := x"0D";  -- CR
        rom(16#028#) := x"20";
        rom(16#029#) := x"50";
        rom(16#02A#) := x"00";
        
        -- LDA #LF, JSR putc
        rom(16#02B#) := x"A9";
        rom(16#02C#) := x"0A";  -- LF
        rom(16#02D#) := x"20";
        rom(16#02E#) := x"50";
        rom(16#02F#) := x"00";
        
        -- Echo loop at offset $30
        -- loop: JSR getc
        rom(16#030#) := x"20";  -- JSR
        rom(16#031#) := x"60";  -- getc low (offset $60)
        rom(16#032#) := x"00";  -- getc high
        
        -- JSR putc
        rom(16#033#) := x"20";
        rom(16#034#) := x"50";
        rom(16#035#) := x"00";
        
        -- BRA loop
        rom(16#036#) := x"80";  -- BRA
        rom(16#037#) := x"F8";  -- -8 (back to $30)
        
        -- Padding to putc at offset $50
        
        -- putc: Wait for TX ready, then send
        -- putc: PHA
        rom(16#050#) := x"48";  -- PHA
        
        -- wait_tx: LDA $FFF100 (UART status, absolute)
        rom(16#051#) := x"AD";  -- LDA abs
        rom(16#052#) := x"00";  -- low
        rom(16#053#) := x"F1";  -- mid ($FFF100)
        -- Note: For 24-bit addressing we need LDA long ($AF)
        -- but let's use bank 0 relative for now
        
        -- AND #$01 (TX_READY)
        rom(16#054#) := x"29";  -- AND #imm
        rom(16#055#) := x"01";
        
        -- BEQ wait_tx (loop if not ready)
        rom(16#056#) := x"F0";  -- BEQ
        rom(16#057#) := x"F9";  -- -7 (back to $51)
        
        -- PLA
        rom(16#058#) := x"68";  -- PLA
        
        -- STA $FFF104 (UART TX)
        rom(16#059#) := x"8D";  -- STA abs
        rom(16#05A#) := x"04";  -- low
        rom(16#05B#) := x"F1";  -- mid ($FFF104)
        
        -- RTS
        rom(16#05C#) := x"60";  -- RTS
        
        -- getc: Wait for RX data available, then read
        -- getc: LDA $FFF100 (UART status)
        rom(16#060#) := x"AD";  -- LDA abs
        rom(16#061#) := x"00";  -- low
        rom(16#062#) := x"F1";  -- mid
        
        -- AND #$02 (RX_AVAIL)
        rom(16#063#) := x"29";  -- AND #imm
        rom(16#064#) := x"02";
        
        -- BEQ getc (loop if no data)
        rom(16#065#) := x"F0";  -- BEQ
        rom(16#066#) := x"F9";  -- -7 (back to $60)
        
        -- LDA $FFF108 (UART RX)
        rom(16#067#) := x"AD";  -- LDA abs
        rom(16#068#) := x"08";  -- low
        rom(16#069#) := x"F1";  -- mid
        
        -- RTS
        rom(16#06A#) := x"60";  -- RTS
        
        -- Reset vectors at end of ROM (offset $FF0-$FFF maps to $FFFFFF0-$FFFFFFF)
        -- For 4KB ROM at $FFFF0000, vectors are at $FFFF0FF0-$FFFF0FFF
        -- But 65816 reset vector is at $FFFC-$FFFD (bank 0)
        -- For M65832, the core should fetch from VBR-relative or absolute
        --
        -- For now, put reset vector pointing to ROM base
        -- Native mode vectors (emulation vectors at $FFF4-$FFFF are in bank 0)
        
        -- We'll use the last 16 bytes for vectors
        -- Assuming the address decoder maps $FFFF_FFF0-$FFFF_FFFF to ROM $FF0-$FFF
        
        -- Reset vector (6502/65816 at $FFFC)
        -- For this ROM, we assume it's mapped so $FFFC-$FFFD come from ROM
        rom(16#FFC#) := x"00";  -- Reset vector low  -> $FFFF0000
        rom(16#FFD#) := x"00";  -- Reset vector high
        rom(16#FFE#) := x"FF";  -- Bank (if 24-bit)
        rom(16#FFF#) := x"FF";  -- Extended
        
        return rom;
    end function;
    
    signal rom : rom_t := init_rom;
    signal data_reg : std_logic_vector(7 downto 0);

begin

    -- Synchronous read
    process(CLK)
    begin
        if rising_edge(CLK) then
            data_reg <= rom(to_integer(unsigned(ADDR)));
        end if;
    end process;
    
    DATA_OUT <= data_reg;

end rtl;
