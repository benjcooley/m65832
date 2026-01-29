// Test byte stores don't corrupt adjacent memory (critical for REP/SEP bug)
// Expected: A = 0x00000001

#include <stdint.h>

// All bytes in same data section
volatile uint8_t g_bytes[4] = {0x00, 0xFF, 0x00, 0xFF};

int main(void) {
    // Store to middle byte - should ONLY affect g_bytes[1]
    g_bytes[1] = 0x42;
    
    // Check that adjacent bytes are unchanged
    int pass = 1;
    if (g_bytes[0] != 0x00) pass = 0;
    if (g_bytes[1] != 0x42) pass = 0;  // This one should change
    if (g_bytes[2] != 0x00) pass = 0;
    if (g_bytes[3] != 0xFF) pass = 0;
    
    return pass;
}
