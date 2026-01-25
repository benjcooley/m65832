# M65832 Linux Porting Guide

**Requirements and Implementation Notes for Linux Kernel Support**

---

## 1. Linux Hardware Requirements

Linux requires specific hardware features. Here's how the M65832 addresses each:

| Requirement | Linux Needs | M65832 Provides |
|-------------|-------------|-----------------|
| Virtual Memory | Page-based MMU | ✅ 2-level page tables, 4KB pages |
| User/Kernel Split | Privilege separation | ✅ S flag (Supervisor/User) |
| Context Switch | Save/restore all state | ✅ Full register save, RTI restores mode |
| System Calls | Trap to kernel | ✅ TRAP instruction with vector table |
| Interrupts | IRQ, timer | ✅ IRQ/NMI vectors, programmable timer |
| Atomics | Lock-free primitives | ✅ CAS, LLI/SCI, FENCE |
| Byte Order | Little-endian preferred | ✅ Native little-endian |
| Address Space | 32-bit minimum | ✅ 32-bit VA, 65-bit PA |

---

## 2. Memory Management

### 2.1 Virtual Memory Layout

Suggested Linux memory map:

```
0x0000_0000 - 0x0000_FFFF   Reserved (6502 compatibility zone)
0x0001_0000 - 0x7FFF_FFFF   User space (~2GB)
    0x0001_0000             User code start
    0x1000_0000             User heap start (brk)
    0x4000_0000             Shared libraries (mmap)
    0x7FFF_0000             User stack (grows down)
    
0x8000_0000 - 0xBFFF_FFFF   Kernel direct-mapped (~1GB)
    0x8000_0000             Kernel code/data
    0xA000_0000             Kernel modules
    0xB000_0000             Device I/O (uncached)
    
0xC000_0000 - 0xFFFF_EFFF   Kernel vmalloc/ioremap
0xFFFF_F000 - 0xFFFF_FFFF   Exception vectors, system registers
```

### 2.2 System MMIO Window

MMU/system registers are at fixed addresses in the `$FFFFF0xx` range:

| Address | Register | Description |
|---------|----------|-------------|
| $FFFFF000 | MMUCR | MMU Control Register |
| $FFFFF004 | TLBINVAL | TLB Invalidate (write VA) |
| $FFFFF008 | ASID | Address Space ID (8 bits) |
| $FFFFF00C | ASIDINVAL | Invalidate by ASID |
| $FFFFF010 | FAULTVA | Faulting Virtual Address |
| $FFFFF014 | PTBR_LO | Page Table Base, low 32 bits |
| $FFFFF018 | PTBR_HI | Page Table Base, high 33 bits |
| $FFFFF01C | TLBFLUSH | Write 1 to flush entire TLB |
| $FFFFF040 | TIMER_CTRL | Timer control register |
| $FFFFF044 | TIMER_CMP | Timer compare value |
| $FFFFF048 | TIMER_COUNT | Current timer count |

> **RTL Reference:** Constants defined in `m65832_pkg.vhd`

These addresses bypass MMU translation (detected by hardware) so the kernel can always access MMU control registers even when paging is enabled.

### 2.3 Page Table Structure

The M65832 uses a 2-level page table with 10+10+12 bit split:

```c
// Level 1 Page Directory (1024 entries × 8 bytes = 8KB)
typedef struct {
    uint64_t entries[1024];
} pgd_t;

// Level 2 Page Table (1024 entries × 8 bytes = 8KB)
typedef struct {
    uint64_t entries[1024];
} pte_t;

// Page Table Entry format (64-bit)
//
// Bit 63:    NX (No Execute) - set to disable execution
// Bits 62:12: Physical Page Number (52 bits)
//            Note: For full 65-bit PA, bit 64 stored in PTBR_HI
// Bit 11:    Global - not flushed on ASID change
// Bit 10:    Dirty - set by hardware on write
// Bit 9:     Accessed - set by hardware on access
// Bits 8:5:  Reserved
// Bit 4:     PCD - Page Cache Disable
// Bit 3:     PWT - Page Write-Through
// Bit 2:     User - 1 = user accessible
// Bit 1:     Writable - 1 = read/write
// Bit 0:     Present - 1 = valid entry

#define PTE_PRESENT     (1ULL << 0)
#define PTE_WRITABLE    (1ULL << 1)
#define PTE_USER        (1ULL << 2)
#define PTE_PWT         (1ULL << 3)
#define PTE_PCD         (1ULL << 4)
#define PTE_ACCESSED    (1ULL << 9)
#define PTE_DIRTY       (1ULL << 10)
#define PTE_GLOBAL      (1ULL << 11)
#define PTE_NX          (1ULL << 63)

#define PTE_PPN_SHIFT   12
#define PTE_PPN_MASK    0x000FFFFFFFFFF000ULL
```

