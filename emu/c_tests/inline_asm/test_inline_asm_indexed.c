// Test inline assembly with X and Y index registers

int _c_main(void) {
    int failures = 0;
    
    // Test 1: LDX immediate and transfer to A
    {
        int val;
        asm volatile(
            "LDX #10\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 10) failures++;
    }
    
    // Test 2: LDY immediate and transfer to A
    {
        int val;
        asm volatile(
            "LDY #20\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "y"
        );
        if (val != 20) failures++;
    }
    
    // Test 3: TAX transfer
    {
        int val = 42;
        int result;
        asm volatile(
            "LDA %1\n"
            "TAX\n"
            "TXA\n"
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a", "x"
        );
        if (result != 42) failures++;
    }
    
    // Test 4: TAY transfer
    {
        int val = 55;
        int result;
        asm volatile(
            "LDA %1\n"
            "TAY\n"
            "TYA\n"
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a", "y"
        );
        if (result != 55) failures++;
    }
    
    // Test 5: LDX from register
    {
        int src = 33;
        int result;
        asm volatile(
            "LDX %1\n"
            "TXA\n"
            "STA %0"
            : "=r"(result)
            : "r"(src)
            : "a", "x"
        );
        if (result != 33) failures++;
    }
    
    // Test 6: LDY from register
    {
        int src = 44;
        int result;
        asm volatile(
            "LDY %1\n"
            "TYA\n"
            "STA %0"
            : "=r"(result)
            : "r"(src)
            : "a", "y"
        );
        if (result != 44) failures++;
    }
    
    // Test 7: STX to register
    {
        int result;
        asm volatile(
            "LDX #77\n"
            "STX %0"
            : "=r"(result)
            :
            : "x"
        );
        if (result != 77) failures++;
    }
    
    // Test 8: STY to register
    {
        int result;
        asm volatile(
            "LDY #88\n"
            "STY %0"
            : "=r"(result)
            :
            : "y"
        );
        if (result != 88) failures++;
    }
    
    return failures;
}
