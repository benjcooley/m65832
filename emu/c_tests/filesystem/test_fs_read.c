/*
 * test_fs_read.c - basic sandbox read test
 */

#include <fcntl.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char buf[32];
    int fd = open("input.txt", O_RDONLY);
    if (fd < 0) {
        _exit(1);
    }

    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n < 0) {
        close(fd);
        _exit(2);
    }
    buf[n] = '\0';
    close(fd);
    _exit(0);
}
