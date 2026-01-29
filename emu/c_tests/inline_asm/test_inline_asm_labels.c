// Test inline assembly with local labels
// Uses uppercase .L prefix labels for m65832as compatibility

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Simple forward label
    {
        int result;
        asm volatile(
            "LDA #5\n"
            "BNE .LSKIP1\n"
            "LDA #99\n"
            ".LSKIP1:\n"
            "STA %0"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 5) failures++;  // Should skip the LDA #99
    }
    
    // Test 2: Forward label with different condition
    {
        int result;
        asm volatile(
            "LDA #0\n"
            "BNE .LSKIP2\n"
            "LDA #42\n"
            ".LSKIP2:\n"
            "STA %0"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 42) failures++;  // Should NOT skip (zero, so BNE not taken)
    }
    
    // Test 3: Multiple labels
    {
        int result;
        asm volatile(
            "LDA #0\n"
            "BEQ .LTRUE3\n"
            "LDA #0\n"
            "BRA .LEND3\n"
            ".LTRUE3:\n"
            "LDA #1\n"
            ".LEND3:\n"
            "STA %0"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 1) failures++;  // Zero flag set, should branch to true
    }
    
    // Test 4: Loop with counter
    {
        int result = 0;
        int count = 3;
        asm volatile(
            "LDA #0\n"
            ".LLOOP4:\n"
            "CLC\n"
            "ADC #10\n"        // Add 10 each iteration
            "DEC %1\n"
            "LDX %1\n"
            "BNE .LLOOP4\n"
            "STA %0"
            : "=r"(result), "+r"(count)
            :
            : "a", "x"
        );
        if (result != 30) failures++;  // 10 * 3 = 30
    }
    
    // Test 5: Conditional with compare
    {
        int a = 10;
        int b = 20;
        int result;
        asm volatile(
            "LDA %1\n"
            "CMP %2\n"
            "BCS .LGEQ5\n"     // Branch if a >= b (unsigned)
            "LDA #0\n"         // a < b
            "BRA .LEND5\n"
            ".LGEQ5:\n"
            "LDA #1\n"         // a >= b
            ".LEND5:\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "a"
        );
        if (result != 0) failures++;  // 10 < 20, so result should be 0
    }
    
    return failures;
}
