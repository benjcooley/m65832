# M65832 C Standard Library Bootstrap Checklist

**Goal:** Bootstrap a complete C standard library for the M65832 CPU, get it passing tests, and prepare to boot Linux on the emulator.

**Last Updated:** 2026-01-27

---

## Current State Summary

| Component | Status | Location |
|-----------|--------|----------|
| **LLVM Backend** | ✅ Working | `llvm-m65832/llvm/lib/Target/M65832/` |
| **Clang Target** | ✅ Working | `llvm-m65832/clang/lib/Basic/Targets/M65832.*` |
| **LLD Support** | ✅ Working | `llvm-m65832/lld/ELF/Arch/M65832.cpp` |
| **Emulator** | ✅ Working | `M65832/emu/` |
| **Assembler** | ✅ Working | `M65832/as/m65832as` |
| **Temp Stdlib** | ⚠️ Minimal | `llvm-m65832/m65832-stdlib/` |
| **LLVM libc Config** | ⚠️ Started | `llvm-m65832/libc/config/baremetal/m65832/` |
| **Clang Driver Toolchain** | ❌ Missing | `llvm-m65832/clang/lib/Driver/ToolChains/BareMetal.cpp` |

---

## Temporary Stdlib Inventory

### Headers (m65832-stdlib/libc/include/)

| Header | Functions | Status |
|--------|-----------|--------|
| `ctype.h` | 13 functions | ✅ Complete |
| `stdarg.h` | va_list, va_start, etc. | ✅ Compiler builtins |
| `stdbool.h` | bool, true, false | ✅ Macros |
| `stddef.h` | size_t, NULL, offsetof | ✅ Compiler builtins |
| `stdint.h` | int8_t through int64_t | ✅ Type definitions |
| `stdio.h` | 9 functions | ✅ Basic (no float printf) |
| `stdlib.h` | 14 functions | ⚠️ Missing bsearch, qsort |
| `string.h` | 17 functions | ✅ Complete |

### Implementation Status

| Module | Implemented | Missing |
|--------|-------------|---------|
| `ctype/ctype.c` | 13/13 | - |
| `string/*.c` | 17/17 | - |
| `stdio/stdio.c` | 9/9 | precision, floats, %lld |
| `stdlib/stdlib.c` | 12/14 | `bsearch`, `qsort` |

### Startup/Runtime

- [x] `crt0.s` - Assembly startup with ctor/dtor support
- [x] `init.c` - `__libc_init_array` / `__libc_fini_array`
- [x] Linker script - `scripts/baremetal/m65832.ld`

---

## Phase 1: Fix Toolchain Issues & Add Tests

### 1.1 Add m65832 to BareMetal toolchain handler
- [ ] **File:** `clang/lib/Driver/ToolChains/BareMetal.cpp`
- [ ] **Function:** `BareMetal::handlesTarget()` (line ~351)
- [ ] **Action:** Add `case llvm::Triple::m65832:` to the switch
- [ ] **Why:** `clang -target m65832-unknown-elf` doesn't pick correct linker flags

### 1.2 Complete ASR (arithmetic shift right) implementation
- [ ] **File:** `llvm/lib/Target/M65832/M65832InstrInfo.cpp:1165`
- [ ] **Issue:** Currently falls back to LSR for positive numbers
- [ ] **Action:** Implement proper sign-preserving ASR

### 1.3 Fix f32 load instructions
- [ ] **File:** `llvm/lib/Target/M65832/M65832InstrInfo.cpp:918,938`
- [ ] **Issue:** Uses 64-bit loads for f32
- [ ] **Action:** Use `LDF_S_ind` when assembler supports LDF.S

### 1.4 Add CodeGen lit tests
- [ ] **Location:** `llvm/test/CodeGen/M65832/`
- [ ] **Current:** Only 1 test (`load-zext.ll`)
- [ ] **Add tests for:**
  - [ ] Arithmetic (add, sub, mul via libcall)
  - [ ] Logical (and, or, xor)
  - [ ] Shifts (shl, shr, sar)
  - [ ] Comparisons (eq, ne, lt, gt, le, ge)
  - [ ] Function calls / calling convention
  - [ ] Stack frames / alloca
  - [ ] FPU operations
  - [ ] Global variables

