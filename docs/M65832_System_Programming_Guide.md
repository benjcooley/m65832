# M65832 System Programming Guide

**Supervisor Mode, MMU, Interrupts, and Multitasking**

---

## 1. Overview

This guide covers system-level programming for the M65832 processor, including:
- Privilege levels and supervisor mode
- Memory management unit (MMU) configuration
- Interrupt and exception handling
- Context switching and multitasking
- Running mixed-mode processes (6502/65816/32-bit)

> **RTL Reference:** `m65832_core.vhd`, `m65832_mmu.vhd`, `m65832_pkg.vhd`

---

## 2. Privilege Model

### 2.1 Privilege Levels

The M65832 implements a two-level privilege model via the S flag in the status register:

| S Flag | Level | Description |
|--------|-------|-------------|
| 1 | Supervisor | Full system access, can modify MMU and system registers |
| 0 | User | Restricted access, page permissions enforced |

### 2.2 Status Register (P) Layout

The M65832 status register is 14 bits internally:

```
Internal P Register (14 bits):
Bit:  13  12  11  10   9   8   7   6   5   4   3   2   1   0
     ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
     │ K │ R │ S │rsv│W1 │W0 │ N │ V │ M │ X │ D │ I │ Z │ C │
     └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
```

| Bit | Name | Description |
|-----|------|-------------|
| 0 | C | Carry flag |
| 1 | Z | Zero flag |
| 2 | I | IRQ disable (1 = disabled) |
| 3 | D | Decimal mode (BCD arithmetic, 8/16-bit only) |
| 4 | X | Index width (65816-compatible position): 0=8-bit, 1=16-bit |
| 5 | M | Accumulator width (65816-compatible position): 0=8-bit, 1=16-bit |
| 6 | V | Overflow flag |
| 7 | N | Negative flag |
| 8 | W0 | Width mode bit 0 |
| 9 | W1 | Width mode bit 1 |
| 10 | reserved | Reserved for future W2 (64-bit mode) |
| 11 | S | Supervisor mode (1 = supervisor privilege) |
| 12 | R | Register window enable (1 = DP accesses register file) |
| 13 | K | Compatibility mode (1 = illegal opcodes become NOP) |

### 2.3 Width Encoding

The W bits use thermometer encoding to select processor width mode:

| W1:W0 | Mode | Description |
|-------|------|-------------|
| 00 | 6502 Emulation | 8-bit, E is derived (E = W==00) |
| 01 | 65816 Native | M/X flags control widths |
| 11 | 32-bit Native | Full 32-bit, M/X ignored |
| 10 | Reserved | Reserved for future use |

Single-bit M and X at 65816-compatible positions (bit 5 = M, bit 4 = X):
- REP/SEP operate on P[0:7] (C, Z, I, D, X, M, V, N) — same as 65816
- REPE/SEPE operate on P[8:13] (W0, W1, reserved, S, R, K)

Future: W2 bit (P[10]) for 64-bit mode (W=111).

### 2.4 Stack Pointer Behavior

- **Emulation mode (E=1):** Stack pointer is 8-bit, constrained to $0100-$01FF (relative to VBR)
- **Native mode (E=0):** Stack pointer is 16-bit or 32-bit depending on mode
  - The M65832 uses the full 32-bit SP in native-32 mode

### 2.5 Privileged Operations

The following operations require supervisor mode (S=1). Executing them with S=0 triggers a privilege violation trap:

| Operation | Description |
|-----------|-------------|
| SVBR | Set Virtual Base Register |
| Modify MMUCR | Enable/disable paging, set control bits |
| Modify PTBR | Set page table base register |
| Modify ASID | Set address space ID |
| Access MMIO ($FFFFF0xx) | System register space |
| STP | Stop processor |
| SEPE with S bit (bit 3) | Attempt to enter supervisor mode directly |

### 2.6 Entering Supervisor Mode

Supervisor mode is entered automatically on:
- Reset (S=1 after reset)
- Interrupts (IRQ, NMI, ABORT)
- Exceptions (page fault, illegal instruction)
- TRAP instruction (system calls)
- BRK instruction

---

## 3. Memory Management Unit

### 3.1 MMU Overview

> **RTL Reference:** `m65832_mmu.vhd`

