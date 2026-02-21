# M65832 Architecture Integrity Audit

## Design Goals (restated for clarity)
- A proper 32-bit Linux-compatible modern CPU that is an evolution of the 65816
- **Binary compatible** with 6502 (W=00) and 65816 (W=01) code
- Familiar assembly with natural extensions, not disruptive changes
- All 65816 opcodes work as-is — **zero ISA changes in W=00/W=01** except $02 (COP→extended prefix, needed for mode switching)
- No 24-bit addressing in 32-bit mode — the M65832 is a 32-bit machine
- 24-bit long addressing preserved in W=00/W=01 for 65816 binary compatibility

---

## What Went Wrong

### Bug 1: cc=11 bbb off-by-one (emulator + RTL decoder) — FIXED

The cc=11 opcode group encodes addressing modes via the `bbb` field. Someone shifted (sr,S),Y and [dp],Y down by one position to "free up" bbb=010 for long addressing, but this broke 65816 compatibility:

```
bbb   65816           M65832 (broken)     Fix
000   sr,S            sr,S                (same)
001   [dp]            [dp]                (same)
010   (implied)       long (wrong!)       implied (handled separately)
011   long            (sr,S),Y (wrong!)   long
100   (sr,S),Y        [dp],Y (wrong!)     (sr,S),Y
101   [dp],Y          ??? (dropped!)      [dp],Y
110   (implied)       (implied)           (same)
111   long,X          long,X              (same)
```

**Root cause**: An off-by-one in the original emulator implementation. The bbb=010 slot (implied ops like PHD/PLD) is handled by individual opcode checks *before* the bbb addressing mode switch, so it should have been skipped in the bbb→addressing-mode mapping. Instead it was counted as the first slot, shifting everything down by one. This made LDA long at 0xAF (bbb=011) *appear* missing (it was mapped to (sr,S),Y instead). To "fix" the apparently missing LDA long, PLB (0xAB, bbb=010) was moved to extended opcode `$02 $73` and its slot reused. But LDA long was never missing — it was just at the wrong bbb position.

**Inconsistency**: Only LDA (0xAF, 0xB3) and STA (0x93) got the wrong addressing mode. The other 6 ALU ops (ADC, SBC, CMP, AND, ORA, EOR) at bbb=100 were correctly using (sr,S),Y. This confirms the shift was a bug, not intentional — only the ops that were explicitly added (LDA/STA) got the wrong mode; the ones that were implemented systematically were fine.

**Affected opcodes**:
- 0xAB: Was LDA long, should be PLB (implied)
- 0xAF: Was (sr,S),Y, should be LDA long
- 0xB3: Was [dp],Y, should be LDA (sr,S),Y
- 0x93: Was [dp],Y, should be STA (sr,S),Y
- RTL decoder: bbb=011/100/101 all wrong

**Status**: Fixed in emulator, RTL decoder, disassembler, and VHDL testbench. All tests pass.

### Bug 2: Missing 65816 long/long,X opcodes (emulator only) — FIXED

12 standard 65816 opcodes were never implemented:

| Missing | Instruction | 65816 standard |
|---------|-------------|----------------|
| 0x0F | ORA long | bbb=011 |
| 0x1F | ORA long,X | bbb=111 |
| 0x2F | AND long | bbb=011 |
| 0x3F | AND long,X | bbb=111 |
| 0x4F | EOR long | bbb=011 |
| 0x5F | EOR long,X | bbb=111 |
| 0x6F | ADC long | bbb=011 |
| 0x7F | ADC long,X | bbb=111 |
| 0xCF | CMP long | bbb=011 |
| 0xDF | CMP long,X | bbb=111 |
| 0xEF | SBC long | bbb=011 |
| 0xFF | SBC long,X | bbb=111 |

Only LDA long (0xAF), LDA long,X (0xBF), STA long (0x8F), STA long,X (0x9F) existed.

The RTL decoder handles these generically via the bbb case statement, so RTL was fine. Only the emulator was missing them.

**Status**: All 16 long/long,X opcodes now implemented in emulator. They work in W=00/W=01 mode and trap as ILLEGAL_OP in W=11 (32-bit mode uses extended ALU instead).

### Bug 3: Long addressing is 24-bit instead of 32-bit — MOOT

This was identified as a fundamental architecture bug: `addr_long()` calls `fetch24()` instead of `fetch32()`. However, since long addressing opcodes are now correctly **illegal in W=11 (32-bit) mode**, this is moot — long addressing only runs in W=00/W=01 where 24-bit is correct per 65816 spec.

The M65832 uses extended ALU ($02 prefix) with 32-bit absolute addresses for all "long" operations in 32-bit mode. Standard long addressing is reserved for 65816 backward compatibility.