### 1.5 Regression tests added
- [x] **Location:** `M65832/emu/c_tests/tests/`
- [x] `regress_stack_spill.c` - Tests stack spilling with many local variables
- [x] `regress_stack_spill_complex.c` - Complex function mimicking printf
- [x] `regress_brcond.c` - Tests complex boolean expressions (BRCOND)
- [x] `regress_call_frame.c` - Tests call frame reservation for local buffers
- [x] `regress_branch_offset.c` - Tests SELECT_CC conditional expressions
- [x] `test_regressions.sh` - Script to run all regression tests

### 1.5 Set up automated test runner
- [ ] Create script to build test → run on emulator → validate output
- [ ] Connect `m65832-stdlib/test/*.c` to emulator
- [ ] Add CI integration (optional)

---

## Phase 2: Complete Temporary Stdlib

### 2.1 Implement missing stdlib functions
- [ ] `bsearch()` - binary search
- [ ] `qsort()` - quicksort

### 2.2 Enhance printf
- [ ] Add precision support (`%.2f`, `%.5s`, etc.)
- [ ] Add `long long` support (`%lld`, `%llu`, `%llx`)
- [ ] Add float support (`%f`, `%e`, `%g`) - needs soft-float or FPU integration

### 2.3 Fix memory allocator
- [ ] Current `free()` is a no-op (bump allocator)
- [ ] Implement proper free list or upgrade allocator
- [ ] Add `realloc()` that actually reallocates

### 2.4 Create comprehensive test suite
- [ ] Test each ctype function
- [ ] Test each string function
- [ ] Test printf format specifiers
- [ ] Test malloc/free/realloc
- [ ] Test atoi/strtol edge cases

---

## Phase 3: Transition to LLVM libc

### 3.1 Complete LLVM libc configuration
- [ ] Add `headers.txt` to `libc/config/baremetal/m65832/`
- [ ] Verify `entrypoints.txt` covers needed functions
- [ ] Add `config.json` if needed

### 3.2 Configure LLVM libc CMake
- [ ] Add m65832 to `libc/CMakeLists.txt` target checks
- [ ] Verify freestanding build configuration
- [ ] Test: `cmake -DLLVM_LIBC_FULL_BUILD=ON -DLIBC_TARGET_TRIPLE=m65832-unknown-elf`

### 3.3 Verify __support files
- [x] `io.cpp` - UART hooks (exists at `libc/src/__support/OSUtil/baremetal/m65832/`)
- [x] `syscalls.cpp` - sbrk, exit, abort (exists)
- [ ] Test that hooks work with LLVM libc

### 3.4 Build LLVM libc
- [ ] Configure cross-compilation
- [ ] Build libc.a for m65832-unknown-elf
- [ ] Verify all entrypoints are present

### 3.5 Run LLVM libc tests
- [ ] Set up test execution on emulator
- [ ] Run string tests
- [ ] Run stdlib tests
- [ ] Run stdio tests
- [ ] Run ctype tests

### 3.6 Fix test failures
- [ ] Track and fix each failure
- [ ] Add regression tests for fixes

---

## Phase 4: Linux Prerequisites

### 4.1 Implement compiler-rt builtins
- [ ] `__mulsi3` - 32-bit multiply (no HW mul)
- [ ] `__divsi3` - 32-bit signed divide
- [ ] `__udivsi3` - 32-bit unsigned divide
- [ ] `__modsi3` - 32-bit signed modulo
- [ ] `__umodsi3` - 32-bit unsigned modulo
- [ ] `__muldi3` - 64-bit multiply
- [ ] `__divdi3` - 64-bit divide
- [ ] Soft-float routines (if FPU not always available)

### 4.2 Define syscall interface
- [ ] Design m65832 syscall ABI (which register for syscall number, args, return)
- [ ] Document in `M65832_Linux_Porting_Guide.md`
- [ ] Implement syscall instruction or trap mechanism

### 4.3 Add Linux libc configuration
- [ ] Create `libc/config/linux/m65832/`
- [ ] `entrypoints.txt` - full POSIX subset
- [ ] `headers.txt`
- [ ] Syscall wrapper implementations