The MMU translates 32-bit virtual addresses to 65-bit physical addresses:

| Feature | Specification |
|---------|---------------|
| Page size | 4 KB (12-bit offset) |
| Page table levels | 2 (10-bit L1 index, 10-bit L2 index) |
| TLB entries | 16 (fully associative) |
| ASID bits | 8 (256 address spaces) |
| Physical address | 65 bits (32 EB) |

### 3.2 Address Translation

```
Virtual Address (32 bits):
┌──────────────┬──────────────┬──────────────┐
│   L1 Index   │   L2 Index   │    Offset    │
│   [31:22]    │   [21:12]    │   [11:0]     │
│   10 bits    │   10 bits    │   12 bits    │
└──────────────┴──────────────┴──────────────┘

Translation:
1. L1_PTE_addr = PTBR + (L1_Index × 8)
2. L1_PTE = read(L1_PTE_addr)
3. L2_table_base = L1_PTE[63:12] << 12
4. L2_PTE_addr = L2_table_base + (L2_Index × 8)
5. L2_PTE = read(L2_PTE_addr)
6. Physical_addr = L2_PTE[63:12] || Offset[11:0]
```

### 3.3 Page Table Entry Format

Each PTE is 64 bits:

```
Bit 63:    NX (No Execute) - execution disallowed if set
Bits 62:12: Physical Page Number (52 bits, gives 64-bit PA; bit 64 stored separately for 65-bit)
Bit 11:    Global - entry not flushed on ASID change
Bit 10:    Dirty - set by hardware on write
Bit 9:     Accessed - set by hardware on access
Bits 8-5:  Reserved
Bit 4:     PCD (Page Cache Disable)
Bit 3:     PWT (Page Write-Through)
Bit 2:     User - 1 = user accessible, 0 = supervisor only
Bit 1:     Writable - 1 = read/write, 0 = read-only
Bit 0:     Present - 1 = valid entry
```

### 3.4 MMU Control Registers

All MMU registers are memory-mapped in the system register space:

| Address | Register | Description |
|---------|----------|-------------|
| $FFFFF000 | MMUCR | MMU Control Register |
| $FFFFF004 | TLBINVAL | TLB Invalidate (write VA to flush entry) |
| $FFFFF008 | ASID | Address Space ID (8 bits used) |
| $FFFFF00C | ASIDINVAL | Invalidate by ASID |
| $FFFFF010 | FAULTVA | Faulting Virtual Address (read-only) |
| $FFFFF014 | PTBR_LO | Page Table Base Register, low 32 bits |
| $FFFFF018 | PTBR_HI | Page Table Base Register, high 33 bits |
| $FFFFF01C | TLBFLUSH | Write 1 to flush entire TLB |

#### MMUCR Bit Layout

| Bit | Name | Description |
|-----|------|-------------|
| 0 | PG | Paging enable (1 = enabled) |
| 1 | WP | Write-protect supervisor pages |
| 2 | NX | No-execute bit enabled |
| 4:3 | FTYPE | Last fault type (read-only) |

Fault type encoding:
- `00` = Page not present
- `01` = Write to read-only page
- `10` = User access to supervisor page
- `11` = Execute on non-executable page

### 3.5 TLB Management

The 16-entry TLB is fully associative with ASID tagging:

```asm
; Flush single TLB entry by VA
tlb_invalidate_page:
    STA TLBINVAL            ; Write VA to invalidate register
    RTS

; Flush all TLB entries
tlb_flush_all:
    LDA #1
    STA TLBFLUSH
    RTS

; Flush entries for current ASID only
tlb_flush_asid:
    LDA #1
    STA ASIDINVAL
    RTS
```

### 3.6 MMIO Bypass and System Register Addressing

The system register space bypasses MMU translation, allowing the kernel to access
MMU registers, timer, and other system registers even when paging is enabled.

System registers are accessible at **two address ranges**:

| Mode | Address Range | Example |
|------|---------------|---------|
| 8/16-bit (emulation) | `$F000-$F0FF` | `STA $F000` (MMUCR) |
| 32-bit (native) | `$FFFFF000-$FFFFF0FF` | `STA $FFFFF000` (MMUCR) |

