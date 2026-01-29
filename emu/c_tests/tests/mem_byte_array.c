// Test byte array access - indexed loads and stores
// Expected: A = 0x00000001

#include <stdint.h>

// Byte array for testing
volatile uint8_t g_arr[8] = {0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80};

int main(void) {
    int pass = 1;
    
    // Test indexed loads
    if (g_arr[0] != 0x10) pass = 0;
    if (g_arr[3] != 0x40) pass = 0;
    if (g_arr[7] != 0x80) pass = 0;
    
    // Test indexed stores
    g_arr[2] = 0xAB;
    if (g_arr[2] != 0xAB) pass = 0;
    
    // Verify adjacent elements unchanged
    if (g_arr[1] != 0x20) pass = 0;
    if (g_arr[3] != 0x40) pass = 0;
    
    return pass;
}
