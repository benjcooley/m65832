// Test sign extension from halfword to int32
// Expected: A = 0xFFFF8000 (which is -32768 as signed int32)

#include <stdint.h>

// Global halfword with high bit set
volatile int16_t g_shalf = -32768;  // 0x8000

int main(void) {
    // Load and sign-extend halfword
    int32_t val = g_shalf;
    
    // Return the sign-extended value (should be 0xFFFF8000)
    return val;
}