### 2.4 TLB Management

The MMU provides a 16-entry fully-associative TLB with 8-bit ASID tagging:

```asm
; Invalidate single TLB entry by virtual address
; Input: A = virtual address to invalidate
tlb_invalidate_page:
    STA $FFFFF004           ; TLBINVAL register
    RTS

; Invalidate entire TLB
tlb_flush_all:
    LDA #1
    STA $FFFFF01C           ; TLBFLUSH register
    RTS
    
; Invalidate all entries for current ASID
tlb_invalidate_asid:
    LDA #1
    STA $FFFFF00C           ; ASIDINVAL register
    RTS

; Switch to new ASID (context switch optimization)
; No TLB flush needed if ASID differs
switch_asid:
    ; A = new ASID
    STA $FFFFF008           ; ASID register
    ; TLB entries tagged with old ASID are automatically ignored
    RTS
```

### 2.5 MMUCR Bit Layout

| Bit | Name | Description |
|-----|------|-------------|
| 0 | PG | Paging enable |
| 1 | WP | Write-protect in supervisor mode |
| 2 | NX | No-execute bit enforcement |
| 4:3 | FTYPE | Last fault type (read-only) |

Fault type encoding:
- `00` = Page not present
- `01` = Write to read-only page
- `10` = User access to supervisor page
- `11` = Execute on non-executable page

### 2.6 Page Fault Handling

```asm
; Page fault handler (vectored from $0000FFD0)
page_fault_handler:
    ; Save all registers
    PHA
    PHX
    PHY
    PHD
    PHB
    
    ; Get fault information from MMIO registers
    LDA $FFFFF010           ; FAULTVA - faulting address
    STA fault_address
    LDA $FFFFF000           ; MMUCR - contains fault type
    AND #$18                ; Extract FTYPE bits [4:3]
    LSR
    LSR
    LSR
    STA fault_type          ; 0=not present, 1=write, 2=user, 3=exec
    
    ; Call C handler
    ; void do_page_fault(uint32_t fault_address, int fault_type);
    LDA fault_address
    STA $00                 ; R0 = address
    LDA fault_type
    STA $04                 ; R1 = type
    JSR do_page_fault
    
    ; Restore and return
    PLB
    PLD
    PLY
    PLX
    PLA
    RTI
```

---

## 3. Process Management

### 3.1 Task State Structure

```c
// Kernel task_struct register state
struct m65832_regs {
    uint32_t a;             // Accumulator
    uint32_t x;             // Index X
    uint32_t y;             // Index Y
    uint32_t sp;            // Stack pointer
    uint32_t pc;            // Program counter
    uint32_t d;             // Direct page base
    uint32_t b;             // Absolute base
    uint32_t t;             // Temp register (MUL/DIV high word)
    uint16_t p;             // Status register (14 bits used)
    uint32_t r[64];         // Register window R0-R63 (if R=1)
};

struct task_struct {
    struct m65832_regs regs;
    uint32_t asid;          // Address space ID (8 bits used)
    pgd_t *pgd;             // Page directory physical address
    // ... other Linux task fields
};
```

### 3.2 Status Register Format

The 14-bit status register is stored as 16 bits in memory:

```
Byte 0 (low): C Z I D X0 X1 M0 M1 (standard 65816-like)
Byte 1 (high): V N E S R K -- -- (extended flags)

Internal mapping:
  Bit 0:  C  (Carry)
  Bit 1:  Z  (Zero)
  Bit 2:  I  (IRQ disable)
  Bit 3:  D  (Decimal mode)
  Bit 4:  X0 (Index width bit 0)
  Bit 5:  X1 (Index width bit 1)
  Bit 6:  M0 (Accumulator width bit 0)
  Bit 7:  M1 (Accumulator width bit 1)
  Bit 8:  V  (Overflow)
  Bit 9:  N  (Negative)
  Bit 10: E  (Emulation mode)
  Bit 11: S  (Supervisor mode)
  Bit 12: R  (Register window enable)
  Bit 13: K  (Compatibility mode)
```

### 3.3 Context Switch

