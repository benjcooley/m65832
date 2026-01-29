/* syscalls.c - Linux system call interface for M65832
 *
 * This file provides the low-level syscall interface for M65832 Linux userspace.
 * System calls are invoked using the TRAP #0 instruction.
 *
 * Calling convention:
 *   R0 = syscall number
 *   R1-R6 = arguments
 *   Return: R0 = result (or -errno on error)
 *
 * This file is used when building musl or other Linux libc for M65832.
 */

#include <stdint.h>
#include <errno.h>

/* ============================================================================
 * Linux System Call Numbers (M65832)
 * These match the standard Linux syscall numbers used in the M65832 port.
 * ========================================================================= */

#define __NR_exit           1
#define __NR_fork           2
#define __NR_read           3
#define __NR_write          4
#define __NR_open           5
#define __NR_close          6
#define __NR_waitpid        7
#define __NR_creat          8
#define __NR_link           9
#define __NR_unlink         10
#define __NR_execve         11
#define __NR_chdir          12
#define __NR_time           13
#define __NR_mknod          14
#define __NR_chmod          15
#define __NR_lseek          19
#define __NR_getpid         20
#define __NR_mount          21
#define __NR_umount         22
#define __NR_setuid         23
#define __NR_getuid         24
#define __NR_stime          25
#define __NR_ptrace         26
#define __NR_alarm          27
#define __NR_pause          29
#define __NR_utime          30
#define __NR_access         33
#define __NR_sync           36
#define __NR_kill           37
#define __NR_rename         38
#define __NR_mkdir          39
#define __NR_rmdir          40
#define __NR_dup            41
#define __NR_pipe           42
#define __NR_times          43
#define __NR_brk            45
#define __NR_setgid         46
#define __NR_getgid         47
#define __NR_signal         48
#define __NR_geteuid        49
#define __NR_getegid        50
#define __NR_ioctl          54
#define __NR_fcntl          55
#define __NR_setpgid        57
#define __NR_umask          60
#define __NR_chroot         61
#define __NR_dup2           63
#define __NR_getppid        64
#define __NR_getpgrp        65
#define __NR_setsid         66
#define __NR_sigaction      67
#define __NR_setreuid       70
#define __NR_setregid       71
#define __NR_sigsuspend     72
#define __NR_sigpending     73
#define __NR_sethostname    74
#define __NR_setrlimit      75
#define __NR_getrlimit      76
#define __NR_getrusage      77
#define __NR_gettimeofday   78
#define __NR_settimeofday   79
#define __NR_getgroups      80
#define __NR_setgroups      81
#define __NR_symlink        83
#define __NR_readlink       85
#define __NR_mmap           90
#define __NR_munmap         91
#define __NR_truncate       92
#define __NR_ftruncate      93
#define __NR_fchmod         94
#define __NR_fchown         95
#define __NR_getpriority    96
#define __NR_setpriority    97
#define __NR_statfs         99
#define __NR_fstatfs        100
#define __NR_socketcall     102
#define __NR_syslog         103
#define __NR_setitimer      104
#define __NR_getitimer      105
#define __NR_stat           106
#define __NR_lstat          107
#define __NR_fstat          108
#define __NR_wait4          114
#define __NR_sysinfo        116
#define __NR_clone          120
#define __NR_mprotect       125
#define __NR_getpgid        132
#define __NR_fchdir         133
#define __NR_personality    136
#define __NR_setfsuid       138
#define __NR_setfsgid       139
#define __NR_getdents       141
#define __NR_select         142
#define __NR_flock          143
#define __NR_msync          144
#define __NR_readv          145
#define __NR_writev         146
#define __NR_getsid         147
#define __NR_fdatasync      148
#define __NR_mlock          150
#define __NR_munlock        151
#define __NR_mlockall       152
#define __NR_munlockall     153
#define __NR_nanosleep      162
#define __NR_mremap         163
#define __NR_poll           168
#define __NR_prctl          172
#define __NR_rt_sigaction   174
#define __NR_rt_sigprocmask 175
#define __NR_rt_sigpending  176
#define __NR_rt_sigtimedwait 177
#define __NR_rt_sigqueueinfo 178
#define __NR_rt_sigsuspend  179
#define __NR_pread64        180
#define __NR_pwrite64       181
#define __NR_getcwd         183
#define __NR_sigaltstack    186
#define __NR_vfork          190
#define __NR_getdents64     220
#define __NR_madvise        219
#define __NR_mincore        218
#define __NR_gettid         224
#define __NR_tkill          238
#define __NR_futex          240
#define __NR_sched_setaffinity 241
#define __NR_sched_getaffinity 242
#define __NR_exit_group     248
#define __NR_set_tid_address 258
#define __NR_clock_gettime  265
#define __NR_clock_getres   266
#define __NR_clock_nanosleep 267
#define __NR_tgkill         270
#define __NR_openat         295
#define __NR_mkdirat        296
#define __NR_mknodat        297
#define __NR_fchownat       298
#define __NR_fstatat64      300
#define __NR_unlinkat       301
#define __NR_renameat       302
#define __NR_linkat         303
#define __NR_symlinkat      304
#define __NR_readlinkat     305
#define __NR_fchmodat       306
#define __NR_faccessat      307
#define __NR_pselect6       308
#define __NR_ppoll          309
#define __NR_set_robust_list 311
#define __NR_get_robust_list 312
#define __NR_utimensat      320
#define __NR_pipe2          331
#define __NR_prlimit64      340