### 4.4 Implement setjmp/longjmp
- [ ] `setjmp()` - save registers to jmp_buf
- [ ] `longjmp()` - restore registers from jmp_buf
- [ ] Define jmp_buf layout for m65832

### 4.5 Implement signal handling
- [ ] Signal delivery mechanism
- [ ] `signal()`, `sigaction()`
- [ ] Signal stack

### 4.6 Threading support
- [ ] Determine if m65832 has SMP support
- [ ] Implement pthreads basics
- [ ] Thread-local storage (TLS)

---

## Phase 5: Linux Kernel Bootstrap

### 5.1 Create arch/m65832/ in Linux kernel
- [ ] `Kconfig` - architecture configuration
- [ ] `Makefile` - build rules
- [ ] `include/asm/` - architecture headers
- [ ] `kernel/head.S` - kernel entry point
- [ ] `kernel/setup.c` - machine setup
- [ ] `kernel/irq.c` - interrupt handling
- [ ] `kernel/time.c` - timer support
- [ ] `mm/` - memory management

### 5.2 Implement MMU support
- [ ] Define page table format
- [ ] Implement TLB management
- [ ] Page fault handler
- [ ] Memory zones

### 5.3 Enhance emulator for Linux
- [ ] MMU emulation
- [ ] Timer interrupts
- [ ] Block device (virtio or simple)
- [ ] Console/serial for rootfs
- [ ] Optional: network device

### 5.4 Build minimal kernel
- [ ] Configure kernel (make m65832_defconfig)
- [ ] Cross-compile with clang
- [ ] Generate kernel image

### 5.5 Boot to init
- [ ] Create minimal initramfs
- [ ] Boot kernel on emulator
- [ ] Verify /init runs

### 5.6 Build userspace
- [ ] Cross-compile busybox
- [ ] Create rootfs with busybox
- [ ] Add essential /etc files

### 5.7 Interactive shell
- [ ] Boot to busybox shell
- [ ] Verify basic commands work
- [ ] Test file I/O

---

## Known Toolchain Issues

Track issues discovered during development:

| Issue | File | Status | Notes |
|-------|------|--------|-------|
| Stack spill used wrong instructions | `M65832InstrInfo.cpp:177-254` | **FIXED** | Used LOAD32/STORE32 instead of LDA_DP/STA_DP |
| BRCOND not handled | `M65832ISelLowering.cpp:63` | **FIXED** | Added Expand action for BRCOND |
| Branch relocations wrong | `M65832MCCodeEmitter.cpp`, `M65832ELFObjectWriter.cpp` | **FIXED** | Used custom fixup kind with -2 offset adjustment |
| MC layer crash with isPCRel flag | `MCAssembler.cpp` | **WORKAROUND** | Don't set isPCRel=true, use custom fixup kind instead |
| STP instruction not encoded | `M65832MCCodeEmitter.cpp:198-200` | **FIXED** | Added STP/WAI opcodes to getOpcode() |
| Call frame not reserved | `M65832ISelLowering.cpp:591-597` | **FIXED** | Reserve 2+ bytes for JSR return address |
| Branch immediate offset wrong | `M65832MCCodeEmitter.cpp:276-285` | **FIXED** | Subtract 3 from immediate branch offsets for PC-rel |
| analyzeBranch crashes on non-MBB | `M65832InstrInfo.cpp:262,280` | **FIXED** | Check isMBB() before calling getMBB() |
| Missing shl_parts pattern | `M65832ISelLowering.cpp` | **FIXED** | Added Custom lowering for SHL_PARTS/SRL_PARTS/SRA_PARTS |
| Missing f32/f64 load patterns | `M65832InstrInfo.td` | **FIXED** | Added LDF32_CP, LDF64_CP patterns |
| Missing variable rotate patterns | `M65832InstrInfo.td` | **FIXED** | Added ROLR_VAR, RORR_VAR |
| JSR missing FPU clobbers | `M65832InstrInfo.td` | **FIXED** | Added F0-F13 to Defs list |
| FP truncating store missing | `M65832ISelLowering.cpp` | **FIXED** | setTruncStoreAction(f64, f32, Expand) |
| SELECT_CC/SELECT both Expand | `M65832ISelLowering.cpp` | **FIXED** | Added Custom lowering for FP types |
| Missing SELECT_CC_MIXED | `M65832ISelLowering.cpp`, `.td` | **FIXED** | Integer compare, FP result |
| SIGN_EXTEND_INREG i1 | `M65832ISelLowering.cpp` | **FIXED** | Added Expand for MVT::i1 |
| FPR spill/reload missing | `M65832InstrInfo.cpp` | **FIXED** | Added FPR32/FPR64 stack slot support |
| SELECT_CC_FP patterns missing | `M65832InstrInfo.td` | **FIXED** | Added F32/F64 result patterns |
| Inline asm 'r' constraint | `M65832ISelLowering.cpp` | **FIXED** | Added getConstraintType/getRegForInlineAsmConstraint |
| Debug info (-g) crashes | `MCAssembler::layout()` | Open | Backend debug info incomplete, crashes during layout |
| BareMetal doesn't handle m65832 | `BareMetal.cpp:351` | Open | Blocks linker integration |
| ASR uses LSR fallback | `M65832InstrInfo.cpp:1165` | Open | Wrong for negative numbers |
| f32 uses 64-bit loads | `M65832InstrInfo.cpp:918` | Open | Inefficient |
| MCCodeEmitter commented out | `CMakeLists.txt:12` | Open | Manual encoding works |
| No hardware mul/div | - | By design | Uses libcalls |
| C++ exceptions | - | Open | Not yet supported |

