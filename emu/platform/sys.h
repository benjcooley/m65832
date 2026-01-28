/* sys.h - M65832 System Platform API
 *
 * Low-level system functions, no LLVM dependencies.
 */

#ifndef M65832_PLATFORM_SYS_H
#define M65832_PLATFORM_SYS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Heap management - extends the heap by 'incr' bytes
 * Returns previous break on success, (void*)-1 on failure */
void *sys_sbrk(int incr);

/* Exit the program */
void sys_exit(int status) __attribute__((noreturn));

/* Abort the program */
void sys_abort(void) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#endif /* M65832_PLATFORM_SYS_H */
