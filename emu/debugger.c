/*
 * debugger.c - M65832 Remote Debug Server
 *
 * Architecture:
 *   - A command thread listens on a Unix domain socket.
 *   - Each client connection sends one command, receives one response.
 *   - Commands are posted to a single-slot queue (volatile flag).
 *   - The main emulator loop calls dbg_poll() every iteration.
 *     Hot path: two volatile reads, zero locks.
 *     Only when has_cmd==1 does it acquire the mutex.
 *   - Responses are written to a fixed buffer via rsp_printf().
 */

#include "debugger.h"
#include "system.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <errno.h>

/* ============================================================================
 * Response Buffer
 * ========================================================================= */

static void rsp_clear(dbg_state_t *dbg) {
    dbg->rsp_len = 0;
    dbg->rsp_buf[0] = '\0';
}

static void rsp_printf(dbg_state_t *dbg, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int remaining = DBG_RSP_MAX - dbg->rsp_len;
    if (remaining > 1) {
        int n = vsnprintf(dbg->rsp_buf + dbg->rsp_len, remaining, fmt, ap);
        if (n > 0) {
            if (n >= remaining) n = remaining - 1;
            dbg->rsp_len += n;
        }
    }
    va_end(ap);
}

/* ============================================================================
 * Helpers
 * ========================================================================= */

static void print_regs(dbg_state_t *dbg) {
    m65832_cpu_t *cpu = dbg->cpu;
    uint32_t pc = m65832_get_pc(cpu);
    char disasm[64];
    m65832_disassemble(cpu, pc, disasm, sizeof(disasm));

    char symbuf[48] = "";
    if (dbg->symbols) {
        uint32_t soff;
        const char *s = elf_lookup_symbol(dbg->symbols, pc, &soff);
        if (s) {
            if (soff == 0) snprintf(symbuf, sizeof(symbuf), " <%s>", s);
            else snprintf(symbuf, sizeof(symbuf), " <%s+0x%X>", s, soff);
        }
    }

    /* Source line info */
    char srcbuf[80] = "";
    if (dbg->lines) {
        int line;
        const char *file = elf_lookup_line(dbg->lines, pc, &line);
        if (file) {
            /* Strip long paths: show last component(s) */
            const char *short_file = file;
            const char *p = file;
            int slashes = 0;
            for (; *p; p++) if (*p == '/') slashes++;
            if (slashes > 2) {
                /* Keep last 2 path components */
                int seen = 0;
                for (p = file + strlen(file) - 1; p > file; p--)
                    if (*p == '/' && ++seen == 2) { short_file = p + 1; break; }
            }
            snprintf(srcbuf, sizeof(srcbuf), " @ %s:%d", short_file, line);
        }
    }

    rsp_printf(dbg, "PC=%08X A=%08X X=%08X Y=%08X S=%08X P=%04X\n",
               pc, m65832_get_a(cpu), m65832_get_x(cpu),
               m65832_get_y(cpu), m65832_get_s(cpu), m65832_get_p(cpu));
    rsp_printf(dbg, "  %08X  %s%s%s\n", pc, disasm, symbuf, srcbuf);
}

static void hex_dump(dbg_state_t *dbg, uint32_t addr, int lines) {
    m65832_cpu_t *cpu = dbg->cpu;
    for (int i = 0; i < lines; i++) {
        rsp_printf(dbg, "%08X: ", addr);
        for (int j = 0; j < 16; j++) {
            rsp_printf(dbg, "%02X ", m65832_emu_read8(cpu, addr + j));
            if (j == 7) rsp_printf(dbg, " ");
        }
        rsp_printf(dbg, " |");
        for (int j = 0; j < 16; j++) {
            uint8_t c = m65832_emu_read8(cpu, addr + j);
            rsp_printf(dbg, "%c", (c >= 32 && c < 127) ? c : '.');
        }
        rsp_printf(dbg, "|\n");
        addr += 16;
    }
}

/* ============================================================================
 * Command Processing
 *
 * Returns:
 *   0  = done, response ready (stay paused if was paused)
 *   1  = resume running (continue)
 *   2  = "wait" — don't send response yet
 *  -1  = quit
 * ========================================================================= */

/* Forward declarations for helpers used by process_cmd and dbg_poll */
static int  dbg_check_swbp(dbg_state_t *dbg);
static void dbg_reinsert_swbp(dbg_state_t *dbg);
static void dbg_notify_stop(dbg_state_t *dbg, const char *reason, uint32_t addr);

/* Translate a kernel VA to PA using MMU page tables first, falling back
 * to the ELF-derived VA offset (vaddr - paddr from first LOAD segment).
 * Returns (uint64_t)-1 if translation fails entirely. */
static uint64_t dbg_va_to_pa(dbg_state_t *dbg, uint32_t va) {
    uint64_t pa = m65832_virt_to_phys(dbg->cpu, va);
    if (pa != (uint64_t)-1 && pa < dbg->cpu->memory_size)
        return pa;
    /* Fallback: use kernel VA offset from ELF headers */
    if (dbg->kernel_va_offset && va >= dbg->kernel_va_offset) {
        pa = va - dbg->kernel_va_offset;
        if (pa < dbg->cpu->memory_size)
            return pa;
    }
    return (uint64_t)-1;
}