**Status**: No fix needed. Long addressing is 24-bit in W=00/W=01 (correct per 65816) and illegal in W=11 (correct per M65832 design).

### Not a bug: JML/JSL/RTL illegal in 32-bit mode (correct)

JML/JSL/RTL are deprecated in 32-bit mode — JMP/JSR/RTS already use 32-bit addresses, so the "long" variants are redundant. Deprecated instructions correctly trap as illegal. Keep as-is.

### Not a bug: Branch offsets (RTL and emulator agree)

Both RTL and emulator use 16-bit branch offsets in 32-bit mode, 8-bit in W=00/W=01. LLVM confirms: all branches are Size=3 (opcode + 16-bit relative). No fix needed.

### Bug 6: LLVM JMP Size=3 instead of Size=5 — DEFERRED

LLVM defines `JMP : F3<0x4C>` with Size=3 (opcode + 16-bit operand). The emulator correctly handles JMP as 5 bytes in 32-bit mode (`fetch32()`). JMP is a 5-byte instruction in W=11 — same as JSR which is correctly `F8` (Size=5).

**Why it hasn't broken**: LLVM codegen uses BRA (16-bit PC-relative) for all direct intra-function jumps. JMP is only defined for indirect jumps (JMP_IND, JMP_DP_IND). The Size=3 definition is latent.

**Fix**: Change `def JMP : F3<0x4C, ...>` to `def JMP : F8<0x4C, ...>` (Size=5). Same for JMP_IND (0x6C).

**Status**: Deferred — latent bug, not blocking anything.

---

## Intentional Changes (NOT bugs)

These are legitimate M65832 extensions:

1. **$02 repurposed from COP to extended prefix**: $02 was undefined on 6502 (no compat issue) and COP on 65816 (rarely used). Repurposing as extended prefix is necessary — SEPE ($02 $61) is the only way to enter 32-bit mode. Works in all W modes. ~80+ new instructions behind the prefix.

2. **PLB/PHB extended to 32-bit B register**: In 65816, B was an 8-bit bank register. In M65832, B is a 32-bit frame pointer. PLB/PHB at their original opcodes (0xAB/0x8B) now push/pull 32-bit B. Natural extension.

3. **PHD/PLD extended to 32-bit D register**: Same pattern — D was 16-bit in 65816, now 32-bit. Natural extension.

4. **SEPE/REPE ($02 $61/$60)**: New instructions to set/clear extended P register bits (W mode, S supervisor, R register window, K compatibility). Required for mode switching.

5. **Register window (R bit)**: DP accesses map to hardware register file when R=1. Essential for LLVM codegen performance.

---

## Changes Completed

### Change 1: Fix cc=11 bbb off-by-one (emulator + RTL + disassembler)
- Emulator: 0xAB→PLB, 0xAF→LDA long, 0xB3→LDA (sr,S),Y, 0x93→STA (sr,S),Y
- RTL decoder: fixed bbb case (011→long, 100→(sr,S),Y, 101→[dp],Y)
- Disassembler: all 256 entries corrected

### Change 2: Add all 16 long/long,X opcodes to emulator
- All 16 opcodes (8 long + 8 long,X) now implemented for W=00/W=01
- All 16 trap as TRAP_ILLEGAL_OP in W=11 (32-bit mode)
- Extended ALU provides 32-bit addressing instead

### Change 3: Make long addressing illegal in W=11
- Emulator: width_m==4 guard on all 16 long opcodes
- RTL core: `illegal_long` signal (IS_ALU_OP + ADDR_MODE="1111" + W_mode='1')
- JML ($5C), JML [$abs] ($DC), JSL ($22), RTL ($6B) also trap in W=11

### Change 4: Fix VHDL testbench for corrected encodings
- Fixed opcode bytes: 0xAB→0xAF (long), 0xAF→0xB3 ((sr,S),Y), 0xB3→0xB7 ([dp],Y), 0x93→0x97 (STA [dp],Y)
- Test 105 converted from LDA long to LD.L abs32 (extended ALU)
- All 518 VHDL tests pass

### Change 5: Assembler/disassembler round-trip tests
- Created comprehensive round-trip test files for 8-bit, 16-bit, 32-bit, and extended ALU modes
- Tests assemble, disassemble, and verify expected mnemonics/addressing mode syntax
- 61 assembler/disassembler tests pass

### Change 6: Emulator test for long opcodes trapping in W=11
- Created `emu/test/test_long_illegal.asm` — verifies LDA long ($AF) triggers TRAP_ILLEGAL_OP in 32-bit mode
- Added `run_test_trap()` helper to `emu/run_tests.sh` for trap-based test validation
- 38 emulator tests pass

