// Test inline assembly with all transfer instructions
//
// Standard transfers: TAX, TXA, TAY, TYA, TSX, TXS, TXY, TYX
// Stack/DP transfers: TCS, TSC, TCD, TDC
// Extended transfers: TAB, TBA, TXB, TBX, TYB, TBY, TSPB

int main(void) {
    int failures = 0;

    // Test 1: TAX - Transfer A to X
    {
        int val;
        asm volatile(
            "LDA #42\n"
            "TAX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 42) failures++;
    }

    // Test 2: TXA - Transfer X to A
    {
        int val;
        asm volatile(
            "LDX #55\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 55) failures++;
    }

    // Test 3: TAY - Transfer A to Y
    {
        int val;
        asm volatile(
            "LDA #77\n"
            "TAY\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "y"
        );
        if (val != 77) failures++;
    }

    // Test 4: TYA - Transfer Y to A
    {
        int val;
        asm volatile(
            "LDY #33\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "y"
        );
        if (val != 33) failures++;
    }

    // Test 5: TXY - Transfer X to Y
    {
        int val;
        asm volatile(
            "LDX #88\n"
            "TXY\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x", "y"
        );
        if (val != 88) failures++;
    }

    // Test 6: TYX - Transfer Y to X
    {
        int val;
        asm volatile(
            "LDY #66\n"
            "TYX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x", "y"
        );
        if (val != 66) failures++;
    }

    // Test 7: TSX/TXS round-trip (save SP, restore SP)
    {
        int val;
        asm volatile(
            "TSX\n"
            "TXA\n"
            "TAX\n"
            "TXS\n"
            "TSX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        // SP should be non-zero (stack is in use)
        if (val == 0) failures++;
    }

    // Test 8: TCS/TSC round-trip (save SP via TSC, verify with TSC)
    {
        int val;
        asm volatile(
            "TSC\n"
            "TCS\n"
            "TSC\n"
            "STA %0"
            : "=r"(val)
            :
            : "a"
        );
        // SP should be non-zero
        if (val == 0) failures++;
    }

    // Test 9: TAB/TBA round-trip
    {
        int val;
        asm volatile(
            "LDA #0x99\n"
            "TAB\n"
            "LDA #0\n"
            "TBA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a"
        );
        if (val != 0x99) failures++;
    }

    // Test 10: TXB/TBX round-trip
    {
        int val;
        asm volatile(
            "LDX #0xAA\n"
            "TXB\n"
            "LDX #0\n"
            "TBX\n"
            "TXA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 0xAA) failures++;
    }

    // Test 11: TYB/TBY round-trip
    {
        int val;
        asm volatile(
            "LDY #0xBB\n"
            "TYB\n"
            "LDY #0\n"
            "TBY\n"
            "TYA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a", "y"
        );
        if (val != 0xBB) failures++;
    }

    // Test 12: TSPB - Transfer SP to B, then TBA to read it
    {
        int val;
        asm volatile(
            "TSPB\n"
            "TBA\n"
            "STA %0"
            : "=r"(val)
            :
            : "a"
        );
        // SP should be non-zero
        if (val == 0) failures++;
    }

    // Test 13: TCD/TDC round-trip (save D, set new D, read back, restore)
    {
        int val;
        asm volatile(
            "TDC\n"          // save current D in A
            "PHA\n"          // push original D
            "LDA #0x1234\n"
            "TCD\n"          // set D = 0x1234
            "TDC\n"          // read D back into A
            "TAX\n"          // save result in X
            "PLA\n"          // restore original D
            "TCD\n"
            "TXA\n"          // get result back
            "STA %0"
            : "=r"(val)
            :
            : "a", "x"
        );
        if (val != 0x1234) failures++;
    }

    return failures;
}