Both ranges map to the same register set. The 16-bit alias `$F0xx` exists for
compatibility with 65816 emulation mode code that uses 16-bit absolute addressing.
In the VHDL, this is detected by checking `mem_addr_virt(15 downto 8) = x"F0"`:

```vhdl
-- From m65832_core.vhd
mmu_bypass <= '1' when mem_addr_virt(15 downto 8) = x"F0" else '0';
```

Both address ranges bypass the MMU -- no page table entries are needed for system
register access.

### 3.7 Enabling the MMU

```asm
enable_paging:
    ; Ensure we're in supervisor mode
    ; Set up identity mapping for current code first!
    
    ; Set page table base
    LDA ptbr_low
    STA PTBR_LO
    LDA ptbr_high
    STA PTBR_HI
    
    ; Set ASID
    LDA #0
    STA ASID
    
    ; Enable paging
    LDA #$01                ; PG=1
    STA MMUCR
    
    ; Now running with paging enabled
    RTS
```

---

## 4. Interrupts and Exceptions

### 4.1 Exception Vectors

> **RTL Reference:** Vector constants in `m65832_pkg.vhd`

#### Native Mode Vectors

| Address | Exception | Description |
|---------|-----------|-------------|
| $0000FFE4 | COP | Coprocessor instruction |
| $0000FFE6 | BRK | Software breakpoint |
| $0000FFE8 | ABORT | Abort signal |
| $0000FFEA | NMI | Non-maskable interrupt |
| $0000FFEE | IRQ | Maskable interrupt |

#### M65832 Extended Vectors

| Address | Exception | Description |
|---------|-----------|-------------|
| $0000FFD0 | Page Fault | MMU page fault |
| $0000FFD4 | SYSCALL | System call (TRAP base) |
| $0000FFF8 | Illegal | Invalid instruction |

TRAP uses a vector table: `handler = SYSCALL_BASE + (trap_code × 4)`

#### Emulation Mode Vectors (VBR-relative)

| Offset | Exception |
|--------|-----------|
| $FFF4 | COP |
| $FFF8 | ABORT |
| $FFFA | NMI |
| $FFFC | RESET |
| $FFFE | IRQ/BRK |

### 4.2 Exception Processing

When an exception occurs:

1. **Save state:** Push PC (32-bit), Push P (including extended bits)
2. **Set flags:** S=1 (supervisor), I=1 (disable IRQ)
3. **Read vector:** From the exception vector table in **physical memory**
4. **Load PC:** From the vector
5. **Continue execution:** In supervisor mode at the handler address

```asm
; Exception entry (automatic, done by hardware)
; Stack after exception:
;   [SP+0]  P_low (standard flags)
;   [SP+1]  P_high (extended flags: K,R,S,rsv,W1,W0,0,0)
;   [SP+2]  PC byte 0
;   [SP+3]  PC byte 1
;   [SP+4]  PC byte 2
;   [SP+5]  PC byte 3
```

**Important: All exceptions are vectored and continue execution.** Page faults,
illegal instruction traps, and privilege violations are NOT fatal -- they vector to
their respective handler routines (just like BRK and TRAP). The handler runs in
supervisor mode and returns via RTI.

**Important: Exception vector reads bypass the MMU.** The vector table at `$FFD0-$FFFF`
is read from physical memory, not virtual memory. This is critical because exceptions
can occur when the MMU is enabled, and the vector table page may not have a mapping.
In the VHDL, vector fetches are performed in the exception state machine which does not
go through the normal MMU translation pipeline.

For page faults specifically:
- The faulting virtual address is latched in FAULTVA (`$FFFFF010`)
- The fault type is written to MMUCR bits 4:3
- The handler reads FAULTVA and MMUCR to determine the fault cause
- The handler can fix the page tables (e.g., map the page) and RTI to retry

### 4.3 Return from Exception

```asm
; RTI restores full processor state
exception_return:
    ; ... handler code ...
    RTI                     ; Pull P, Pull PC, return to previous mode
```

RTI automatically restores the privilege level from the saved P register.

### 4.4 Timer Interrupt

The M65832 includes a system timer:

| Address | Register | Description |
|---------|----------|-------------|
| $FFFFF040 | TIMER_CTRL | Timer control |
| $FFFFF044 | TIMER_CMP | Compare value |
| $FFFFF048 | TIMER_COUNT | Current count |

