// Test: 64-bit multiplication for M65832
// Expected: 0 (all tests pass)
// This test exercises the __muldi3 compiler-rt function

#include <stdint.h>

// Prevent inlining to ensure actual function calls
__attribute__((noinline))
int64_t mul64(int64_t a, int64_t b) {
    return a * b;
}

__attribute__((noinline))
uint64_t umul64(uint64_t a, uint64_t b) {
    return a * b;
}

int main(void) {
    // Test 1: Simple multiplication (fits in 32 bits)
    int64_t r1 = mul64(100LL, 200LL);
    if (r1 != 20000LL) return 1;
    
    // Test 2: Multiplication with result > 32 bits
    // 100,000 * 100,000 = 10,000,000,000 (0x2540BE400)
    int64_t r2 = mul64(100000LL, 100000LL);
    
    // Check low word (0x540BE400 = 1410065408)
    uint32_t r2_lo = (uint32_t)(r2 & 0xFFFFFFFF);
    if (r2_lo != 0x540BE400) return 2;
    
    // Check high word (should be 2)
    uint32_t r2_hi = (uint32_t)((r2 >> 32) & 0xFFFFFFFF);
    if (r2_hi != 2) return 3;
    
    // Test 3: Full comparison
    if (r2 != 10000000000LL) return 4;
    
    // Test 4: Multiply by 0
    int64_t r4 = mul64(12345678LL, 0LL);
    if (r4 != 0LL) return 5;
    
    // Test 5: Multiply by 1
    int64_t r5 = mul64(0x123456789ABCDEF0LL, 1LL);
    if (r5 != 0x123456789ABCDEF0LL) return 6;
    
    // Test 6: Multiply involving high bits
    // (2^32) * 2 = 2^33
    uint64_t r6 = umul64(0x100000000ULL, 2ULL);
    uint32_t r6_lo = (uint32_t)(r6 & 0xFFFFFFFF);
    uint32_t r6_hi = (uint32_t)((r6 >> 32) & 0xFFFFFFFF);
    if (r6_lo != 0) return 7;
    if (r6_hi != 2) return 8;
    
    // Test 7: Negative multiplication
    int64_t r7 = mul64(-10LL, 5LL);
    if (r7 != -50LL) return 9;
    
    // Test 8: Negative * Negative = Positive
    int64_t r8 = mul64(-100LL, -200LL);
    if (r8 != 20000LL) return 10;
    
    return 0;
}
