// Test: 64-bit comparison operations for M65832
// Expected: 0 (all tests pass)

#include <stdint.h>

// Prevent inlining
__attribute__((noinline))
int cmp_eq(int64_t a, int64_t b) {
    return a == b;
}

__attribute__((noinline))
int cmp_ne(int64_t a, int64_t b) {
    return a != b;
}

__attribute__((noinline))
int cmp_lt(int64_t a, int64_t b) {
    return a < b;
}

__attribute__((noinline))
int cmp_le(int64_t a, int64_t b) {
    return a <= b;
}

__attribute__((noinline))
int cmp_gt(int64_t a, int64_t b) {
    return a > b;
}

__attribute__((noinline))
int cmp_ge(int64_t a, int64_t b) {
    return a >= b;
}

__attribute__((noinline))
int ucmp_lt(uint64_t a, uint64_t b) {
    return a < b;
}

int main(void) {
    // Test 1: Equal comparison
    if (!cmp_eq(0x123456789ABCDEF0LL, 0x123456789ABCDEF0LL)) return 1;
    if (cmp_eq(0x123456789ABCDEF0LL, 0x123456789ABCDEF1LL)) return 2;
    
    // Test 2: Not equal comparison
    if (!cmp_ne(1LL, 2LL)) return 3;
    if (cmp_ne(1LL, 1LL)) return 4;
    
    // Test 3: Less than - same high word, different low
    if (!cmp_lt(0x100000000LL, 0x100000001LL)) return 5;
    if (cmp_lt(0x100000001LL, 0x100000000LL)) return 6;
    
    // Test 4: Less than - different high words
    if (!cmp_lt(0x0FFFFFFFFFFFFFFFFLL, 0x1000000000000000LL)) return 7;
    
    // Test 5: Less than with negative numbers
    if (!cmp_lt(-2LL, -1LL)) return 8;
    if (!cmp_lt(-1LL, 0LL)) return 9;
    if (cmp_lt(0LL, -1LL)) return 10;
    
    // Test 6: Greater than
    if (!cmp_gt(0x200000000LL, 0x100000000LL)) return 11;
    if (cmp_gt(0x100000000LL, 0x200000000LL)) return 12;
    
    // Test 7: Less than or equal
    if (!cmp_le(1LL, 1LL)) return 13;
    if (!cmp_le(1LL, 2LL)) return 14;
    if (cmp_le(2LL, 1LL)) return 15;
    
    // Test 8: Greater than or equal
    if (!cmp_ge(1LL, 1LL)) return 16;
    if (!cmp_ge(2LL, 1LL)) return 17;
    if (cmp_ge(1LL, 2LL)) return 18;
    
    // Test 9: Unsigned comparison
    // -1 as unsigned is MAX_UINT64, should be > 0
    if (ucmp_lt(0xFFFFFFFFFFFFFFFFULL, 0ULL)) return 19;
    if (!ucmp_lt(0ULL, 0xFFFFFFFFFFFFFFFFULL)) return 20;
    
    return 0;
}
