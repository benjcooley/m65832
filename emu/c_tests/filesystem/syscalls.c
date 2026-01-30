/*
 * syscalls.c - Minimal syscall wrappers for emulator filesystem tests
 */

#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

#define M65832_SYS_EXIT     1
#define M65832_SYS_READ     3
#define M65832_SYS_WRITE    4
#define M65832_SYS_OPEN     5
#define M65832_SYS_CLOSE    6
#define M65832_SYS_LSEEK    19
#define M65832_SYS_GETPID   20
#define M65832_SYS_FSTAT    108
#define M65832_SYS_EXIT_GRP 248

static inline long __syscall0(long n) {
    register long r0 __asm__("r0") = n;
    asm volatile("trap #0" : "+r"(r0) : : "memory");
    return r0;
}

static inline long __syscall1(long n, long a1) {
    register long r0 __asm__("r0") = n;
    register long r1 __asm__("r1") = a1;
    asm volatile("trap #0" : "+r"(r0) : "r"(r1) : "memory");
    return r0;
}

static inline long __syscall2(long n, long a1, long a2) {
    register long r0 __asm__("r0") = n;
    register long r1 __asm__("r1") = a1;
    register long r2 __asm__("r2") = a2;
    asm volatile("trap #0" : "+r"(r0) : "r"(r1), "r"(r2) : "memory");
    return r0;
}

static inline long __syscall3(long n, long a1, long a2, long a3) {
    register long r0 __asm__("r0") = n;
    register long r1 __asm__("r1") = a1;
    register long r2 __asm__("r2") = a2;
    register long r3 __asm__("r3") = a3;
    asm volatile("trap #0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r3) : "memory");
    return r0;
}

static inline long __syscall_ret(long r) {
    if (r < 0 && r > -4096) {
        errno = -r;
        return -1;
    }
    return r;
}

void __attribute__((noreturn)) _exit(int status) {
    __syscall1(M65832_SYS_EXIT_GRP, status);
    __syscall1(M65832_SYS_EXIT, status);
    __builtin_unreachable();
}

ssize_t _write(int fd, const void *buf, size_t len) {
    return __syscall_ret(__syscall3(M65832_SYS_WRITE, fd, (long)buf, (long)len));
}

ssize_t _read(int fd, void *buf, size_t len) {
    return __syscall_ret(__syscall3(M65832_SYS_READ, fd, (long)buf, (long)len));
}

int _open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return (int)__syscall_ret(__syscall3(M65832_SYS_OPEN, (long)path, flags, mode));
}

int _close(int fd) {
    return (int)__syscall_ret(__syscall1(M65832_SYS_CLOSE, fd));
}

off_t _lseek(int fd, off_t offset, int whence) {
    return (off_t)__syscall_ret(__syscall3(M65832_SYS_LSEEK, fd, (long)offset, whence));
}

int _fstat(int fd, struct stat *st) {
    return (int)__syscall_ret(__syscall2(M65832_SYS_FSTAT, fd, (long)st));
}

int _isatty(int fd) {
    if (fd >= 0 && fd <= 2) {
        return 1;
    }
    errno = EBADF;
    return 0;
}

int _getpid(void) {
    return (int)__syscall_ret(__syscall0(M65832_SYS_GETPID));
}

int _kill(pid_t pid, int sig) {
    (void)pid;
    (void)sig;
    errno = EINVAL;
    return -1;
}

ssize_t write(int fd, const void *buf, size_t len) { return _write(fd, buf, len); }
ssize_t read(int fd, void *buf, size_t len) { return _read(fd, buf, len); }
int open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return _open(path, flags, mode);
}
int close(int fd) { return _close(fd); }
off_t lseek(int fd, off_t offset, int whence) { return _lseek(fd, offset, whence); }
int fstat(int fd, struct stat *st) { return _fstat(fd, st); }
