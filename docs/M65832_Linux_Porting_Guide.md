# M65832 Linux Porting Guide

**Requirements and Implementation Notes for Linux Kernel Support**

---

## 1. Linux Hardware Requirements

Linux requires specific hardware features. Here's how M65832 addresses each:

| Requirement | Linux Needs | M65832 Provides |
|-------------|-------------|-----------------|
| Virtual Memory | Page-based MMU | ✅ 2-level page tables, 4KB pages |
| User/Kernel Split | Privilege separation | ✅ S flag (Supervisor/User) |
| Context Switch | Save/restore all state | ✅ Full register save via stack |
| System Calls | Trap to kernel | ✅ TRAP instruction |
| Interrupts | IRQ, timer | ✅ IRQ/NMI vectors |
| Atomics | Lock-free primitives | ✅ CAS, LL/SC, FENCE |
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
    0x4000_0000             Shared libraries
    0x7FFF_0000             User stack (grows down)
    
0x8000_0000 - 0xBFFF_FFFF   Kernel direct-mapped (~1GB)
    0x8000_0000             Kernel code/data
    0xA000_0000             Kernel modules
    0xB000_0000             Device I/O (uncached)
    
0xC000_0000 - 0xFFFF_EFFF   Kernel vmalloc/ioremap
0xFFFF_F000 - 0xFFFF_FFFF   Exception vectors, system
```

**System MMIO window (current RTL):**

- MMU/system registers are decoded by the core on the low 16-bit `0xF0xx` window
  (e.g. `0xFFFF_F000`, `0xFFFF_F004`, `0xFFFF_F010`, `0xFFFF_F014`).
- These addresses bypass MMU translation so the kernel can always reach MMU control
  registers even when paging is enabled.

### 2.2 Page Table Structure

```c
// Level 1 Page Directory (1024 entries, 4KB)
typedef struct {
    uint64_t entries[1024];
} pgd_t;

// Level 2 Page Table (1024 entries, 4KB)  
typedef struct {
    uint64_t entries[1024];
} pte_t;

// Page Table Entry format (64-bit)
// Bits 63:     Valid
// Bits 62-53:  Reserved
// Bits 52-12:  Physical Page Number (53 bits, but top stored elsewhere for 65-bit)
// Bits 11-8:   Reserved
// Bits 7-0:    Flags (P, W, U, WT, CD, A, D, NX)
```

### 2.3 TLB Management

```asm
; Invalidate single TLB entry
; Input: A = virtual address
tlb_invalidate_page:
    ; Store address to TLBINVAL register
    WID STA $FFFFF004   ; TLBINVAL MMIO register
    RTS

; Invalidate entire TLB
tlb_flush_all:
    LDA MMUCR
    ORA #$80            ; Set TLBFLUSH bit
    STA MMUCR
    RTS
    
; Invalidate by ASID (context switch optimization)
tlb_invalidate_asid:
    ; A = ASID to invalidate
    STA ASID_INVAL      ; Invalidate all entries with this ASID
    RTS
```

### 2.4 Page Fault Handling

```asm
; Page fault handler (vectored from $FFFF_FFF4)
page_fault_handler:
    ; Save all registers
    PHA
    PHX
    PHY
    PHD
    PHB
    
    ; Get fault information
    WID LDA $FFFFF010   ; FAULTVA register
    STA fault_address
    LDA MMUCR
    AND #$1C            ; Extract fault type bits
    LSR
    LSR
    STA fault_type      ; 0=read, 1=write, 2=exec
    
    ; Call C handler
    ; do_page_fault(fault_address, fault_type)
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
    uint32_t a;         // Accumulator
    uint32_t x;         // Index X
    uint32_t y;         // Index Y
    uint32_t s;         // Stack pointer
    uint32_t pc;        // Program counter
    uint32_t d;         // Direct page base
    uint32_t b;         // Absolute base
    uint16_t p;         // Status (P + extended)
    uint32_t r[64];     // Register window R0-R63
};