static int process_cmd(dbg_state_t *dbg, const char *line) {
    m65832_cpu_t *cpu = dbg->cpu;
    char cmd[64] = {0};
    uint32_t arg1 = 0, arg2 = 0;

    int argc = sscanf(line, "%63s %x %x", cmd, &arg1, &arg2);
    if (argc < 1) return 0;

    for (char *p = cmd; *p; p++) *p = tolower(*p);

    /* --- Inspection ---------------------------------------------------- */

    if (strcmp(cmd, "reg") == 0 || strcmp(cmd, "regs") == 0) {
        print_regs(dbg);
    }
    else if (strcmp(cmd, "m") == 0 || strcmp(cmd, "mem") == 0) {
        if (argc >= 2) {
            int lines = (argc >= 3) ? (int)arg2 : 4;
            hex_dump(dbg, arg1, lines);
        } else {
            rsp_printf(dbg, "Usage: mem ADDR [lines]\n");
        }
    }
    else if (strcmp(cmd, "d") == 0 || strcmp(cmd, "dis") == 0) {
        uint32_t addr = (argc >= 2) ? arg1 : m65832_get_pc(cpu);
        int n = (argc >= 3) ? (int)arg2 : 10;
        char buf[128];
        int last_line = -1;
        for (int i = 0; i < n; i++) {
            /* Show source line annotation when line changes */
            if (dbg->lines) {
                int line;
                const char *file = elf_lookup_line(dbg->lines, addr, &line);
                if (file && line != last_line) {
                    rsp_printf(dbg, "  ; %s:%d\n", file, line);
                    last_line = line;
                }
            }
            int len = m65832_disassemble(cpu, addr, buf, sizeof(buf));
            char symbuf[48] = "";
            if (dbg->symbols) {
                uint32_t soff;
                const char *s = elf_lookup_symbol(dbg->symbols, addr, &soff);
                if (s) {
                    if (soff == 0) snprintf(symbuf, sizeof(symbuf), " <%s>", s);
                    else snprintf(symbuf, sizeof(symbuf), " <%s+0x%X>", s, soff);
                }
            }
            rsp_printf(dbg, "%c %08X: %s%s\n",
                       addr == m65832_get_pc(cpu) ? '>' : ' ', addr, buf, symbuf);
            addr += len;
        }
    }
    else if (strcmp(cmd, "sym") == 0) {
        if (!dbg->symbols) {
            rsp_printf(dbg, "No symbols loaded\n");
        } else if (argc >= 2) {
            uint32_t soff;
            const char *s = elf_lookup_symbol(dbg->symbols, arg1, &soff);
            if (s) rsp_printf(dbg, "%08X  <%s+0x%X>\n", arg1, s, soff);
            else   rsp_printf(dbg, "%08X  (no symbol)\n", arg1);
        } else {
            rsp_printf(dbg, "Usage: sym ADDR\n");
        }
    }
    else if (strcmp(cmd, "addr") == 0) {
        if (!dbg->symbols) {
            rsp_printf(dbg, "No symbols loaded\n");
        } else {
            char name[64] = {0};
            sscanf(line, "%*s %63s", name);
            if (name[0]) {
                uint32_t a = elf_find_symbol(dbg->symbols, name);
                if (a) rsp_printf(dbg, "%s = %08X\n", name, a);
                else   rsp_printf(dbg, "Symbol '%s' not found\n", name);
            } else {
                rsp_printf(dbg, "Usage: addr NAME\n");
            }
        }
    }
    else if (strcmp(cmd, "bt") == 0 || strcmp(cmd, "backtrace") == 0) {
        rsp_printf(dbg, "Backtrace (SP=%08X):\n", cpu->s);
        uint32_t sp = cpu->s;
        int width = IS_EMU(cpu) ? 2 : 4;
        for (int i = 0; i < 16 && sp < cpu->memory_size - width; i++) {
            uint32_t ret;
            if (width == 2) {
                ret = m65832_emu_read16(cpu, sp + 1);
                sp += 3;
            } else {
                ret = m65832_emu_read8(cpu, sp + 3) |
                      ((uint32_t)m65832_emu_read8(cpu, sp + 4) << 8) |
                      ((uint32_t)m65832_emu_read8(cpu, sp + 5) << 16) |
                      ((uint32_t)m65832_emu_read8(cpu, sp + 6) << 24);
                sp += 7;
            }
            if (ret == 0 || ret >= cpu->memory_size) break;
            uint32_t soff;
            const char *s = elf_lookup_symbol(dbg->symbols, ret, &soff);
            if (s) rsp_printf(dbg, "  #%d  %08X  <%s+0x%X>\n", i, ret, s, soff);
            else   rsp_printf(dbg, "  #%d  %08X\n", i, ret);
        }
    }
    else if (strcmp(cmd, "l") == 0 || strcmp(cmd, "list") == 0) {
        if (!dbg->lines) {
            rsp_printf(dbg, "No DWARF line info (rebuild with CONFIG_DEBUG_INFO_DWARF4=y)\n");
        } else {
            uint32_t addr = (argc >= 2) ? arg1 : m65832_get_pc(cpu);
            int line;
            const char *file = elf_lookup_line(dbg->lines, addr, &line);
            if (file) {
                rsp_printf(dbg, "%s:%d\n", file, line);
                /* Show surrounding source: try to read the file */
                FILE *srcf = fopen(file, "r");
                if (srcf) {
                    char buf[256];
                    int cur_line = 0;
                    int start = (line > 5) ? line - 5 : 1;
                    int end = line + 5;
                    while (fgets(buf, sizeof(buf), srcf)) {
                        cur_line++;
                        if (cur_line < start) continue;
                        if (cur_line > end) break;
                        /* Remove trailing newline */
                        int len = (int)strlen(buf);
                        if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';
                        rsp_printf(dbg, "%c %4d  %s\n",
                                   cur_line == line ? '>' : ' ', cur_line, buf);
                    }
                    fclose(srcf);
                } else {
                    rsp_printf(dbg, "(source file not found: %s)\n", file);
                }
            } else {
                rsp_printf(dbg, "No source info for %08X\n", addr);
            }
        }
    }
    else if (strcmp(cmd, "sys") == 0 || strcmp(cmd, "sysregs") == 0) {
        rsp_printf(dbg, "MMUCR=%08X (PG=%d WP=%d)  ASID=%02X  PTBR=%08X_%08X\n",
                   cpu->mmucr, (cpu->mmucr & 1) ? 1 : 0, (cpu->mmucr & 2) ? 1 : 0,
                   cpu->asid, (uint32_t)(cpu->ptbr >> 32), (uint32_t)(cpu->ptbr));
        rsp_printf(dbg, "VBR=%08X  FAULTVA=%08X\n", cpu->vbr, cpu->faultva);
        rsp_printf(dbg, "Timer: CTRL=%02X CMP=%08X CNT=%08X\n",
                   cpu->timer_ctrl, cpu->timer_cmp, cpu->timer_cnt);
    }
    else if (strcmp(cmd, "tlb") == 0) {
        rsp_printf(dbg, "TLB (next=%d):\n", cpu->tlb_next);
        int found = 0;
        for (int i = 0; i < 16; i++) {
            if (cpu->tlb[i].valid) {
                rsp_printf(dbg, "  %2d %08X->%08X ASID=%02X %c%c%c%c\n", i,
                           cpu->tlb[i].vpn << 12,
                           (uint32_t)(cpu->tlb[i].ppn << 12),
                           cpu->tlb[i].asid,
                           (cpu->tlb[i].flags & 1) ? 'P' : '-',
                           (cpu->tlb[i].flags & 2) ? 'W' : '-',
                           (cpu->tlb[i].flags & 4) ? 'U' : '-',
                           (cpu->tlb[i].flags & 8) ? 'X' : '-');
                found = 1;
            }
        }
        if (!found) rsp_printf(dbg, "  (empty)\n");
    }

    /* --- Breakpoints / Watchpoints ------------------------------------- */

    else if (strcmp(cmd, "b") == 0 || strcmp(cmd, "break") == 0) {
        char name[64] = {0};
        sscanf(line, "%*s %63s", name);
        if (name[0]) {
            uint32_t baddr = 0;
            char *end;
            baddr = (uint32_t)strtoul(name, &end, 16);
            if (*end != '\0') {
                baddr = elf_find_symbol(dbg->symbols, name);
                if (baddr == 0) {
                    rsp_printf(dbg, "Symbol '%s' not found\n", name);
                    return 0;
                }
            }
            /* Check for duplicate */
            for (int i = 0; i < dbg->num_swbp; i++) {
                if (dbg->swbp[i].va == baddr) {
                    rsp_printf(dbg, "Breakpoint already set at %08X\n", baddr);
                    return 0;
                }
            }
            if (dbg->num_swbp >= DBG_MAX_SWBP) {
                rsp_printf(dbg, "Too many breakpoints (max %d)\n", DBG_MAX_SWBP);
                return 0;
            }
            /* Translate VA → PA using page table or ELF offset fallback */
            uint64_t pa = dbg_va_to_pa(dbg, baddr);
            if (pa == (uint64_t)-1) {
                rsp_printf(dbg, "Cannot translate %08X to physical\n", baddr);
                return 0;
            }
            /* Save original byte and write BRK */
            int idx = dbg->num_swbp++;
            dbg->swbp[idx].va = baddr;
            dbg->swbp[idx].pa = pa;
            dbg->swbp[idx].saved_byte = cpu->memory[pa];
            dbg->swbp[idx].active = 1;
            dbg->swbp[idx].temporary = 0;
            cpu->memory[pa] = 0x00;  /* BRK opcode */

            uint32_t soff;
            const char *s = elf_lookup_symbol(dbg->symbols, baddr, &soff);
            if (s) rsp_printf(dbg, "Breakpoint at %08X <%s>\n", baddr, s);
            else   rsp_printf(dbg, "Breakpoint at %08X\n", baddr);
        } else {
            rsp_printf(dbg, "Usage: break ADDR|SYMBOL\n");
        }
    }
    else if (strcmp(cmd, "bc") == 0 || strcmp(cmd, "clear") == 0) {
        if (argc >= 2) {
            int found = 0;
            for (int i = 0; i < dbg->num_swbp; i++) {
                if (dbg->swbp[i].va == arg1) {
                    /* Restore original byte */
                    if (dbg->swbp[i].active && dbg->swbp[i].pa < cpu->memory_size)
                        cpu->memory[dbg->swbp[i].pa] = dbg->swbp[i].saved_byte;
                    /* Remove by shifting */
                    if (dbg->swbp_step_idx == i) dbg->swbp_step_idx = -1;
                    else if (dbg->swbp_step_idx > i) dbg->swbp_step_idx--;
                    dbg->num_swbp--;
                    for (int j = i; j < dbg->num_swbp; j++)
                        dbg->swbp[j] = dbg->swbp[j + 1];
                    found = 1;
                    rsp_printf(dbg, "Breakpoint removed at %08X\n", arg1);
                    break;
                }
            }
            if (!found) rsp_printf(dbg, "No breakpoint at %08X\n", arg1);
        } else {
            /* Clear all */
            for (int i = 0; i < dbg->num_swbp; i++) {
                if (dbg->swbp[i].active && dbg->swbp[i].pa < cpu->memory_size)
                    cpu->memory[dbg->swbp[i].pa] = dbg->swbp[i].saved_byte;
            }
            dbg->num_swbp = 0;
            dbg->swbp_step_idx = -1;
            rsp_printf(dbg, "All breakpoints cleared\n");
        }
    }
    else if (strcmp(cmd, "bl") == 0 || strcmp(cmd, "list") == 0) {
        if (dbg->num_swbp == 0) {
            rsp_printf(dbg, "No breakpoints\n");
        } else {
            for (int i = 0; i < dbg->num_swbp; i++) {
                uint32_t soff;
                const char *s = elf_lookup_symbol(dbg->symbols, dbg->swbp[i].va, &soff);
                if (s) rsp_printf(dbg, "  %08X  <%s>%s\n", dbg->swbp[i].va, s,
                                  dbg->swbp[i].active ? "" : " (stepped)");
                else   rsp_printf(dbg, "  %08X%s\n", dbg->swbp[i].va,
                                  dbg->swbp[i].active ? "" : " (stepped)");
            }
        }
    }
    else if (strcmp(cmd, "wp") == 0 || strcmp(cmd, "watch") == 0) {
        if (argc >= 2) {
            bool on_read = true, on_write = true;
            if (argc >= 3 && arg2 == 1) on_read = false;
            if (m65832_add_watchpoint(cpu, arg1, 1, on_read, on_write) >= 0)
                rsp_printf(dbg, "Watchpoint at %08X (%s)\n", arg1,
                           on_read ? "r/w" : "write");
            else
                rsp_printf(dbg, "Failed to set watchpoint\n");
        } else {
            rsp_printf(dbg, "Usage: watch ADDR [0=r/w 1=write]\n");
        }
    }
    else if (strcmp(cmd, "wc") == 0) {
        if (argc >= 2) {
            if (m65832_remove_watchpoint(cpu, arg1))
                rsp_printf(dbg, "Watchpoint removed at %08X\n", arg1);
            else
                rsp_printf(dbg, "No watchpoint at %08X\n", arg1);
        } else {
            cpu->num_watchpoints = 0;
            rsp_printf(dbg, "All watchpoints cleared\n");
        }
    }
    else if (strcmp(cmd, "wl") == 0) {
        if (cpu->num_watchpoints == 0) {
            rsp_printf(dbg, "No watchpoints\n");
        } else {
            for (int i = 0; i < cpu->num_watchpoints; i++) {
                rsp_printf(dbg, "  %08X-%08X %s\n",
                           cpu->watchpoints[i].addr,
                           cpu->watchpoints[i].addr + cpu->watchpoints[i].size - 1,
                           cpu->watchpoints[i].on_read ? "r/w" : "write");
            }
        }
    }

    /* --- Register modification ----------------------------------------- */

    else if (strcmp(cmd, "pc") == 0) {
        if (argc >= 2) { m65832_set_pc(cpu, arg1); rsp_printf(dbg, "PC=%08X\n", arg1); }
        else rsp_printf(dbg, "PC=%08X\n", m65832_get_pc(cpu));
    }
    else if (strcmp(cmd, "a") == 0) {
        if (argc >= 2) { m65832_set_a(cpu, arg1); rsp_printf(dbg, "A=%08X\n", arg1); }
        else rsp_printf(dbg, "A=%08X\n", m65832_get_a(cpu));
    }
    else if (strcmp(cmd, "x") == 0) {
        if (argc >= 2) { m65832_set_x(cpu, arg1); rsp_printf(dbg, "X=%08X\n", arg1); }
        else rsp_printf(dbg, "X=%08X\n", m65832_get_x(cpu));
    }
    else if (strcmp(cmd, "y") == 0) {
        if (argc >= 2) { m65832_set_y(cpu, arg1); rsp_printf(dbg, "Y=%08X\n", arg1); }
        else rsp_printf(dbg, "Y=%08X\n", m65832_get_y(cpu));
    }
    else if (strcmp(cmd, "w") == 0 || strcmp(cmd, "write") == 0) {
        if (argc >= 3) {
            m65832_emu_write8(cpu, arg1, (uint8_t)arg2);
            rsp_printf(dbg, "Wrote %02X to %08X\n", arg2 & 0xFF, arg1);
        } else {
            rsp_printf(dbg, "Usage: write ADDR VALUE\n");
        }
    }

    /* --- Control ------------------------------------------------------- */

    else if (strcmp(cmd, "trace") == 0) {
        if (dbg->trace_flag) {
            char arg_str[16] = {0};
            if (argc >= 2) sscanf(line, "%*s %15s", arg_str);
            for (char *p = arg_str; *p; p++) *p = tolower(*p);

            if (strcmp(arg_str, "on") == 0)       *dbg->trace_flag = 1;
            else if (strcmp(arg_str, "off") == 0)  *dbg->trace_flag = 0;
            else                                   *dbg->trace_flag = !*dbg->trace_flag;

            if (*dbg->trace_flag && dbg->trace_fn)
                m65832_set_trace(cpu, true, dbg->trace_fn, NULL);
            else
                m65832_set_trace(cpu, false, NULL, NULL);

            rsp_printf(dbg, "Tracing %s\n", *dbg->trace_flag ? "on" : "off");
        } else {
            rsp_printf(dbg, "Trace not available\n");
        }
    }
    else if (strcmp(cmd, "c") == 0 || strcmp(cmd, "continue") == 0) {
        /* If we're sitting on a restored breakpoint, step past it first */
        if (dbg->swbp_step_idx >= 0) {
            m65832_emu_step(cpu);
            dbg_reinsert_swbp(dbg);
        }
        /* Re-apply inactive breakpoints (skip already-active ones to
         * avoid clobbering saved_byte with our own BRK opcode) */
        for (int i = 0; i < dbg->num_swbp; i++) {
            if (dbg->swbp[i].active) continue;
            uint64_t pa = dbg_va_to_pa(dbg, dbg->swbp[i].va);
            if (pa != (uint64_t)-1) {
                dbg->swbp[i].pa = pa;
                dbg->swbp[i].saved_byte = cpu->memory[pa];
                cpu->memory[pa] = 0x00;
                dbg->swbp[i].active = 1;
            }
        }
        dbg->paused = 0;
        rsp_printf(dbg, "Running\n");
        return 1;  /* resume */
    }
    else if (strcmp(cmd, "s") == 0 || strcmp(cmd, "step") == 0) {
        int n = (argc >= 2) ? (int)arg1 : 1;
        for (int i = 0; i < n; i++) {
            if (cpu->tracing && cpu->trace_fn) {
                uint8_t op = m65832_emu_read8(cpu, m65832_get_pc(cpu));
                cpu->trace_fn(cpu, m65832_get_pc(cpu), &op, 1, cpu->trace_user);
            }
            m65832_emu_step(cpu);
            dbg_reinsert_swbp(dbg);
            if (dbg->hit_bp) {
                dbg->hit_bp = 0;
                dbg_check_swbp(dbg);
                rsp_printf(dbg, "Breakpoint at %08X\n", m65832_get_pc(cpu));
                break;
            }
        }
        print_regs(dbg);
        return 0;  /* stay paused */
    }
    else if (strcmp(cmd, "n") == 0 || strcmp(cmd, "next") == 0) {
        /* Step over: if current instruction is a call, set temp BP at next inst */
        uint32_t pc = m65832_get_pc(cpu);
        char disasm[64];
        int len = m65832_disassemble(cpu, pc, disasm, sizeof(disasm));
        int is_call = (strncmp(disasm, "JSR", 3) == 0 ||
                       strncmp(disasm, "BSR", 3) == 0 ||
                       strncmp(disasm, "TRAP", 4) == 0);
        if (is_call) {
            uint32_t next_pc = pc + len;
            /* Set temporary breakpoint at return address */
            if (dbg->num_swbp < DBG_MAX_SWBP) {
                uint64_t pa = dbg_va_to_pa(dbg, next_pc);
                if (pa != (uint64_t)-1) {
                    int idx = dbg->num_swbp++;
                    dbg->swbp[idx].va = next_pc;
                    dbg->swbp[idx].pa = pa;
                    dbg->swbp[idx].saved_byte = cpu->memory[pa];
                    dbg->swbp[idx].active = 1;
                    dbg->swbp[idx].temporary = 1;
                    cpu->memory[pa] = 0x00;
                }
            }
            /* Step past restored BP if sitting on one, then continue */
            if (dbg->swbp_step_idx >= 0) {
                m65832_emu_step(cpu);
                dbg_reinsert_swbp(dbg);
            }
            dbg->paused = 0;
            return 1;  /* resume */
        } else {
            /* Not a call: single step */
            if (dbg->swbp_step_idx >= 0) {
                m65832_emu_step(cpu);
                dbg_reinsert_swbp(dbg);
            } else {
                m65832_emu_step(cpu);
            }
            print_regs(dbg);
            return 0;  /* stay paused */
        }
    }
    else if (strcmp(cmd, "until") == 0) {
        if (argc >= 2) {
            char name[64] = {0};
            sscanf(line, "%*s %63s", name);
            uint32_t target = arg1;
            if (name[0]) {
                char *end;
                target = (uint32_t)strtoul(name, &end, 16);
                if (*end != '\0') {
                    target = elf_find_symbol(dbg->symbols, name);
                    if (target == 0) {
                        rsp_printf(dbg, "Symbol '%s' not found\n", name);
                        return 0;
                    }
                }
            }
            /* Set temporary breakpoint */
            if (dbg->num_swbp < DBG_MAX_SWBP) {
                uint64_t pa = dbg_va_to_pa(dbg, target);
                if (pa != (uint64_t)-1) {
                    int idx = dbg->num_swbp++;
                    dbg->swbp[idx].va = target;
                    dbg->swbp[idx].pa = pa;
                    dbg->swbp[idx].saved_byte = cpu->memory[pa];
                    dbg->swbp[idx].active = 1;
                    dbg->swbp[idx].temporary = 1;
                    cpu->memory[pa] = 0x00;
                }
            }
            if (dbg->swbp_step_idx >= 0) {
                m65832_emu_step(cpu);
                dbg_reinsert_swbp(dbg);
            }
            dbg->paused = 0;
            return 1;  /* resume */
        } else {
            rsp_printf(dbg, "Usage: until ADDR|SYMBOL\n");
        }
    }
    else if (strcmp(cmd, "finish") == 0 || strcmp(cmd, "fin") == 0) {
        /* Run until current function returns.
         * Read return address from stack: in 32-bit mode, SP points at last pushed byte,
         * return address is at SP+3..SP+6 (status word at SP+1..SP+2, then RA).
         * For JSR: stack has [RA-1] (32-bit), so RA = read32(SP+1) + 1 */
        int width = IS_EMU(cpu) ? 2 : 4;
        uint32_t ret_addr;
        if (width == 4) {
            ret_addr = m65832_emu_read8(cpu, cpu->s + 1) |
                       ((uint32_t)m65832_emu_read8(cpu, cpu->s + 2) << 8) |
                       ((uint32_t)m65832_emu_read8(cpu, cpu->s + 3) << 16) |
                       ((uint32_t)m65832_emu_read8(cpu, cpu->s + 4) << 24);
            ret_addr += 1;  /* JSR pushes PC-1 */
        } else {
            ret_addr = m65832_emu_read16(cpu, cpu->s + 1) + 1;
        }
        uint32_t soff;
        const char *s = elf_lookup_symbol(dbg->symbols, ret_addr, &soff);
        if (s) rsp_printf(dbg, "Running until return to %08X <%s+0x%X>\n", ret_addr, s, soff);
        else   rsp_printf(dbg, "Running until return to %08X\n", ret_addr);
        /* Set temporary breakpoint at return address */
        if (dbg->num_swbp < DBG_MAX_SWBP) {
            uint64_t pa = dbg_va_to_pa(dbg, ret_addr);
            if (pa != (uint64_t)-1) {
                int idx = dbg->num_swbp++;
                dbg->swbp[idx].va = ret_addr;
                dbg->swbp[idx].pa = pa;
                dbg->swbp[idx].saved_byte = cpu->memory[pa];
                dbg->swbp[idx].active = 1;
                dbg->swbp[idx].temporary = 1;
                cpu->memory[pa] = 0x00;
            }
        }
        if (dbg->swbp_step_idx >= 0) {
            m65832_emu_step(cpu);
            dbg_reinsert_swbp(dbg);
        }
        dbg->paused = 0;
        return 1;  /* resume */
    }
    else if (strcmp(cmd, "r") == 0 || strcmp(cmd, "run") == 0) {
        if (argc >= 2) {
            /* Run for N cycles synchronously */
            uint64_t target = arg1;
            uint64_t start = cpu->cycles;
            while ((cpu->cycles - start) < target && m65832_emu_is_running(cpu)) {
                m65832_emu_step(cpu);
                dbg_reinsert_swbp(dbg);
                if (dbg->hit_bp) {
                    dbg->hit_bp = 0;
                    dbg_check_swbp(dbg);
                    rsp_printf(dbg, "Breakpoint at %08X\n", m65832_get_pc(cpu));
                    break;
                }
            }
            rsp_printf(dbg, "Ran %llu cycles\n", (unsigned long long)(cpu->cycles - start));
            print_regs(dbg);
        } else {
            /* No argument: same as continue */
            dbg->paused = 0;
            rsp_printf(dbg, "Running\n");
            return 1;
        }
    }
    else if (strcmp(cmd, "pause") == 0 || strcmp(cmd, "stop") == 0 ||
             strcmp(cmd, "halt") == 0) {
        dbg->paused = 1;
        print_regs(dbg);
    }
    else if (strcmp(cmd, "wait") == 0) {
        /* Block until CPU stops (breakpoint/halt). */
        if (dbg->paused) {
            rsp_printf(dbg, "Already paused\n");
            print_regs(dbg);
            return 0;
        }
        /* Don't send response yet — main loop will respond on next stop */
        return 2;
    }
    else if (strcmp(cmd, "status") == 0) {
        rsp_printf(dbg, "%s  cycles=%llu inst=%llu\n",
                   dbg->paused ? "Paused" : "Running",
                   (unsigned long long)cpu->cycles,
                   (unsigned long long)cpu->inst_count);
        print_regs(dbg);
    }
    else if (strcmp(cmd, "reset") == 0) {
        m65832_emu_reset(cpu);
        rsp_printf(dbg, "CPU reset\n");
        print_regs(dbg);
    }
    else if (strcmp(cmd, "irq") == 0) {
        int active = (argc >= 2) ? (int)arg1 : 1;
        m65832_irq(cpu, active != 0);
        rsp_printf(dbg, "IRQ %s\n", active ? "asserted" : "deasserted");
    }
    else if (strcmp(cmd, "nmi") == 0) {
        m65832_nmi(cpu);
        rsp_printf(dbg, "NMI triggered\n");
    }
    else if (strcmp(cmd, "q") == 0 || strcmp(cmd, "quit") == 0 ||
             strcmp(cmd, "exit") == 0) {
        rsp_printf(dbg, "Quitting\n");
        return -1;
    }
    else if (strcmp(cmd, "help") == 0 || strcmp(cmd, "?") == 0) {
        rsp_printf(dbg, "Inspection:\n");
        rsp_printf(dbg, "  reg            Show all registers\n");
        rsp_printf(dbg, "  mem ADDR [N]   Hex dump N lines at ADDR\n");
        rsp_printf(dbg, "  dis [ADDR] [N] Disassemble N instructions\n");
        rsp_printf(dbg, "  bt             Backtrace (stack walk)\n");
        rsp_printf(dbg, "  list [ADDR]    Show source code at address\n");
        rsp_printf(dbg, "  sys            System registers (MMU, VBR, timer)\n");
        rsp_printf(dbg, "  tlb            TLB entries\n");
        rsp_printf(dbg, "Symbols:\n");
        rsp_printf(dbg, "  sym ADDR       Look up symbol at address\n");
        rsp_printf(dbg, "  addr NAME      Find address of symbol\n");
        rsp_printf(dbg, "Breakpoints:\n");
        rsp_printf(dbg, "  b ADDR|SYM     Set breakpoint\n");
        rsp_printf(dbg, "  bc [ADDR]      Clear breakpoint (all if no arg)\n");
        rsp_printf(dbg, "  bl             List breakpoints\n");
        rsp_printf(dbg, "Watchpoints:\n");
        rsp_printf(dbg, "  wp ADDR [0|1]  Set watchpoint (0=r/w, 1=write-only)\n");
        rsp_printf(dbg, "  wc [ADDR]      Clear watchpoint (all if no arg)\n");
        rsp_printf(dbg, "  wl             List watchpoints\n");
        rsp_printf(dbg, "Registers:\n");
        rsp_printf(dbg, "  pc [VAL]       Get/set PC\n");
        rsp_printf(dbg, "  a/x/y [VAL]    Get/set register\n");
        rsp_printf(dbg, "  w ADDR VAL     Write byte to memory\n");
        rsp_printf(dbg, "Execution:\n");
        rsp_printf(dbg, "  s [N]          Step N instructions (default 1)\n");
        rsp_printf(dbg, "  n              Next (step over calls)\n");
        rsp_printf(dbg, "  finish         Run until current function returns\n");
        rsp_printf(dbg, "  until ADDR|SYM Run until address\n");
        rsp_printf(dbg, "  c              Continue\n");
        rsp_printf(dbg, "  r [N]          Run N cycles\n");
        rsp_printf(dbg, "  pause          Pause execution\n");
        rsp_printf(dbg, "  wait           Block until CPU stops\n");
        rsp_printf(dbg, "  trace [on|off] Toggle instruction tracing\n");
        rsp_printf(dbg, "Other:\n");
        rsp_printf(dbg, "  status         Show execution status\n");
        rsp_printf(dbg, "  reset          CPU reset\n");
        rsp_printf(dbg, "  irq [0|1]      Assert/deassert IRQ\n");
        rsp_printf(dbg, "  nmi            Trigger NMI\n");
        rsp_printf(dbg, "  q              Quit emulator\n");
    }
    else if (cmd[0]) {
        rsp_printf(dbg, "Unknown command: %s (try 'help')\n", cmd);
    }

    return 0;
}

