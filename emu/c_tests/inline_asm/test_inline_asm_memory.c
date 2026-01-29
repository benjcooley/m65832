// Test inline assembly with memory operations
// Basic memory operations without indirect addressing (which may crash)

int main(void) {
    int failures = 0;
    
    // Test 1: Load and store through accumulator
    {
        int src = 42;
        int dst;
        asm volatile(
            "LDA %1\n"
            "STA %0"
            : "=r"(dst)
            : "r"(src)
            : "a"
        );
        if (dst != 42) failures++;
    }
    
    // Test 2: Multiple loads and stores
    {
        int a = 10;
        int b = 20;
        int c = 30;
        int sum;
        
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "CLC\n"
            "ADC %3\n"
            "STA %0"
            : "=r"(sum)
            : "r"(a), "r"(b), "r"(c)
            : "a"
        );
        if (sum != 60) failures++;
    }
    
    // Test 3: Store zero (STZ)
    {
        int val = 99;
        asm volatile(
            "STZ %0"
            : "=r"(val)
        );
        if (val != 0) failures++;
    }
    
    // Test 4: INC on register
    {
        int val = 10;
        asm volatile(
            "INC %0"
            : "+r"(val)
        );
        if (val != 11) failures++;
    }
    
    // Test 5: DEC on register
    {
        int val = 10;
        asm volatile(
            "DEC %0"
            : "+r"(val)
        );
        if (val != 9) failures++;
    }
    
    return failures;
}
