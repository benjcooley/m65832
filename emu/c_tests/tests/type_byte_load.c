// Test byte (8-bit) loads - should exercise LOAD8 pseudo-instruction
// Expected: A = 0x000000AB

#include <stdint.h>

// Global byte value to load
volatile uint8_t g_byte = 0xAB;

int main(void) {
    // Load byte from global - tests LOAD8_GLOBAL
    uint8_t val = g_byte;
    
    // Return the loaded value (should be 0xAB, zero-extended to 32-bit)
    return val;
}
