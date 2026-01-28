/* sys.c - M65832 System Platform Implementation
 *
 * Low-level system functions, no LLVM dependencies.
 */

#include "sys.h"

/* Heap boundaries - provided by linker script */
extern char __heap_start[];
extern char __heap_end[];

static char *heap_brk = 0;

void *sys_sbrk(int incr) {
    if (heap_brk == 0) {
        heap_brk = __heap_start;
    }
    
    char *prev = heap_brk;
    
    if (heap_brk + incr > __heap_end || heap_brk + incr < __heap_start) {
        return (void *)-1;  /* Out of memory */
    }
    
    heap_brk += incr;
    return prev;
}

/* Note: Without inline asm support, we can't emit STP directly.
 * Write exit status to a magic MMIO address that emulator watches.
 */
#define EXIT_MMIO_ADDR 0x00FFFFF0

void sys_exit(int status) {
    volatile int *exit_port = (volatile int *)EXIT_MMIO_ADDR;
    *exit_port = status;
    /* Should never return - emulator halts on write to exit port */
    while (1) {}
}

void sys_abort(void) {
    sys_exit(1);
}