#### TIMER_CTRL Bits

| Bit | Name | Description |
|-----|------|-------------|
| 0 | EN | Timer enable |
| 1 | IE | Interrupt enable |
| 2 | IF | Interrupt flag (write 1 to clear) |

```asm
; Initialize timer for 10ms interrupt at 50MHz
init_timer:
    LDA #0
    STA TIMER_CTRL          ; Disable during setup
    LDA #500000             ; 50MHz / 100 = 10ms
    STA TIMER_CMP
    LDA #$03                ; EN=1, IE=1
    STA TIMER_CTRL
    RTS
```

---

## 5. Context Switching

### 5.1 Task State Structure

```c
// Recommended task state structure
struct m65832_task_state {
    // Core registers
    uint32_t a;             // Accumulator
    uint32_t x;             // Index X
    uint32_t y;             // Index Y
    uint32_t pc;            // Program counter
    uint32_t sp;            // Stack pointer
    uint16_t p;             // Status register (14 bits used)
    
    // Base registers
    uint32_t d;             // Direct page base
    uint32_t b;             // Absolute base
    uint32_t vbr;           // Virtual 6502 base (E=1 processes)
    
    // Register window (if R=1)
    uint32_t r[64];         // R0-R63
    
    // MMU state
    uint64_t ptbr;          // Page table base (65-bit, high bit usually 0)
    uint8_t  asid;          // Address space ID
    
    // For multiply/divide results
    uint32_t t;             // Temp register
};
```

### 5.2 Save Context

```asm
; save_context - Save current process state
; Input: X = pointer to task_state structure
;
; Note: Called from interrupt handler, so some state
; is already on the interrupt stack
save_context:
    ; A, X, Y should be saved first (A often on stack from ISR entry)
    ; Get saved A from interrupt stack frame
    LDA saved_a_from_isr
    STA TASK_A,X
    
    ; Save current X (caller passed task pointer, save it first)
    PHX
    TYA
    PLX                     ; X = task pointer again
    STA TASK_Y,X
    
    ; The real X was passed in, we used it as pointer
    ; Need to get original X from ISR save area
    LDA saved_x_from_isr
    STA TASK_X,X
    
    ; Save stack pointer (user's SP, not current kernel SP)
    LDA user_sp_save        ; Captured on IRQ entry
    STA TASK_SP,X
    
    ; Save base registers
    TDA                     ; A = D
    STA TASK_D,X
    TBA                     ; A = B
    STA TASK_B,X
    
    ; Save VBR (only meaningful for E=1 processes)
    ; Use extended instruction
    LDA VBR_SAVE            ; Assumes VBR was captured
    STA TASK_VBR,X
    
    ; Save status register (from interrupt stack)
    LDA saved_p_from_isr    ; Low byte
    STA TASK_P,X
    LDA saved_p_from_isr+1  ; High byte (extended flags)
    STA TASK_P+1,X
    
    ; Save PC (from interrupt stack)
    LDA saved_pc_from_isr
    STA TASK_PC,X
    LDA saved_pc_from_isr+2
    STA TASK_PC+2,X
    
    ; If process uses register window, save R0-R63
    LDA TASK_P+1,X
    AND #$10                ; Check R bit (bit 12 = bit 4 of high byte)
    BEQ skip_regwin_save
    
    ; Save register window
    PHX                     ; Preserve task pointer
    RSET                    ; Ensure R=1 for reading
    LDY #0
save_regs_loop:
    LDA $00,Y               ; Read from register window
    PLX
    STA TASK_R0,X           ; Store to task struct
    PHX
    INX : INX : INX : INX   ; task pointer += 4
    INY : INY : INY : INY   ; reg offset += 4
    CPY #256                ; 64 regs × 4 bytes
    BNE save_regs_loop
    PLX
    
skip_regwin_save:
    RTS
```

### 5.3 Restore Context