```asm
; switch_to(prev, next)
; R0 = prev task pointer, R1 = next task pointer
switch_to:
    ; Save current task state
    LDA $00                 ; R0 = prev pointer
    TAX
    
    ; Save registers
    TYA
    STA TASK_Y,X
    TXA
    PHA                     ; Save prev pointer
    TSX                     ; Get stack pointer
    TXA
    PLX                     ; Restore prev pointer
    STA TASK_SP,X
    
    ; Save callee-saved registers R16-R23
    LDA $40                 ; R16
    STA TASK_R16,X
    LDA $44                 ; R17
    STA TASK_R17,X
    ; ... continue for R18-R23
    
    ; Switch page tables
    LDA $04                 ; R1 = next pointer
    TAX
    LDA TASK_PGD,X
    STA $FFFFF014           ; PTBR_LO
    LDA TASK_ASID,X
    STA $FFFFF008           ; ASID
    
    ; Restore callee-saved registers
    LDA TASK_R16,X
    STA $40
    ; ...
    
    ; Restore stack pointer and return
    LDA TASK_SP,X
    TAX
    TXS
    RTS
```

### 3.4 Fork Implementation

```asm
; sys_fork - create child process
sys_fork:
    ; Allocate new task_struct
    JSR alloc_task_struct
    STA $00                 ; R0 = child task
    
    ; Copy parent page tables (copy-on-write)
    LDA current_task
    STA $04                 ; R1 = parent
    JSR copy_page_tables
    
    ; Copy register state
    JSR copy_regs
    
    ; Set child return value to 0 (fork returns 0 to child)
    LDA $00
    TAX
    STZ TASK_A,X            ; Child sees A = 0
    
    ; Get child PID as parent return value
    LDA TASK_PID,X
    STA $00                 ; Return PID in R0
    
    ; Add child to scheduler run queue
    JSR sched_add_task
    
    RTS
```

---

## 4. System Calls

### 4.1 System Call Convention

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

### 4.2 System Call Handler

```asm
; TRAP #0 handler - entry point at $0000FFD4
syscall_handler:
    ; CPU automatically set S=1 (supervisor) and I=1 (IRQ disabled)
    ; User state was pushed to stack
    
    ; Save additional registers to kernel stack
    PHA
    PHX
    PHY
    PHD
    PHB
    
    ; Set up kernel direct page for register window access
    SD #kernel_data_base
    RSET
    
    ; Access user's register window to get syscall args
    ; Note: Need to map user's DP area or use saved values
    
    ; Get syscall number
    LDA user_r0_saved
    
    ; Bounds check
    CMP #NR_SYSCALLS
    BCS bad_syscall
    
    ; Look up handler in syscall table
    ASL                     ; × 4 for pointer size
    ASL
    TAX
    LDA syscall_table,X
    STA handler_addr
    
    ; Call handler (arguments in R1-R6)
    JSR (handler_addr)
    
    ; Return value in A, copy to user's R0
    STA user_r0_return
    
syscall_return:
    PLB
    PLD
    PLY
    PLX
    PLA
    RTI                     ; Return to user mode
    
bad_syscall:
    LDA #-ENOSYS            ; -38 typically
    STA user_r0_return
    BRA syscall_return
```

### 4.3 Example System Calls

```asm
; sys_write(fd, buf, count) - syscall #1
; R1 = fd, R2 = buf, R3 = count
sys_write:
    LDA $04                 ; R1 = fd
    STA fd_temp
    LDA $08                 ; R2 = buf (user pointer)
    STA buf_temp
    LDA $0C                 ; R3 = count
    STA count_temp
    
    ; Validate user buffer is readable
    LDA buf_temp
    LDX count_temp
    JSR verify_user_read    ; Returns C=1 if valid
    BCC write_fault
    
    ; Get file struct from fd
    LDA fd_temp
    JSR fd_to_file
    BCC write_bad_fd
    
    ; Call file->write() method
    ; ... implementation
    RTS
    
write_fault:
    LDA #-EFAULT
    RTS
    
write_bad_fd:
    LDA #-EBADF
    RTS
```

### 4.4 FP Trap ABI (Software Emulation)

Reserved FP opcodes trap to software handlers. The trap vector is computed as:

```
handler_address = TRAP_BASE + (fp_opcode * 4)
```

**Inputs (on trap entry):**
- F0/F1/F2 contain FP operands
- A contains last integer operand (for I2F)
- P flags reflect pre-trap state

**Outputs (before RTI):**
- F0 holds result for FP ops returning float/double
- A holds result for F2I
- Flags set per FP operation semantics (Z/N/V/C)