---

## Testing Commands

```bash
# Build temp stdlib
cd llvm-m65832/m65832-stdlib
make clean && make

# Compile a test
clang-23 -target m65832-unknown-elf -O2 -ffreestanding -nostdlib \
    -I libc/include -c test/hello.c -o build/hello.o

# Link with stdlib
ld.lld -T scripts/baremetal/m65832.ld \
    build/crt0.o build/hello.o build/libc.a build/libplatform.a \
    -o build/hello.elf

# Run on emulator (from M65832/emu/)
./m65832emu ../../llvm-m65832/m65832-stdlib/build/hello.elf

# Run LLVM lit tests
llvm-lit llvm/test/CodeGen/M65832/ -v
```

---

## Resources

- LLVM libc docs: https://libc.llvm.org/
- M65832 Architecture Reference: `M65832/docs/M65832_Architecture_Reference.md`
- M65832 C ABI: `M65832/docs/M65832_C_ABI.md`
- M65832 Linux Porting Guide: `M65832/docs/M65832_Linux_Porting_Guide.md`
- Emulator README: `M65832/emu/README.md`

---

## Progress Log

| Date | Phase | Task | Status |
|------|-------|------|--------|
| 2026-01-27 | - | Initial inventory | ✅ Complete |
| 2026-01-27 | 1 | Fixed stack spill bug (LOAD32/STORE32) | ✅ Complete |
| 2026-01-27 | 1 | Fixed BRCOND expansion | ✅ Complete |
| 2026-01-27 | 1 | Added regression tests for fixes | ✅ Complete |
| 2026-01-27 | 1 | Added TextAlignFillValue to MCAsmInfo | ✅ Complete |
| 2026-01-27 | 2 | Stdlib builds successfully | ✅ Complete |
| 2026-01-27 | 2 | test.elf links successfully | ✅ Complete |
| 2026-01-27 | 2 | Existing C tests pass (arithmetic, control, memory, functions) | ✅ Complete |
| 2026-01-27 | - | Discovered branch relocation bug | ⚠️ Initially BLOCKING |
| 2026-01-27 | 1 | Fixed branch relocation bug | ✅ Complete |
| 2026-01-27 | - | BSS clearing loop executes correctly | ✅ Complete |
| 2026-01-27 | 1 | Fixed STP instruction encoding | ✅ Complete |
| 2026-01-27 | 1 | Fixed call frame reservation for JSR return address | ✅ Complete |
| 2026-01-27 | 1 | Added call frame regression test | ✅ Complete |
| 2026-01-27 | 2 | Simple stdlib tests (strcpy, strlen) pass | ✅ Complete |
| 2026-01-27 | 1 | Fixed branch immediate offset bug | ✅ Complete |
| 2026-01-27 | 1 | Added branch offset regression test | ✅ Complete |
| 2026-01-27 | 2 | Comprehensive stdlib tests (string, ctype, stdlib) pass | ✅ Complete |
| 2026-01-27 | - | Created picolibc-m65832 fork | ✅ Complete |
| 2026-01-27 | - | Added M65832 arch support to picolibc | ✅ Complete |
| 2026-01-27 | 1 | Fixed analyzeBranch crash on non-MBB operands | ✅ Complete |
| 2026-01-27 | 1 | Fixed shl_parts/srl_parts/sra_parts lowering | ✅ Complete |
| 2026-01-27 | 1 | Fixed f32/f64 constant pool load patterns | ✅ Complete |
| 2026-01-27 | 1 | Fixed BITCAST expansion through memory | ✅ Complete |
| 2026-01-27 | 1 | Fixed variable rotate patterns (ROLR_VAR, RORR_VAR) | ✅ Complete |
| 2026-01-27 | 1 | Fixed JSR FPU register clobbers (F0-F13) | ✅ Complete |
| 2026-01-27 | 1 | Fixed f64->f32 truncating store (Expand) | ✅ Complete |
| 2026-01-27 | 1 | Fixed FP SELECT/SELECT_CC lowering with PHI nodes | ✅ Complete |
| 2026-01-27 | 1 | Added SELECT_CC_MIXED for int-compare/FP-result | ✅ Complete |
| 2026-01-27 | 1 | Fixed SIGN_EXTEND_INREG i1 (Expand) | ✅ Complete |
| 2026-01-27 | 1 | Fixed FPR32/FPR64 stack spill/reload | ✅ Complete |
| 2026-01-27 | 1 | Added SELECT_CC_FP F32/F64 patterns | ✅ Complete |
| 2026-01-27 | 1 | Added inline asm 'r' constraint support | ✅ Complete |
| 2026-01-28 | 3 | **PICOLIBC BUILD SUCCESS** - Full library compiles | ✅ Complete |
| | | | |

