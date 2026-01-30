/*
 * sandbox_filesystem.c - Host-backed sandbox filesystem for emulator syscalls
 */

#include "sandbox_filesystem.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define M65832_SYS_READ     3
#define M65832_SYS_WRITE    4
#define M65832_SYS_OPEN     5
#define M65832_SYS_CLOSE    6
#define M65832_SYS_LSEEK    19
#define M65832_SYS_GETPID   20
#define M65832_SYS_FSTAT    108
#define M65832_SYS_EXIT     1
#define M65832_SYS_EXIT_GRP 248

#define M65832_GUEST_FD_MAX 32

typedef struct {
    uint16_t st_dev;
    uint16_t st_ino;
    uint32_t st_mode;
    uint16_t st_nlink;
    uint16_t st_uid;
    uint16_t st_gid;
    uint16_t st_rdev;
    int32_t  st_size;
    struct { int32_t tv_sec; int32_t tv_nsec; } st_atim;
    struct { int32_t tv_sec; int32_t tv_nsec; } st_mtim;
    struct { int32_t tv_sec; int32_t tv_nsec; } st_ctim;
    int32_t  st_blksize;
    int32_t  st_blocks;
    int32_t  st_spare4[2];
} m65832_stat_t;

static uint32_t sandbox_get_arg(system_state_t *sys, int index) {
    m65832_cpu_t *cpu = sys->cpu;
    if (m65832_flag_r(cpu)) {
        return cpu->regs[index];
    }
    uint32_t addr = cpu->d + (uint32_t)(index * 4);
    return m65832_emu_read32(cpu, addr);
}

static void sandbox_set_ret(system_state_t *sys, uint32_t value) {
    m65832_cpu_t *cpu = sys->cpu;
    if (m65832_flag_r(cpu)) {
        cpu->regs[0] = value;
    } else {
        m65832_emu_write32(cpu, cpu->d + 0, value);
    }
}

static int sandbox_alloc_fd(system_state_t *sys, int host_fd) {
    for (int i = 3; i < M65832_GUEST_FD_MAX; i++) {
        if (!sys->fd_used[i]) {
            sys->fd_used[i] = true;
            sys->host_fds[i] = host_fd;
            return i;
        }
    }
    return -1;
}

static int sandbox_get_host_fd(system_state_t *sys, int guest_fd) {
    if (guest_fd < 0 || guest_fd >= M65832_GUEST_FD_MAX) return -1;
    if (!sys->fd_used[guest_fd]) return -1;
    return sys->host_fds[guest_fd];
}

static int sandbox_read_guest_string(system_state_t *sys, uint32_t addr, char *buf, size_t maxlen) {
    size_t i = 0;
    while (i + 1 < maxlen) {
        uint8_t c = m65832_emu_read8(sys->cpu, addr + (uint32_t)i);
        buf[i++] = (char)c;
        if (c == '\0') {
            return 0;
        }
    }
    buf[maxlen - 1] = '\0';
    return -1;
}

static bool sandbox_path_has_parent_ref(const char *path) {
    if (strcmp(path, "..") == 0) return true;
    if (strncmp(path, "../", 3) == 0) return true;
    if (strstr(path, "/../") != NULL) return true;
    if (strstr(path, "/..") && path[strlen(path) - 3] == '/' &&
        path[strlen(path) - 2] == '.' && path[strlen(path) - 1] == '.') {
        return true;
    }
    return false;
}

static int sandbox_build_path(system_state_t *sys, const char *guest_path, char *out, size_t out_len) {
    if (!sys->sandbox_root || sys->sandbox_root[0] == '\0') {
        return -1;
    }
    if (sandbox_path_has_parent_ref(guest_path)) {
        return -1;
    }
    const char *path = guest_path;
    while (*path == '/') path++;
    if (snprintf(out, out_len, "%s/%s", sys->sandbox_root, path) >= (int)out_len) {
        return -1;
    }
    return 0;
}

