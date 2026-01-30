/*
 * test_fs_read.c - basic sandbox read test
 */

#include <fcntl.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    const char *expected = "input-data\n";
    char buf[32];
    int fd = open("input.txt", O_RDONLY);
    if (fd < 0) {
        return 1;
    }

    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n < 0) {
        close(fd);
        return 2;
    }
    buf[n] = '\0';
    close(fd);

    if (strcmp(buf, expected) != 0) {
        return 3;
    }
    return 0;
}