/* ============================================================================
 * Command Thread (Unix Domain Socket Listener)
 * ========================================================================= */

static void *cmd_thread(void *arg) {
    dbg_state_t *dbg = (dbg_state_t *)arg;

    /* Create listening socket */
    dbg->listen_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (dbg->listen_fd < 0) {
        perror("dbg: socket");
        return NULL;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, dbg->socket_path, sizeof(addr.sun_path) - 1);

    unlink(dbg->socket_path);  /* remove stale socket */

    if (bind(dbg->listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("dbg: bind");
        close(dbg->listen_fd);
        dbg->listen_fd = -1;
        return NULL;
    }

    if (listen(dbg->listen_fd, 2) < 0) {
        perror("dbg: listen");
        close(dbg->listen_fd);
        dbg->listen_fd = -1;
        return NULL;
    }

    fprintf(stderr, "Debug server listening on %s\n", dbg->socket_path);

    while (!dbg->quit) {
        int client = accept(dbg->listen_fd, NULL, NULL);
        if (client < 0) {
            if (dbg->quit || errno == EINVAL) break;
            continue;
        }

        /* Read command */
        char buf[256];
        int n = (int)read(client, buf, sizeof(buf) - 1);
        if (n <= 0) { close(client); continue; }
        buf[n] = '\0';

        /* Strip trailing whitespace */
        while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' '))
            buf[--n] = '\0';
        if (n == 0) { close(client); continue; }

        /* Post command to queue */
        pthread_mutex_lock(&dbg->lock);

        strncpy(dbg->cmd, buf, sizeof(dbg->cmd) - 1);
        dbg->cmd[sizeof(dbg->cmd) - 1] = '\0';
        dbg->has_cmd = 1;
        dbg->irq = 1;                           /* interrupt the main loop   */
        pthread_cond_signal(&dbg->cmd_ready);   /* wake main loop if paused  */

        /* Wait for response */
        while (!dbg->has_rsp && !dbg->quit)
            pthread_cond_wait(&dbg->rsp_ready, &dbg->lock);

        /* Send response */
        if (dbg->has_rsp && dbg->rsp_len > 0)
            (void)write(client, dbg->rsp_buf, dbg->rsp_len);
        dbg->has_rsp = 0;

        pthread_mutex_unlock(&dbg->lock);
        close(client);
    }

    close(dbg->listen_fd);
    dbg->listen_fd = -1;
    unlink(dbg->socket_path);
    return NULL;
}

