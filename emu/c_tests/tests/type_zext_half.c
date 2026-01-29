// Test zero extension from halfword to uint32
// Expected: A = 0x00008000

#include <stdint.h>

// Global halfword with high bit set
volatile uint16_t g_half = 0x8000;

int main(void) {
    // Load and zero-extend halfword
    uint32_t val = g_half;
    
    // Return the zero-extended value (should be 0x8000, NOT sign-extended)
    return val;
}
