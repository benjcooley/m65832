// Test halfword stores don't corrupt adjacent memory (critical for REP/SEP bug)
// Expected: A = 0x00000001

#include <stdint.h>

// All halfwords in same data section
volatile uint16_t g_halfs[4] = {0x0000, 0xFFFF, 0x0000, 0xFFFF};

int main(void) {
    // Store to middle halfword - should ONLY affect g_halfs[1]
    g_halfs[1] = 0x1234;
    
    // Check that adjacent halfwords are unchanged
    int pass = 1;
    if (g_halfs[0] != 0x0000) pass = 0;
    if (g_halfs[1] != 0x1234) pass = 0;  // This one should change
    if (g_halfs[2] != 0x0000) pass = 0;
    if (g_halfs[3] != 0xFFFF) pass = 0;
    
    return pass;
}
