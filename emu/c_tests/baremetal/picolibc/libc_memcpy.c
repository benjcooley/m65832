// Test: memcpy from m65832-stdlib
// Expected: sum of copied bytes = 10
#include <string.h>

char src[] = {1, 2, 3, 4};
char dst[4];

int main(void) {
    memcpy(dst, src, 4);
    return dst[0] + dst[1] + dst[2] + dst[3];
}