```asm
; restore_context - Restore process state and return to it
; Input: X = pointer to task_state structure
restore_context:
    ; Switch MMU context first (before accessing user memory)
    LDA TASK_PTBR,X
    STA PTBR_LO
    LDA TASK_PTBR+4,X
    STA PTBR_HI
    LDA TASK_ASID,X
    STA ASID
    
    ; If process uses register window, restore R0-R63
    LDA TASK_P+1,X
    AND #$10                ; Check R bit
    BEQ skip_regwin_restore
    
    RSET                    ; Enable register window
    PHX
    LDY #0
restore_regs_loop:
    PLX
    LDA TASK_R0,X           ; Load from task struct
    PHX
    STA $00,Y               ; Write to register window
    INX : INX : INX : INX
    INY : INY : INY : INY
    CPY #256
    BNE restore_regs_loop
    PLX
    
skip_regwin_restore:
    ; Restore base registers
    LDA TASK_D,X
    TAD                     ; D = A
    LDA TASK_B,X
    TAB                     ; B = A
    LDA TASK_VBR,X
    ; Store to VBR (supervisor only)
    STA vbr_temp
    ; Use SVBR instruction
    
    ; Build return frame on stack
    ; For RTI: PC (4 bytes), P (2 bytes)
    
    ; Push PC
    LDA TASK_PC+2,X
    PHA
    LDA TASK_PC,X
    PHA
    
    ; Push P (extended format)
    LDA TASK_P+1,X          ; Extended flags
    PHA
    LDA TASK_P,X            ; Standard flags
    PHA
    
    ; Restore working registers
    LDA TASK_SP,X
    ; Complex: need to switch to user stack
    ; Store for later use after RTI prep
    STA user_sp_temp
    
    LDA TASK_Y,X
    TAY
    LDA TASK_A,X
    PHA                     ; Save A for last
    LDA TASK_X,X
    TAX                     ; X now has user value
    PLA                     ; A now has user value
    
    ; Final step: restore user SP and RTI
    ; Note: actual SP switch is complex and depends on 
    ; whether user stack is in same address space
    
    RTI                     ; Return to user mode
```

### 5.4 The Magic: RTI Restores Everything

The key insight is that **RTI pulls the complete P register**, including:
- W1:W0 (width mode - determines emu/native-16/32-bit; E is derived from W=00)
- S flag (privilege level - returns to user mode if saved S=0)
- R flag (register window enable)
- M, X flags (accumulator/index widths for native-16 mode)

This means a single RTI instruction:
1. Restores the processor mode (6502/65816/32-bit)
2. Restores the privilege level (user/supervisor)
3. Restores the program counter
4. Continues execution as if nothing happened

---

## 6. Mixed-Mode Multitasking

### 6.1 Mode Summary

The M65832 can run processes in three modes simultaneously:

| Mode | W1:W0 | M/X | Description |
|------|-------|-----|-------------|
| 6502 Emulation | 00 | ignored | 8-bit, 64KB via VBR (E derived) |
| 65816 Native-16 | 01 | active | M/X control widths |
| M65832 Native-32 | 11 | ignored | Full 32-bit |

The kernel always runs in Native-32 supervisor mode.

### 6.2 6502 Process Setup

```asm
; Set up a 6502 emulation process
setup_6502_process:
    ; Allocate task structure
    JSR alloc_task
    TAX                     ; X = task pointer
    
    ; Set W=00 in saved P (emulation mode, E derived from W=00)
    ; Extended P byte: K R S rsv W1 W0 0 0
    ;                  0 0 0  0   0  0 0 0 = $00
    LDA #$00
    STA TASK_P+1,X          ; Extended P (W=00 = emulation)
    LDA #$00                ; Standard flags (M/X ignored in emu mode)
    STA TASK_P,X
    
    ; Set VBR to process's 64KB window
    LDA process_base        ; e.g., $10000000
    STA TASK_VBR,X
    
    ; Set initial PC (6502 reset vector within window)
    ; The 6502 code thinks it's at $C000, but actual VA is VBR+$C000
    LDA #$C000
    STA TASK_PC,X
    STZ TASK_PC+2,X
    
    ; Set up stack at $01FF (6502 convention)
    LDA #$01FF
    STA TASK_SP,X
    STZ TASK_SP+2,X
    
    ; Set up page tables for VBR..VBR+$FFFF
    JSR setup_6502_pages
    
    RTS
```

