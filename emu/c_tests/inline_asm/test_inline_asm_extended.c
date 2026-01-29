// Test inline assembly with extended ALU instructions
// Tests LD, CMP with R-register targets

int _c_main(void) {
    int failures = 0;
    
    // Test 1: LD immediate to register
    {
        int result;
        asm volatile(
            "LD %0, #42\n"
            : "=r"(result)
        );
        if (result != 42) failures++;
    }
    
    // Test 2: LD register to register
    {
        int src = 77;
        int dst;
        asm volatile(
            "LD %0, %1\n"
            : "=r"(dst)
            : "r"(src)
        );
        if (dst != 77) failures++;
    }
    
    // Test 3: Complex expression with multiple registers
    {
        int a = 10;
        int b = 20;
        int c = 30;
        int result;
        
        // result = a + b + c using accumulator
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "CLC\n"
            "ADC %3\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b), "r"(c)
            : "a"
        );
        if (result != 60) failures++;
    }
    
    // Test 4: Load large immediate
    {
        int result;
        asm volatile(
            "LD %0, #1000\n"
            : "=r"(result)
        );
        if (result != 1000) failures++;
    }
    
    // Test 5: Register move chain
    {
        int a = 123;
        int b, c;
        asm volatile(
            "LD %0, %2\n"
            "LD %1, %0\n"
            : "=r"(b), "=r"(c)
            : "r"(a)
        );
        if (b != 123 || c != 123) failures++;
    }
    
    return failures;
}
