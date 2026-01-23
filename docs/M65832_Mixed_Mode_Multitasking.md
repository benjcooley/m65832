# M65832 Mixed-Mode Multitasking

**Running 8-bit, 16-bit, and 32-bit Processes Simultaneously**

---

## 1. Overview

The M65832 can multitask processes running in different modes:

| Mode | Typical Use | E | M | X | Address Space |
|------|-------------|---|---|---|---------------|
| 6502 Emulation | C64, Apple II, NES games | 1 | - | - | 64KB via VBR |
| 65816 Native-16 | SNES games, legacy 65816 | 0 | 01 | 01 | 16MB (via B) or 4GB |
| M65832 Native-32 | Linux apps, modern code | 0 | 10 | 10 | 4GB |

The kernel always runs in Native-32 supervisor mode, but can switch between user processes of any mode.

---

## 2. Process State by Mode

### 2.1 Full Task State

```c
struct m65832_task_state {
    // Core registers (all modes)
    uint32_t a;         // Accumulator (width varies by mode)
    uint32_t x;         // Index X
    uint32_t y;         // Index Y
    uint32_t pc;        // Program counter
    uint32_t s;         // Stack pointer
    uint16_t p;         // Status: P[7:0] + ExtP[7:0]
    
    // Base registers
    uint32_t d;         // Direct page base
    uint32_t b;         // Absolute base
    uint32_t vbr;       // Virtual 6502 base (used when E=1)
    
    // Register window (Native-32 processes)
    uint32_t r[64];     // R0-R63
    
    // MMU state
    uint64_t ptbr;      // Page table base
    uint16_t asid;      // Address space ID
};
```

### 2.2 Mode-Specific State

| Register | 6502 (E=1) | Native-16 | Native-32 |
|----------|------------|-----------|-----------|
| A | 8-bit | 8/16-bit | 8/16/32-bit |
| X, Y | 8-bit | 8/16-bit | 8/16/32-bit |
| PC | 16-bit (VBR-relative) | 16/32-bit | 32-bit |
| S | 8-bit ($01xx) | 16-bit | 16/32-bit |
| D | Fixed at VBR | 16/32-bit | 32-bit |
| VBR | Active | Ignored | Ignored |
| R0-R63 | N/A | Optional | Full use |

---

## 3. Context Switch Implementation

### 3.1 Save Current Process

```asm
; save_context - save current process state
; Input: X = pointer to task_state
save_context:
    ; Save core registers
    ; (A already saved by IRQ entry)
    TXA
    PHA                     ; Save task pointer
    
    ; Get actual A value from IRQ stack frame
    TSX
    LDA $0103,X             ; Saved A from stack
    PLX                     ; Restore task pointer
    STA TASK_A,X
    
    ; Save other registers (already in supervisor mode, so 32-bit)
    TYA
    STA TASK_Y,X
    
    ; Save stack pointer (from before interrupt)
    ; This requires care - the interrupt pushed PC and P
    ; We need the user's S value
    LDA user_sp_save        ; Captured on IRQ entry
    STA TASK_S,X
    
    ; Save base registers
    TDA                     
    STA TASK_D,X
    TBA
    STA TASK_B,X
    TVA
    STA TASK_VBR,X
    
    ; Save status (was pushed by IRQ, get from stack)
    TSX
    LDA $0101,X             ; P from stack (includes E, M, X bits)
    PLX
    STA TASK_P,X
    
    ; Save PC (from stack)
    ; ... similar pattern
    
    ; If process uses register window, save R0-R63
    LDA TASK_P,X
    AND #$0004              ; Check R bit
    BEQ skip_regwin_save
    
    ; Save register window
    RSET                    ; Ensure our R=1
    LDY #0
save_regs:
    LDA $00,Y               ; Read from register window
    STA TASK_R0,X
    INX
    INX
    INX
    INX
    INY
    INY
    INY
    INY
    CPY #256
    BNE save_regs
    
skip_regwin_save:
    RTS
```

### 3.2 Restore New Process

