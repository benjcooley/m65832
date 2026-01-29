// Test inline assembly with "m" memory constraint
// The "m" constraint provides a register containing the address

int main(void) {
    int failures = 0;
    
    // Test 1: Load from memory using "m" constraint
    // With "m", %1 is a register containing the address of src
    // Use indirect addressing: LDA (%1) to load the value
    {
        int src = 42;
        int dst;
        asm volatile(
            "LDA (%1)\n"
            "STA (%0)"
            :
            : "m"(dst), "m"(src)
            : "a", "memory"
        );
        if (dst != 42) failures++;
    }
    
    // Test 2: Read-modify-write using "m"
    {
        int val = 10;
        asm volatile(
            "LDA (%0)\n"
            "CLC\n"
            "ADC #5\n"
            "STA (%0)"
            :
            : "m"(val)
            : "a", "memory"
        );
        if (val != 15) failures++;
    }
    
    // Test 3: Multiple memory operands
    {
        int a = 100;
        int b = 200;
        int sum;
        asm volatile(
            "LDA (%1)\n"
            "CLC\n"
            "ADC (%2)\n"
            "STA (%0)"
            :
            : "m"(sum), "m"(a), "m"(b)
            : "a", "memory"
        );
        if (sum != 300) failures++;
    }
    
    return failures;
}
