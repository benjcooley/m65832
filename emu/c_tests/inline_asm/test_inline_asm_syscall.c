// Test inline assembly patterns used for syscalls
// Tests named register variables and syscall-like patterns

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Named register variable with explicit constraint
    {
        register int r0 __asm__("r0") = 42;
        int result;
        asm volatile(
            "LD %0, %1"
            : "=r"(result)
            : "r"(r0)
        );
        if (result != 42) failures++;
    }
    
    // Test 2: Multiple named register variables (syscall pattern)
    {
        register int r0 __asm__("r0") = 100;
        register int r1 __asm__("r1") = 50;
        int sum;
        
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(sum)
            : "r"(r0), "r"(r1)
            : "a"
        );
        if (sum != 150) failures++;
    }
    
    // Test 3: "0" constraint (same register as output 0)
    {
        int val = 10;
        int result;
        asm volatile(
            "LDA %0\n"
            "CLC\n"
            "ADC #5\n"
            "STA %0"
            : "=r"(result)
            : "0"(val)    // Use same reg as output %0
            : "a"
        );
        if (result != 15) failures++;
    }
    
    // Test 4: Syscall-like pattern with return value in same register
    {
        register int r0 __asm__("r0") = 7;  // "syscall number"
        register int r1 __asm__("r1") = 3;  // "arg1"
        
        // Simulate syscall: result = r0 + r1
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(r0)
            : "0"(r0), "r"(r1)
            : "a", "memory"
        );
        if (r0 != 10) failures++;
    }
    
    // Test 5: Memory clobber ordering
    {
        volatile int shared = 0;
        int val = 99;
        
        asm volatile(
            "LDA %1\n"
            "STA %0"
            : "=r"(shared)
            : "r"(val)
            : "a", "memory"
        );
        if (shared != 99) failures++;
    }
    
    return failures;
}
