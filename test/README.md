# M65832 VHDL Test Extraction and Emulator Validation

This directory contains tools to extract tests from the VHDL testbench and run them on the emulator, ensuring consistency between RTL and emulator behavior.

## Usage

```bash
# List all tests
./extract_vhdl_tests.py --list

# Run all tests
./extract_vhdl_tests.py

# Run specific test
./extract_vhdl_tests.py --test 31

# Run with verbose output
./extract_vhdl_tests.py --test 31 --verbose
```

## Current Test Results

**Overall: 295 passed, 63 failed (82.4% pass rate)**

### Fully Passing Categories

| Category | Tests | Status |
|----------|-------|--------|
| Basic LDA/STA/LDX/LDY/STX/STY | 1-4 | PASS |
| INC/DEC | 5, 23-24 | PASS |
| Branches | 6, 15, 20-22 | PASS |
| JSR/RTS | 7 | PASS |
| Indexed addressing | 8, 14, 41-44 | PASS |
| Register transfers | 9-10 | PASS |
| Logical operations (ORA/AND/EOR) | 11 | PASS |
| Arithmetic (ADC/SBC) | 3, 12, 27, 35-36, 38-39, 49-52 | PASS |
| Shifts (ASL/LSR/ROL/ROR) | 13, 18-19, 25-26, 45-48 | PASS |
| Compare (CMP/CPX/CPY) | 16-17, 29-30, 37, 40 | PASS |
| BIT instruction | 28 | PASS |
| 16/32-bit modes | 31-52 | PASS |
| Indirect addressing | 53-67 | PASS |
| Long indirect [dp],Y | 68, 74, 107 | PASS |
| LDA/STA long | 71-72, 77-78, 82, 105-106 | PASS |
| Stack relative | 69, 75, 109-110 | PASS |
| JMP indirect | 57, 66 | PASS |
| XCE (enter native) | 104 | PASS |
| JML/JSL/RTL | 115-116 | PASS |
| PER | 117 | PASS |
| JMP (abs,X) / JML [abs] | 118-119 | PASS |
| MMU MMIO registers | 120 | PASS |
| MVN/MVP block move | 102-103 | PASS |
| SD/SB/LEA instructions | 88-89 | PASS |
| MULU/DIVU | 90 | PASS |
| CAS atomic | 91-92 | PASS |
| LLI/SCI atomic | 93-94 | PASS |
| LDQ/STQ 64-bit | 98 | PASS |

### Remaining Failures

| Category | Tests | Issue |
|----------|-------|-------|
| Test framework: overlapping pokes | 79, 84, 87 | Multiple sub-tests write to same memory addresses |
| RSET register window | 95-97, 99 | Register window feature not fully implemented |
| Interrupt handling | 100-101, 111-114 | Tests require hardware IRQ/NMI signal generation |
| MMU translation | 121 | Page table walking needs implementation |
| Privilege traps | 122-123 | User mode MMIO access |
| Illegal opcode | 124-126 | Trap vs NOP behavior |
| Page fault | 127 | MMU fault handling |
| Timer | 128 | Timer interrupt generation |

## Key Fixes Applied

### M65832 vs 65816 Differences

1. **Width in Emulation Mode**: M65832 allows width changes via SEP/REP even in emulation mode (E=1), unlike 65816 which forces 8-bit.

2. **Long Addressing**: Uses 24-bit addresses (3 bytes), not 32-bit.

3. **Extended Opcode Prefix**: $02 is always extended prefix in M65832 (even in emulation mode), not COP.

4. **Opcode Mappings** (cc=11 group):
   - $AB = LDA long (not PLB as in 65816)
   - $B3 = LDA [dp],Y (not LDA (sr,S),Y)
   - $BF = LDA long,X
   - $8F = STA long
   - $9F = STA long,X

5. **MVN/MVP Swap**: 
   - $44 = MVN (increment, unlike 65816's MVP)
   - $54 = MVP (decrement, unlike 65816's MVN)

6. **Extended Instructions** ($02 prefix):
   - $00-$07 = MUL/MULU/DIV/DIVU (dp and abs)
   - $10-$15 = CAS/LLI/SCI (atomic ops)
   - $20-$25 = SD/SB (set D/B registers)
   - $30-$31 = ENR/DSR (register window)
   - $40 = TRAP
   - $86-$87 = TTA/TAT (T register transfer)
   - $88-$8B = LDQ/STQ (64-bit)
   - $A0-$A3 = LEA (load effective address)
   - $E8 = Register-targeted ALU (LD/ADC/SBC/AND/ORA/EOR/CMP to DP dest)
   - $E9 = Barrel shifter (SHL/SHR/SAR/ROL/ROR)
   - $EA = Extend operations (SEXT8/SEXT16/ZEXT8/ZEXT16/CLZ/CTZ/POPCNT)

7. **LL/SC Semantics**: Any store invalidates the load-linked reservation.

## Files

- `extract_vhdl_tests.py` - Test extraction and execution tool
- `README.md` - This file

## To Reach 100% Pass Rate

The remaining failures require:

1. **Test Framework Enhancement**: Support for tests with overlapping memory regions (multiple sub-tests at $8000)

2. **RSET Register Window**: Implement register file array and route dp accesses when P_R is set

3. **Interrupt Signal Generation**: Add ability to trigger IRQ/NMI/ABORT signals during test execution

4. **MMU Features**: Page table walking, page fault handling

5. **Privilege Enforcement**: User mode MMIO access trapping

6. **Timer**: Timer interrupt generation and counter readback