/* ============================================================================
 * Public API
 * ========================================================================= */

dbg_state_t *dbg_init(m65832_cpu_t *cpu, elf_symtab_t *symbols,
                       elf_linetab_t *lines,
                       struct system_state *system, int *trace_flag,
                       m65832_trace_fn trace_fn) {
    dbg_state_t *dbg = calloc(1, sizeof(dbg_state_t));
    if (!dbg) return NULL;

    pthread_mutex_init(&dbg->lock, NULL);
    pthread_cond_init(&dbg->cmd_ready, NULL);
    pthread_cond_init(&dbg->rsp_ready, NULL);

    dbg->cpu = cpu;
    dbg->symbols = symbols;
    dbg->lines = lines;
    dbg->system = system;
    dbg->trace_flag = trace_flag;
    dbg->trace_fn = trace_fn;
    dbg->paused = 1;              /* start paused */
    dbg->irq = 1;                 /* main loop will see this immediately */
    dbg->listen_fd = -1;
    dbg->swbp_step_idx = -1;
    cpu->dbg_irq = &dbg->irq;    /* BRK sets irq directly */
    cpu->dbg_hit_bp = &dbg->hit_bp;
    cpu->dbg_hit_wp = &dbg->hit_wp;
    cpu->dbg_kernel_ready = &dbg->kernel_ready;

    dbg->socket_path = getenv("M65832_DBG_SOCK");
    if (!dbg->socket_path) dbg->socket_path = DBG_SOCKET_PATH;

    return dbg;
}

