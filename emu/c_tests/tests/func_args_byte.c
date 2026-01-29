// Test byte function arguments
// Expected: A = 0x00000055

#include <stdint.h>

// Function taking byte arguments
__attribute__((noinline))
uint8_t add_bytes(uint8_t a, uint8_t b, uint8_t c) {
    return a + b + c;
}

int main(void) {
    // Test byte argument passing and return
    uint8_t result = add_bytes(0x11, 0x22, 0x22);
    return result;  // 0x11 + 0x22 + 0x22 = 0x55
}
