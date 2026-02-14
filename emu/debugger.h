/*
 * debugger.h - M65832 Remote Debug Server
 *
 * A command thread listens on a Unix domain socket.
 * The main emulator loop checks a volatile flag each iteration;
 * no lock is acquired unless a command is actually pending.
 *
 * Usage from bash:  edb reg
 *                   edb "b 8054BF30"
 *                   edb c
 */

#ifndef DEBUGGER_H
#define DEBUGGER_H

#include "m65832emu.h"
#include "elf_loader.h"
#include <pthread.h>

#define DBG_SOCKET_PATH "/tmp/m65832-dbg.sock"
#define DBG_RSP_MAX     65536
#define DBG_MAX_SWBP    64

/* Forward declaration */
struct system_state;

/* Software breakpoint: save original byte, write BRK (0x00) */
typedef struct {
    uint32_t va;            /* virtual address of breakpoint         */
    uint64_t pa;            /* physical address (where BRK lives)    */
    uint8_t  saved_byte;    /* original opcode byte                  */
    int      active;        /* 1 = BRK is currently written in mem   */
    int      temporary;     /* 1 = auto-remove on hit (next/until)   */
} dbg_swbp_t;

typedef struct {
    /* Single-slot command queue ----------------------------------------- */
    pthread_mutex_t lock;
    pthread_cond_t  cmd_ready;      /* wakes main loop when paused       */
    pthread_cond_t  rsp_ready;      /* wakes cmd thread after response   */
    volatile int    has_cmd;        /* checked by main loop WITHOUT lock */
    volatile int    has_rsp;

    char            cmd[256];       /* command from client               */
    char            rsp_buf[DBG_RSP_MAX]; /* response built by main loop */
    int             rsp_len;

    /* State ------------------------------------------------------------- */
    volatile int    irq;            /* "interrupt" — checked by main loop*/
    volatile int    paused;         /* CPU is paused (not stepping)      */
    volatile int    hit_bp;         /* BRK set this — handle on slow path*/
    volatile int    hit_wp;         /* Watchpoint hit — show addr/value  */
    volatile int    kernel_ready;   /* WDM #$01: re-insert breakpoints   */
    volatile int    quit;           /* emulator should exit              */
    volatile int    waiting_for_stop; /* "wait" cmd: respond on next pause */

    /* Software breakpoints ---------------------------------------------- */
    dbg_swbp_t      swbp[DBG_MAX_SWBP];
    int             num_swbp;
    int             swbp_step_idx;  /* BP to re-insert after one step, -1=none */

    /* Kernel VA→PA offset (vaddr - paddr from ELF first LOAD segment).
     * Used as fallback when MMU paging is off.
     * E.g. PAGE_OFFSET=0x80000000, PHYS_OFFSET=0x00100000 → 0x7FF00000 */
    uint32_t            kernel_va_offset;

    /* References (not owned) -------------------------------------------- */
    m65832_cpu_t         *cpu;
    elf_symtab_t         *symbols;
    elf_linetab_t        *lines;     /* DWARF line table (NULL if none)   */
    struct system_state  *system;    /* NULL in legacy mode               */
    int                  *trace_flag; /* &g_trace_enabled                 */
    m65832_trace_fn       trace_fn;  /* trace callback from main.c       */

    /* Thread ------------------------------------------------------------- */
    pthread_t       thread;
    int             listen_fd;
    const char     *socket_path;
} dbg_state_t;

/*
 * Create debug server state.  Starts PAUSED.
 * trace_fn may be NULL if tracing is not desired.
 */
dbg_state_t *dbg_init(m65832_cpu_t *cpu, elf_symtab_t *symbols,
                       elf_linetab_t *lines,
                       struct system_state *system, int *trace_flag,
                       m65832_trace_fn trace_fn);

/* Launch the socket-listener thread. */
int dbg_start(dbg_state_t *dbg);

/*
 * Called from the main loop when cpu->dbg_paused or has_cmd is set.
 *
 * Returns:
 *   0  = resume stepping
 *   1  = still paused — do NOT step
 *  -1  = quit requested
 *
 * The main loop checks a single volatile (paused) to decide whether
 * to call this.  BRK sets paused directly — zero per-step overhead.
 */
int dbg_poll(dbg_state_t *dbg);

/* Tear down: join thread, unlink socket, free. */
void dbg_destroy(dbg_state_t *dbg);

#endif /* DEBUGGER_H */
