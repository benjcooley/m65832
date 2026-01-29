// Test packed struct access (unaligned fields)
// Expected: A = 0x00000001

#include <stdint.h>

struct __attribute__((packed)) Packed {
    uint8_t  a;    // offset 0
    uint32_t b;    // offset 1 (unaligned!)
    uint16_t c;    // offset 5 (unaligned!)
    uint8_t  d;    // offset 7
};

volatile struct Packed g_packed = {0x11, 0x22334455, 0x6677, 0x88};

int main(void) {
    int pass = 1;
    
    // Test loading unaligned fields
    if (g_packed.a != 0x11) pass = 0;
    if (g_packed.b != 0x22334455) pass = 0;
    if (g_packed.c != 0x6677) pass = 0;
    if (g_packed.d != 0x88) pass = 0;
    
    // Test storing to unaligned fields
    g_packed.b = 0xAABBCCDD;
    g_packed.c = 0x1234;
    
    // Verify stores
    if (g_packed.a != 0x11) pass = 0;  // Should be unchanged
    if (g_packed.b != 0xAABBCCDD) pass = 0;
    if (g_packed.c != 0x1234) pass = 0;
    if (g_packed.d != 0x88) pass = 0;  // Should be unchanged
    
    return pass;
}
