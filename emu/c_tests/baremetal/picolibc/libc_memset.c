// Test: memset from m65832-stdlib
// Expected: sum of 4 bytes set to 0x42 = 264
#include <string.h>

char buf[4];

int main(void) {
    memset(buf, 0x42, 4);
    return buf[0] + buf[1] + buf[2] + buf[3];
}
