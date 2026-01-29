// Test byte operations in a loop (like memset)
// Expected: A = 0x00000001

#include <stdint.h>

volatile uint8_t g_buffer[16];

int main(void) {
    int pass = 1;
    
    // Fill buffer with known pattern
    for (int i = 0; i < 16; i++) {
        g_buffer[i] = 0x42;
    }
    
    // Verify all bytes are correct
    for (int i = 0; i < 16; i++) {
        if (g_buffer[i] != 0x42) pass = 0;
    }
    
    return pass;
}
