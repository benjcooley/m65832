// Test inline assembly clobber lists and memory constraints

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Clobber list with memory
    {
        volatile int x = 10;
        volatile int y = 20;
        int result;
        
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(x), "r"(y)
            : "memory"
        );
        if (result != 30) failures++;
    }
    
    // Test 2: Input/output constraint (tied operand)
    {
        int val = 10;
        asm volatile(
            "LDA %0\n"
            "CLC\n"
            "ADC %0\n"
            "STA %0"
            : "+r"(val)
        );
        if (val != 20) failures++;
    }
    
    // Test 3: Early clobber constraint
    {
        int a = 100;
        int b = 50;
        int result;
        
        asm volatile(
            "LDA %1\n"
            "SEC\n"
            "SBC %2\n"
            "STA %0"
            : "=&r"(result)
            : "r"(a), "r"(b)
        );
        if (result != 50) failures++;
    }
    
    // Test 4: Multiple clobbers including accumulator
    {
        int a = 15;
        int b = 5;
        int result;
        
        asm volatile(
            "LDA %1\n"
            "SEC\n"
            "SBC %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "a"  // Clobber accumulator
        );
        if (result != 10) failures++;
    }
    
    // Test 5: CC (condition codes) clobber - arithmetic modifies flags
    {
        int a = 50;
        int b = 25;
        int result;
        
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "cc"  // Condition codes modified
        );
        if (result != 75) failures++;
    }
    
    return failures;
}
