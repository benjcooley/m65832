# M65832 LLVM Compiler Codegen Bugs

## How to run tests

From the m65832 repo:
```bash
cd emu/c_tests
OPT_LEVEL="-O2" bash run_c_test.sh regression/regress_select_cmov.c 0 500000
OPT_LEVEL="-Os" bash run_c_test.sh regression/regress_select_cmov.c 0 500000
```

The runner compiles with clang, links with lld, runs on the emulator.
Expected return value = 0 (in A register). Non-zero = test number that failed.

**Important:** Bugs 1 and 2 only trigger at `-O2` or `-Os` (not `-O0`).
Set `OPT_LEVEL="-O2"` or `OPT_LEVEL="-Os"` when running.

---

## Bug 1: select/cmov lowering in binary-search bit scanning

**Status:** FAILS — reliably reproduces  
**Test:** `test_ffs.c`  
**Severity:** Critical — affects all bitops in the kernel

### Symptom
`ffs(4)` returns 4 instead of 2. The conditional-increment pattern
`if ((word & MASK) == 0) { num += N; word >>= N; }` is miscompiled.
The compiler's select/cmov lowering assigns `word` to `num` instead of `N`.

### Minimal pattern
```c
unsigned int num = 0;
if ((word & 0xf) == 0) {
    num += 4;        // BUG: compiler generates num = word instead of num += 4
    word >>= 4;
}
```

### Compile and run
```bash
cd emu/c_tests
OPT_LEVEL="-O2" bash run_c_test.sh regression/regress_select_cmov.c 0 500000
# Expected: PASS (A=0)
# Actual:   FAIL (A=00000003) — test 3 failed: ffs(4) returns 4 instead of 2
```

### Kernel workaround
`arch/m65832/include/asm/bitops.h` uses byte lookup tables instead of
the binary-search pattern. See `__ffs_byte_tab[]` in `arch/m65832/lib/bitops.c`.

---

## Bug 2: ROL instruction encoding mismatch

**Status:** May be fixed — passes in bare-metal mode with -O2/-Os. Previously hung in system mode.  
**Test:** `regress_rol_encoding.c`  
**Severity:** Critical if still present — affects __clear_bit, __change_bit

### Symptom
`__clear_bit(n, bitmap)` using `*p &= ~(1UL << n)` generates a ROL
instruction. The assembler and emulator disagree on the ROL encoding,
producing incorrect results or crashes.

### Minimal pattern
```c
unsigned long mask = 1UL << (nr % 32);
*p &= ~mask;    // BUG: compiler emits ROL Rd,Rs,A with wrong encoding
```

### Compile and run
```bash
cd emu/c_tests
OPT_LEVEL="-O2" bash run_c_test.sh regression/regress_rol_encoding.c 0 500000
# Currently: PASS (A=0) — may have been fixed in latest compiler
```

### Kernel workaround
`arch/m65832/include/asm/bitops.h` uses `__bit_mask_tab[32]` lookup
table for bit masks, avoiding the ROL instruction entirely.

---

## Bug 3: Variable reuse miscompilation

**Status:** Does not reproduce in standalone test  
**Test:** `test_pcpu_alloc.c`  
**Severity:** Medium — only observed in `mm/percpu.c`

### Symptom
A local variable reused for multiple `size_t` calculations across
function calls gets a garbage value (~2GB) on later reuses. Only
triggers in the kernel build with specific struct sizes and register
pressure from surrounding code.

### Minimal pattern
```c
size_t alloc_size;
alloc_size = compute_size_1(...);  // OK
func(alloc_size);
alloc_size = compute_size_2(...);  // BUG: gets garbage value
func(alloc_size);                  // passes ~2GB to allocator
```

### Compile and run
```bash
bash run_test_o2.sh test_pcpu_alloc.c
# Currently PASSES — does not reproduce outside kernel context
```

### To reproduce
The bug requires the full kernel compilation context. Compile the
kernel with `CONFIG_CC_OPTIMIZE_FOR_SIZE=y` (i.e., `-Os`) and the
`volatile` removed from `mm/percpu.c:1351`. The kernel will crash
during `pcpu_alloc_first_chunk` with a multi-GB allocation.

### Kernel workaround
`mm/percpu.c` marks `alloc_size` as `volatile`.

---

## Bug 4: Branch/jump to garbage address 0x0aeb1bb0

**Status:** Does not reproduce in standalone test  
**Test:** `test_branch_target.c`  
**Severity:** Critical — blocks kernel boot

