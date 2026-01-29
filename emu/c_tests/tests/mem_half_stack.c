// Test halfword operations on stack-allocated variables
// Expected: A = 0x00000001

#include <stdint.h>

__attribute__((noinline))
int test_stack_halfs(void) {
    volatile uint16_t a = 0x1111;
    volatile uint16_t b = 0x2222;
    volatile uint16_t c = 0x3333;
    volatile uint16_t d = 0x4444;
    
    int pass = 1;
    
    // Test stack stores worked
    if (a != 0x1111) pass = 0;
    if (b != 0x2222) pass = 0;
    if (c != 0x3333) pass = 0;
    if (d != 0x4444) pass = 0;
    
    // Modify one variable
    b = 0xAAAA;
    
    // Verify only b changed
    if (a != 0x1111) pass = 0;
    if (b != 0xAAAA) pass = 0;
    if (c != 0x3333) pass = 0;
    if (d != 0x4444) pass = 0;
    
    return pass;
}

int main(void) {
    return test_stack_halfs();
}
