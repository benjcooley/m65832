// Test inline assembly with INX/INY/DEX/DEY instructions

int _c_main(void) {
    int failures = 0;
    
    // Test 1: INX
    {
        int val;
        asm volatile(
            "LDX #5\n"
            "INX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 6) failures++;
    }
    
    // Test 2: DEX
    {
        int val;
        asm volatile(
            "LDX #10\n"
            "DEX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 9) failures++;
    }
    
    // Test 3: INY
    {
        int val;
        asm volatile(
            "LDY #15\n"
            "INY\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "y"
        );
        if (val != 16) failures++;
    }
    
    // Test 4: DEY
    {
        int val;
        asm volatile(
            "LDY #20\n"
            "DEY\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "y"
        );
        if (val != 19) failures++;
    }
    
    // Test 5: Multiple INX
    {
        int val;
        asm volatile(
            "LDX #0\n"
            "INX\n"
            "INX\n"
            "INX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 3) failures++;
    }
    
    // Test 6: DEX to zero
    {
        int val;
        asm volatile(
            "LDX #2\n"
            "DEX\n"
            "DEX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 0) failures++;
    }
    
    return failures;
}