**Notes:**
- Trap handler should preserve non-argument registers
- Return via RTI
- For R=1, software reads F0-F2 from register pairs in DP

---

## 5. Interrupt Handling

### 5.1 Exception Vectors

> **RTL Reference:** Vector addresses in `m65832_pkg.vhd`

```asm
; Exception vector addresses (native mode)
VEC_COP_N    = $0000FFE4
VEC_BRK_N    = $0000FFE6
VEC_ABORT_N  = $0000FFE8
VEC_NMI_N    = $0000FFEA
VEC_IRQ_N    = $0000FFEE

; M65832 extended vectors
VEC_PGFAULT  = $0000FFD0
VEC_SYSCALL  = $0000FFD4    ; TRAP base
VEC_ILLEGAL  = $0000FFF8

; Emulation mode vectors (VBR-relative)
VEC_COP_E    = $FFF4
VEC_ABORT_E  = $FFF8
VEC_NMI_E    = $FFFA
VEC_RESET    = $FFFC
VEC_IRQ_E    = $FFFE
```

### 5.2 IRQ Handler

```asm
irq_handler:
    ; Save minimal state (more if needed)
    PHA
    PHX
    PHY
    
    ; Check interrupt sources
    ; Timer interrupt?
    LDA $FFFFF040           ; TIMER_CTRL
    AND #$04                ; IF bit
    BEQ check_external
    
    ; Clear timer interrupt
    LDA #$04
    STA $FFFFF040           ; Write 1 to IF to clear
    JSR timer_handler
    BRA irq_done
    
check_external:
    ; Read external interrupt controller (platform-specific)
    LDA INTC_PENDING
    BEQ irq_done
    
    ; Dispatch to handler
    ASL : ASL
    TAX
    LDA irq_handlers,X
    STA handler_ptr
    JSR (handler_ptr)
    
    ; Acknowledge interrupt
    STA INTC_ACK
    
irq_done:
    PLY
    PLX
    PLA
    RTI
```

### 5.3 Timer Interrupt (Preemptive Scheduling)

```asm
timer_handler:
    ; Increment jiffies counter
    INC jiffies
    BNE no_overflow
    INC jiffies+4
no_overflow:

    ; Decrement current task's time slice
    LDA current_task
    TAX
    DEC TASK_TIMESLICE,X
    BNE timer_done
    
    ; Time slice expired - set reschedule flag
    LDA #1
    STA need_resched
    
timer_done:
    RTS

; Called before returning to user mode
check_resched:
    LDA need_resched
    BEQ no_schedule
    STZ need_resched
    
    ; Find next runnable task
    JSR pick_next_task
    BEQ no_schedule         ; No other task
    
    ; Perform context switch
    STA $04                 ; R1 = next task
    LDA current_task
    STA $00                 ; R0 = prev task
    JSR switch_to
    
no_schedule:
    RTS
```

---

## 6. Atomic Operations for SMP

### 6.1 Spinlock Implementation

```asm
; spinlock_t is a 32-bit value: 0 = unlocked, 1 = locked

spin_lock:
    ; Input: A = pointer to lock
    STA $20                 ; Save lock address
    
spin_retry:
    LDX #0                  ; Expected: unlocked
    LDA #1                  ; Desired: locked
    CAS ($20)               ; Atomic compare-and-swap
    BNE spin_retry          ; Z=0 means failed, retry
    
    FENCE                   ; Memory barrier after acquiring lock
    RTS

spin_unlock:
    ; Input: A = pointer to lock
    STA $20
    FENCEW                  ; Write barrier before release
    STZ ($20)               ; Store 0 (unlocked)
    RTS

spin_trylock:
    ; Input: A = pointer to lock
    ; Output: Z=1 if acquired, Z=0 if failed
    STA $20
    LDX #0
    LDA #1
    CAS ($20)
    PHP                     ; Save Z flag
    BNE trylock_failed
    FENCE
trylock_failed:
    PLP                     ; Restore Z flag
    RTS
```

### 6.2 Load-Linked / Store-Conditional