void sandbox_fs_init(system_state_t *sys, const char *sandbox_root) {
    if (!sys) return;

    sys->sandbox_root = NULL;
    if (sandbox_root && sandbox_root[0] != '\0') {
        sys->sandbox_root = strdup(sandbox_root);
    }

    for (int i = 0; i < M65832_GUEST_FD_MAX; i++) {
        sys->fd_used[i] = false;
        sys->host_fds[i] = -1;
    }
    sys->fd_used[0] = true;
    sys->fd_used[1] = true;
    sys->fd_used[2] = true;
    sys->host_fds[0] = STDIN_FILENO;
    sys->host_fds[1] = STDOUT_FILENO;
    sys->host_fds[2] = STDERR_FILENO;
}

void sandbox_fs_cleanup(system_state_t *sys) {
    if (!sys) return;
    if (sys->sandbox_root) {
        free(sys->sandbox_root);
        sys->sandbox_root = NULL;
    }
    for (int i = 3; i < M65832_GUEST_FD_MAX; i++) {
        if (sys->fd_used[i] && sys->host_fds[i] >= 0) {
            close(sys->host_fds[i]);
        }
        sys->fd_used[i] = false;
        sys->host_fds[i] = -1;
    }
}

bool sandbox_fs_handle_syscall(system_state_t *sys, uint8_t trap_code) {
    (void)trap_code;
    if (!sys || !sys->cpu) return false;

    m65832_cpu_t *cpu = sys->cpu;
    uint32_t nr = sandbox_get_arg(sys, 0);
    uint32_t a1 = sandbox_get_arg(sys, 1);
    uint32_t a2 = sandbox_get_arg(sys, 2);
    uint32_t a3 = sandbox_get_arg(sys, 3);
    uint32_t a4 = sandbox_get_arg(sys, 4);
    uint32_t a5 = sandbox_get_arg(sys, 5);
    uint32_t a6 = sandbox_get_arg(sys, 6);

    (void)a4;
    (void)a5;
    (void)a6;

    if (!sys->sandbox_root || sys->sandbox_root[0] == '\0') {
        if (nr != M65832_SYS_EXIT && nr != M65832_SYS_EXIT_GRP && nr != M65832_SYS_GETPID) {
            cpu->regs[0] = (uint32_t)-ENOSYS;
            return true;
        }
    }

    switch (nr) {
        case M65832_SYS_EXIT:
        case M65832_SYS_EXIT_GRP:
            cpu->exit_code = a1;
            m65832_stop(cpu);
            return true;

        case M65832_SYS_GETPID:
            sandbox_set_ret(sys, 1);
            return true;

        case M65832_SYS_OPEN: {
            char guest_path[512];
            char host_path[PATH_MAX];
            if (sandbox_read_guest_string(sys, a1, guest_path, sizeof(guest_path)) < 0) {
                sandbox_set_ret(sys, (uint32_t)-ENAMETOOLONG);
                return true;
            }
            if (sandbox_build_path(sys, guest_path, host_path, sizeof(host_path)) < 0) {
                sandbox_set_ret(sys, (uint32_t)-EACCES);
                return true;
            }
            int host_fd = open(host_path, (int)a2, (mode_t)a3);
            if (host_fd < 0) {
                sandbox_set_ret(sys, (uint32_t)-errno);
                return true;
            }
            int guest_fd = sandbox_alloc_fd(sys, host_fd);
            if (guest_fd < 0) {
                close(host_fd);
                sandbox_set_ret(sys, (uint32_t)-EMFILE);
                return true;
            }
            sandbox_set_ret(sys, (uint32_t)guest_fd);
            return true;
        }

        case M65832_SYS_CLOSE: {
            int guest_fd = (int)a1;
            if (guest_fd >= 0 && guest_fd <= 2) {
                sandbox_set_ret(sys, 0);
                return true;
            }
            int host_fd = sandbox_get_host_fd(sys, guest_fd);
            if (host_fd < 0) {
                sandbox_set_ret(sys, (uint32_t)-EBADF);
                return true;
            }
            close(host_fd);
            sys->fd_used[guest_fd] = false;
            sys->host_fds[guest_fd] = -1;
            sandbox_set_ret(sys, 0);
            return true;
        }

        case M65832_SYS_READ: {
            int guest_fd = (int)a1;
            int host_fd = sandbox_get_host_fd(sys, guest_fd);
            if (host_fd < 0) {
                sandbox_set_ret(sys, (uint32_t)-EBADF);
                return true;
            }
            size_t len = (size_t)a3;
            uint32_t addr = a2;
            size_t total = 0;
            char buf[1024];
            while (total < len) {
                size_t chunk = len - total;
                if (chunk > sizeof(buf)) chunk = sizeof(buf);
                ssize_t r = read(host_fd, buf, chunk);
                if (r < 0) {
                    sandbox_set_ret(sys, (uint32_t)-errno);
                    return true;
                }
                if (r == 0) break;
                m65832_emu_write_block(cpu, addr + (uint32_t)total, buf, (size_t)r);
                total += (size_t)r;
                if ((size_t)r < chunk) break;
            }
            sandbox_set_ret(sys, (uint32_t)total);
            return true;
        }

        case M65832_SYS_WRITE: {
            int guest_fd = (int)a1;
            int host_fd = sandbox_get_host_fd(sys, guest_fd);
            if (host_fd < 0) {
                sandbox_set_ret(sys, (uint32_t)-EBADF);
                return true;
            }
            size_t len = (size_t)a3;
            uint32_t addr = a2;
            size_t total = 0;
            char buf[1024];
            while (total < len) {
                size_t chunk = len - total;
                if (chunk > sizeof(buf)) chunk = sizeof(buf);
                m65832_emu_read_block(cpu, addr + (uint32_t)total, buf, chunk);
                ssize_t w = write(host_fd, buf, chunk);
                if (w < 0) {
                    sandbox_set_ret(sys, (uint32_t)-errno);
                    return true;
                }
                total += (size_t)w;
                if ((size_t)w < chunk) break;
            }
            sandbox_set_ret(sys, (uint32_t)total);
            return true;
        }

        case M65832_SYS_LSEEK: {
            int guest_fd = (int)a1;
            int host_fd = sandbox_get_host_fd(sys, guest_fd);
            if (host_fd < 0) {
                sandbox_set_ret(sys, (uint32_t)-EBADF);
                return true;
            }
            off_t res = lseek(host_fd, (off_t)(int32_t)a2, (int)a3);
            if (res < 0) {
                sandbox_set_ret(sys, (uint32_t)-errno);
            } else {
                sandbox_set_ret(sys, (uint32_t)res);
            }
            return true;
        }

        case M65832_SYS_FSTAT: {
            int guest_fd = (int)a1;
            uint32_t stat_addr = a2;
            int host_fd = sandbox_get_host_fd(sys, guest_fd);
            if (host_fd < 0) {
                sandbox_set_ret(sys, (uint32_t)-EBADF);
                return true;
            }
            struct stat st;
            if (fstat(host_fd, &st) < 0) {
                sandbox_set_ret(sys, (uint32_t)-errno);
                return true;
            }
            m65832_stat_t gst;
            memset(&gst, 0, sizeof(gst));
            gst.st_mode = (uint32_t)st.st_mode;
            gst.st_size = (int32_t)st.st_size;
            gst.st_nlink = (uint16_t)st.st_nlink;
            gst.st_uid = (uint16_t)st.st_uid;
            gst.st_gid = (uint16_t)st.st_gid;
            gst.st_atim.tv_sec = (int32_t)st.st_atime;
            gst.st_mtim.tv_sec = (int32_t)st.st_mtime;
            gst.st_ctim.tv_sec = (int32_t)st.st_ctime;
            m65832_emu_write_block(cpu, stat_addr, &gst, sizeof(gst));
            sandbox_set_ret(sys, 0);
            return true;
        }

        default:
            sandbox_set_ret(sys, (uint32_t)-ENOSYS);
            return true;
    }
}
