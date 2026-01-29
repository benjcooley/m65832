// Test halfword array access - indexed loads and stores
// Expected: A = 0x00000001

#include <stdint.h>

// Halfword array for testing
volatile uint16_t g_arr[8] = {0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000, 0x8000};

int main(void) {
    int pass = 1;
    
    // Test indexed loads
    if (g_arr[0] != 0x1000) pass = 0;
    if (g_arr[3] != 0x4000) pass = 0;
    if (g_arr[7] != 0x8000) pass = 0;
    
    // Test indexed stores
    g_arr[2] = 0xABCD;
    if (g_arr[2] != 0xABCD) pass = 0;
    
    // Verify adjacent elements unchanged
    if (g_arr[1] != 0x2000) pass = 0;
    if (g_arr[3] != 0x4000) pass = 0;
    
    return pass;
}
