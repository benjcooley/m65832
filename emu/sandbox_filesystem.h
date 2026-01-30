/*
 * sandbox_filesystem.h - Host-backed sandbox filesystem for emulator syscalls
 */

#ifndef SANDBOX_FILESYSTEM_H
#define SANDBOX_FILESYSTEM_H

#include "system.h"
#include <stdbool.h>
#include <stdint.h>

void sandbox_fs_init(system_state_t *sys, const char *sandbox_root);
void sandbox_fs_cleanup(system_state_t *sys);
bool sandbox_fs_handle_syscall(system_state_t *sys, uint8_t trap_code);

#endif /* SANDBOX_FILESYSTEM_H */
