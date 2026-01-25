/*
 * main.c - M65832 Emulator Standalone Program
 *
 * Command-line interface for the M65832 emulator.
 * Supports loading binaries, ELF executables, tracing, debugging.
 */

#include "m65832emu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <signal.h>
#include <time.h>

/* ============================================================================
 * ELF32 Definitions (bare minimum for loading)
 * ========================================================================= */

#define ELF_MAGIC       0x464C457F  /* "\x7FELF" */
#define ET_EXEC         2           /* Executable */
#define EM_M65832       0x6583      /* M65832 machine type (custom) */
#define PT_LOAD         1           /* Loadable segment */
#define PT_NULL         0           /* Unused */

typedef struct {
    uint32_t e_magic;       /* ELF magic */
    uint8_t  e_class;       /* 1=32-bit, 2=64-bit */
    uint8_t  e_data;        /* 1=LE, 2=BE */
    uint8_t  e_version;     /* 1 */
    uint8_t  e_osabi;       /* OS/ABI */
    uint8_t  e_pad[8];      /* Padding */
    uint16_t e_type;        /* Object type */
    uint16_t e_machine;     /* Machine type */
    uint32_t e_version2;    /* Version */
    uint32_t e_entry;       /* Entry point */
    uint32_t e_phoff;       /* Program header offset */
    uint32_t e_shoff;       /* Section header offset */
    uint32_t e_flags;       /* Flags */
    uint16_t e_ehsize;      /* ELF header size */
    uint16_t e_phentsize;   /* Program header entry size */
    uint16_t e_phnum;       /* Number of program headers */
    uint16_t e_shentsize;   /* Section header entry size */
    uint16_t e_shnum;       /* Number of section headers */
    uint16_t e_shstrndx;    /* Section name string table index */
} Elf32_Ehdr;

typedef struct {
    uint32_t p_type;        /* Segment type */
    uint32_t p_offset;      /* File offset */
    uint32_t p_vaddr;       /* Virtual address */
    uint32_t p_paddr;       /* Physical address */
    uint32_t p_filesz;      /* Size in file */
    uint32_t p_memsz;       /* Size in memory */
    uint32_t p_flags;       /* Flags */
    uint32_t p_align;       /* Alignment */
} Elf32_Phdr;

typedef struct {
    uint32_t st_name;       /* Symbol name (string table index) */
    uint32_t st_value;      /* Symbol value */
    uint32_t st_size;       /* Symbol size */
    uint8_t  st_info;       /* Type and binding */
    uint8_t  st_other;      /* Visibility */
    uint16_t st_shndx;      /* Section index */
} Elf32_Sym;

typedef struct {
    uint32_t sh_name;       /* Section name */
    uint32_t sh_type;       /* Section type */
    uint32_t sh_flags;      /* Section flags */
    uint32_t sh_addr;       /* Virtual address */
    uint32_t sh_offset;     /* File offset */
    uint32_t sh_size;       /* Section size */
    uint32_t sh_link;       /* Link to another section */
    uint32_t sh_info;       /* Additional info */
    uint32_t sh_addralign;  /* Alignment */
    uint32_t sh_entsize;    /* Entry size if table */
} Elf32_Shdr;

#define SHT_SYMTAB  2
#define SHT_STRTAB  3

/* ============================================================================
 * Globals
 * ========================================================================= */

static m65832_cpu_t *g_cpu = NULL;
static volatile int g_running = 0;
static int g_trace_enabled = 0;
static int g_verbose = 0;
static uint64_t g_max_cycles = 0;
static uint64_t g_max_instructions = 0;

/* ============================================================================
 * Signal Handler
 * ========================================================================= */