**6502 Memory Layout:**
```
VBR + $0000-$00FF  → Zero Page (read/write)
VBR + $0100-$01FF  → Stack (read/write)
VBR + $0200-$BFFF  → RAM (read/write)
VBR + $C000-$FFFF  → ROM (read-only, or RAM)

All mapped via page tables to physical memory
```

### 6.3 65816 Native-16 Process Setup

```asm
setup_65816_process:
    JSR alloc_task
    TAX
    
    ; W=01 (native-16 mode)
    ; Extended P byte: K=0 R=0 S=0 rsv=0 W1=0 W0=1 0 0 = $01
    LDA #$01
    STA TASK_P+1,X
    LDA #$30                ; Standard flags: M=1, X=1 (16-bit widths)
    STA TASK_P,X
    
    ; Set B to base address
    LDA process_base
    STA TASK_B,X
    
    ; D for direct page
    LDA #$0000
    STA TASK_D,X
    
    RTS
```

### 6.4 Native-32 Process Setup

```asm
setup_32bit_process:
    JSR alloc_task
    TAX
    
    ; W=11, R=1 (32-bit with register window)
    ; Extended P byte: K=0 R=1 S=0 rsv=0 W1=1 W0=1 0 0 = $13
    LDA #$13
    STA TASK_P+1,X
    LDA #$00                ; Standard flags clear
    STA TASK_P,X
    
    ; B=0 for flat addressing
    STZ TASK_B,X
    STZ TASK_B+2,X
    
    ; D points to process data area (register window overlays this)
    LDA user_data_base
    STA TASK_D,X
    
    RTS
```

### 6.5 Example: Three Processes Running

```
┌─────────────────────────────────────────────────────────────────┐
│                        M65832 System                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Process 1: C64 Game            Process 2: SNES Game            │
│  ┌─────────────────────┐       ┌─────────────────────┐          │
│  │ Mode: W=00 (6502)   │       │ Mode: W=01, M/X     │          │
│  │ VBR: $10000000      │       │ B: $20000000        │          │
│  │ Address: 64KB       │       │ Address: 16MB       │          │
│  │ Running: Pac-Man    │       │ Running: SMW        │          │
│  └─────────────────────┘       └─────────────────────┘          │
│                                                                 │
│  Process 3: Linux Shell         Kernel                          │
│  ┌─────────────────────┐       ┌─────────────────────┐          │
│  │ Mode: W=11          │       │ Mode: W=11           │          │
│  │ R=1 (reg window)    │       │ S=1 (supervisor)    │          │
│  │ Address: Full 4GB   │       │ Manages all above   │          │
│  │ Running: bash       │       │                     │          │
│  └─────────────────────┘       └─────────────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.6 Scheduler Timeline

```
Time    Active Process    Mode        Notes
─────────────────────────────────────────────────────────
0ms     Process 1         W=00 6502    Playing Pac-Man
10ms    [Timer IRQ]       Supervisor   Scheduler runs
10ms    Process 3         W=11 32-bit  bash waiting
20ms    [Timer IRQ]       Supervisor   Scheduler runs
20ms    Process 2         W=01 16-bit  SMW running
30ms    [Timer IRQ]       Supervisor   Scheduler runs
30ms    Process 1         W=00 6502    Back to Pac-Man
...
```

---

## 7. System Calls

### 7.1 TRAP Instruction

User programs invoke kernel services via the TRAP instruction:

```asm
; TRAP #imm8 - System call
; Vector address = $0000FFD4 + (imm8 × 4)
```

### 7.2 System Call Convention

```
Input:
    R0 ($00) = syscall number
    R1 ($04) = arg1
    R2 ($08) = arg2
    R3 ($0C) = arg3
    R4 ($10) = arg4
    R5 ($14) = arg5
    R6 ($18) = arg6

Output:
    R0 ($00) = return value (or -errno on error)

Invocation:
    TRAP #0