### Symptom
Multiple kernel functions jump to address `0x0aeb1bb0` (not in kernel
text), causing immediate page faults. The address is not present in the
kernel binary — it's computed at runtime from a corrupted return address
or function pointer.

### Key finding
The value 0x0aeb1bb0 does NOT exist anywhere in the kernel binary
(vmlinux.bin). It is computed at runtime, likely from a corrupted
stack frame. The bug is in the compiler's prologue/epilogue code
generation or the stack frame layout under high register pressure.

### Affected functions (in kernel)
- `printk_get_console_flush_type` (switch statement, inlined)
- `timerqueue_add` → `rb_add_cached` (rb-tree insert with callback)
- Occurs during `sched_clock_init` → printk path

### Compile and run
```bash
bash run_test_o2.sh test_branch_target.c
# Currently PASSES — does not reproduce outside kernel context
```

### To reproduce
Build the full kernel (`bash scripts/build-m65832.sh`) and boot:
```bash
~/projects/m65832/emu/m65832emu --kernel vmlinux.bin --cycles 10000000000
```
The crash occurs after "past setup_per_cpu_pageset" when the first
printk after `sched_clock_init` calls into `vprintk_emit` →
`printk_get_console_flush_type` or `timerqueue_add`.

### Debugging approach
Use emulator instruction tracing to capture the exact instruction
sequence leading to the bad PC:
```bash
~/projects/m65832/emu/m65832emu --kernel vmlinux.bin --trace-ring 200 --cycles 500000000
```
Look for the RTS or JSR instruction that produces PC=0x0aeb1bb0.
The likely root cause is:
- Incorrect stack frame push/pull sequence in a deeply nested call
- Off-by-one in the PHB32/PLB32 stack offset calculation
- Register spill/reload generating wrong stack offsets

### Kernel workaround
`kernel/printk/internal.h` has a simplified `printk_get_console_flush_type`
under `#ifdef CONFIG_M65832` that avoids the problematic switch statement.
The `timerqueue_add` crash is not yet worked around.

---

## Compilation flags

The kernel compiles with these flags (extract from `make V=1`):
```
--target=m65832-unknown-linux -Os -fomit-frame-pointer -fno-common
-fno-PIE -fno-strict-aliasing -ffreestanding -fno-builtin
-fno-delete-null-pointer-checks -fno-stack-protector
```

To compile standalone tests with matching flags:
```bash
clang --target=m65832-unknown-linux -Os -fomit-frame-pointer \
    -fno-common -fno-PIE -fno-strict-aliasing -ffreestanding \
    -fno-builtin -c test.c -o test.o
```

---

## Bug 5: va_arg for pointer types returns NULL/garbage

**Status:** FAILS — reliably reproduces at ALL optimization levels (-O0, -O2, -Os)  
**Test:** `regress_varargs_string.c`  
**Severity:** CRITICAL — blocks kernel boot (all printk %s formatting broken)

### Symptom
`va_arg(ap, const char *)` returns NULL instead of the actual pointer
value passed as a variadic argument. This causes any `printk` with `%s`
to crash the kernel by dereferencing NULL or garbage in `string()`.

### Minimal pattern
```c
#include <stdarg.h>
const char *get_str(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    const char *s = va_arg(ap, const char *);  // BUG: returns NULL
    va_end(ap);
    return s;
}
// get_str("%s", "hello") returns NULL instead of pointer to "hello"
```

### Compile and run
```bash
cd emu/c_tests
OPT_LEVEL="-O0" bash run_c_test.sh regression/regress_varargs_string.c 0 50000
# Expected: PASS (A=0)
# Actual:   FAIL (A=00000001) — test 1 failed: va_arg returned NULL
```

### Impact on kernel
This is the ROOT CAUSE of the "branch to 0x0aeb1bb0" crashes. The crash
chain is:
1. `printk("console [%s%d] enabled", con->name, con->index)` in printk.c
2. `vsnprintf` calls `string()` for %s, passes `va_arg(ap, char *)` as the string pointer
3. `va_arg` returns garbage/NULL
4. `string()` dereferences the bad pointer → page fault
5. Page fault handler calls `die()` → `printk()` → recursive fault

### Root cause
The M65832 ABI passes the first 8 arguments in R0-R7. For varargs
functions, arguments beyond the named parameters should be accessed via
`va_list` which walks the register-saved area or stack. The `va_arg`
implementation is incorrectly computing the offset or reading from the
wrong location.

### Kernel workaround
None currently — this bug blocks all printk %s formatting. The kernel
bypasses it by having the raw UART console avoid printk's format engine
for direct output.
