// Test inline assembly with explicit register constraints
// Tests "a", "x", "y" constraints and named register variables

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Explicit "a" output
    {
        int result;
        asm volatile(
            "LDA #42"
            : "=a"(result)
        );
        if (result != 42) failures++;
    }
    
    // Test 2: Explicit "a" input  
    {
        int val = 77;
        int result;
        asm volatile(
            "STA %0"
            : "=r"(result)
            : "a"(val)
        );
        if (result != 77) failures++;
    }
    
    // Test 3: X register input constraint
    {
        int val = 33;
        int result;
        asm volatile(
            "TXA\n"
            "STA %0"
            : "=r"(result)
            : "x"(val)
            : "a"
        );
        if (result != 33) failures++;
    }
    
    // Test 4: Y register input constraint
    {
        int val = 55;
        int result;
        asm volatile(
            "TYA\n"
            "STA %0"
            : "=r"(result)
            : "y"(val)
            : "a"
        );
        if (result != 55) failures++;
    }
    
    // Test 5: Accumulator as both input and output (tied)
    {
        int val = 10;
        int result;
        asm volatile(
            "CLC\n"
            "ADC #5"
            : "=a"(result)
            : "a"(val)
        );
        if (result != 15) failures++;
    }
    
    // Test 6: Accumulator +a constraint (read-modify-write)
    {
        int val = 20;
        asm volatile(
            "CLC\n"
            "ADC #10"
            : "+a"(val)
        );
        if (val != 30) failures++;
    }
    
    // Test 7: Named register variable for R0
    {
        register int r0 __asm__("r0") = 99;
        int result;
        asm volatile(
            "LDA %1\n"
            "STA %0"
            : "=r"(result)
            : "r"(r0)
            : "a"
        );
        if (result != 99) failures++;
    }
    
    // Test 8: Named register variable with write
    {
        register int r1 __asm__("r1");
        asm volatile(
            "LDA #55\n"
            "STA %0"
            : "=r"(r1)
            :
            : "a"
        );
        if (r1 != 55) failures++;
    }
    
    // Test 9: Multiple named register variables
    {
        register int r2 __asm__("r2") = 30;
        register int r3 __asm__("r3") = 12;
        int result;
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(r2), "r"(r3)
            : "a"
        );
        if (result != 42) failures++;
    }
    
    return failures;
}
