// Test: 64-bit division for M65832
// Expected: 0 (all tests pass)
// This test exercises the __divdi3/__udivdi3 compiler-rt functions

#include <stdint.h>

// Prevent inlining to ensure actual function calls
__attribute__((noinline))
int64_t sdiv64(int64_t a, int64_t b) {
    return a / b;
}

__attribute__((noinline))
uint64_t udiv64(uint64_t a, uint64_t b) {
    return a / b;
}

__attribute__((noinline))
int64_t smod64(int64_t a, int64_t b) {
    return a % b;
}

__attribute__((noinline))
uint64_t umod64(uint64_t a, uint64_t b) {
    return a % b;
}

int main(void) {
    // Test 1: Simple division
    int64_t r1 = sdiv64(100LL, 10LL);
    if (r1 != 10LL) return 1;
    
    // Test 2: Division with 64-bit dividend
    uint64_t r2 = udiv64(10000000000ULL, 100000ULL);
    if (r2 != 100000ULL) return 2;
    
    // Test 3: Division resulting in 64-bit quotient
    uint64_t r3 = udiv64(0x200000000ULL, 2ULL);
    if (r3 != 0x100000000ULL) return 3;
    
    // Test 4: Division by 1
    int64_t r4 = sdiv64(0x123456789ABCDEF0LL, 1LL);
    if (r4 != 0x123456789ABCDEF0LL) return 4;
    
    // Test 5: Negative division
    int64_t r5 = sdiv64(-100LL, 10LL);
    if (r5 != -10LL) return 5;
    
    // Test 6: Negative dividend, negative divisor
    int64_t r6 = sdiv64(-100LL, -10LL);
    if (r6 != 10LL) return 6;
    
    // Test 7: Modulo operation
    int64_t r7 = smod64(17LL, 5LL);
    if (r7 != 2LL) return 7;
    
    // Test 8: Modulo with 64-bit values
    uint64_t r8 = umod64(10000000007ULL, 10000000000ULL);
    if (r8 != 7ULL) return 8;
    
    return 0;
}
