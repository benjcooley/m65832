/*
 * main.c - M65832 Emulator Standalone Program
 *
 * Command-line interface for the M65832 emulator.
 * Supports loading binaries, ELF executables, tracing, debugging.
 */

#include "m65832emu.h"
#include "system.h"
#include "elf_loader.h"
#include "debugger.h"
#include "uart.h"
#include "blkdev.h"
#include "platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

/* ELF loader is in elf_loader.h/c (shared with system.c) */

/* ============================================================================
 * Globals
 * ========================================================================= */

static m65832_cpu_t *g_cpu = NULL;
static system_state_t *g_system = NULL;
static volatile int g_running = 0;
static int g_trace_enabled = 0;
static int g_verbose = 0;
static uint64_t g_max_cycles = 0;
static uint64_t g_max_instructions = 0;
static int g_system_mode = 0;  /* Use system layer instead of raw CPU */
static int g_stop_on_brk = 0;  /* Stop on BRK instruction (for test harnesses) */
static elf_symtab_t *g_symbols = NULL;  /* Loaded symbol table for debugging */
static elf_linetab_t *g_lines = NULL;  /* DWARF line info for source debugging */
static dbg_state_t *g_debugger = NULL;  /* Remote debug server (--debug) */

/* ============================================================================
 * Signal Handler
 * ========================================================================= */

static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
    if (g_debugger) {
        g_debugger->paused = 1;
    }
    if (g_system) {
        system_stop(g_system);
    } else if (g_cpu) {
        m65832_stop(g_cpu);
    }
}

