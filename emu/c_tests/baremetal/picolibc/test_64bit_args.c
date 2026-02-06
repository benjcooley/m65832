// Test: 64-bit function argument passing for M65832
// Expected: 0 (all tests pass)
// This test verifies 64-bit values are correctly passed to functions

#include <stdint.h>

// Test passing single 64-bit argument
__attribute__((noinline))
int64_t identity64(int64_t x) {
    return x;
}

// Test passing two 64-bit arguments
__attribute__((noinline))
int64_t add64(int64_t a, int64_t b) {
    return a + b;
}

// Test passing mixed 32-bit and 64-bit arguments
__attribute__((noinline))
int64_t mixed_args(int32_t a, int64_t b, int32_t c) {
    return (int64_t)a + b + (int64_t)c;
}

// Test passing many 64-bit arguments (some may go on stack)
__attribute__((noinline))
int64_t many_args(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e) {
    return a + b + c + d + e;
}

// Test correct word order
__attribute__((noinline))
uint32_t get_low(int64_t x) {
    return (uint32_t)(x & 0xFFFFFFFF);
}

__attribute__((noinline))
uint32_t get_high(int64_t x) {
    return (uint32_t)((x >> 32) & 0xFFFFFFFF);
}

int main(void) {
    // Test 1: Identity function preserves value
    int64_t r1 = identity64(0x123456789ABCDEF0LL);
    if (r1 != 0x123456789ABCDEF0LL) return 1;
    
    // Test 2: Add two 64-bit values
    int64_t r2 = add64(0x0000000100000000LL, 0x00000000FFFFFFFFLL);
    if (r2 != 0x00000001FFFFFFFFLL) return 2;
    
    // Test 3: Add with carry across word boundary
    int64_t r3 = add64(0x00000000FFFFFFFFLL, 1LL);
    if (r3 != 0x0000000100000000LL) return 3;
    
    // Test 4: Mixed argument types
    int64_t r4 = mixed_args(1, 0x100000000LL, 2);
    if (r4 != 0x100000003LL) return 4;
    
    // Test 5: Many 64-bit arguments
    int64_t r5 = many_args(1LL, 2LL, 3LL, 4LL, 5LL);
    if (r5 != 15LL) return 5;
    
    // Test 6: Many 64-bit arguments with large values
    int64_t r6 = many_args(0x100000000LL, 0x200000000LL, 
                           0x300000000LL, 0x400000000LL, 0x500000000LL);
    if (r6 != 0xF00000000LL) return 6;
    
    // Test 7: Verify word order - low word
    uint32_t lo = get_low(0x123456789ABCDEF0LL);
    if (lo != 0x9ABCDEF0) return 7;
    
    // Test 8: Verify word order - high word
    uint32_t hi = get_high(0x123456789ABCDEF0LL);
    if (hi != 0x12345678) return 8;
    
    // Test 9: Negative value preservation
    int64_t r9 = identity64(-1LL);
    if (r9 != -1LL) return 9;
    
    // Test 10: Large negative value
    int64_t r10 = identity64(-0x123456789ABCDEF0LL);
    if (r10 != -0x123456789ABCDEF0LL) return 10;
    
    return 0;
}
