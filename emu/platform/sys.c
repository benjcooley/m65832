/* sys.c - M65832 System Platform Implementation
 *
 * Low-level system functions, no LLVM dependencies.
 */

#include "sys.h"
#include <stdint.h>

/* Heap boundaries - provided by linker script */
extern char __heap_start[];
extern char __heap_end[];

static char *heap_brk = 0;

void *sys_sbrk(int incr) {
    if (heap_brk == 0) {
        heap_brk = __heap_start;
    }

    uintptr_t cur = (uintptr_t)heap_brk;
    uintptr_t start = (uintptr_t)__heap_start;
    uintptr_t end = (uintptr_t)__heap_end;
    uintptr_t next = cur + (uintptr_t)incr;

    if ((incr >= 0 && next > end) || (incr < 0 && next < start)) {
        return (void *)-1;  /* Out of memory */
    }

    heap_brk = (char *)next;
    return (void *)cur;
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
