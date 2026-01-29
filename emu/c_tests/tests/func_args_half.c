// Test halfword function arguments
// Expected: A = 0x00003333

#include <stdint.h>

// Function taking halfword arguments
__attribute__((noinline))
uint16_t add_halfs(uint16_t a, uint16_t b, uint16_t c) {
    return a + b + c;
}

int main(void) {
    // Test halfword argument passing and return
    uint16_t result = add_halfs(0x1111, 0x1111, 0x1111);
    return result;  // 0x1111 + 0x1111 + 0x1111 = 0x3333
}