```asm
; atomic_add using LL/SC
; Input: R0 = pointer, R1 = value to add
; Output: R0 = new value
atomic_add:
    LDA $00                 ; ptr
    STA $20
    
retry_add:
    LLI ($20)               ; Load linked: A = *ptr, set link
    CLC
    ADC $04                 ; A = A + value
    SCI ($20)               ; Store conditional
    BNE retry_add           ; Z=0 means link broken, retry
    
    STA $00                 ; Return new value in R0
    RTS

; atomic_cmpxchg
; Input: R0 = ptr, R1 = old, R2 = new
; Output: R0 = actual old value, Z=1 if swapped
atomic_cmpxchg:
    LDA $00
    STA $20                 ; ptr
    LDA $04
    TAX                     ; X = expected old
    LDA $08                 ; A = new value
    CAS ($20)               ; Atomic CAS
    STX $00                 ; Return actual old value in R0
    RTS                     ; Z flag indicates success
```

### 6.3 Read-Write Locks

```asm
; rwlock: 32-bit value
; Bits 30:0 = reader count
; Bit 31 = writer flag

read_lock:
    STA $20                 ; Save lock pointer
read_retry:
    LLI ($20)               ; Load current value
    BMI read_retry          ; If writer held (bit 31), spin
    INC                     ; Increment reader count
    SCI ($20)               ; Try to store
    BNE read_retry          ; Retry if failed
    FENCE
    RTS

read_unlock:
    STA $20
    FENCEW
read_dec:
    LLI ($20)
    DEC                     ; Decrement reader count
    SCI ($20)
    BNE read_dec
    RTS

write_lock:
    STA $20
write_retry:
    LDX #0                  ; Expected: 0 (no readers, no writer)
    LDA #$80000000          ; Desired: writer bit set
    CAS ($20)
    BNE write_retry
    FENCE
    RTS

write_unlock:
    STA $20
    FENCEW
    STZ ($20)               ; Clear all bits
    RTS
```

---

## 7. Device Drivers

### 7.1 Memory-Mapped I/O

```asm
; Read from device register (through MMU with PCD bit)
; Input: A = register offset from device base
mmio_read:
    CLC
    ADC device_base         ; A = base + offset
    STA $20
    FENCER                  ; Read barrier
    LDA ($20)               ; Load from device (uncached via PTE)
    RTS

; Write to device register
; Input: A = value, X = offset
mmio_write:
    PHA
    TXA
    CLC
    ADC device_base
    STA $20
    PLA
    STA ($20)
    FENCEW                  ; Write barrier
    RTS
```

### 7.2 Interrupt-Driven UART Example

```asm
; UART register offsets (platform-specific)
UART_DATA   = $0000
UART_STATUS = $0004
UART_CTRL   = $0008

uart_init:
    ; Set B to UART base for short addressing
    SB #$B0000000
    
    ; Enable RX interrupt
    LDA UART_CTRL
    ORA #$04                ; RX interrupt enable bit
    STA UART_CTRL
    
    ; Register IRQ handler
    LDA #UART_IRQ_NUM
    LDX #uart_irq_handler
    JSR register_irq
    RTS

uart_irq_handler:
    SB #$B0000000
    
    ; Check RX ready
    LDA UART_STATUS
    AND #$01
    BEQ uart_irq_done
    
    ; Read received byte
    LDA UART_DATA
    
    ; Add to circular buffer
    LDX rx_head
    STA rx_buffer,X
    INX
    CPX #RX_BUF_SIZE
    BCC no_wrap
    LDX #0
no_wrap:
    STX rx_head
    
    ; Wake up waiting processes
    JSR wake_up_rx_waiters
    
uart_irq_done:
    RTS
```

---

## 8. Boot Process

### 8.1 Bootloader Handoff

The bootloader should:

1. Load kernel image to physical memory
2. Set up initial identity-mapped page tables
3. Configure PTBR with page table address
4. Enable MMU
5. Jump to kernel entry point in supervisor mode

```asm
; Bootloader final stage
boot_to_kernel:
    ; Disable interrupts
    SEI
    
    ; Set up initial page table (identity map + kernel map)
    LDA #<boot_pgd
    STA $FFFFF014           ; PTBR_LO
    LDA #>boot_pgd
    STA $FFFFF018           ; PTBR_HI (usually 0)
    
    ; Set ASID 0
    STZ $FFFFF008
    
    ; Enable paging
    LDA #$01                ; PG=1
    STA $FFFFF000           ; MMUCR
    
    ; Jump to kernel (now at virtual address)
    WID JMP $80001000       ; kernel_entry
```

### 8.2 Kernel Early Init

