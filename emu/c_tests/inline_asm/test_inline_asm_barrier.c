// Test inline assembly for memory barriers and compiler barriers

int _c_main(void) {
    int failures = 0;
    
    // Test 1: Compiler barrier (empty asm with memory clobber)
    {
        volatile int a = 1;
        volatile int b = 2;
        
        a = 10;
        asm volatile("" : : : "memory");  // Compiler barrier
        b = 20;
        
        if (a != 10 || b != 20) failures++;
    }
    
    // Test 2: Full memory fence
    {
        volatile int shared = 0;
        
        shared = 42;
        asm volatile("fence" : : : "memory");
        
        if (shared != 42) failures++;
    }
    
    // Test 3: NOP as spin hint
    {
        int count = 0;
        asm volatile(
            "NOP\n"
            "NOP\n"
            "NOP"
            : : : "memory"
        );
        // If we got here, NOPs worked
    }
    
    // Test 4: Barrier between writes
    {
        volatile int x = 0;
        volatile int y = 0;
        
        x = 1;
        asm volatile("fence" : : : "memory");
        y = 2;
        
        // Ensure writes are ordered
        if (x != 1 || y != 2) failures++;
    }
    
    return failures;
}