### Change 7: Disassembler "(Illegal)" annotation
- Long addressing modes (AM_ABSL, AM_ABSLX, AM_ABSLIND) and RTL ($6B) annotated with "(Illegal)" when disassembling in 32-bit mode (m_flag >= 3)

### Change 8: Documentation fixes
- Fixed `LD A, new_value` → `LDA new_value` in README.md atomic operations example
- Fixed `ST A,` → `STA` in VHDL testbench comments

---

## LLVM Backend Audit

### What LLVM actually emits (32-bit mode only)

**Standard 65816 opcodes used (all cc=00 or cc=01):**
- DP: LDA 0xA5, STA 0x85, ADC 0x65, SBC 0xE5, AND 0x25, ORA 0x05, EOR 0x45, CMP 0xC5, etc.
- Immediate: LDA 0xA9 (32-bit imm in W=11), ADC 0x69, etc.
- Absolute 16-bit: LDA 0xAD, STA 0x8D (B-relative in 32-bit mode)
- Indirect: LDA 0xB2, STA 0x92
- Indirect,Y: LDA 0xB1, STA 0x91
- Branches: BEQ 0xF0, BNE 0xD0, BRA 0x80, etc. (3-byte, 16-bit PC-relative)
- JSR 0x20 (5-byte, 32-bit absolute)
- PLB 0xAB, PHB 0x8B (standard 65816 positions)
- All standard transfers, stack ops, flags

**Extended instructions ($02 prefix) used:**
- Extended ALU: LDL/STL ($02 $80/$81) with 32-bit abs, B-relative, indirect Y
- Sized ops: LDB/STB (8-bit), LDW/STW (16-bit) via extended ALU mode byte
- Register ops: MOVR, ADDR, SUBR, ANDR, ORAR, EORR, CMPR (DP and IMM variants)
- Barrel shifter: SHL/SHR/SAR/ROL/ROR ($02 $98)
- Extend: SEXT8/SEXT16/ZEXT8/ZEXT16/CLZ/CTZ/POPCNT ($02 $99)
- Stack: PHD32/PLD32/PHB32/PLB32 ($02 $70-$73)
- Transfers: TAB/TBA/TXB/TBX/TYB/TBY ($02 $91-$96)
- System: RSET/RCLR, TRAP, FENCE, SB
- FPU: full single/double precision arithmetic, load/store, transfers
- MUL/DIV, CAS (atomics)

**NOT used by LLVM codegen (safe to fix without LLVM impact):**
- All cc=11 opcodes (long, (sr,S),Y, [dp],Y addressing)
- Standard long addressing (0xAF, 0xBF, 0x8F, 0x9F, 0x0F-0xFF)
- JML (0x5C), JSL (0x22), RTL (0x6B) — deprecated, correctly absent from codegen

---

## How We Avoid This in the Future

1. **65816 opcode table as ground truth**: Maintain a reference table mapping every opcode to its 65816 behavior. Any deviation must be explicitly documented with rationale.

2. **Test every opcode in every mode**: Automated tests for all 256 base opcodes × 3 modes (W=00, W=01, W=11). The cc=11 off-by-one survived because we had no tests for (sr,S),Y vs [dp],Y addressing in all modes.

3. **Emulator-RTL parity checks**: The emulator and RTL should agree on every opcode's addressing mode and instruction length. A test harness that runs the same program on both and compares cycle-by-cycle would catch mismatches like the branch offset issue.

4. **No remapping without documentation**: If a 65816 opcode is changed, it must be noted in a CHANGES.md file with the rationale. The PLB→LDA long remap was undocumented.

5. **Design rule**: "If the 65816 defines it, we keep it. Extensions go through $02 prefix or truly unused slots."

---

## Remaining Work

- **LLVM JMP Size**: Fix `JMP : F3` → `JMP : F8` (Size=5) in LLVM backend. Latent bug, not blocking.

---

## Verification
- Build assembler/disassembler: `make -C as`
- Run asm/dis tests: `cd as && ./run_tests.sh`
- Build emulator: `make -C emu`
- Run emu tests: `cd emu && ./run_tests.sh`
- Run C tests: `./emu/c_tests/run_core_tests.sh`
- Run picolibc sysroot tests: `./emu/c_tests/run_picolibc_suite.sh`
- Run full picolibc suite: `cd picolibc-m65832 && python3 run_picolibc_gtest.py --no-rebuild`

## Test Results (all passing)
- Assembler/disassembler: 61 tests
- Emulator: 38 tests
- C compiler (core + regression + inline asm): 189 tests
- Picolibc sysroot: 15 tests
- Full picolibc suite: 162 passed, 19 skipped, 0 failed