/* Minimal async-signal-safe hex printer */
static void write_hex(int fd, uint32_t val) {
    char buf[9];
    for (int i = 7; i >= 0; i--) {
        int d = val & 0xF;
        buf[i] = (d < 10) ? ('0' + d) : ('A' + d - 10);
        val >>= 4;
    }
    buf[8] = ' ';
    (void)write(fd, buf, 9);
}
static void crash_handler(int sig) {
    const char msg[] = "\n*** EMU CRASH ***\nPC=";
    (void)write(STDERR_FILENO, msg, sizeof(msg)-1);
    if (g_cpu) {
        write_hex(STDERR_FILENO, g_cpu->pc);
        const char sp_msg[] = "SP=";
        (void)write(STDERR_FILENO, sp_msg, 3);
        write_hex(STDERR_FILENO, g_cpu->s);
        const char ip_msg[] = "ipc=";
        (void)write(STDERR_FILENO, ip_msg, 4);
        write_hex(STDERR_FILENO, g_cpu->inst_pc);
        (void)write(STDERR_FILENO, "\n", 1);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

/* ============================================================================
 * Trace Callback
 * ========================================================================= */

static void trace_callback(m65832_cpu_t *cpu, uint32_t pc,
                           const uint8_t *opcode, int len, void *user) {
    (void)opcode;
    (void)len;
    (void)user;
    
    char disasm[64];
    int inst_len = m65832_disassemble(cpu, pc, disasm, sizeof(disasm));
    
    /* Show hex bytes for instruction (up to 12 bytes for largest extended ops) */
    char hexbuf[48];
    int hpos = 0;
    for (int i = 0; i < inst_len && i < 12; i++) {
        hpos += snprintf(hexbuf + hpos, sizeof(hexbuf) - hpos, "%02X ", 
                         m65832_emu_read8(cpu, pc + i));
    }
    
    /* Symbol lookup */
    char symbuf[48] = "";
    if (g_symbols) {
        uint32_t sym_off;
        const char *sym = elf_lookup_symbol(g_symbols, pc, &sym_off);
        if (sym) {
            if (sym_off == 0)
                snprintf(symbuf, sizeof(symbuf), "<%s>", sym);
            else
                snprintf(symbuf, sizeof(symbuf), "<%s+0x%X>", sym, sym_off);
        }
    }

    /* Trace format: PC: BYTES  DISASM  SYMBOL  A=... X=... Y=... S=... P=... */
    printf("%08X: %-36s %-24s %-32s A=%08X X=%08X Y=%08X S=%08X P=%04X\n",
           pc, hexbuf, disasm, symbuf,
           m65832_get_a(cpu), m65832_get_x(cpu), m65832_get_y(cpu),
           m65832_get_s(cpu), m65832_get_p(cpu));
}

/* ============================================================================
 * Command-Line Help
 * ========================================================================= */

static void print_usage(const char *prog) {
    printf("M65832 Emulator v%s\n", m65832_version());
    printf("Usage: %s [options] <program>\n\n", prog);
    printf("Supported formats: raw binary, Intel HEX, ELF32 executable\n");
    printf("ELF files are auto-detected by magic number.\n\n");
    printf("Options:\n");
    printf("  -h, --help           Show this help message\n");
    printf("  -o, --org ADDR       Load address for binary (default: 0x1000)\n");
    printf("  -e, --entry ADDR     Entry point (default: from ELF or load address)\n");
    printf("  -m, --memory SIZE    Memory size in KB (default: 64)\n");
    printf("  -c, --cycles N       Maximum cycles to run (0 = unlimited)\n");
    printf("  -n, --instructions N Maximum instructions to run\n");
    printf("  -t, --trace          Enable instruction tracing\n");
    printf("  -v, --verbose        Verbose output\n");
    printf("  -s, --state          Print CPU state after execution\n");
    printf("  -i, --interactive    Interactive debugger mode\n");
    printf("  -x, --hex            Load Intel HEX file instead of binary\n");
    printf("  --emulation          Start in 6502 emulation mode (default: 32-bit native)\n");
    printf("  --stop-on-brk        Stop execution on BRK instruction (for test harnesses)\n");
    printf("  --coproc FREQ        Enable 6502 coprocessor at frequency (Hz)\n");
    printf("  --symbols FILE       Load symbols from ELF for trace/debug\n");
    printf("  --debug              Start debug server (use 'edb' to send commands)\n");
    printf("\nSystem Mode (Linux boot support):\n");
    printf("  --system             Enable system mode with UART and boot support\n");
    printf("  --ram SIZE           RAM size (e.g., 256M, 1G) (default: 256M)\n");
    printf("  --kernel FILE        Load kernel at 0x00100000\n");
    printf("  --initrd FILE        Load initrd at 0x01000000\n");
    printf("  --cmdline \"STRING\"   Kernel command line\n");
    printf("  --bootrom FILE       Boot ROM binary (enables hardware boot flow)\n");
    printf("  --disk FILE          Block device disk image file\n");
    printf("  --disk-ro            Open disk image read-only\n");
    printf("  --raw                Put terminal in raw mode (for UART I/O)\n");
    printf("  --sandbox DIR        Sandbox root for syscall file I/O\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s program.elf                  Load and run ELF executable\n", prog);
    printf("  %s -o 0x1000 program.bin        Load and run binary at 0x1000\n", prog);
    printf("  %s -t -c 1000 program.bin       Trace first 1000 cycles\n", prog);
    printf("  %s -m 1024 -x program.hex       Load HEX file with 1MB RAM\n", prog);
    printf("  %s -i program.bin               Interactive debugger\n", prog);
    printf("  %s --system --kernel vmlinux    Boot Linux kernel\n", prog);
    printf("  %s --system --disk root.img     Run with disk image\n", prog);
    printf("  %s --system --raw test.bin      Run with UART in raw mode\n", prog);
}

/* ============================================================================
 * Hex Dump Utility
 * ========================================================================= */

static void hex_dump(m65832_cpu_t *cpu, uint32_t addr, int lines) {
    for (int i = 0; i < lines; i++) {
        printf("%08X: ", addr);
        for (int j = 0; j < 16; j++) {
            printf("%02X ", m65832_emu_read8(cpu, addr + j));
            if (j == 7) printf(" ");
        }
        printf(" |");
        for (int j = 0; j < 16; j++) {
            uint8_t c = m65832_emu_read8(cpu, addr + j);
            printf("%c", (c >= 32 && c < 127) ? c : '.');
        }
        printf("|\n");
        addr += 16;
    }
}

/* ELF loading functions: elf_is_elf_file(), elf_load() - see elf_loader.h */

/* ============================================================================
 * Interactive Debugger
 * ========================================================================= */

static void interactive_mode(m65832_cpu_t *cpu) {
    char line[256];
    char cmd[64];
    uint32_t arg1, arg2;
    
    printf("\nM65832 Interactive Debugger\n");
    printf("Type 'help' for commands\n\n");
    
    while (1) {
        printf("m65832> ");
        fflush(stdout);
        
        if (!fgets(line, sizeof(line), stdin)) break;
        
        /* Parse command */
        int argc = sscanf(line, "%63s %x %x", cmd, &arg1, &arg2);
        if (argc < 1) continue;
        
        /* Convert command to lowercase */
        for (char *p = cmd; *p; p++) *p = tolower(*p);
        
        if (strcmp(cmd, "help") == 0 || strcmp(cmd, "?") == 0) {
            printf("Commands:\n");
            printf("  s, step [n]        Step n instructions (default 1)\n");
            printf("  c, continue        Continue execution\n");
            printf("  r, run [cycles]    Run for cycles (default: until halt)\n");
            printf("  reg, regs          Show registers\n");
            printf("  m, mem ADDR [n]    Show memory (n lines, default 4)\n");
            printf("  d, dis ADDR [n]    Disassemble n instructions\n");
            printf("Breakpoints:\n");
            printf("  b, break ADDR      Set breakpoint\n");
            printf("  bc, clear [ADDR]   Clear breakpoint(s)\n");
            printf("  bl, list           List breakpoints\n");
            printf("Watchpoints:\n");
            printf("  wp ADDR [type]     Set watchpoint (0=r/w, 1=write)\n");
            printf("  wc [ADDR]          Clear watchpoint(s)\n");
            printf("  wl                 List watchpoints\n");
            printf("Registers:\n");
            printf("  w, write ADDR VAL  Write byte to memory\n");
            printf("  pc ADDR            Set program counter\n");
            printf("  a VAL              Set accumulator\n");
            printf("  x VAL              Set X register\n");
            printf("  y VAL              Set Y register\n");
            printf("System:\n");
            printf("  sys, sysregs       Show system registers (MMU, Timer)\n");
            printf("  tlb                Show TLB contents\n");
            printf("  bt, backtrace      Show stack backtrace\n");
            printf("  coproc             Show 6502 coprocessor state\n");
            printf("  mmio               Show MMIO regions\n");
            printf("  blk, disk          Show block device state\n");
            printf("Symbols:\n");
            printf("  sym ADDR           Look up symbol at address\n");
            printf("  addr NAME          Find address of symbol\n");
            printf("Control:\n");
            printf("  reset              Reset CPU\n");
            printf("  irq [0|1]          Assert/deassert IRQ (default: assert)\n");
            printf("  nmi                Trigger NMI\n");
            printf("  abort              Trigger ABORT\n");
            printf("  trace [on|off]     Toggle instruction tracing\n");
            printf("  q, quit            Exit debugger\n");
        }
        else if (strcmp(cmd, "s") == 0 || strcmp(cmd, "step") == 0) {
            int n = (argc >= 2) ? (int)arg1 : 1;
            for (int i = 0; i < n && m65832_emu_is_running(cpu); i++) {
                if (g_trace_enabled) {
                    uint8_t op = m65832_emu_read8(cpu, m65832_get_pc(cpu));
                    trace_callback(cpu, m65832_get_pc(cpu), &op, 1, NULL);
                }
                int cycles = m65832_emu_step(cpu);
                if (cycles < 0 || m65832_get_trap(cpu) == TRAP_BREAKPOINT) break;
            }
            m65832_print_state(cpu);
        }
        else if (strcmp(cmd, "c") == 0 || strcmp(cmd, "continue") == 0) {
            g_running = 1;
            while (g_running && m65832_emu_is_running(cpu)) {
                if (g_trace_enabled) {
                    uint8_t op = m65832_emu_read8(cpu, m65832_get_pc(cpu));
                    trace_callback(cpu, m65832_get_pc(cpu), &op, 1, NULL);
                }
                int cycles = m65832_emu_step(cpu);
                if (cycles < 0) break;
                if (m65832_get_trap(cpu) == TRAP_BREAKPOINT) {
                    printf("Breakpoint at %08X\n", m65832_get_pc(cpu));
                    break;
                }
            }
            m65832_print_state(cpu);
        }
        else if (strcmp(cmd, "r") == 0 || strcmp(cmd, "run") == 0) {
            uint64_t cycles = (argc >= 2) ? arg1 : 0;
            if (cycles > 0) {
                m65832_emu_run(cpu, cycles);
            } else {
                m65832_run_until_halt(cpu);
            }
            m65832_print_state(cpu);
        }
        else if (strcmp(cmd, "reg") == 0 || strcmp(cmd, "regs") == 0) {
            m65832_print_state(cpu);
        }
        else if (strcmp(cmd, "m") == 0 || strcmp(cmd, "mem") == 0) {
            if (argc >= 2) {
                int lines = (argc >= 3) ? (int)arg2 : 4;
                hex_dump(cpu, arg1, lines);
            } else {
                printf("Usage: mem ADDR [lines]\n");
            }
        }
        else if (strcmp(cmd, "d") == 0 || strcmp(cmd, "dis") == 0) {
            uint32_t addr = (argc >= 2) ? arg1 : m65832_get_pc(cpu);
            int n = (argc >= 3) ? (int)arg2 : 10;
            char buf[128];
            for (int i = 0; i < n; i++) {
                printf("%08X: %02X  ", addr, m65832_emu_read8(cpu, addr));
                int len = m65832_disassemble(cpu, addr, buf, sizeof(buf));
                printf("%s\n", buf);
                addr += len;
            }
        }
        else if (strcmp(cmd, "b") == 0 || strcmp(cmd, "break") == 0) {
            if (argc >= 2) {
                if (m65832_add_breakpoint(cpu, arg1) >= 0) {
                    printf("Breakpoint set at %08X\n", arg1);
                } else {
                    printf("Failed to set breakpoint\n");
                }
            } else {
                printf("Usage: break ADDR\n");
            }
        }
        else if (strcmp(cmd, "bc") == 0 || strcmp(cmd, "clear") == 0) {
            if (argc >= 2) {
                if (m65832_remove_breakpoint(cpu, arg1)) {
                    printf("Breakpoint removed at %08X\n", arg1);
                } else {
                    printf("No breakpoint at %08X\n", arg1);
                }
            } else {
                m65832_clear_breakpoints(cpu);
                printf("All breakpoints cleared\n");
            }
        }
        else if (strcmp(cmd, "bl") == 0 || strcmp(cmd, "list") == 0) {
            printf("Breakpoints: ");
            int found = 0;
            for (int i = 0; i < cpu->num_breakpoints; i++) {
                printf("%08X ", cpu->breakpoints[i]);
                found = 1;
            }
            if (!found) printf("(none)");
            printf("\n");
        }
        else if (strcmp(cmd, "w") == 0 || strcmp(cmd, "write") == 0) {
            if (argc >= 3) {
                m65832_emu_write8(cpu, arg1, (uint8_t)arg2);
                printf("Wrote %02X to %08X\n", arg2 & 0xFF, arg1);
            } else {
                printf("Usage: write ADDR VALUE\n");
            }
        }
        else if (strcmp(cmd, "pc") == 0) {
            if (argc >= 2) {
                m65832_set_pc(cpu, arg1);
                printf("PC = %08X\n", arg1);
            } else {
                printf("PC = %08X\n", m65832_get_pc(cpu));
            }
        }
        else if (strcmp(cmd, "a") == 0) {
            if (argc >= 2) {
                m65832_set_a(cpu, arg1);
                printf("A = %08X\n", arg1);
            } else {
                printf("A = %08X\n", m65832_get_a(cpu));
            }
        }
        else if (strcmp(cmd, "x") == 0) {
            if (argc >= 2) {
                m65832_set_x(cpu, arg1);
                printf("X = %08X\n", arg1);
            } else {
                printf("X = %08X\n", m65832_get_x(cpu));
            }
        }
        else if (strcmp(cmd, "y") == 0) {
            if (argc >= 2) {
                m65832_set_y(cpu, arg1);
                printf("Y = %08X\n", arg1);
            } else {
                printf("Y = %08X\n", m65832_get_y(cpu));
            }
        }
        else if (strcmp(cmd, "reset") == 0) {
            m65832_emu_reset(cpu);
            printf("CPU reset\n");
            m65832_print_state(cpu);
        }
        else if (strcmp(cmd, "irq") == 0) {
            int active = (argc >= 2) ? (int)arg1 : 1;
            m65832_irq(cpu, active != 0);
            printf("IRQ %s\n", active ? "asserted" : "deasserted");
        }
        else if (strcmp(cmd, "nmi") == 0) {
            m65832_nmi(cpu);
            printf("NMI triggered\n");
        }
        else if (strcmp(cmd, "abort") == 0) {
            m65832_abort(cpu);
            printf("ABORT triggered\n");
        }
        else if (strcmp(cmd, "trace") == 0) {
            if (argc >= 2) {
                g_trace_enabled = (arg1 != 0);
            } else {
                g_trace_enabled = !g_trace_enabled;
            }
            printf("Tracing %s\n", g_trace_enabled ? "enabled" : "disabled");
        }
        else if (strcmp(cmd, "coproc") == 0) {
            m65832_coproc_print_state(cpu);
        }
        else if (strcmp(cmd, "mmio") == 0) {
            m65832_mmio_print(cpu);
        }
        else if (strcmp(cmd, "blk") == 0 || strcmp(cmd, "disk") == 0) {
            if (g_system && g_system->blkdev) {
                blkdev_state_t *blk = g_system->blkdev;
                printf("Block Device:\n");
                printf("  Status:   %02X  (READY=%d BUSY=%d ERR=%d DRQ=%d PRESENT=%d WR=%d IRQ=%d)\n",
                       blk->status & 0xFF,
                       (blk->status & BLKDEV_STATUS_READY) ? 1 : 0,
                       (blk->status & BLKDEV_STATUS_BUSY) ? 1 : 0,
                       (blk->status & BLKDEV_STATUS_ERROR) ? 1 : 0,
                       (blk->status & BLKDEV_STATUS_DRQ) ? 1 : 0,
                       (blk->status & BLKDEV_STATUS_PRESENT) ? 1 : 0,
                       (blk->status & BLKDEV_STATUS_WRITABLE) ? 1 : 0,
                       (blk->status & BLKDEV_STATUS_IRQ) ? 1 : 0);
                if (blk->error != BLKDEV_ERR_NONE) {
                    printf("  Error:    %02X\n", blk->error);
                }
                printf("  Sector:   %llu\n", (unsigned long long)blk->sector);
                printf("  DMA Addr: %08X\n", blk->dma_addr);
                printf("  Count:    %u\n", blk->count);
                printf("  Capacity: %llu sectors (%llu MB)\n",
                       (unsigned long long)blkdev_get_capacity(blk),
                       (unsigned long long)blkdev_get_capacity_bytes(blk) / (1024 * 1024));
            } else {
                printf("Block device not available (use --system mode)\n");
            }
        }
        else if (strcmp(cmd, "sys") == 0 || strcmp(cmd, "sysregs") == 0) {
            /* Display system registers */
            printf("System Registers:\n");
            printf("  MMUCR:    %08X  (PG=%d WP=%d)\n", 
                   cpu->mmucr,
                   (cpu->mmucr & 0x01) ? 1 : 0,
                   (cpu->mmucr & 0x02) ? 1 : 0);
            printf("  ASID:     %02X\n", cpu->asid);
            printf("  PTBR:     %08X_%08X\n", 
                   (uint32_t)(cpu->ptbr >> 32), (uint32_t)(cpu->ptbr & 0xFFFFFFFF));
            printf("  FAULTVA:  %08X\n", cpu->faultva);
            printf("  VBR:      %08X\n", cpu->vbr);
            printf("Timer:\n");
            printf("  CTRL:     %02X  (EN=%d IE=%d IF=%d)\n",
                   cpu->timer_ctrl,
                   (cpu->timer_ctrl & 0x01) ? 1 : 0,
                   (cpu->timer_ctrl & 0x04) ? 1 : 0,
                   (cpu->timer_ctrl & 0x80) ? 1 : 0);
            printf("  CMP:      %08X\n", cpu->timer_cmp);
            printf("  CNT:      %08X\n", cpu->timer_cnt);
        }
        else if (strcmp(cmd, "tlb") == 0) {
            /* Display TLB contents */
            printf("TLB (16 entries, next=%d):\n", cpu->tlb_next);
            printf("  #  VPN       PPN       ASID  FLAGS\n");
            int found = 0;
            for (int i = 0; i < 16; i++) {
                if (cpu->tlb[i].valid) {
                    printf("  %2d %08X  %08X  %02X    %c%c%c%c\n",
                           i,
                           cpu->tlb[i].vpn << 12,
                           (uint32_t)(cpu->tlb[i].ppn << 12),
                           cpu->tlb[i].asid,
                           (cpu->tlb[i].flags & 0x01) ? 'P' : '-',
                           (cpu->tlb[i].flags & 0x02) ? 'W' : '-',
                           (cpu->tlb[i].flags & 0x04) ? 'U' : '-',
                           (cpu->tlb[i].flags & 0x08) ? 'X' : '-');
                    found = 1;
                }
            }
            if (!found) printf("  (empty)\n");
        }
        else if (strcmp(cmd, "bt") == 0 || strcmp(cmd, "backtrace") == 0) {
            /* Simple stack backtrace */
            printf("Stack backtrace (SP=%08X):\n", cpu->s);
            uint32_t sp = cpu->s;
            int width = (cpu->p & P_E) ? 2 : 4;  /* PC width based on mode */
            for (int i = 0; i < 16 && sp < cpu->memory_size - width; i++) {
                uint32_t ret_addr;
                if (width == 2) {
                    ret_addr = m65832_emu_read16(cpu, sp + 1);
                    sp += 3;  /* P + 2-byte PC */
                } else {
                    /* Native mode: P_lo, P_hi, PC[3:0] */
                    ret_addr = m65832_emu_read8(cpu, sp + 3) |
                               ((uint32_t)m65832_emu_read8(cpu, sp + 4) << 8) |
                               ((uint32_t)m65832_emu_read8(cpu, sp + 5) << 16) |
                               ((uint32_t)m65832_emu_read8(cpu, sp + 6) << 24);
                    sp += 7;  /* 2-byte P + 4-byte PC */
                }
                if (ret_addr == 0 || ret_addr >= cpu->memory_size) break;
                uint32_t bt_off;
                const char *bt_sym = elf_lookup_symbol(g_symbols, ret_addr, &bt_off);
                if (bt_sym)
                    printf("  #%d  %08X  <%s+0x%X>\n", i, ret_addr, bt_sym, bt_off);
                else
                    printf("  #%d  %08X\n", i, ret_addr);
            }
        }
        else if (strcmp(cmd, "wp") == 0 || strcmp(cmd, "watch") == 0) {
            if (argc >= 2) {
                bool on_read = true, on_write = true;
                if (argc >= 3 && arg2 == 1) {
                    on_read = false;  /* Write-only watchpoint */
                }
                if (m65832_add_watchpoint(cpu, arg1, 1, on_read, on_write) >= 0) {
                    printf("Watchpoint set at %08X (%s)\n", arg1,
                           on_read ? "read/write" : "write-only");
                } else {
                    printf("Failed to set watchpoint (max 16)\n");
                }
            } else {
                printf("Usage: watch ADDR [type: 0=r/w, 1=write-only]\n");
            }
        }
        else if (strcmp(cmd, "wc") == 0 || strcmp(cmd, "wclr") == 0) {
            if (argc >= 2) {
                if (m65832_remove_watchpoint(cpu, arg1)) {
                    printf("Watchpoint removed at %08X\n", arg1);
                } else {
                    printf("No watchpoint at %08X\n", arg1);
                }
            } else {
                cpu->num_watchpoints = 0;
                printf("All watchpoints cleared\n");
            }
        }
        else if (strcmp(cmd, "wl") == 0 || strcmp(cmd, "wlist") == 0) {
            printf("Watchpoints:\n");
            if (cpu->num_watchpoints == 0) {
                printf("  (none)\n");
            } else {
                for (int i = 0; i < cpu->num_watchpoints; i++) {
                    printf("  %08X-%08X %s\n",
                           cpu->watchpoints[i].addr,
                           cpu->watchpoints[i].addr + cpu->watchpoints[i].size - 1,
                           cpu->watchpoints[i].on_read ? "read/write" : "write-only");
                }
            }
        }
        else if (strcmp(cmd, "sym") == 0) {
            if (!g_symbols) {
                printf("No symbols loaded (use --symbols FILE)\n");
            } else if (argc >= 2) {
                uint32_t sym_off;
                const char *sym = elf_lookup_symbol(g_symbols, arg1, &sym_off);
                if (sym)
                    printf("%08X  <%s+0x%X>\n", arg1, sym, sym_off);
                else
                    printf("%08X  (no symbol)\n", arg1);
            } else {
                printf("Usage: sym ADDR\n");
            }
        }
        else if (strcmp(cmd, "addr") == 0) {
            if (!g_symbols) {
                printf("No symbols loaded (use --symbols FILE)\n");
            } else if (argc >= 2) {
                /* arg1 was parsed as hex, but we need the raw string */
                char name[64];
                sscanf(line, "%*s %63s", name);
                uint32_t a = elf_find_symbol(g_symbols, name);
                if (a)
                    printf("%s = %08X\n", name, a);
                else
                    printf("Symbol '%s' not found\n", name);
            } else {
                printf("Usage: addr SYMBOL_NAME\n");
            }
        }
        else if (strcmp(cmd, "q") == 0 || strcmp(cmd, "quit") == 0 ||
                 strcmp(cmd, "exit") == 0) {
            break;
        }
        else if (strlen(cmd) > 0) {
            printf("Unknown command: %s\n", cmd);
        }
    }
}

/* ============================================================================
 * Main Entry Point
 * ========================================================================= */

/* Parse RAM size with suffixes (e.g., "256M", "1G") */
static size_t parse_ram_size(const char *str) {
    char *endptr;
    size_t size = strtoul(str, &endptr, 0);
    
    if (*endptr == 'K' || *endptr == 'k') {
        size *= 1024;
    } else if (*endptr == 'M' || *endptr == 'm') {
        size *= 1024 * 1024;
    } else if (*endptr == 'G' || *endptr == 'g') {
        size *= 1024 * 1024 * 1024;
    }
    
    return size;
}

int main(int argc, char *argv[]) {
    const char *filename = NULL;
    uint32_t load_addr = 0x1000;
    uint32_t entry_addr = 0;
    int entry_specified = 0;
    size_t memory_kb = 1024;  /* 1MB default - proper 32-bit memory size */
    int show_state = 0;
    int interactive = 0;
    int load_hex = 0;
    int emulation_mode = 0;
    uint32_t coproc_freq = 0;
    const char *symbols_file = NULL;
    int debug_server = 0;

    /* System mode options */
    const char *kernel_file = NULL;
    const char *initrd_file = NULL;
    const char *cmdline = NULL;
    const char *sandbox_root = NULL;
    const char *disk_file = NULL;
    const char *bootrom_file = NULL;
    int disk_readonly = 0;
    size_t sys_ram_size = 256 * 1024 * 1024;  /* Default 256 MB */
    int raw_mode = 0;
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        }
        else if (strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--org") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            load_addr = (uint32_t)strtoul(argv[i], NULL, 0);
        }
        else if (strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--entry") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            entry_addr = (uint32_t)strtoul(argv[i], NULL, 0);
            entry_specified = 1;
        }
        else if (strcmp(argv[i], "-m") == 0 || strcmp(argv[i], "--memory") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            memory_kb = (size_t)strtoul(argv[i], NULL, 0);
        }
        else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--cycles") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            g_max_cycles = (uint64_t)strtoull(argv[i], NULL, 0);
        }
        else if (strcmp(argv[i], "-n") == 0 || strcmp(argv[i], "--instructions") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            g_max_instructions = (uint64_t)strtoull(argv[i], NULL, 0);
        }
        else if (strcmp(argv[i], "-t") == 0 || strcmp(argv[i], "--trace") == 0) {
            g_trace_enabled = 1;
        }
        else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            g_verbose = 1;
        }
        else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--state") == 0) {
            show_state = 1;
        }
        else if (strcmp(argv[i], "-i") == 0 || strcmp(argv[i], "--interactive") == 0) {
            interactive = 1;
        }
        else if (strcmp(argv[i], "-x") == 0 || strcmp(argv[i], "--hex") == 0) {
            load_hex = 1;
        }
        else if (strcmp(argv[i], "--emulation") == 0 || strcmp(argv[i], "--emu") == 0) {
            emulation_mode = 1;
        }
        else if (strcmp(argv[i], "--stop-on-brk") == 0) {
            g_stop_on_brk = 1;
        }
        else if (strcmp(argv[i], "--coproc") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            coproc_freq = (uint32_t)strtoul(argv[i], NULL, 0);
        }
        else if (strcmp(argv[i], "--symbols") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            symbols_file = argv[i];
        }
        else if (strcmp(argv[i], "--debug") == 0) {
            debug_server = 1;
        }
        /* System mode options */
        else if (strcmp(argv[i], "--system") == 0) {
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--ram") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            sys_ram_size = parse_ram_size(argv[i]);
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--kernel") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            kernel_file = argv[i];
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--initrd") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            initrd_file = argv[i];
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--cmdline") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            cmdline = argv[i];
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--raw") == 0) {
            raw_mode = 1;
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--disk") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            disk_file = argv[i];
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--disk-ro") == 0) {
            disk_readonly = 1;
        }
        else if (strcmp(argv[i], "--bootrom") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            bootrom_file = argv[i];
            g_system_mode = 1;
        }
        else if (strcmp(argv[i], "--sandbox") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            sandbox_root = argv[i];
            g_system_mode = 1;
        }
        else if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            return 1;
        }
        else {
            filename = argv[i];
        }
    }
    
    if (!filename && !interactive && !g_system_mode) {
        print_usage(argv[0]);
        return 1;
    }
    
    /* Set up signal handler */
    signal(SIGINT, signal_handler);
    signal(SIGSEGV, crash_handler);
    signal(SIGBUS, crash_handler);
    
    /* ========================================================================
     * SYSTEM MODE - Use system layer with UART and boot support
     * ====================================================================== */
    if (g_system_mode) {
        system_config_t config;
        system_config_init(&config);
        
        config.ram_size = sys_ram_size;
        config.kernel_file = kernel_file;
        config.initrd_file = initrd_file;
        config.cmdline = cmdline;
        config.entry_point = entry_specified ? entry_addr : 0;
        config.enable_uart = true;
        config.uart_raw_mode = raw_mode;
        config.enable_blkdev = true;
        config.disk_file = disk_file;
        config.disk_readonly = disk_readonly;
        config.bootrom_file = bootrom_file;
        config.supervisor_mode = true;
        config.native32_mode = !emulation_mode;
        config.verbose = g_verbose;
        config.sandbox_root = sandbox_root;
        
        /* If filename provided without --kernel, treat it as kernel */
        if (filename && !kernel_file) {
            config.kernel_file = filename;
        }
        
        if (g_verbose) {
            printf("Initializing M65832 system v%s\n", m65832_version());
        }
        
        g_system = system_init(&config);
        if (!g_system) {
            fprintf(stderr, "Failed to initialize system\n");
            return 1;
        }
        
        g_cpu = system_get_cpu(g_system);
        
        if (g_verbose) {
            system_print_info(g_system);
        }
        
        /* Load symbols and DWARF line info */
        {
            const char *elf_file = symbols_file ? symbols_file :
                (config.kernel_file && elf_is_elf_file(config.kernel_file)) ?
                config.kernel_file : NULL;
            if (elf_file) {
                g_symbols = elf_load_symbols(elf_file, g_verbose);
                g_lines = elf_load_lines(elf_file, g_verbose);
            }
        }

        /* Enable tracing if requested */
        if (g_trace_enabled) {
            m65832_set_trace(g_cpu, true, trace_callback, NULL);
        }

        /* Interactive debugger or run */
        if (interactive) {
            interactive_mode(g_cpu);
            elf_free_symbols(g_symbols);
    elf_free_lines(g_lines);
            system_destroy(g_system);
            return 0;
        }

        /* Debug server mode */
        if (debug_server) {
            g_debugger = dbg_init(g_cpu, g_symbols, g_lines, g_system,
                                  &g_trace_enabled, trace_callback);
            if (!g_debugger || dbg_start(g_debugger) != 0) {
                fprintf(stderr, "Failed to start debug server\n");
                elf_free_symbols(g_symbols);
    elf_free_lines(g_lines);
                system_destroy(g_system);
                return 1;
            }
            /* Set kernel VA→PA offset from ELF for breakpoint translation */
            {
                const char *elf_file = symbols_file ? symbols_file :
                    (config.kernel_file && elf_is_elf_file(config.kernel_file)) ?
                    config.kernel_file : NULL;
                if (elf_file) {
                    g_debugger->kernel_va_offset = elf_get_va_offset(elf_file);
                    if (g_verbose && g_debugger->kernel_va_offset) {
                        printf("Kernel VA offset: 0x%08X\n",
                               g_debugger->kernel_va_offset);
                    }
                }
            }

            g_running = 1;
            while (g_running) {
                if (g_debugger->irq) {
                    int r = dbg_poll(g_debugger);
                    if (r < 0) break;
                    if (r > 0) continue;
                }
                m65832_emu_step(g_cpu);
                if ((g_cpu->inst_count & 0xFF) == 0)
                    system_poll_devices(g_system);
            }

            dbg_destroy(g_debugger);
            g_debugger = NULL;
            elf_free_symbols(g_symbols);
    elf_free_lines(g_lines);
            system_destroy(g_system);
            return 0;
        }

        /* Run system */
        g_running = 1;
        clock_t start = clock();
        uint64_t start_cycles = g_cpu->cycles;
        uint64_t start_inst = g_cpu->inst_count;

        if (g_max_cycles > 0) {
            system_run(g_system, g_max_cycles);
        } else {
            system_run_until_halt(g_system);
        }
        
        clock_t end = clock();
        double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
        uint64_t cycles_run = g_cpu->cycles - start_cycles;
        uint64_t inst_run = g_cpu->inst_count - start_inst;
        
        if (g_verbose || show_state) {
            printf("\nExecution complete:\n");
            printf("  Cycles: %llu\n", (unsigned long long)cycles_run);
            printf("  Instructions: %llu\n", (unsigned long long)inst_run);
            printf("  Time: %.3f seconds\n", elapsed);
            if (elapsed > 0) {
                printf("  Performance: %.2f MHz (%.2f MIPS)\n",
                       cycles_run / elapsed / 1000000.0,
                       inst_run / elapsed / 1000000.0);
            }
            printf("\nFinal CPU state:\n");
            m65832_print_state(g_cpu);
        }
        
        elf_free_symbols(g_symbols);
    elf_free_lines(g_lines);
        system_destroy(g_system);
        return 0;
    }
    
    /* ========================================================================
     * LEGACY MODE - Direct CPU emulator without system layer
     * ====================================================================== */
    
    /* Initialize emulator */
    if (g_verbose) {
        printf("Initializing M65832 emulator v%s\n", m65832_version());
        printf("Memory: %zu KB\n", memory_kb);
    }
    
    g_cpu = m65832_emu_init(memory_kb * 1024);
    if (!g_cpu) {
        fprintf(stderr, "Failed to initialize emulator\n");
        return 1;
    }
    
    /* Initialize UART for console I/O (always enabled in legacy mode) */
    const platform_config_t *platform = platform_get_config(platform_get_default());
    uart_state_t *uart = uart_init(g_cpu, platform);
    if (!uart && g_verbose) {
        fprintf(stderr, "Warning: Failed to initialize UART\n");
    }
    
    /* Load program */
    int is_elf = 0;
    uint32_t elf_entry = 0;
    
    if (filename) {
        /* Auto-detect ELF format */
        if (elf_is_elf_file(filename)) {
            is_elf = 1;
            elf_entry = elf_load(g_cpu, filename, g_verbose);
            if (elf_entry == 0) {
                fprintf(stderr, "Failed to load ELF %s\n", filename);
                m65832_emu_close(g_cpu);
                return 1;
            }
            if (g_verbose) {
                printf("ELF entry point: 0x%08X\n", elf_entry);
            }
            /* Auto-load symbols and DWARF from ELF */
            if (!symbols_file) {
                g_symbols = elf_load_symbols(filename, g_verbose);
                g_lines = elf_load_lines(filename, g_verbose);
            }
        } else if (load_hex) {
            int loaded = m65832_load_hex(g_cpu, filename);
            if (loaded < 0) {
                fprintf(stderr, "Failed to load HEX %s\n", filename);
                m65832_emu_close(g_cpu);
                return 1;
            }
            if (g_verbose) {
                printf("Loaded %d bytes from HEX %s\n", loaded, filename);
            }
        } else {
            int loaded = m65832_load_binary(g_cpu, filename, load_addr);
            if (loaded < 0) {
                fprintf(stderr, "Failed to load %s\n", filename);
                m65832_emu_close(g_cpu);
                return 1;
            }
            if (g_verbose) {
                printf("Loaded %d bytes from %s at 0x%08X\n", loaded, filename, load_addr);
            }
        }
    }

    /* Load symbols from explicit --symbols option */
    if (symbols_file && !g_symbols) {
        g_symbols = elf_load_symbols(symbols_file, g_verbose);
        g_lines = elf_load_lines(symbols_file, g_verbose);
    }

    /* Set up entry point */
    if (is_elf) {
        /* ELF provides entry point directly */
        m65832_emu_write32(g_cpu, 0xFFFC, elf_entry);
        m65832_emu_reset(g_cpu);
        m65832_set_pc(g_cpu, elf_entry);
    } else if (!load_hex && filename) {
        uint32_t entry = entry_specified ? entry_addr : load_addr;
        m65832_emu_write16(g_cpu, 0xFFFC, (uint16_t)entry);
        m65832_emu_reset(g_cpu);
        
        if (!entry_specified) {
            /* For direct execution, set PC directly */
            m65832_set_pc(g_cpu, entry);
        }
    }
    
    /* CPU starts in emulation mode (RTL-faithful reset).
     * Switch to native 32-bit mode unless --emulation was specified. */
    if (!emulation_mode) {
        m65832_emu_enter_native32(g_cpu);
    }
    
    /* Set up 6502 coprocessor if requested */
    if (coproc_freq > 0) {
        if (m65832_coproc_init(g_cpu, coproc_freq, 50000000, COMPAT_DECIMAL_EN) < 0) {
            fprintf(stderr, "Failed to initialize 6502 coprocessor\n");
        } else if (g_verbose) {
            printf("6502 coprocessor enabled at %u Hz\n", coproc_freq);
        }
    }
    
    /* Enable tracing if requested */
    if (g_trace_enabled && !interactive) {
        m65832_set_trace(g_cpu, true, trace_callback, NULL);
    }
    
    if (g_verbose) {
        m65832_print_state(g_cpu);
    }
    
    /* Run or enter interactive mode */
    if (interactive) {
        interactive_mode(g_cpu);
    } else if (debug_server) {
        /* Debug server mode (legacy) */
        g_debugger = dbg_init(g_cpu, g_symbols, g_lines, NULL,
                              &g_trace_enabled, trace_callback);
        if (!g_debugger || dbg_start(g_debugger) != 0) {
            fprintf(stderr, "Failed to start debug server\n");
            elf_free_symbols(g_symbols);
    elf_free_lines(g_lines);
            if (uart) uart_destroy(uart);
            m65832_emu_close(g_cpu);
            return 1;
        }

        g_running = 1;
        while (g_running) {
            if (g_debugger->irq) {
                int r = dbg_poll(g_debugger);
                if (r < 0) break;
                if (r > 0) continue;
            }
            m65832_emu_step(g_cpu);
            if (uart) uart_poll(uart);
        }

        dbg_destroy(g_debugger);
        g_debugger = NULL;
    } else {
        /* Execute */
        g_running = 1;
        clock_t start = clock();
        uint64_t start_cycles = g_cpu->cycles;
        uint64_t start_inst = g_cpu->inst_count;

        while (g_running && m65832_emu_is_running(g_cpu)) {
            int cycles = m65832_emu_step(g_cpu);
            if (cycles < 0) break;

            /* Poll UART for input (non-blocking) */
            if (uart) uart_poll(uart);

            /* Check limits */
            if (g_max_cycles > 0 && (g_cpu->cycles - start_cycles) >= g_max_cycles) break;
            if (g_max_instructions > 0 && (g_cpu->inst_count - start_inst) >= g_max_instructions) break;

            /* Handle traps */
            m65832_trap_t trap = m65832_get_trap(g_cpu);
            if (trap != TRAP_NONE && trap != TRAP_COP && trap != TRAP_SYSCALL) {
                /* BRK: stop if --stop-on-brk flag is set */
                if (trap == TRAP_BRK && g_stop_on_brk) {
                    if (g_verbose) {
                        printf("Trap: BRK at %08X (--stop-on-brk)\n", g_cpu->trap_addr);
                    }
                    break;
                }
                /* Other traps (except BRK without flag) stop execution */
                if (trap != TRAP_BRK) {
                    if (g_verbose) {
                        printf("Trap: %s at %08X\n", m65832_trap_name(trap), g_cpu->trap_addr);
                    }
                    break;
                }
            }
        }
        
        clock_t end = clock();
        double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
        uint64_t cycles_run = g_cpu->cycles - start_cycles;
        uint64_t inst_run = g_cpu->inst_count - start_inst;
        
        if (g_verbose) {
            printf("\nExecution complete:\n");
            printf("  Cycles: %llu\n", (unsigned long long)cycles_run);
            printf("  Instructions: %llu\n", (unsigned long long)inst_run);
            printf("  Time: %.3f seconds\n", elapsed);
            if (elapsed > 0) {
                printf("  Performance: %.2f MHz (%.2f MIPS)\n",
                       cycles_run / elapsed / 1000000.0,
                       inst_run / elapsed / 1000000.0);
            }
        }
    }
    
    /* Show final state */
    if (show_state || g_verbose) {
        printf("\nFinal CPU state:\n");
        m65832_print_state(g_cpu);
    }
    
    /* Clean up */
    elf_free_symbols(g_symbols);
    elf_free_lines(g_lines);
    if (uart) uart_destroy(uart);
    m65832_emu_close(g_cpu);
    
    return 0;
}
