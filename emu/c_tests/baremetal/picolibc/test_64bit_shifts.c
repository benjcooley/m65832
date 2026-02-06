// Test: 64-bit shift operations for M65832
// Expected: 0 (all tests pass)
// This test exercises __ashldi3/__lshrdi3/__ashrdi3 compiler-rt functions

#include <stdint.h>

// Prevent inlining
__attribute__((noinline))
uint64_t shl64(uint64_t x, int n) {
    return x << n;
}

__attribute__((noinline))
uint64_t shr64(uint64_t x, int n) {
    return x >> n;
}

__attribute__((noinline))
int64_t sar64(int64_t x, int n) {
    return x >> n;
}

int main(void) {
    // Test 1: Shift left by 0 (no-op)
    uint64_t r1 = shl64(0x123456789ABCDEF0ULL, 0);
    if (r1 != 0x123456789ABCDEF0ULL) return 1;
    
    // Test 2: Shift left by 4
    uint64_t r2 = shl64(0x123456789ABCDEF0ULL, 4);
    if (r2 != 0x23456789ABCDEF00ULL) return 2;
    
    // Test 3: Shift left by 32 (cross word boundary)
    uint64_t r3 = shl64(0x12345678ULL, 32);
    if (r3 != 0x1234567800000000ULL) return 3;
    
    // Test 4: Shift left by 1 from low to high word
    uint64_t r4 = shl64(0x80000000ULL, 1);
    if (r4 != 0x100000000ULL) return 4;
    
    // Test 5: Shift right by 32
    uint64_t r5 = shr64(0x123456789ABCDEF0ULL, 32);
    if (r5 != 0x12345678ULL) return 5;
    
    // Test 6: Shift right by 4
    uint64_t r6 = shr64(0x123456789ABCDEF0ULL, 4);
    if (r6 != 0x0123456789ABCDEFULL) return 6;
    
    // Test 7: Arithmetic shift right (negative number)
    int64_t r7 = sar64(-2LL, 1);  // -2 >> 1 = -1
    if (r7 != -1LL) return 7;
    
    // Test 8: Arithmetic shift right preserves sign
    int64_t r8 = sar64(0x8000000000000000LL, 63);
    if (r8 != -1LL) return 8;
    
    // Test 9: Shift left by 63
    uint64_t r9 = shl64(1ULL, 63);
    if (r9 != 0x8000000000000000ULL) return 9;
    
    // Test 10: Shift right by 63
    uint64_t r10 = shr64(0x8000000000000000ULL, 63);
    if (r10 != 1ULL) return 10;
    
    return 0;
}
