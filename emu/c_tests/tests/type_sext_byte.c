// Test sign extension from byte to int32
// Expected: A = 0xFFFFFF80 (which is -128 as signed int32)

#include <stdint.h>

// Global byte with high bit set
volatile int8_t g_sbyte = -128;  // 0x80

int main(void) {
    // Load and sign-extend byte
    int32_t val = g_sbyte;
    
    // Return the sign-extended value (should be 0xFFFFFF80)
    return val;
}