```asm
; kernel_entry - first kernel code
kernel_entry:
    ; We're now in virtual address space with paging enabled
    
    ; Ensure we're in 32-bit supervisor mode
    CLC
    XCE                     ; E=0 (native mode)
    REP #$30                ; M=01, X=01
    REPE #$A0               ; M=10, X=10 (32-bit)
    
    ; Set up kernel stack
    LDX #$8FFFF000          ; Top of kernel stack
    TXS
    
    ; Set up kernel DP for locals
    SD #$80010000
    RSET                    ; Enable register window
    
    ; Clear BSS section
    JSR clear_bss
    
    ; Initialize memory management
    JSR mm_init
    
    ; Initialize interrupt handlers
    JSR irq_init
    
    ; Initialize scheduler
    JSR sched_init
    
    ; Create init process (PID 1)
    JSR kernel_thread_init
    
    ; Enable interrupts and start scheduler
    CLI
    JSR schedule
    
    ; Should never reach here
    STP
```

---

## 9. GCC/LLVM Toolchain Notes

### 9.1 Register Allocation

Suggested ABI register usage:

```
R0-R7    : Function arguments / return values (caller-saved)
R8-R15   : Caller-saved temporaries
R16-R23  : Callee-saved (preserved across calls)
R24-R27  : Reserved for kernel use
R28      : Global pointer (GP) - points to GOT
R29      : Frame pointer (FP)
R30      : Reserved (potential link register for leaf optimization)
R31      : Reserved

A, X, Y  : Compiler temporaries (caller-saved)
S        : Stack pointer (callee-saved, obviously)
D        : Direct page base (points to register window area)
B        : Data segment base (usually 0 for flat model)
```

### 9.2 Calling Convention

```c
// C function: int add(int a, int b)
// a in R0 ($00), b in R1 ($04), return in R0
```

```asm
add:
    RSET                    ; Ensure register window enabled
    LDA $00                 ; A = R0 (first arg)
    CLC
    ADC $04                 ; A += R1 (second arg)
    STA $00                 ; R0 = result
    RTS
```

### 9.3 Function Prologue/Epilogue

```asm
; Function with local variables and frame pointer
function:
    ; Prologue
    PHD                     ; Save caller's D
    TSX
    TXA
    SEC
    SBC #FRAME_SIZE         ; Allocate frame
    TAX
    TXS
    TAD                     ; D = frame base (locals via DP)
    
    ; Save callee-saved registers
    LDA $40                 ; R16
    PHA
    LDA $44                 ; R17
    PHA
    ; ...
    
    ; Function body
    ; Local variables accessed via DP ($00, $04, etc.)
    ; ...
    
    ; Epilogue
    PLA                     ; Restore R17
    STA $44
    PLA                     ; Restore R16
    STA $40
    
    TSX
    TXA
    CLC
    ADC #FRAME_SIZE
    TAX
    TXS                     ; Deallocate frame
    PLD                     ; Restore caller's D
    RTS
```

### 9.4 Variadic Functions

For functions with variable arguments:
- First 6 args in R1-R6 (R0 reserved for return)
- Additional args on stack
- Callee can use va_start/va_arg macros that walk the stack

---

## 10. Testing Checklist

Before Linux bring-up, verify:

**MMU Tests:**
- [ ] MMU enables/disables correctly
- [ ] Page table walk produces correct physical addresses
- [ ] Page faults trigger with correct fault address in FAULTVA
- [ ] TLB invalidation works (single entry and flush all)
- [ ] ASID tagging prevents cross-process TLB hits
- [ ] Global pages not flushed on ASID change

**Privilege Tests:**
- [ ] User/Supervisor mode separation works
- [ ] User cannot access supervisor pages (fault generated)
- [ ] TRAP enters supervisor mode correctly
- [ ] RTI returns to user mode correctly
- [ ] Privilege violations generate correct trap

**Interrupt Tests:**
- [ ] Timer interrupt fires at expected rate
- [ ] IRQ vectoring works correctly
- [ ] NMI is edge-triggered and non-maskable
- [ ] Nested interrupts work (if supported)

**Atomic Tests:**
- [ ] CAS is truly atomic under contention
- [ ] LLI/SCI pair works correctly
- [ ] LLI/SCI fails with intervening stores
- [ ] FENCE instructions order memory correctly

**Context Switch Tests:**
- [ ] All registers preserved across switch
- [ ] Page table switch works
- [ ] ASID switch without TLB flush works
- [ ] Mixed-mode processes switch correctly

**System Call Tests:**
- [ ] TRAP instruction vectors correctly
- [ ] Arguments passed in R0-R6
- [ ] Return value in R0
- [ ] RTI returns to user code

---

*End of Linux Porting Guide*  
*Verified against RTL implementation - January 2026*
