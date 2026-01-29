// Test byte operations on stack-allocated variables
// Expected: A = 0x00000001

#include <stdint.h>

__attribute__((noinline))
int test_stack_bytes(void) {
    volatile uint8_t a = 0x11;
    volatile uint8_t b = 0x22;
    volatile uint8_t c = 0x33;
    volatile uint8_t d = 0x44;
    
    int pass = 1;
    
    // Test stack stores worked
    if (a != 0x11) pass = 0;
    if (b != 0x22) pass = 0;
    if (c != 0x33) pass = 0;
    if (d != 0x44) pass = 0;
    
    // Modify one variable
    b = 0xAA;
    
    // Verify only b changed
    if (a != 0x11) pass = 0;
    if (b != 0xAA) pass = 0;
    if (c != 0x33) pass = 0;
    if (d != 0x44) pass = 0;
    
    return pass;
}

int main(void) {
    return test_stack_bytes();
}