```asm
; restore_context - restore process state and return to it
; Input: X = pointer to task_state
restore_context:
    ; Switch page tables first
    LDA TASK_PTBR,X
    STA PTBR
    LDA TASK_ASID,X
    STA ASID
    
    ; If new process uses register window, restore R0-R63
    LDA TASK_P,X
    AND #$0004              ; Check R bit
    BEQ skip_regwin_restore
    
    RSET
    PHX                     ; Save task pointer
    LDY #0
restore_regs:
    LDA TASK_R0,X
    STA $00,Y
    INX
    INX
    INX
    INX
    INY
    INY
    INY
    INY
    CPY #256
    BNE restore_regs
    PLX
    
skip_regwin_restore:
    ; Restore base registers
    LDA TASK_D,X
    TAD
    LDA TASK_B,X
    TAB
    LDA TASK_VBR,X
    TAV                     ; VBR only matters if E=1
    
    ; Set up return stack frame
    ; Push PC (will be popped by RTI)
    LDA TASK_PC+2,X         ; High word
    PHA
    LDA TASK_PC,X           ; Low word
    PHA
    
    ; Push P (will be popped by RTI)
    ; This includes E, M, X flags - RTI will restore the mode!
    LDA TASK_P,X
    PHA
    
    ; Restore working registers
    LDA TASK_Y,X
    TAY
    LDA TASK_A,X
    PHA                     ; Save A for last
    
    ; Restore stack pointer
    ; Tricky: we need to switch stacks
    LDA TASK_S,X
    ; ... complex: need to copy return frame to user stack
    
    ; Restore A last
    PLA
    
    ; Return to process - RTI restores P (including mode!) and PC
    RTI
```

### 3.3 The Magic: RTI Restores Mode

The key insight is that **RTI pulls the full P register**, which includes:
- E flag (emulation mode)
- M1:M0 (accumulator width)  
- X1:X0 (index width)
- S flag (will be 0 for user mode)
- R flag (register window enable)
- W flag (wide stack)

So when RTI executes:
1. P is pulled → CPU mode changes to whatever the process was using
2. PC is pulled → Execution continues where process was interrupted

---

## 4. Mode-Specific Considerations

### 4.1 6502 Emulation Mode Processes

For processes running classic 6502 code:

```asm
; Set up a 6502 process
setup_6502_process:
    ; Allocate and init task_state
    JSR alloc_task
    TAX
    
    ; Set E=1 in saved P
    LDA #$01                ; E bit in extended P
    STA TASK_P+1,X          ; Extended P byte
    
    ; Set VBR to process's 64KB window
    LDA process_base
    STA TASK_VBR,X
    
    ; Set initial PC (relative to VBR)
    LDA #$C000              ; Typical 6502 entry point
    STA TASK_PC,X
    STZ TASK_PC+2,X
    
    ; Set up page tables to map VBR..VBR+$FFFF
    ; with appropriate permissions
    JSR setup_6502_pages
    
    RTS
```

**Memory Layout for 6502 Process:**
```
VBR + $0000-$00FF  → Zero Page (read/write)
VBR + $0100-$01FF  → Stack (read/write)
VBR + $0200-$BFFF  → RAM (read/write)
VBR + $C000-$FFFF  → ROM (read-only, or RAM)

All mapped via page tables to actual physical memory
```

### 4.2 65816 Native-16 Processes

For 16-bit processes (like SNES games):

```asm
setup_65816_process:
    JSR alloc_task
    TAX
    
    ; E=0, M=01, X=01 (16-bit mode)
    LDA #$00                ; E=0
    STA TASK_P+1,X
    LDA #$30                ; M=1, X=1 in standard P
    STA TASK_P,X
    
    ; Set B to base address (like bank 0)
    LDA process_base
    STA TASK_B,X
    
    ; D for direct page
    LDA #$0000
    STA TASK_D,X
    
    RTS
```

### 4.3 Native-32 Processes

For full 32-bit Linux-style processes:

```asm
setup_32bit_process:
    JSR alloc_task
    TAX
    
    ; E=0, M=10, X=10 (32-bit mode), R=1 (register window)
    LDA #$04                ; R=1 in extended P
    STA TASK_P+1,X
    
    ; Set up for register window ABI
    LDA #user_register_area
    STA TASK_D,X
    
    ; B=0 for flat addressing
    STZ TASK_B,X
    
    RTS
```

---

## 5. Example: Three Processes Running