```

### 7.3 System Call Handler

```asm
; TRAP #0 handler
syscall_handler:
    ; Already in supervisor mode, interrupts disabled
    
    ; Save user registers to kernel stack
    PHA
    PHX
    PHY
    PHD
    PHB
    
    ; Get syscall number from user's R0
    ; Note: User's D points to their register window
    ; We need to access their memory, which may require
    ; saving and setting up our own D
    
    LDA user_d_saved        ; Get user's D register
    TAD                     ; D = user's register base
    RSET                    ; Enable register window access
    
    LDA $00                 ; R0 = syscall number
    
    ; Bounds check
    CMP #NR_SYSCALLS
    BCS bad_syscall
    
    ; Look up handler in syscall table
    ASL : ASL               ; × 4 for pointer size
    TAX
    LDA syscall_table,X
    STA handler_ptr
    
    ; Call handler
    JSR (handler_ptr)
    
    ; Return value now in A, store back to user's R0
    STA $00
    
syscall_return:
    ; Restore kernel context
    PLB
    PLD
    PLY
    PLX
    PLA
    RTI                     ; Return to user mode

bad_syscall:
    LDA #-ENOSYS            ; -38 typically
    STA $00
    BRA syscall_return
```

---

## 8. Inter-Process Communication

### 8.1 6502 Process Calling Kernel Services

6502 code can use BRK or COP to request services:

```asm
; In 6502 process
    LDA #$01                ; Service: read sector
    STA $FE                 ; Service code in ZP
    LDA #$00
    STA $FF                 ; Sector number
    BRK                     ; Trap to kernel
    ; Kernel reads sector, puts data at $0200
    ; Returns here when done
```

### 8.2 Shared Memory Between Modes

Different-mode processes can share memory via page tables:

```c
// Kernel sets up shared page
void setup_shared_memory(task_t *proc_6502, task_t *proc_32bit) {
    // Map same physical page into both address spaces
    physical_addr_t shared = alloc_physical_page();
    
    // For 6502 process: map at VBR + $0800
    map_page(proc_6502->pgd, proc_6502->vbr + 0x0800, 
             shared, PROT_RW | PROT_USER);
    
    // For 32-bit process: map at $50000000
    map_page(proc_32bit->pgd, 0x50000000, 
             shared, PROT_RW | PROT_USER);
}
```

---

## 9. Performance Considerations

### 9.1 Context Switch Cost

| From Mode | To Mode | Approx. Cycles | Notes |
|-----------|---------|----------------|-------|
| 32-bit | 32-bit | ~50 | Baseline |
| 32-bit | 6502 | ~55 | +VBR write |
| 6502 | 32-bit | ~55 | +VBR read |
| 6502 | 6502 | ~60 | +VBR swap |
| Any | Any w/R=1 | ~300 | +R0-R63 save/restore |

### 9.2 Lazy Register Window Save

Only save/restore R0-R63 if actually used:

```asm
context_switch:
    ; Check if outgoing process dirtied registers
    LDA current_task
    TAX
    LDA TASK_FLAGS,X
    AND #FLAG_REGS_DIRTY
    BEQ skip_save_regs
    
    JSR save_register_window
    
skip_save_regs:
    ; Mark incoming process as not-dirty initially
    ; First write to DP will set flag
```

### 9.3 ASID Optimization

With 8-bit ASIDs (256 address spaces):
- Switching between processes with different ASIDs: **no TLB flush needed**
- TLB entries are tagged with ASID
- Only flush when ASID pool exhausted and must be recycled

```asm
; Fast context switch with different ASID
fast_switch:
    ; Just change ASID register - no TLB flush!
    LDA new_task_asid
    STA ASID
    ; TLB automatically filters by new ASID
```

---

## 10. Summary

The M65832 provides comprehensive system programming support:

| Feature | Support |
|---------|---------|
| User/Supervisor modes | ✅ S flag in P register |
| Virtual memory | ✅ 2-level page tables, 4KB pages |
| TLB with ASID | ✅ 16-entry, 8-bit ASID |
| Exception handling | ✅ Vectored exceptions with full state save |
| System calls | ✅ TRAP instruction with vector table |
| Timer interrupt | ✅ Programmable system timer |
| Mode switching | ✅ RTI restores full mode state |
| Mixed-mode multitasking | ✅ 6502/65816/32-bit processes |

This enables:
- **Full Linux support:** All required OS primitives
- **Classic system emulation:** Run original 6502/65816 code alongside modern apps
- **Efficient context switching:** ASID tagging minimizes TLB flushes

---

*System Programming Guide - Verified against RTL implementation*  
*Last Updated: January 2026*
