// Test basic inline assembly with GPR register constraints
// Tests 'r' constraint - compiler chooses register
// M65832 GPRs are R0-R63 real general purpose registers

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Basic 'r' constraint - addition
    {
        int a = 10;
        int b = 5;
        int sum;
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(sum)
            : "r"(a), "r"(b)
        );
        if (sum != 15) failures++;
    }
    
    // Test 2: Subtraction
    {
        int a = 50;
        int b = 20;
        int diff;
        asm volatile(
            "LDA %1\n"
            "SEC\n"
            "SBC %2\n"
            "STA %0"
            : "=r"(diff)
            : "r"(a), "r"(b)
        );
        if (diff != 30) failures++;
    }
    
    // Test 3: Input/output constraint (tied operand)
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
    
    return failures;
}