int dbg_start(dbg_state_t *dbg) {
    return pthread_create(&dbg->thread, NULL, cmd_thread, dbg);
}

/* ============================================================================
 * Internal helpers (called only from slow path)
 * ========================================================================= */

static void dbg_notify_stop(dbg_state_t *dbg, const char *reason, uint32_t addr) {
    dbg->paused = 1;

    uint32_t soff;
    const char *s = elf_lookup_symbol(dbg->symbols, addr, &soff);
    if (s) fprintf(stderr, "%s at %08X <%s+0x%X>\n", reason, addr, s, soff);
    else   fprintf(stderr, "%s at %08X\n", reason, addr);

    if (dbg->waiting_for_stop) {
        pthread_mutex_lock(&dbg->lock);
        rsp_clear(dbg);
        if (s) rsp_printf(dbg, "%s at %08X <%s+0x%X>\n", reason, addr, s, soff);
        else   rsp_printf(dbg, "%s at %08X\n", reason, addr);
        print_regs(dbg);
        dbg->waiting_for_stop = 0;
        dbg->has_rsp = 1;
        pthread_cond_signal(&dbg->rsp_ready);
        pthread_mutex_unlock(&dbg->lock);
    }
}

static int dbg_check_swbp(dbg_state_t *dbg) {
    m65832_cpu_t *cpu = dbg->cpu;
    uint32_t brk_va = cpu->pc;

    for (int i = 0; i < dbg->num_swbp; i++) {
        if (dbg->swbp[i].va == brk_va) {
            /* Restore original byte */
            if (dbg->swbp[i].pa < cpu->memory_size)
                cpu->memory[dbg->swbp[i].pa] = dbg->swbp[i].saved_byte;
            if (dbg->swbp[i].temporary) {
                /* Auto-remove temporary breakpoint (next/until/finish) */
                if (dbg->swbp_step_idx == i) dbg->swbp_step_idx = -1;
                else if (dbg->swbp_step_idx > i) dbg->swbp_step_idx--;
                dbg->num_swbp--;
                for (int j = i; j < dbg->num_swbp; j++)
                    dbg->swbp[j] = dbg->swbp[j + 1];
            } else {
                dbg->swbp[i].active = 0;
                dbg->swbp_step_idx = i;
            }
            return 1;
        }
    }
    return 0;
}

