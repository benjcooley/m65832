// Test halfword (16-bit) loads - should exercise LOAD16 pseudo-instruction
// Expected: A = 0x0000ABCD

#include <stdint.h>

// Global halfword value to load
volatile uint16_t g_half = 0xABCD;

int main(void) {
    // Load halfword from global - tests LOAD16_GLOBAL
    uint16_t val = g_half;
    
    // Return the loaded value (should be 0xABCD, zero-extended to 32-bit)
    return val;
}