```
┌─────────────────────────────────────────────────────────────────┐
│                        M65832 System                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Process 1: Commodore 64 Game          Process 2: SNES Game     │
│  ┌─────────────────────────┐          ┌─────────────────────┐   │
│  │ Mode: E=1 (6502)        │          │ Mode: E=0, M=01     │   │
│  │ VBR: $10000000          │          │ B: $20000000        │   │
│  │ Address: 64KB window    │          │ Address: 16MB       │   │
│  │ Running: Pac-Man        │          │ Running: SMW        │   │
│  └─────────────────────────┘          └─────────────────────┘   │
│                                                                  │
│  Process 3: Linux Shell               Kernel                     │
│  ┌─────────────────────────┐          ┌─────────────────────┐   │
│  │ Mode: E=0, M=10, X=10   │          │ Mode: E=0, M=10     │   │
│  │ D: $40000000 (regs)     │          │ S=1 (supervisor)    │   │
│  │ Address: Full 4GB       │          │ Manages all above   │   │
│  │ Running: bash           │          │                     │   │
│  └─────────────────────────┘          └─────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Timeline

```
Time    Active Process    Mode        Notes
─────────────────────────────────────────────────────────
0ms     Process 1         6502        Playing Pac-Man
10ms    [Timer IRQ]       Kernel      Scheduler runs
10ms    Process 3         32-bit      bash prompt
20ms    [Timer IRQ]       Kernel      Scheduler runs
20ms    Process 2         65816       SMW running
30ms    [Timer IRQ]       Kernel      Scheduler runs
30ms    Process 1         6502        Back to Pac-Man
...
```

---

## 6. Inter-Process Communication

### 6.1 6502 Process Calling System Services

A 6502 process can request services from the kernel:

```asm
; In 6502 process - request disk I/O
; Use BRK or COP as "escape" to kernel
    LDA #$01            ; Service: read sector
    STA $FE             ; Service code in ZP
    LDA #$00
    STA $FF             ; Sector number
    BRK                 ; Trap to kernel
    ; Kernel reads sector, puts data at $0200
    ; Returns here when done
```

### 6.2 Shared Memory Between Modes

Different-mode processes can share memory via page tables:

```c
// Kernel sets up shared page
void setup_shared_memory(task_t *proc_6502, task_t *proc_32bit) {
    // Map same physical page into both address spaces
    physical_addr_t shared = alloc_physical_page();
    
    // For 6502 process: map at VBR + $0800
    map_page(proc_6502->pgd, proc_6502->vbr + 0x0800, shared, PROT_RW);
    
    // For 32-bit process: map at $50000000
    map_page(proc_32bit->pgd, 0x50000000, shared, PROT_RW);
}
```

---

## 7. Performance Considerations

### 7.1 Context Switch Cost

| From Mode | To Mode | Extra Cost | Notes |
|-----------|---------|------------|-------|
| 32-bit | 32-bit | Baseline | ~50 cycles |
| 32-bit | 6502 | +VBR write | ~55 cycles |
| 6502 | 32-bit | +VBR read | ~55 cycles |
| 6502 | 6502 | +VBR swap | ~60 cycles |
| Any | Any w/R=1 | +R0-R63 save | ~300 cycles |

### 7.2 Optimization: Lazy Register Window

Only save/restore R0-R63 if actually used:

```asm
; Track if register window was touched
context_switch:
    ; Check if outgoing process dirtied registers
    LDA current_task
    TAX
    LDA TASK_FLAGS,X
    AND #FLAG_REGS_DIRTY
    BEQ skip_save_regs
    
    JSR save_register_window
    
skip_save_regs:
    ; Mark incoming process as not-dirty
    LDA new_task
    TAX
    LDA TASK_FLAGS,X
    AND #~FLAG_REGS_DIRTY
    STA TASK_FLAGS,X
    
    ; Lazily restore on first DP access (trap handler)
    ; Or eagerly if known to use registers
```

### 7.3 ASID Optimization

With Address Space IDs, TLB entries are tagged:
- Switching between processes with different ASIDs: **no TLB flush needed**
- Only flush when ASID pool exhausted and must be recycled

---

## 8. Debugging Mixed-Mode Systems

### 8.1 Kernel Debug Output

```asm
; Print current process info
debug_print_task:
    LDA current_task
    TAX
    
    ; Print mode
    LDA TASK_P+1,X
    AND #$01                ; E bit
    BEQ not_emu
    JSR print "6502 emulation"
    BRA print_rest
not_emu:
    LDA TASK_P,X
    AND #$20                ; M bit
    BEQ is_8bit
    LDA TASK_P+1,X
    AND #$80                ; M1 bit
    BEQ is_16bit
    JSR print "32-bit native"
    BRA print_rest
is_16bit:
    JSR print "16-bit native"
    BRA print_rest
is_8bit:
    JSR print "8-bit native"
print_rest:
    ; Print VBR if emulation mode
    ; Print PC, registers, etc.
    RTS
```

---

## 9. Summary

**Yes, the M65832 fully supports mixed-mode multitasking:**

1. ✅ Mode state (E, M, X) is saved per-process
2. ✅ VBR allows 6502 processes at any address
3. ✅ RTI restores full mode on context switch
4. ✅ Page tables provide memory isolation
5. ✅ Kernel always runs in 32-bit supervisor mode
6. ✅ Processes can share memory across modes

This enables the "Ultra" vision:
- **C-64 Ultra**: Run original C64 software alongside Linux
- **SNES Ultra**: Play SNES games while running modern apps
- **Apple II Ultra**: Classic Apple II programs with modern extensions

All without software emulation - the CPU natively executes the original instruction set!
