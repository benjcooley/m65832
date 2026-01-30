/*
 * test_fs_write.c - basic sandbox write/fstat test
 */

#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    const char *msg = "hello";
    int fd = open("output.txt", O_CREAT | O_TRUNC | O_WRONLY, 0644);
    if (fd < 0) {
        _exit(1);
    }

    ssize_t n = write(fd, msg, strlen(msg));
    if (n != (ssize_t)strlen(msg)) {
        close(fd);
        _exit(2);
    }
    close(fd);

    fd = open("output.txt", O_RDONLY);
    if (fd < 0) {
        _exit(3);
    }

    struct stat st;
    if (fstat(fd, &st) != 0) {
        close(fd);
        _exit(4);
    }
    close(fd);

    if (st.st_size != (off_t)strlen(msg)) {
        _exit(5);
    }
    _exit(0);
}