static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
    if (g_cpu) {
        m65832_stop(g_cpu);
    }
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
    
    /* Show hex bytes for instruction */
    char hexbuf[16];
    int hpos = 0;
    for (int i = 0; i < inst_len && i < 4; i++) {
        hpos += snprintf(hexbuf + hpos, sizeof(hexbuf) - hpos, "%02X ", 
                         m65832_emu_read8(cpu, pc + i));
    }
    
    /* Trace format: PC: BYTES  DISASM  | A=... X=... Y=... S=... P=... */
    printf("%08X: %-12s %-20s A=%08X X=%08X Y=%08X S=%08X P=%04X\n",
           pc, hexbuf, disasm,
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
    printf("  --coproc FREQ        Enable 6502 coprocessor at frequency (Hz)\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s program.elf                  Load and run ELF executable\n", prog);
    printf("  %s -o 0x1000 program.bin        Load and run binary at 0x1000\n", prog);
    printf("  %s -t -c 1000 program.bin       Trace first 1000 cycles\n", prog);
    printf("  %s -m 1024 -x program.hex       Load HEX file with 1MB RAM\n", prog);
    printf("  %s -i program.bin               Interactive debugger\n", prog);
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

/* ============================================================================
 * ELF Loader
 * ========================================================================= */

/* Check if file is ELF format */
static int is_elf_file(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;
    
    uint32_t magic;
    size_t n = fread(&magic, 1, 4, f);
    fclose(f);
    
    return (n == 4 && magic == ELF_MAGIC);
}

/* Load ELF executable into emulator memory
 * Returns entry point address, or 0 on error */
static uint32_t load_elf(m65832_cpu_t *cpu, const char *filename, int verbose) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s'\n", filename);
        return 0;
    }
    
    /* Read ELF header */
    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(ehdr), 1, f) != 1) {
        fprintf(stderr, "error: cannot read ELF header\n");
        fclose(f);
        return 0;
    }
    
    /* Validate ELF header */
    if (ehdr.e_magic != ELF_MAGIC) {
        fprintf(stderr, "error: not an ELF file\n");
        fclose(f);
        return 0;
    }
    
    if (ehdr.e_class != 1) {
        fprintf(stderr, "error: not a 32-bit ELF (class=%d)\n", ehdr.e_class);
        fclose(f);
        return 0;
    }
    
    if (ehdr.e_data != 1) {
        fprintf(stderr, "error: not little-endian ELF\n");
        fclose(f);
        return 0;
    }
    
    if (ehdr.e_type != ET_EXEC) {
        fprintf(stderr, "warning: ELF type is %d (expected executable)\n", ehdr.e_type);
    }
    
    if (verbose) {
        printf("ELF: entry=0x%08X, %d program headers\n", 
               ehdr.e_entry, ehdr.e_phnum);
    }
    
    /* Load program segments */
    uint32_t total_loaded = 0;
    for (int i = 0; i < ehdr.e_phnum; i++) {
        Elf32_Phdr phdr;
        
        fseek(f, ehdr.e_phoff + i * ehdr.e_phentsize, SEEK_SET);
        if (fread(&phdr, sizeof(phdr), 1, f) != 1) {
            fprintf(stderr, "error: cannot read program header %d\n", i);
            fclose(f);
            return 0;
        }
        
        if (phdr.p_type != PT_LOAD) continue;
        if (phdr.p_filesz == 0 && phdr.p_memsz == 0) continue;
        
        if (verbose) {
            printf("  LOAD: vaddr=0x%08X filesz=%u memsz=%u\n",
                   phdr.p_vaddr, phdr.p_filesz, phdr.p_memsz);
        }
        
        /* Check bounds */
        if (phdr.p_vaddr + phdr.p_memsz > cpu->memory_size) {
            fprintf(stderr, "error: segment exceeds memory (0x%X + %u > %zu)\n",
                    phdr.p_vaddr, phdr.p_memsz, cpu->memory_size);
            fclose(f);
            return 0;
        }
        
        /* Zero the memory region first (for .bss) */
        for (uint32_t j = 0; j < phdr.p_memsz; j++) {
            m65832_emu_write8(cpu, phdr.p_vaddr + j, 0);
        }
        
        /* Load file contents */
        if (phdr.p_filesz > 0) {
            fseek(f, phdr.p_offset, SEEK_SET);
            for (uint32_t j = 0; j < phdr.p_filesz; j++) {
                int c = fgetc(f);
                if (c == EOF) {
                    fprintf(stderr, "error: unexpected end of file\n");
                    fclose(f);
                    return 0;
                }
                m65832_emu_write8(cpu, phdr.p_vaddr + j, (uint8_t)c);
            }
            total_loaded += phdr.p_filesz;
        }
    }
    
    if (verbose) {
        printf("Loaded %u bytes from ELF\n", total_loaded);
    }
    
    fclose(f);
    return ehdr.e_entry;
}

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

int main(int argc, char *argv[]) {
    const char *filename = NULL;
    uint32_t load_addr = 0x1000;
    uint32_t entry_addr = 0;
    int entry_specified = 0;
    size_t memory_kb = 64;
    int show_state = 0;
    int interactive = 0;
    int load_hex = 0;
    int emulation_mode = 0;
    uint32_t coproc_freq = 0;
    
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
        else if (strcmp(argv[i], "--coproc") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing argument for %s\n", argv[i-1]); return 1; }
            coproc_freq = (uint32_t)strtoul(argv[i], NULL, 0);
        }
        else if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            return 1;
        }
        else {
            filename = argv[i];
        }
    }
    
    if (!filename && !interactive) {
        print_usage(argv[0]);
        return 1;
    }
    
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
    
    /* Set up signal handler */
    signal(SIGINT, signal_handler);
    
    /* Load program */
    int is_elf = 0;
    uint32_t elf_entry = 0;
    
    if (filename) {
        /* Auto-detect ELF format */
        if (is_elf_file(filename)) {
            is_elf = 1;
            elf_entry = load_elf(g_cpu, filename, g_verbose);
            if (elf_entry == 0) {
                fprintf(stderr, "Failed to load ELF %s\n", filename);
                m65832_emu_close(g_cpu);
                return 1;
            }
            if (g_verbose) {
                printf("ELF entry point: 0x%08X\n", elf_entry);
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
    } else {
        /* Execute */
        g_running = 1;
        clock_t start = clock();
        uint64_t start_cycles = g_cpu->cycles;
        uint64_t start_inst = g_cpu->inst_count;
        
        while (g_running && m65832_emu_is_running(g_cpu)) {
            int cycles = m65832_emu_step(g_cpu);
            if (cycles < 0) break;
            
            /* Check limits */
            if (g_max_cycles > 0 && (g_cpu->cycles - start_cycles) >= g_max_cycles) break;
            if (g_max_instructions > 0 && (g_cpu->inst_count - start_inst) >= g_max_instructions) break;
            
            /* Handle traps */
            m65832_trap_t trap = m65832_get_trap(g_cpu);
            if (trap != TRAP_NONE && trap != TRAP_BRK && trap != TRAP_COP &&
                trap != TRAP_SYSCALL) {
                if (g_verbose) {
                    printf("Trap: %s at %08X\n", m65832_trap_name(trap), g_cpu->trap_addr);
                }
                break;
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
    m65832_emu_close(g_cpu);
    
    return 0;
}