---

## Branch Relocation Bug Details

**Status:** ✅ FIXED - Branch instructions now use correct PC-relative offsets

### Problem (Original)
When code used branches with symbolic labels (e.g., `BEQ .LBB0_4`), the integrated assembler/linker wrote the absolute address of the target instead of a PC-relative offset. The emulator interpreted these as relative offsets, causing branches to jump to wrong addresses.

### Root Cause (Original)
1. The `M65832MCCodeEmitter` created `FK_Data_2` fixups for branches without PC-relative handling
2. The ELF object writer emitted `R_M65832_16` (absolute) relocations instead of `R_M65832_PCREL_16`
3. The linker computed and wrote absolute addresses

### Solution Implemented
1. **MCCodeEmitter** (`M65832MCCodeEmitter.cpp`):
   - Use `M65832::fixup_m65832_pcrel_16` fixup kind for branch instructions (BEQ, BNE, BCS, BCC, BMI, BPL, BVS, BVC, BRA, BRL)
   - Add `-2` offset to the expression to account for instruction-end vs relocation-location difference
   - Note: Do NOT set `isPCRel=true` on MCFixup (causes MCAssembler crashes)

2. **ELF Object Writer** (`M65832ELFObjectWriter.cpp`):
   - Handle `fixup_m65832_pcrel_8` and `fixup_m65832_pcrel_16` fixup kinds
   - Emit `R_M65832_PCREL_8` and `R_M65832_PCREL_16` relocation types

3. **LLD Linker** (`lld/ELF/Arch/M65832.cpp`):
   - Already had correct handling for `R_M65832_PCREL_*` relocations with `R_PC` expression

### Why isPCRel=true causes crashes
Setting `isPCRel = true` on MCFixup causes a crash in `MCAssembler::writeSectionData` with assertion:
```
"Invalid virtual align in concrete fragment!"
```
This is likely an LLVM MC layer bug or missing configuration. The workaround is to use a custom fixup kind to identify PC-relative fixups without setting the MCFixup flag.

### Verification
- `llvm-objdump -r` shows `R_M65832_PCREL_16` relocations for branches
- BSS clearing loop in crt0.c executes correctly with proper branch targets
- Simple branch instructions (BNE, BEQ, BRA, BCS) work correctly

