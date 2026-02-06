// Test: 64-bit function return values for M65832
// Expected: 0 (all tests pass)
// This test verifies that 64-bit values are correctly returned from functions

#include <stdint.h>

// Prevent inlining to ensure actual function calls
__attribute__((noinline))
int64_t return_i64_simple(void) {
    return 0x123456789ABCDEF0LL;
}

__attribute__((noinline))
int64_t return_i64_from_args(int32_t lo, int32_t hi) {
    return ((int64_t)hi << 32) | (uint32_t)lo;
}

__attribute__((noinline))
uint64_t return_u64_add(uint64_t a, uint64_t b) {
    return a + b;
}

__attribute__((noinline))
int64_t return_i64_negate(int64_t x) {
    return -x;
}

int main(void) {
    // Test 1: Simple 64-bit return
    int64_t r1 = return_i64_simple();
    if (r1 != 0x123456789ABCDEF0LL) return 1;
    
    // Test 2: Build 64-bit from two 32-bit halves
    int64_t r2 = return_i64_from_args(0xDEADBEEF, 0x12345678);
    if (r2 != 0x12345678DEADBEEFLL) return 2;
    
    // Check low word
    uint32_t r2_lo = (uint32_t)(r2 & 0xFFFFFFFF);
    if (r2_lo != 0xDEADBEEF) return 3;
    
    // Check high word
    uint32_t r2_hi = (uint32_t)((r2 >> 32) & 0xFFFFFFFF);
    if (r2_hi != 0x12345678) return 4;
    
    // Test 3: 64-bit addition returning 64-bit
    uint64_t r3 = return_u64_add(0xFFFFFFFFULL, 1ULL);
    if (r3 != 0x100000000ULL) return 5;
    
    // Check the result components
    uint32_t r3_lo = (uint32_t)(r3 & 0xFFFFFFFF);
    uint32_t r3_hi = (uint32_t)((r3 >> 32) & 0xFFFFFFFF);
    if (r3_lo != 0) return 6;
    if (r3_hi != 1) return 7;
    
    // Test 4: Negate a 64-bit value
    int64_t r4 = return_i64_negate(1LL);
    if (r4 != -1LL) return 8;
    
    // Test 5: Large positive value
    uint64_t r5 = return_u64_add(0x7FFFFFFFFFFFFFFFULL, 0);
    if (r5 != 0x7FFFFFFFFFFFFFFFULL) return 9;
    
    return 0;
}
