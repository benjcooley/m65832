// Test byte (8-bit) stores - should exercise STORE8 pseudo-instruction
// Expected: A = 0x00000042

#include <stdint.h>

// Global byte for testing store
volatile uint8_t g_byte = 0x00;

int main(void) {
    // Store byte to global - tests STORE8_GLOBAL
    g_byte = 0x42;
    
    // Read back to verify store worked
    return g_byte;
}