static void dbg_reinsert_swbp(dbg_state_t *dbg) {
    if (dbg->swbp_step_idx < 0) return;
    int i = dbg->swbp_step_idx;
    if (i < dbg->num_swbp && !dbg->swbp[i].active) {
        uint64_t pa = dbg_va_to_pa(dbg, dbg->swbp[i].va);
        if (pa != (uint64_t)-1) {
            dbg->swbp[i].pa = pa;
            dbg->swbp[i].saved_byte = dbg->cpu->memory[pa];
            dbg->cpu->memory[pa] = 0x00;
            dbg->swbp[i].active = 1;
        }
    }
    dbg->swbp_step_idx = -1;
}

/* ============================================================================
 * dbg_poll — called ONLY when irq is set (breakpoint hit or command pending)
 * ========================================================================= */

int dbg_poll(dbg_state_t *dbg) {
    if (!dbg) return 0;

    /* ---- WDM #$01: kernel loaded — re-insert all breakpoints ---------- */
    if (dbg->kernel_ready) {
        dbg->kernel_ready = 0;
        m65832_cpu_t *cpu = dbg->cpu;
        int applied = 0;
        for (int i = 0; i < dbg->num_swbp; i++) {
            uint64_t pa = dbg_va_to_pa(dbg, dbg->swbp[i].va);
            if (pa != (uint64_t)-1) {
                dbg->swbp[i].pa = pa;
                dbg->swbp[i].saved_byte = cpu->memory[pa];
                cpu->memory[pa] = 0x00;
                dbg->swbp[i].active = 1;
                applied++;
            }
        }
        if (applied > 0)
            fprintf(stderr, "Kernel loaded: %d breakpoint(s) applied\n", applied);
        dbg->irq = 0;
        return 0;  /* continue running */
    }

    /* ---- Watchpoint hit? ---------------------------------------------- */
    if (dbg->hit_wp) {
        dbg->hit_wp = 0;
        m65832_cpu_t *cpu = dbg->cpu;
        uint32_t wp_addr = cpu->trap_addr;
        uint32_t val = m65832_emu_read8(cpu, wp_addr);
        dbg->paused = 1;

        uint32_t soff;
        const char *s = elf_lookup_symbol(dbg->symbols, cpu->pc, &soff);
        if (s)
            fprintf(stderr, "Watchpoint at %08X (val=%02X) hit from %08X <%s+0x%X>\n",
                    wp_addr, val, cpu->pc, s, soff);
        else
            fprintf(stderr, "Watchpoint at %08X (val=%02X) hit from %08X\n",
                    wp_addr, val, cpu->pc);

        if (dbg->waiting_for_stop) {
            pthread_mutex_lock(&dbg->lock);
            rsp_clear(dbg);
            rsp_printf(dbg, "Watchpoint at %08X (val=%02X)\n", wp_addr, val);
            print_regs(dbg);
            dbg->waiting_for_stop = 0;
            dbg->has_rsp = 1;
            pthread_cond_signal(&dbg->rsp_ready);
            pthread_mutex_unlock(&dbg->lock);
        }
        cpu->trap = TRAP_NONE;  /* clear so CPU doesn't stop */
    }

    /* ---- BRK breakpoint hit? ------------------------------------------ */
    if (dbg->hit_bp) {
        dbg->hit_bp = 0;
        if (dbg_check_swbp(dbg))
            dbg_notify_stop(dbg, "Breakpoint", dbg->cpu->pc);
    }

    /* ---- Handle pending command --------------------------------------- */
    if (dbg->has_cmd) {
        pthread_mutex_lock(&dbg->lock);

        rsp_clear(dbg);
        int result = process_cmd(dbg, dbg->cmd);
        dbg->has_cmd = 0;

        if (result == 2) {
            dbg->waiting_for_stop = 1;
            pthread_mutex_unlock(&dbg->lock);
            dbg->irq = 0;
            return 0;
        }

        dbg->has_rsp = 1;
        pthread_cond_signal(&dbg->rsp_ready);
        pthread_mutex_unlock(&dbg->lock);

        if (result == -1) {
            dbg->quit = 1;
            return -1;
        }
        if (result == 1) {
            dbg->irq = 0;   /* clear interrupt, resume fast path */
            return 0;
        }
    }

    /* ---- Paused: block until next command ----------------------------- */
    if (dbg->paused) {
        pthread_mutex_lock(&dbg->lock);
        while (!dbg->has_cmd && dbg->paused && !dbg->quit)
            pthread_cond_wait(&dbg->cmd_ready, &dbg->lock);
        pthread_mutex_unlock(&dbg->lock);
        return 1;  /* tell caller: don't step */
    }

    dbg->irq = 0;
    return 0;
}

