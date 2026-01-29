// Test inline assembly with accumulator 'a' constraint
// The 'a' constraint forces use of the A register

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Basic 'a' constraint for output
    // Result comes back in accumulator A
    {
        int val = 42;
        int out;
        asm volatile(
            "LDA %1"
            : "=a"(out)
            : "r"(val)
        );
        if (out != 42) failures++;
    }
    
    // Test 2: 'a' constraint for input
    // Value goes into accumulator, then stored
    {
        int val = 99;
        int out;
        asm volatile(
            "STA %0"
            : "=r"(out)
            : "a"(val)
        );
        if (out != 99) failures++;
    }
    
    // Test 3: Arithmetic using accumulator
    {
        int a = 10;
        int b = 5;
        int result;
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2"
            : "=a"(result)
            : "r"(a), "r"(b)
        );
        if (result != 15) failures++;
    }
    
    // Test 4: Subtraction using accumulator
    {
        int a = 20;
        int b = 7;
        int result;
        asm volatile(
            "LDA %1\n"
            "SEC\n"
            "SBC %2"
            : "=a"(result)
            : "r"(a), "r"(b)
        );
        if (result != 13) failures++;
    }
    
    // Test 5: Multiple operations
    {
        int x = 5;
        int y = 3;
        int result;
        // Compute (x + y) * 2 using shifts
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "ASL A"  // Multiply by 2
            : "=a"(result)
            : "r"(x), "r"(y)
        );
        if (result != 16) failures++;
    }
    
    return failures;
}
