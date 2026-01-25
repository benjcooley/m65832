## 6502 Compatibility Matrix

### Must-support systems
- NES (Ricoh 2A03/2A07)
- Commodore 64 (6510/8500/8502)
- Apple II / IIe / IIc (6502/65C02)
- Atari 2600 family (6507)
- Atari 8-bit computers (6502C)

### Should-support arcade families (6502-based)
- Atari vector/early raster boards (Asteroids, Tempest, Centipede, Missile Command)
- Williams-era 6502 boards where applicable

### Not targeted
- Embedded/post-1990 variants
- Simplified or niche derivatives not used by notable systems

## Variant differences that affect software

### NMOS 6502 baseline (C64/Atari/Apple II/2600)
- Decimal mode is supported (ADC/SBC use BCD when D=1)
- JMP (indirect) page-wrap bug must be preserved
- Undocumented opcodes are used by some C64/Atari software (optional group)

### Ricoh 2A03/2A07 (NES)
- Decimal mode is **disabled** (D flag ignored by ADC/SBC)
- Instruction set otherwise matches NMOS 6502

### WDC 65C02 (Apple IIe/IIc)
- Adds new opcodes and addressing modes
- Fixes JMP (indirect) page-wrap bug

## Compatibility control bits (coprocessor state)

`COMPAT[7:0]` is stored with the 6502 coprocessor state:
- `COMPAT[0]` **DECIMAL_EN**: 1 = enable BCD in ADC/SBC, 0 = force binary
- `COMPAT[1]` **CMOS65C02_EN**: 1 = enable 65C02 instruction group (subset below)
- `COMPAT[2]` **NMOS_ILLEGAL_EN**: 1 = enable undocumented NMOS opcodes (planned)

## Implemented 65C02 subset (when `CMOS65C02_EN=1`)
- `BRA` (0x80)
- `PHX/PLX/PHY/PLY` (0xDA/0xFA/0x5A/0x7A)
- `STZ` (0x64/0x74/0x9C/0x9E)
- `BIT #imm` (0x89), `BIT zp,X` (0x34), `BIT abs,X` (0x3C)
- `TRB/TSB` (0x14/0x1C, 0x04/0x0C)
- `JMP (abs,X)` (0x7C)
- `(zp)` indirect: ORA/AND/EOR/ADC/STA/LDA/CMP/SBC (0x12/0x32/0x52/0x72/0x92/0xB2/0xD2/0xF2)
- `INC A / DEC A` (0x1A/0x3A)

## Remaining 65C02 ops (planned)
- `TRB/TSB` side effects and timing audits

## Implemented undocumented NMOS group (when `NMOS_ILLEGAL_EN=1`)
- `LAX` (0xA7/0xB7/0xAF/0xBF/0xA3/0xB3/0xAB)
- `SAX` (0x87/0x97/0x8F/0x83)
- `DCP` (0xC7/0xD7/0xCF/0xDF/0xDB/0xC3/0xD3)
- `ISC/ISB` (0xE7/0xF7/0xEF/0xFF/0xFB/0xE3/0xF3)
- `SLO` (0x07/0x17/0x0F/0x1F/0x1B/0x03/0x13)
- `RLA` (0x27/0x37/0x2F/0x3F/0x3B/0x23/0x33)
- `SRE` (0x47/0x57/0x4F/0x5F/0x5B/0x43/0x53)
- `RRA` (0x67/0x77/0x6F/0x7F/0x7B/0x63/0x73)
- `ANC` (0x0B/0x2B), `ALR` (0x4B), `ARR` (0x6B), `SBX/AXS` (0xCB)

## Default profiles
- **NES profile:** `DECIMAL_EN=0`, `CMOS65C02_EN=0`
- **NMOS profile:** `DECIMAL_EN=1`, `CMOS65C02_EN=0`
- **Apple IIe/IIc profile:** `DECIMAL_EN=1`, `CMOS65C02_EN=1`
