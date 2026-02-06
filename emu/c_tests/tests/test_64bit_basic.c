// Test: Basic 64-bit operations for M65832
// Expected: 0 (all tests pass)
// Tests: 64-bit multiplication, division, shifts

#include <stdint.h>

// Simple test: 64-bit multiplication
int test_mul64(void) {
    int64_t a = 100000LL;
    int64_t b = 100000LL;
    int64_t result = a * b;  // Should be 10,000,000,000
    
    // Check result (10^10 = 0x2540BE400)
    if (result != 10000000000LL) {
        return 1;
    }
    return 0;
}

// Test: 64-bit shift left
int test_shl64(void) {
    uint64_t x = 1;
    uint64_t result = x << 32;  // Should be 0x100000000
    
    if (result != 0x100000000ULL) {
        return 2;
    }
    return 0;
}

// Test: 64-bit shift right
int test_shr64(void) {
    uint64_t x = 0x100000000ULL;
    uint64_t result = x >> 32;  // Should be 1
    
    if (result != 1) {
        return 3;
    }
    return 0;
}

// Test: 64-bit comparison
int test_cmp64(void) {
    int64_t a = 0x100000000LL;
    int64_t b = 0x100000001LL;
    
    if (a >= b) {
        return 4;  // a should be less than b
    }
    if (b <= a) {
        return 5;  // b should be greater than a
    }
    return 0;
}

// Test: Basic strtol-like operation (multiply by 10 and accumulate)
int test_strtol_like(void) {
    // Parse "123" manually
    long result = 0;
    result = result * 10 + ('1' - '0');  // 1
    result = result * 10 + ('2' - '0');  // 12
    result = result * 10 + ('3' - '0');  // 123
    
    if (result != 123) {
        return 6;
    }
    
    // Parse "2147483647" (max 32-bit signed)
    result = 0;
    const char *s = "2147483647";
    while (*s) {
        result = result * 10 + (*s - '0');
        s++;
    }
    
    if (result != 2147483647L) {
        return 7;
    }
    
    return 0;
}

// Test: 64-bit addition
int test_add64(void) {
    int64_t a = 0x7FFFFFFF;  // Max 32-bit signed
    int64_t b = 1;
    int64_t result = a + b;  // Should be 0x80000000 (2^31)
    
    if (result != 0x80000000LL) {
        return 8;
    }
    return 0;
}

int main(void) {
    int err = 0;
    
    err = test_mul64();
    if (err) return err;
    
    err = test_shl64();
    if (err) return err;
    
    err = test_shr64();
    if (err) return err;
    
    err = test_cmp64();
    if (err) return err;
    
    err = test_strtol_like();
    if (err) return err;
    
    err = test_add64();
    if (err) return err;
    
    return 0;  // All tests passed
}