void dbg_destroy(dbg_state_t *dbg) {
    if (!dbg) return;

    /* Restore all software breakpoints before teardown */
    for (int i = 0; i < dbg->num_swbp; i++) {
        if (dbg->swbp[i].active && dbg->swbp[i].pa < dbg->cpu->memory_size)
            dbg->cpu->memory[dbg->swbp[i].pa] = dbg->swbp[i].saved_byte;
    }
    dbg->cpu->dbg_irq = NULL;
    dbg->cpu->dbg_hit_bp = NULL;
    dbg->cpu->dbg_hit_wp = NULL;
    dbg->cpu->dbg_kernel_ready = NULL;

    dbg->quit = 1;
    dbg->paused = 0;
    pthread_cond_signal(&dbg->cmd_ready);
    pthread_cond_signal(&dbg->rsp_ready);

    /* Unblock accept() */
    if (dbg->listen_fd >= 0) {
        shutdown(dbg->listen_fd, SHUT_RDWR);
        close(dbg->listen_fd);
        dbg->listen_fd = -1;
    }

    pthread_join(dbg->thread, NULL);

    if (dbg->socket_path)
        unlink(dbg->socket_path);

    pthread_mutex_destroy(&dbg->lock);
    pthread_cond_destroy(&dbg->cmd_ready);
    pthread_cond_destroy(&dbg->rsp_ready);
    free(dbg);
}