/* ============================================================================
 * Syscall Invocation Macros
 *
 * The TRAP #0 instruction triggers a syscall. Arguments are passed via
 * registers R0-R6 (accessible via direct page when R=1).
 * ========================================================================= */

/* Low-level syscall function implemented in assembly */
extern long __syscall(long number, ...);

/* 
 * Inline syscall macros using TRAP #0
 * 
 * These store arguments in R0-R6 and invoke TRAP #0.
 * The return value comes back in R0.
 */

static inline long __syscall0(long n)
{
    return __syscall(n);
}

static inline long __syscall1(long n, long a1)
{
    return __syscall(n, a1);
}

static inline long __syscall2(long n, long a1, long a2)
{
    return __syscall(n, a1, a2);
}

static inline long __syscall3(long n, long a1, long a2, long a3)
{
    return __syscall(n, a1, a2, a3);
}

static inline long __syscall4(long n, long a1, long a2, long a3, long a4)
{
    return __syscall(n, a1, a2, a3, a4);
}

static inline long __syscall5(long n, long a1, long a2, long a3, long a4, long a5)
{
    return __syscall(n, a1, a2, a3, a4, a5);
}

static inline long __syscall6(long n, long a1, long a2, long a3, long a4, long a5, long a6)
{
    return __syscall(n, a1, a2, a3, a4, a5, a6);
}

/* ============================================================================
 * Error Handling
 * ========================================================================= */

/* Convert syscall return to errno-style error */
static inline long __syscall_ret(long r)
{
    if (r < 0 && r > -4096) {
        errno = -r;
        return -1;
    }
    return r;
}

/* ============================================================================
 * Example Syscall Wrappers
 * These are typically provided by musl, but shown here for reference.
 * ========================================================================= */

#if 0  /* These are provided by musl - shown for documentation */

void _exit(int status)
{
    __syscall1(__NR_exit_group, status);
    __syscall1(__NR_exit, status);
    __builtin_unreachable();
}

ssize_t write(int fd, const void *buf, size_t count)
{
    return __syscall_ret(__syscall3(__NR_write, fd, (long)buf, count));
}

ssize_t read(int fd, void *buf, size_t count)
{
    return __syscall_ret(__syscall3(__NR_read, fd, (long)buf, count));
}

int open(const char *pathname, int flags, ...)
{
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return __syscall_ret(__syscall3(__NR_open, (long)pathname, flags, mode));
}

int close(int fd)
{
    return __syscall_ret(__syscall1(__NR_close, fd));
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset)
{
    return (void *)__syscall_ret(__syscall6(__NR_mmap, (long)addr, length, prot, flags, fd, offset));
}

int munmap(void *addr, size_t length)
{
    return __syscall_ret(__syscall2(__NR_munmap, (long)addr, length));
}

#endif /* musl reference wrappers */
