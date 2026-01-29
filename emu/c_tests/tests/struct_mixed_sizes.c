// Test struct with mixed-size fields
// Expected: A = 0x00000001

#include <stdint.h>

struct Mixed {
    uint8_t  a;    // offset 0
    uint8_t  b;    // offset 1
    uint16_t c;    // offset 2
    uint32_t d;    // offset 4
    uint8_t  e;    // offset 8
    uint16_t f;    // offset 10 (aligned)
};

volatile struct Mixed g_mixed = {0x11, 0x22, 0x3344, 0x55667788, 0x99, 0xAABB};

int main(void) {
    int pass = 1;
    
    // Test loading each field
    if (g_mixed.a != 0x11) pass = 0;
    if (g_mixed.b != 0x22) pass = 0;
    if (g_mixed.c != 0x3344) pass = 0;
    if (g_mixed.d != 0x55667788) pass = 0;
    if (g_mixed.e != 0x99) pass = 0;
    if (g_mixed.f != 0xAABB) pass = 0;
    
    // Test storing to each field
    g_mixed.a = 0xAA;
    g_mixed.c = 0x1122;
    
    // Verify stores
    if (g_mixed.a != 0xAA) pass = 0;
    if (g_mixed.b != 0x22) pass = 0;  // Should be unchanged
    if (g_mixed.c != 0x1122) pass = 0;
    
    return pass;
}