struct task_struct {
    struct m65832_regs regs;
    uint32_t asid;              // Address space ID
    pgd_t *pgd;                 // Page directory
    // ... other Linux task fields
};
```

### 3.2 Context Switch

```asm
; switch_to(prev, next)
; prev in R0, next in R1
switch_to:
    ; Save current task state
    LDA $00             ; prev pointer
    TAX                 ; X = prev
    
    ; Save registers to prev->regs
    LDA A               ; (self-reference trick won't work, need actual save)
    STA TASK_A,X
    TXA
    PHA
    TSX
    TXA
    PLX
    STA TASK_S,X        ; Save stack pointer
    
    ; Save all R0-R63 if register window enabled
    ; (Usually only save callee-saved subset)
    LDA $40             ; R16
    STA TASK_R16,X
    ; ... continue for R16-R23 (callee-saved)
    
    ; Load next task state
    LDA $04             ; next pointer
    TAX
    
    ; Switch page tables
    LDA TASK_PGD,X      ; Get new page directory
    STA PTBR            ; Set page table base
    LDA TASK_ASID,X
    STA ASID            ; Set address space ID
    
    ; Restore registers
    LDA TASK_A,X
    PHA                 ; Save A temporarily
    LDA TASK_S,X
    TXS                 ; Restore stack
    ; ... restore other regs
    PLA                 ; Restore A
    
    RTS
```

### 3.3 Fork Implementation

```asm
; sys_fork - create child process
sys_fork:
    ; Allocate new task_struct
    JSR alloc_task_struct
    STA $00             ; R0 = child task
    
    ; Copy parent page tables (copy-on-write)
    LDA current_task
    STA $04             ; R1 = parent
    JSR copy_page_tables
    
    ; Copy register state
    JSR copy_regs
    
    ; Set child return value to 0
    LDA $00             ; child task
    TAX
    STZ TASK_A,X        ; Child's A = 0 (fork returns 0 to child)
    
    ; Set parent return value to child PID
    LDA $00
    TAX  
    LDA TASK_PID,X      ; Get child PID
    STA $00             ; Return to parent via R0
    
    ; Add child to scheduler
    LDA $00
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

### 4.4 FP Trap ABI (Software Emulation)

Reserved FP opcodes trap through the TRAP vector table using the opcode byte as the index:
`handler = VEC_SYSCALL + (FP_OPCODE * 4)`.

**Inputs (on entry)**:
- `F0/F1/F2` contain the FP operands (single uses low 32 bits, double uses full 64 bits).
- `A` contains the last integer operand for `I2F.*` (if used).
- `P` flags reflect the pre-trap state.

**Outputs (before RTI)**:
- `F0` holds the result for FP ops that return a float/double.
- `A` holds the result for `F2I.*`.
- Flags are set to match the FP op semantics (Z/N/V/C as documented).

**Notes**:
- The trap handler should preserve non-argument registers and return via `RTI`.
- For `R=1`, software saves/restores `F0–F2` by reading `Rk/Rk+1` pairs (DP aligned to 16 bytes).

### 4.2 System Call Handler

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
    
    ; Get syscall number
    LDA current_task
    TAX
    LDA $00             ; R0 = syscall number (from user's DP)
    
    ; Bounds check
    CMP #NR_SYSCALLS
    BCS bad_syscall
    
    ; Look up handler in syscall table
    ASL                 ; * 4 for pointer size
    ASL
    TAX
    LDA syscall_table,X
    STA $20             ; Handler address in temp
    
    ; Call handler (args already in R1-R6)
    JSR ($20)
    
    ; Return value now in A, store to R0
    STA $00
    
syscall_return:
    PLB
    PLD
    PLY
    PLX
    PLA
    RTI                 ; Return to user mode
    
bad_syscall:
    LDA #-ENOSYS
    STA $00
    BRA syscall_return
```

### 4.3 Example System Calls

```asm
; sys_write(fd, buf, count) - syscall #1
sys_write:
    LDA $04             ; R1 = fd
    STA fd_temp
    LDA $08             ; R2 = buf (user pointer)
    STA buf_temp
    LDA $0C             ; R3 = count
    STA count_temp
    
    ; Validate user buffer
    LDA buf_temp
    LDX count_temp
    JSR verify_user_read
    BCC write_fault
    
    ; Get file struct from fd
    LDA fd_temp
    JSR fd_to_file
    BCC write_bad_fd
    
    ; Call file->write()
    ; ... implementation
    RTS
    
; sys_read(fd, buf, count) - syscall #0
sys_read:
    ; Similar to write, but verify_user_write
    ; ...
```

---

## 5. Interrupt Handling

### 5.1 Interrupt Vector Setup

```asm
; Set up interrupt vectors at $FFFF_FFE0
setup_vectors:
    WID LDA #reset_handler
    WID STA $FFFFFFF0   ; Reset vector
    
    WID LDA #nmi_handler
    WID STA $FFFFFFE4   ; NMI vector
    
    WID LDA #irq_handler
    WID STA $FFFFFFE8   ; IRQ vector
    
    WID LDA #trap_handler
    WID STA $FFFFFFF0   ; TRAP vector
    
    WID LDA #pagefault_handler
    WID STA $FFFFFFF4   ; Page fault vector
    
    RTS
```

### 5.2 IRQ Handler

```asm
irq_handler:
    ; Save minimal state
    PHA
    PHX
    PHY
    
    ; Read interrupt controller to get IRQ number
    LDA INTC_PENDING    ; Which IRQ fired?
    
    ; Dispatch to specific handler
    ASL
    ASL
    TAX
    LDA irq_handlers,X
    STA $20
    
    JSR ($20)           ; Call handler
    
    ; Acknowledge interrupt
    LDA INTC_ACK
    
    ; Restore and return
    PLY
    PLX
    PLA
    RTI
```

### 5.3 Timer Interrupt (Preemptive Scheduling)

```asm
timer_irq_handler:
    ; Increment jiffies
    INC jiffies
    BNE no_overflow
    INC jiffies+4
no_overflow:

    ; Decrement current task's time slice
    LDA current_task
    TAX
    DEC TASK_TIMESLICE,X
    BNE timer_done
    
    ; Time slice expired, trigger reschedule
    LDA #1
    STA need_resched
    
timer_done:
    RTS

; Called on return to user space if need_resched set
schedule:
    LDA need_resched
    BEQ no_schedule
    STZ need_resched
    
    ; Find next runnable task
    JSR pick_next_task
    BEQ no_schedule     ; No other task
    
    ; Switch to it
    STA $04             ; next in R1
    LDA current_task
    STA $00             ; prev in R0
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
    STA $20             ; Save lock address
    
spin_retry:
    LDX #0              ; Expected: unlocked
    LDA #1              ; Desired: locked
    CAS ($20)           ; Atomic compare-and-swap
    BNE spin_retry      ; Failed, retry
    
    FENCE               ; Memory barrier after acquiring lock
    RTS

spin_unlock:
    ; Input: A = pointer to lock
    STA $20
    FENCEW              ; Write barrier before release
    LDA #0
    STA ($20)           ; Store 0 (unlocked) - regular store is fine
    RTS

spin_trylock:
    ; Input: A = pointer to lock
    ; Output: Z=1 if acquired, Z=0 if failed
    STA $20
    LDX #0
    LDA #1
    CAS ($20)
    PHP
    FENCE
    PLP
    RTS                 ; Z flag indicates success
```

### 6.2 Atomic Operations

```asm
; atomic_add(ptr, value)
; Input: R0 = pointer, R1 = value to add
; Output: R0 = new value
atomic_add:
    LDA $00             ; ptr
    STA $20
    
retry_add:
    LLI ($20)           ; Load linked: A = *ptr
    CLC
    ADC $04             ; A = A + value
    SCI ($20)           ; Store conditional
    BNE retry_add       ; Retry if failed
    
    STA $00             ; Return new value
    RTS

; atomic_cmpxchg(ptr, old, new)
; Input: R0 = ptr, R1 = old, R2 = new
; Output: R0 = actual old value, Z=1 if swapped
atomic_cmpxchg:
    LDA $00
    STA $20             ; ptr
    LDA $04
    TAX                 ; X = expected old
    LDA $08             ; A = new value
    CAS ($20)           ; Atomic CAS
    STX $00             ; Return actual old value in R0
    RTS
```

### 6.3 Read-Write Locks

```asm
; rwlock: 32-bit value
; Bits 30:0 = reader count
; Bit 31 = writer flag

read_lock:
    STA $20             ; Save lock pointer
read_retry:
    LLI ($20)           ; Load current value
    BMI read_retry      ; If writer held (bit 31), spin
    INC                 ; Increment reader count
    SCI ($20)           ; Try to store
    BNE read_retry
    FENCE
    RTS

read_unlock:
    STA $20
    FENCEW
read_dec:
    LLI ($20)
    DEC                 ; Decrement reader count
    SCI ($20)
    BNE read_dec
    RTS

write_lock:
    STA $20
write_retry:
    LDX #0              ; Expected: 0 (no readers, no writer)
    LDA #$80000000      ; Desired: writer bit set
    CAS ($20)
    BNE write_retry
    FENCE
    RTS

write_unlock:
    STA $20
    FENCEW
    STZ ($20)           ; Clear writer bit
    RTS
```

---

## 7. Device Drivers

### 7.1 Memory-Mapped I/O

```asm
; Read from device register (uncached)
; Input: A = register offset from device base
mmio_read:
    CLC
    ADC device_base     ; A = base + offset
    STA $20
    FENCER              ; Read barrier
    LDA ($20)           ; Uncached read (via page table NoCaching bit)
    RTS

; Write to device register
mmio_write:
    ; A = value, X = offset
    PHA
    TXA
    CLC
    ADC device_base
    STA $20
    PLA
    STA ($20)
    FENCEW              ; Write barrier
    RTS
```

### 7.2 Interrupt-Driven UART Driver

```asm
; UART registers (example, at B+$0000 when B=$B0000000)
UART_DATA   = $0000
UART_STATUS = $0004
UART_CTRL   = $0008

uart_init:
    SB #$B0000000       ; Set B to UART base
    
    ; Enable RX interrupt
    LDA UART_CTRL
    ORA #$04            ; RX interrupt enable
    STA UART_CTRL
    
    ; Register IRQ handler
    LDA #UART_IRQ
    LDX #uart_irq_handler
    JSR register_irq
    RTS

uart_irq_handler:
    SB #$B0000000
    
    ; Read status
    LDA UART_STATUS
    AND #$01            ; RX ready?
    BEQ uart_irq_done
    
    ; Read data
    LDA UART_DATA
    
    ; Add to receive buffer
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
1. Load kernel to physical address (e.g., 0x80000000)
2. Set up initial page tables (identity map + kernel map)
3. Jump to kernel entry in supervisor mode

```asm
; Bootloader final stage
boot_to_kernel:
    ; Disable interrupts
    SEI
    
    ; Set up initial page table
    WID LDA #boot_pgd
    STA PTBR
    
    ; Enable paging
    LDA MMUCR
    ORA #$01            ; PG enable
    STA MMUCR
    
    ; Jump to kernel (now at virtual address)
    WID JMP $80001000   ; kernel_entry
```

### 8.2 Kernel Early Init

```asm
; kernel_entry - first kernel code
kernel_entry:
    ; We're now in virtual address space
    
    ; Set up kernel stack
    WID LDA #$8FFFF000
    TXS
    
    ; Set up kernel D and B
    SD #$80010000       ; Kernel data segment
    RSET                ; Enable register window for fast locals
    
    ; Clear BSS
    JSR clear_bss
    
    ; Initialize memory management
    JSR mm_init
    
    ; Initialize interrupts
    JSR irq_init
    
    ; Initialize scheduler
    JSR sched_init
    
    ; Create init process
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

Suggested mapping for compiler:

```
R0-R7    : Function arguments / return values
R8-R15   : Caller-saved temporaries
R16-R23  : Callee-saved
R24-R27  : Reserved for kernel
R28      : Global pointer (GP) - points to GOT
R29      : Frame pointer (FP)
R30      : Reserved (potential link register)
R31      : Reserved

A, X, Y  : Compiler temporaries (caller-saved)
S        : Stack pointer
D        : Direct page base (points to register window area)
B        : Data segment base (usually 0 for user, kernel base for kernel)
```

### 9.2 Calling Convention

```c
// C function: int add(int a, int b)
// a in R0, b in R1, return in R0
```

```asm
add:
    RSET                ; Ensure register window
    LDA $00             ; A = R0 (first arg)
    CLC
    ADC $04             ; A += R1 (second arg)
    STA $00             ; R0 = result
    RTS
```

### 9.3 Prologue/Epilogue

```asm
; Function with locals and frame pointer
function:
    ; Prologue
    PHD                 ; Save caller's D
    TSX
    TXA
    SEC
    SBC #FRAME_SIZE     ; Allocate frame
    TAX
    TXS
    TDA                 ; A = new SP
    TAD                 ; D = frame base (locals via DP)
    
    ; Save callee-saved regs to frame
    LDA $40             ; R16
    STA LOCAL_R16
    ; ...
    
    ; Function body uses DP for locals
    ; ...
    
    ; Epilogue
    LDA LOCAL_R16
    STA $40             ; Restore R16
    ; ...
    
    TSX
    TXA
    CLC
    ADC #FRAME_SIZE
    TAX
    TXS                 ; Deallocate frame
    PLD                 ; Restore caller's D
    RTS
```

---

## 10. Testing Checklist

Before Linux bring-up, verify:

- [ ] MMU enables/disables correctly
- [ ] Page table walk produces correct physical addresses
- [ ] Page faults trigger with correct fault address
- [ ] TLB invalidation works (single entry and flush all)
- [ ] ASID tagging prevents cross-process TLB hits
- [ ] User/Supervisor mode separation works
- [ ] User cannot access supervisor pages
- [ ] TRAP enters supervisor mode correctly
- [ ] RTI returns to user mode correctly
- [ ] Timer interrupt fires at expected rate
- [ ] IRQ nesting works (if supported)
- [ ] CAS is truly atomic under contention
- [ ] LL/SC pair works with intervening stores
- [ ] FENCE instructions order memory correctly
- [ ] Context switch preserves all state
- [ ] Signal delivery and return works

---

*End of Linux Porting Guide*
