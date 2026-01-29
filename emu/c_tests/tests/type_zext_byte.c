// Test zero extension from byte to uint32
// Expected: A = 0x00000080

#include <stdint.h>

// Global byte with high bit set
volatile uint8_t g_byte = 0x80;

int main(void) {
    // Load and zero-extend byte
    uint32_t val = g_byte;
    
    // Return the zero-extended value (should be 0x80, NOT sign-extended)
    return val;
}
