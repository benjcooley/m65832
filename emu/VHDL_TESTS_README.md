# M65832 VHDL Test Extraction and Emulator Validation

This directory contains tools to extract tests from the VHDL testbench and run them on the emulator, ensuring consistency between RTL and emulator behavior.

## Usage

```bash
# List all tests
python3 extract_vhdl_tests.py --list

# Run all tests
python3 extract_vhdl_tests.py

# Run specific test
python3 extract_vhdl_tests.py --test 31

# Run with verbose output
python3 extract_vhdl_tests.py --test 31 -v
```

## Current Test Results

**Overall: 366 passed, 0 failed (100% pass rate)**

All 126 VHDL tests (containing 366 individual checks) now pass.

### Test Categories

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
| MMU MMIO registers | 120-121 | PASS |
| MVN/MVP block move | 102-103 | PASS |
| SD/SB/LEA instructions | 88-89 | PASS |
| MULU/DIVU | 90 | PASS |
| CAS atomic | 91-92 | PASS |
| LLI/SCI atomic | 93-94 | PASS |
| RSET register window | 95-97 | PASS |
| LDQ/STQ 64-bit | 98 | PASS |
| FPU operations | 99 | PASS |
| Interrupt handling (NMI/IRQ/WAI) | 100-101, 111-114 | PASS |
| Privilege traps | 122-123 | PASS |
| Illegal opcode handling | 124-126 | PASS |
| Page fault handling | 127 | PASS |
| Timer IRQ | 128 | PASS |

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
- `VHDL_TESTS_README.md` - This file

## Implementation Notes

### Features Implemented

1. **RSET Register Window**: DP addresses in R=1 mode map to internal register file with 4-byte alignment requirement

2. **FPU Operations**: Full single and double precision floating point (LDF/STF, FADD/FSUB/FMUL/FDIV, F2I/I2F, FCMP)

3. **Reserved FPU Trap**: Opcodes $D9-$DF trap to software emulation via SYSCALL vector

4. **Interrupt Handling**: Proper IRQ/NMI/ABORT signal timing, WAI instruction wake-on-interrupt

5. **MMU Features**: Page table walking, page fault exception vectoring with FAULTVA/fault type latching

6. **Timer**: Timer IRQ with count latching when interrupt fires

7. **Privilege Enforcement**: User mode MMIO access trapping
