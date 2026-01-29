// Test mixed-size function arguments
// Expected: A = 0x00000001

#include <stdint.h>

// Function taking mixed-size arguments
__attribute__((noinline))
int check_values(uint8_t a, uint16_t b, uint32_t c, uint8_t d) {
    int pass = 1;
    if (a != 0x11) pass = 0;
    if (b != 0x2222) pass = 0;
    if (c != 0x33333333) pass = 0;
    if (d != 0x44) pass = 0;
    return pass;
}

int main(void) {
    return check_values(0x11, 0x2222, 0x33333333, 0x44);
}
