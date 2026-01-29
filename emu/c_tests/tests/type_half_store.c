// Test halfword (16-bit) stores - should exercise STORE16 pseudo-instruction
// Expected: A = 0x00001234

#include <stdint.h>

// Global halfword for testing store
volatile uint16_t g_half = 0x0000;

int main(void) {
    // Store halfword to global - tests STORE16_GLOBAL
    g_half = 0x1234;
    
    // Read back to verify store worked
    return g_half;
}
